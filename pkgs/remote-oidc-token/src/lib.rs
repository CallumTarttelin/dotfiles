//! Copy an OIDC web app's access token from the work browser to a remote machine.
//!
//! The web app keeps its OIDC session in the browser's local storage. This
//! reads that entry from the Firefox profile on disk, opens the web app to let
//! it renew the session when the token is missing or about to expire, and sends
//! only the access token and its expiry to the remote machine over SSH stdin.
//! The refresh token stays in the browser: identity providers such as Zitadel
//! rotate refresh tokens, so sharing it would sign the browser out.

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail, ensure};
use rusqlite::OptionalExtension;
use rusqlite::types::Value as SqlValue;
use serde::{Deserialize, Serialize};

pub const CONFIG_ENV: &str = "REMOTE_OIDC_TOKEN_CONFIG";
const RESULT_MARKER: &str = "__REMOTE_OIDC_TOKEN_RESULT__";

// --- Configuration -----------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub host: String,
    pub browser: String,
    pub profile: String,
    #[serde(default = "default_min_valid")]
    pub min_valid_seconds: u64,
    #[serde(default = "default_wait")]
    pub wait_seconds: u64,
    #[serde(default = "default_poll")]
    pub poll_interval_ms: u64,
    pub environments: BTreeMap<String, Environment>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Environment {
    pub issuer: String,
    pub client_id: String,
    pub app_url: String,
    pub origins: Vec<String>,
    pub token_dir: String,
}

fn default_min_valid() -> u64 {
    1800
}

fn default_wait() -> u64 {
    180
}

fn default_poll() -> u64 {
    2000
}

impl Config {
    pub fn load(path: &Path) -> Result<Self> {
        let text = fs::read_to_string(path)
            .with_context(|| format!("could not read config {}", path.display()))?;
        let config: Config = serde_json::from_str(&text)
            .with_context(|| format!("could not parse config {}", path.display()))?;
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> Result<()> {
        ensure!(
            valid_host(&self.host),
            "config: host must be a non-empty SSH destination"
        );
        ensure!(
            !self.browser.trim().is_empty(),
            "config: browser must not be empty"
        );
        ensure!(
            !self.profile.trim().is_empty(),
            "config: profile must not be empty"
        );
        ensure!(
            self.wait_seconds > 0,
            "config: wait_seconds must be greater than zero"
        );
        ensure!(
            self.poll_interval_ms > 0,
            "config: poll_interval_ms must be greater than zero"
        );
        ensure!(
            !self.environments.is_empty(),
            "config: environments must define at least one environment"
        );
        for (name, env) in &self.environments {
            ensure!(
                env.issuer.starts_with("https://") && !env.issuer.ends_with('/'),
                "config: environments.{name}.issuer must be an https URL without a trailing slash"
            );
            ensure!(
                env.app_url.starts_with("https://"),
                "config: environments.{name}.app_url must be an https URL"
            );
            ensure!(
                !env.client_id.is_empty(),
                "config: environments.{name}.client_id must not be empty"
            );
            ensure!(
                !env.origins.is_empty(),
                "config: environments.{name}.origins must not be empty"
            );
            for origin in &env.origins {
                ensure!(
                    !origin.is_empty() && !origin.contains('/') && origin != "." && origin != "..",
                    "config: environments.{name}.origins must be storage folder names such as https+++example.com"
                );
            }
            ensure!(
                !env.token_dir.trim().is_empty(),
                "config: environments.{name}.token_dir must not be empty"
            );
        }
        Ok(())
    }
}

fn valid_host(host: &str) -> bool {
    !host.is_empty() && !host.starts_with('-') && !host.chars().any(char::is_whitespace)
}

pub fn default_config_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))?;
    Some(base.join("remote-oidc-token").join("config.json"))
}

pub fn expand_home(path: &str) -> PathBuf {
    match (path, std::env::var_os("HOME")) {
        ("~", Some(home)) => PathBuf::from(home),
        (rest, Some(home)) if rest.starts_with("~/") => PathBuf::from(home).join(&rest[2..]),
        _ => PathBuf::from(path),
    }
}

// --- Firefox local storage ---------------------------------------------------

/// Decode a Firefox local storage value (`compression_type` 1 = raw Snappy,
/// `conversion_type` 1 = UTF-8, otherwise UTF-16LE).
pub fn decode_value(value: SqlValue, compression: i64, conversion: i64) -> Result<String> {
    let bytes = match value {
        SqlValue::Text(text) => return Ok(text),
        SqlValue::Null => return Ok(String::new()),
        SqlValue::Blob(bytes) => bytes,
        other => bail!(
            "unexpected local storage value type {:?}",
            other.data_type()
        ),
    };
    let raw = if compression == 1 {
        snap::raw::Decoder::new()
            .decompress_vec(&bytes)
            .context("invalid snappy data")?
    } else {
        bytes
    };
    if conversion == 1 {
        return String::from_utf8(raw).context("invalid UTF-8 value");
    }
    let (pairs, rest) = raw.as_chunks::<2>();
    ensure!(rest.is_empty(), "invalid UTF-16 value length");
    let units: Vec<u16> = pairs.iter().map(|pair| u16::from_le_bytes(*pair)).collect();
    String::from_utf16(&units).context("invalid UTF-16 value")
}

/// Read one key from a Firefox local storage database, using a private copy so
/// the live database is never opened.
pub fn read_storage_value(db: &Path, key: &str) -> Result<Option<String>> {
    if !db.is_file() {
        return Ok(None);
    }
    let dir = tempfile::Builder::new()
        .prefix("remote-oidc-token-")
        .tempdir()?;
    let copy = dir.path().join("data.sqlite");
    fs::copy(db, &copy).with_context(|| format!("could not copy {}", db.display()))?;
    let wal = PathBuf::from(format!("{}-wal", db.display()));
    if wal.is_file() {
        fs::copy(&wal, dir.path().join("data.sqlite-wal"))?;
    }
    let connection = rusqlite::Connection::open(&copy)?;
    let row = connection
        .query_row(
            "SELECT value, compression_type, conversion_type FROM data WHERE key = ?1",
            [key],
            |row| {
                Ok((
                    row.get::<_, SqlValue>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .optional()
        .with_context(|| format!("could not read browser storage {}", db.display()))?;
    row.map(|(value, compression, conversion)| {
        decode_value(value, compression, conversion)
            .with_context(|| format!("could not decode the browser session in {}", db.display()))
    })
    .transpose()
}

pub fn storage_key(env: &Environment) -> String {
    format!("oidc.user:{}:{}", env.issuer, env.client_id)
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Session {
    pub issuer: String,
    pub client_id: String,
    pub access_token: String,
    pub token_type: String,
    pub scope: String,
    pub expires_at: i64,
    #[serde(skip)]
    pub user: String,
}

fn is_token_safe(token: &str) -> bool {
    !token.is_empty()
        && token
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-._~+/=".contains(&b))
}

/// Parse the web app's `oidc.user:*` entry, keeping only what the remote needs.
pub fn parse_session(text: &str, env: &Environment) -> Option<Session> {
    let record: serde_json::Value = serde_json::from_str(text).ok()?;
    let access = record.get("access_token")?.as_str()?;
    let expires_at = record.get("expires_at")?.as_i64()?;
    let profile = record.get("profile")?;
    if !is_token_safe(access) || profile.get("iss")?.as_str()? != env.issuer {
        return None;
    }
    if let Some(client_id) = profile.get("client_id")
        && client_id.as_str() != Some(env.client_id.as_str())
    {
        return None;
    }
    let text_field = |value: Option<&serde_json::Value>| {
        value
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_owned()
    };
    let user = ["preferred_username", "email", "sub"]
        .iter()
        .find_map(|field| {
            profile
                .get(*field)
                .and_then(|v| v.as_str())
                .filter(|v| !v.is_empty())
        })
        .unwrap_or_default()
        .to_owned();
    Some(Session {
        issuer: env.issuer.clone(),
        client_id: env.client_id.clone(),
        access_token: access.to_owned(),
        token_type: Some(text_field(record.get("token_type")))
            .filter(|t| !t.is_empty())
            .unwrap_or_else(|| "Bearer".into()),
        scope: text_field(record.get("scope")),
        expires_at,
        user,
    })
}

/// Return the session with the latest expiry across the web app's origins.
pub fn find_session(profile: &Path, env: &Environment) -> Result<Option<Session>> {
    let key = storage_key(env);
    let mut best: Option<Session> = None;
    for origin in &env.origins {
        let db = profile
            .join("storage")
            .join("default")
            .join(origin)
            .join("ls")
            .join("data.sqlite");
        let session = read_storage_value(&db, &key)?.and_then(|text| parse_session(&text, env));
        if let Some(session) = session
            && best
                .as_ref()
                .is_none_or(|current| session.expires_at > current.expires_at)
        {
            best = Some(session);
        }
    }
    Ok(best)
}

pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or_default()
}

fn is_fresh(session: Option<&Session>, min_valid: u64) -> bool {
    session.is_some_and(|s| s.expires_at - now() >= min_valid as i64)
}

pub fn format_duration(seconds: i64) -> String {
    let minutes = seconds.max(0) / 60;
    format!("{}h {:02}m", minutes / 60, minutes % 60)
}

// --- Processes ---------------------------------------------------------------

fn is_executable(path: &Path) -> bool {
    fs::metadata(path).is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
}

pub fn find_executable(name: &str) -> Option<PathBuf> {
    if name.contains('/') {
        let path = PathBuf::from(name);
        return is_executable(&path).then_some(path);
    }
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|dir| dir.join(name))
        .find(|path| is_executable(path))
}

fn open_browser(browser: &Path, url: &str) -> Result<()> {
    Command::new(browser)
        .arg(url)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .with_context(|| format!("could not start {}", browser.display()))?;
    Ok(())
}

/// Store the token on the remote. It arrives on stdin (first line: the token,
/// rest: token.json) so it never appears in a process list.
pub const REMOTE_SCRIPT: &str = r#"set -eu
umask 077
dir=$1
case $dir in
  "~") dir=$HOME ;;
  "~/"*) dir=$HOME/${dir#"~/"} ;;
esac
mkdir -p "$dir"
chmod 700 "$dir"
IFS= read -r token || true
if [ -z "$token" ]; then
  echo "remote-oidc-token: remote received an empty token" >&2
  exit 2
fi
tmp_json=$(mktemp "$dir/.tmp-XXXXXX")
tmp_token=$(mktemp "$dir/.tmp-XXXXXX")
trap 'rm -f "$tmp_json" "$tmp_token"' EXIT
cat > "$tmp_json"
printf '%s\n' "$token" > "$tmp_token"
mv -f "$tmp_json" "$dir/token.json"
mv -f "$tmp_token" "$dir/token"
trap - EXIT
printf '__REMOTE_OIDC_TOKEN_RESULT__ path=%s\n' "$dir/token"
"#;

pub fn sh_quote(word: &str) -> String {
    let plain = !word.is_empty()
        && word
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_@%+=:,./-".contains(&b));
    if plain {
        word.to_owned()
    } else {
        format!("'{}'", word.replace('\'', r#"'"'"'"#))
    }
}

pub fn build_remote_command(token_dir: &str) -> String {
    ["sh", "-c", REMOTE_SCRIPT, "remote-oidc-token", token_dir]
        .iter()
        .map(|word| sh_quote(word))
        .collect::<Vec<_>>()
        .join(" ")
}

fn push_session(host: &str, env: &Environment, session: &Session) -> Result<String> {
    let ssh = find_executable("ssh").context("local ssh executable was not found")?;
    let mut child = Command::new(ssh)
        .args([
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            "-o",
            "ServerAliveInterval=10",
        ])
        .args([
            "-o",
            "ServerAliveCountMax=3",
            "--",
            host,
            &build_remote_command(&env.token_dir),
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("could not start ssh")?;
    let payload = format!(
        "{}\n{}\n",
        session.access_token,
        serde_json::to_string_pretty(session)?
    );
    if let Some(mut stdin) = child.stdin.take() {
        // A remote that exits early closes the pipe; its output explains why.
        let _ = stdin.write_all(payload.as_bytes());
    }
    let output = child.wait_with_output()?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let path = stdout
        .lines()
        .find_map(|line| {
            line.strip_prefix(RESULT_MARKER)?
                .trim()
                .strip_prefix("path=")
        })
        .map(str::to_owned);
    match path {
        Some(path) if output.status.success() => Ok(path),
        _ => {
            let combined = format!("{}{}", String::from_utf8_lossy(&output.stderr), stdout);
            let redacted = combined.replace(&session.access_token, "<redacted-token>");
            let lines: Vec<&str> = redacted.trim().lines().collect();
            let tail = lines[lines.len().saturating_sub(20)..].join("\n");
            if tail.is_empty() {
                bail!("copying the token to {host} failed");
            }
            bail!("copying the token to {host} failed:\n{tail}")
        }
    }
}

// --- Orchestration -----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct Options {
    pub host: String,
    /// The environments to copy, in config order.
    pub envs: Vec<(String, Environment)>,
    pub profile: PathBuf,
    pub browser: String,
    pub no_browser: bool,
    pub force_open: bool,
    pub min_valid: u64,
    pub wait: Duration,
    pub poll: Duration,
}

impl Options {
    /// Build options from the config, with command-line overrides applied by the caller.
    /// `only` limits the run to one environment; otherwise every environment is copied.
    pub fn from_config(config: &Config, only: Option<&str>) -> Result<Self> {
        let envs = match only {
            None => config
                .environments
                .iter()
                .map(|(name, env)| (name.clone(), env.clone()))
                .collect(),
            Some(name) => {
                let Some(env) = config.environments.get(name) else {
                    let known: Vec<&str> = config.environments.keys().map(String::as_str).collect();
                    bail!(
                        "unknown environment {name:?}; the config defines: {}",
                        known.join(", ")
                    );
                };
                vec![(name.to_owned(), env.clone())]
            }
        };
        Ok(Self {
            host: config.host.clone(),
            envs,
            profile: expand_home(&config.profile),
            browser: config.browser.clone(),
            no_browser: false,
            force_open: false,
            min_valid: config.min_valid_seconds,
            wait: Duration::from_secs(config.wait_seconds),
            poll: Duration::from_millis(config.poll_interval_ms),
        })
    }
}

fn stale_error(profile: &Path, env: &Environment, session: Option<&Session>) -> anyhow::Error {
    let Some(session) = session else {
        return anyhow::anyhow!(
            "no session found in {}; sign in at {} in the work browser",
            profile.display(),
            env.app_url
        );
    };
    let remaining = session.expires_at - now();
    let state = if remaining > 0 {
        format!("expires in {}", format_duration(remaining))
    } else {
        "has expired".to_owned()
    };
    anyhow::anyhow!(
        "the token in the browser {state}; open {} in the work browser to renew it",
        env.app_url
    )
}

/// An environment still waiting for the web app to renew its session.
struct Pending {
    index: usize,
    previous_expiry: i64,
    latest: Option<Session>,
}

/// Find a usable session for every environment, opening the web apps of stale
/// ones together and waiting for all of them in one shared window.
fn obtain_sessions(opts: &Options, out: &mut impl Write) -> Result<Vec<Result<Session>>> {
    let mut results: Vec<Option<Result<Session>>> = Vec::with_capacity(opts.envs.len());
    let mut pending = Vec::new();
    for (index, (_, env)) in opts.envs.iter().enumerate() {
        match find_session(&opts.profile, env) {
            Err(error) => results.push(Some(Err(error))),
            Ok(session) if is_fresh(session.as_ref(), opts.min_valid) && !opts.force_open => {
                results.push(session.map(Ok));
            }
            Ok(session) if opts.no_browser => {
                results.push(Some(Err(stale_error(&opts.profile, env, session.as_ref()))));
            }
            Ok(session) => {
                results.push(None);
                pending.push(Pending {
                    index,
                    previous_expiry: session.as_ref().map_or(0, |s| s.expires_at),
                    latest: session,
                });
            }
        }
    }

    if !pending.is_empty() {
        let browser = find_executable(&opts.browser).with_context(|| {
            format!(
                "browser executable was not found or is not executable: {}",
                opts.browser
            )
        });
        let browser = match browser {
            Ok(browser) => browser,
            Err(error) => {
                let message = format!("{error:#}");
                for item in pending.drain(..) {
                    results[item.index] = Some(Err(anyhow::anyhow!(message.clone())));
                }
                return Ok(results.into_iter().map(Option::unwrap).collect());
            }
        };
        let browser_name = browser
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        pending.retain(|item| {
            let (name, env) = &opts.envs[item.index];
            match open_browser(&browser, &env.app_url) {
                Ok(()) => {
                    let _ = writeln!(
                        out,
                        "Opened {} ({name}) in {browser_name}; sign in there if asked.",
                        env.app_url
                    );
                    true
                }
                Err(error) => {
                    results[item.index] = Some(Err(error));
                    false
                }
            }
        });
        if !pending.is_empty() {
            writeln!(out, "Waiting for the renewed sessions…")?;
        }
        out.flush()?;

        let deadline = Instant::now() + opts.wait;
        while !pending.is_empty() && Instant::now() < deadline {
            thread::sleep(
                opts.poll
                    .min(deadline.saturating_duration_since(Instant::now())),
            );
            pending.retain_mut(|item| {
                let env = &opts.envs[item.index].1;
                match find_session(&opts.profile, env) {
                    Err(error) => {
                        results[item.index] = Some(Err(error));
                        false
                    }
                    Ok(latest) => {
                        let renewed = latest.as_ref().is_some_and(|candidate| {
                            is_fresh(Some(candidate), opts.min_valid)
                                && (!opts.force_open || candidate.expires_at > item.previous_expiry)
                        });
                        if renewed {
                            results[item.index] = latest.map(Ok);
                            return false;
                        }
                        item.latest = latest;
                        true
                    }
                }
            });
        }
        for item in pending {
            results[item.index] = Some(match item.latest {
                Some(session) if is_fresh(Some(&session), opts.min_valid) => Ok(session),
                _ => Err(anyhow::anyhow!(
                    "timed out after {}s waiting for a renewed session in {}; check that you are signed in at {} in the work browser",
                    opts.wait.as_secs(),
                    opts.profile.display(),
                    opts.envs[item.index].1.app_url
                )),
            });
        }
    }
    Ok(results
        .into_iter()
        .map(|result| result.expect("every environment has a result"))
        .collect())
}

/// Copy the token of every selected environment; fails if any environment failed,
/// after copying the ones that worked.
pub fn run(opts: &Options, out: &mut impl Write) -> Result<()> {
    ensure!(
        valid_host(&opts.host),
        "invalid SSH destination {:?}",
        opts.host
    );
    let sessions = obtain_sessions(opts, out)?;
    let mut failures = Vec::new();
    for ((name, env), session) in opts.envs.iter().zip(sessions) {
        let copied = session.and_then(|session| {
            push_session(&opts.host, env, &session).map(|path| (session, path))
        });
        match copied {
            Ok((session, path)) => {
                let who = if session.user.is_empty() {
                    String::new()
                } else {
                    format!(" for {}", session.user)
                };
                writeln!(
                    out,
                    "Copied the {name} token{who} to {} (expires in {}).\n  Use it there with: export ACCESS_TOKEN=$(cat {path})",
                    opts.host,
                    format_duration(session.expires_at - now())
                )?;
            }
            Err(error) => failures.push(format!("{name}: {error:#}")),
        }
    }
    if failures.is_empty() {
        return Ok(());
    }
    if opts.envs.len() == 1 {
        bail!("{}", failures.remove(0));
    }
    bail!(
        "{} of {} environments failed:\n{}",
        failures.len(),
        opts.envs.len(),
        failures.join("\n")
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env() -> Environment {
        Environment {
            issuer: "https://login.example.test".into(),
            client_id: "client@main-project".into(),
            app_url: "https://app.example.test/".into(),
            origins: vec![
                "https+++www.app.example.test".into(),
                "https+++app.example.test".into(),
            ],
            token_dir: "~/.config/remote-oidc-token/test".into(),
        }
    }

    fn config_json() -> serde_json::Value {
        serde_json::json!({
            "host": "devbox",
            "browser": "firefox-work",
            "profile": "~/profile",
            "environments": {"test": {
                "issuer": "https://login.example.test",
                "client_id": "client@main-project",
                "app_url": "https://app.example.test/",
                "origins": ["https+++www.app.example.test"],
                "token_dir": "~/.config/remote-oidc-token/test"
            }}
        })
    }

    fn session_text(access: &str, issuer: &str, client_id: &str) -> String {
        serde_json::json!({
            "access_token": access,
            "refresh_token": "refresh-secret",
            "id_token": "id-secret",
            "token_type": "Bearer",
            "scope": "openid",
            "expires_at": 2_000_000_000i64,
            "profile": {"iss": issuer, "client_id": client_id, "preferred_username": "person@example.com"}
        })
        .to_string()
    }

    fn write_db(path: &Path, key: &str, value: SqlValue, compression: i64, conversion: i64) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        let connection = rusqlite::Connection::open(path).unwrap();
        connection
            .execute_batch(
                "CREATE TABLE IF NOT EXISTS data (key TEXT PRIMARY KEY, utf16_length INTEGER NOT NULL DEFAULT 0, \
                 conversion_type INTEGER NOT NULL, compression_type INTEGER NOT NULL, \
                 last_access_time INTEGER NOT NULL DEFAULT 0, value BLOB NOT NULL)",
            )
            .unwrap();
        connection
            .execute(
                "INSERT OR REPLACE INTO data (key, conversion_type, compression_type, value) VALUES (?1, ?2, ?3, ?4)",
                rusqlite::params![key, conversion, compression, value],
            )
            .unwrap();
    }

    #[test]
    fn decodes_storage_encodings() {
        let compressed = snap::raw::Encoder::new()
            .compress_vec("héllo héllo héllo".as_bytes())
            .unwrap();
        assert_eq!(
            decode_value(SqlValue::Blob(compressed), 1, 1).unwrap(),
            "héllo héllo héllo"
        );
        assert_eq!(
            decode_value(SqlValue::Blob(b"plain".to_vec()), 0, 1).unwrap(),
            "plain"
        );
        let wide: Vec<u8> = "wide".encode_utf16().flat_map(u16::to_le_bytes).collect();
        assert_eq!(decode_value(SqlValue::Blob(wide), 0, 0).unwrap(), "wide");
        assert_eq!(
            decode_value(SqlValue::Text(String::new()), 0, 1).unwrap(),
            ""
        );
        assert!(decode_value(SqlValue::Blob(vec![0xff, 0x01]), 1, 1).is_err());
        assert!(decode_value(SqlValue::Blob(vec![0x41]), 0, 0).is_err());
    }

    #[test]
    fn parses_only_matching_sessions() {
        let env = env();
        let session =
            parse_session(&session_text("eyJ.a.b", &env.issuer, &env.client_id), &env).unwrap();
        assert_eq!(session.access_token, "eyJ.a.b");
        assert_eq!(session.user, "person@example.com");
        assert_eq!(session.expires_at, 2_000_000_000);
        let stored = serde_json::to_value(&session).unwrap();
        assert!(stored.get("user").is_none());
        assert!(stored.get("refresh_token").is_none());

        for text in [
            "not json".to_owned(),
            "[]".to_owned(),
            session_text("eyJ.a.b", "https://evil.example", &env.client_id),
            session_text("eyJ.a.b", &env.issuer, "other@main-project"),
            session_text("bad token\nwith newline", &env.issuer, &env.client_id),
            r#"{"access_token":"a","expires_at":"soon","profile":{"iss":"https://login.example.test"}}"#.to_owned(),
        ] {
            assert!(parse_session(&text, &env).is_none(), "accepted {text}");
        }
    }

    #[test]
    fn finds_latest_session_across_origins_without_touching_live_db() {
        let dir = tempfile::tempdir().unwrap();
        let env = env();
        let key = storage_key(&env);
        let db = |origin: &str| {
            dir.path()
                .join("storage/default")
                .join(origin)
                .join("ls/data.sqlite")
        };
        assert_eq!(find_session(dir.path(), &env).unwrap(), None);

        let old =
            session_text("old", &env.issuer, &env.client_id).replace("2000000000", "1900000000");
        let compressed = snap::raw::Encoder::new()
            .compress_vec(old.as_bytes())
            .unwrap();
        write_db(&db(&env.origins[0]), &key, SqlValue::Blob(compressed), 1, 1);
        write_db(
            &db(&env.origins[1]),
            &key,
            SqlValue::Blob(session_text("new", &env.issuer, &env.client_id).into_bytes()),
            0,
            1,
        );

        let before = fs::read(db(&env.origins[0])).unwrap();
        assert_eq!(
            find_session(dir.path(), &env)
                .unwrap()
                .unwrap()
                .access_token,
            "new"
        );
        assert_eq!(fs::read(db(&env.origins[0])).unwrap(), before);
        let names: Vec<_> = fs::read_dir(db(&env.origins[0]).parent().unwrap())
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names, vec!["data.sqlite"]);
    }

    #[test]
    fn storage_key_matches_web_app_format() {
        assert_eq!(
            storage_key(&env()),
            "oidc.user:https://login.example.test:client@main-project"
        );
    }

    #[test]
    fn validates_config() {
        let config: Config = serde_json::from_value(config_json()).unwrap();
        config.validate().unwrap();
        assert_eq!(config.min_valid_seconds, 1800);
        assert_eq!(config.wait_seconds, 180);

        let broken = [
            ("/host", serde_json::json!("-oProxyCommand=x")),
            ("/environments", serde_json::json!({})),
            (
                "/environments/test/issuer",
                serde_json::json!("http://login.example.test"),
            ),
            (
                "/environments/test/issuer",
                serde_json::json!("https://login.example.test/"),
            ),
            (
                "/environments/test/app_url",
                serde_json::json!("http://app.example.test"),
            ),
            ("/environments/test/origins", serde_json::json!([])),
            (
                "/environments/test/origins",
                serde_json::json!(["../escape"]),
            ),
            ("/environments/test/token_dir", serde_json::json!(" ")),
        ];
        for (pointer, value) in broken {
            let mut json = config_json();
            *json
                .pointer_mut(pointer)
                .unwrap_or_else(|| panic!("{pointer}")) = value;
            let config: Config = serde_json::from_value(json).unwrap();
            assert!(config.validate().is_err(), "accepted {pointer}");
        }
        let mut no_wait = config_json();
        no_wait["wait_seconds"] = serde_json::json!(0);
        assert!(
            serde_json::from_value::<Config>(no_wait)
                .unwrap()
                .validate()
                .is_err()
        );
        let mut unknown = config_json();
        unknown["surprise"] = serde_json::json!(true);
        assert!(serde_json::from_value::<Config>(unknown).is_err());
    }

    #[test]
    fn options_select_all_or_one_environment() {
        let mut json = config_json();
        json["environments"]["another"] = json["environments"]["test"].clone();
        let config: Config = serde_json::from_value(json).unwrap();
        let names = |opts: Options| opts.envs.into_iter().map(|(n, _)| n).collect::<Vec<_>>();
        assert_eq!(
            names(Options::from_config(&config, None).unwrap()),
            ["another", "test"]
        );
        assert_eq!(
            names(Options::from_config(&config, Some("test")).unwrap()),
            ["test"]
        );
        let err = Options::from_config(&config, Some("prod"))
            .unwrap_err()
            .to_string();
        assert!(
            err.contains("unknown environment \"prod\"; the config defines: another, test"),
            "{err}"
        );
    }

    #[test]
    fn sh_quote_round_trips_through_sh() {
        for word in [
            "plain",
            "",
            "with space",
            "it's",
            "~/a dir/it's",
            "$HOME `x` \"q\"",
            REMOTE_SCRIPT,
        ] {
            let output = Command::new("sh")
                .args(["-c", &format!("printf '%s' {}", sh_quote(word))])
                .output()
                .unwrap();
            assert_eq!(String::from_utf8(output.stdout).unwrap(), word);
        }
    }

    #[test]
    fn remote_script_writes_private_files() {
        let dir = tempfile::tempdir().unwrap();
        let token_dir = dir.path().join("tokens/prod");
        let mut child = Command::new("sh")
            .args(["-c", REMOTE_SCRIPT, "remote-oidc-token"])
            .arg(&token_dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(b"tok.en\n{\"expires_at\": 1}\n")
            .unwrap();
        let output = child.wait_with_output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(
            String::from_utf8(output.stdout).unwrap(),
            format!(
                "__REMOTE_OIDC_TOKEN_RESULT__ path={}/token\n",
                token_dir.display()
            )
        );
        assert_eq!(
            fs::read_to_string(token_dir.join("token")).unwrap(),
            "tok.en\n"
        );
        assert_eq!(
            fs::read_to_string(token_dir.join("token.json")).unwrap(),
            "{\"expires_at\": 1}\n"
        );
        assert_eq!(
            fs::metadata(&token_dir).unwrap().permissions().mode() & 0o777,
            0o700
        );
        for name in ["token", "token.json"] {
            assert_eq!(
                fs::metadata(token_dir.join(name))
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
        assert_eq!(fs::read_dir(&token_dir).unwrap().count(), 2);
    }

    #[test]
    fn remote_script_rejects_empty_token() {
        let dir = tempfile::tempdir().unwrap();
        let output = Command::new("sh")
            .args(["-c", REMOTE_SCRIPT, "remote-oidc-token"])
            .arg(dir.path())
            .stdin(Stdio::null())
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(2));
        assert!(String::from_utf8_lossy(&output.stderr).contains("empty token"));
    }

    #[test]
    fn formats_durations() {
        assert_eq!(format_duration(43_199), "11h 59m");
        assert_eq!(format_duration(59), "0h 00m");
        assert_eq!(format_duration(-5), "0h 00m");
    }

    #[test]
    fn expands_home() {
        let home = std::env::var("HOME").unwrap();
        assert_eq!(expand_home("~"), PathBuf::from(&home));
        assert_eq!(expand_home("~/x/y"), PathBuf::from(&home).join("x/y"));
        assert_eq!(expand_home("/abs"), PathBuf::from("/abs"));
        assert_eq!(expand_home("~other/x"), PathBuf::from("~other/x"));
    }
}
