use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rusqlite::params;

const BIN: &str = env!("CARGO_BIN_EXE_remote-oidc-token");
const ACCESS_TOKEN: &str = "eyJhbGciOiJBMjU2R0NNS1cifQ.key.iv.ciphertext.tag";

struct TestEnv {
    name: &'static str,
    issuer: &'static str,
    client_id: &'static str,
    origin: &'static str,
    app_url: &'static str,
}

const DEV: TestEnv = TestEnv {
    name: "dev",
    issuer: "https://login.dev.example.test",
    client_id: "dev-client",
    origin: "https+++www.dev.example.test",
    app_url: "https://www.dev.example.test/",
};

const PROD: TestEnv = TestEnv {
    name: "prod",
    issuer: "https://login.example.test",
    client_id: "client@main-project",
    origin: "https+++www.app.example.test",
    app_url: "https://www.app.example.test/",
};

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
}

fn session_json(env: &TestEnv, access: &str, expires_in: i64) -> String {
    serde_json::json!({
        "id_token": "id-secret",
        "access_token": access,
        "refresh_token": "refresh-secret",
        "token_type": "Bearer",
        "scope": "openid offline_access",
        "profile": {"iss": env.issuer, "client_id": env.client_id, "preferred_username": "person@example.com"},
        "expires_at": now() + expires_in,
    })
    .to_string()
}

fn write_session(profile: &Path, env: &TestEnv, text: &str) {
    let db = profile
        .join("storage/default")
        .join(env.origin)
        .join("ls/data.sqlite");
    fs::create_dir_all(db.parent().unwrap()).unwrap();
    let connection = rusqlite::Connection::open(db).unwrap();
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS data (key TEXT PRIMARY KEY, utf16_length INTEGER NOT NULL DEFAULT 0, \
             conversion_type INTEGER NOT NULL, compression_type INTEGER NOT NULL, \
             last_access_time INTEGER NOT NULL DEFAULT 0, value BLOB NOT NULL)",
        )
        .unwrap();
    let compressed = snap::raw::Encoder::new()
        .compress_vec(text.as_bytes())
        .unwrap();
    connection
        .execute(
            "INSERT OR REPLACE INTO data (key, conversion_type, compression_type, value) VALUES (?1, 1, 1, ?2)",
            params![format!("oidc.user:{}:{}", env.issuer, env.client_id), compressed],
        )
        .unwrap();
}

fn write_executable(path: &Path, body: &str) {
    fs::write(path, body).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

fn text(output: &Output) -> (String, String) {
    (
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

struct Harness {
    _dir: tempfile::TempDir,
    root: PathBuf,
    profile: PathBuf,
    bin: PathBuf,
    browser_log: PathBuf,
}

impl Harness {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().to_path_buf();
        let bin = root.join("bin");
        fs::create_dir(&bin).unwrap();
        // ssh runs the remote command locally, as the remote login shell would.
        write_executable(
            &bin.join("ssh"),
            "#!/bin/sh\nfor last; do :; done\nexec /bin/sh -c \"$last\"\n",
        );
        let browser_log = root.join("browser.log");
        write_executable(
            &bin.join("fake-browser"),
            &format!(
                "#!/bin/sh\nprintf '%s\\n' \"$1\" >> '{}'\n",
                browser_log.display()
            ),
        );
        let harness = Harness {
            profile: root.join("profile"),
            browser_log,
            bin,
            root,
            _dir: dir,
        };
        harness.write_config(serde_json::json!({}));
        harness
    }

    fn config_path(&self) -> PathBuf {
        self.root.join("config.json")
    }

    fn token_dir(&self, env: &TestEnv) -> PathBuf {
        self.root.join("remote-home/tokens").join(env.name)
    }

    fn env_config(&self, env: &TestEnv) -> serde_json::Value {
        serde_json::json!({
            "issuer": env.issuer,
            "client_id": env.client_id,
            "app_url": env.app_url,
            "origins": [env.origin],
            "token_dir": self.token_dir(env),
        })
    }

    fn write_config(&self, overrides: serde_json::Value) {
        let mut config = serde_json::json!({
            "host": "fakehost",
            "browser": self.bin.join("fake-browser"),
            "profile": self.profile,
            "wait_seconds": 20,
            "poll_interval_ms": 100,
            "environments": {
                DEV.name: self.env_config(&DEV),
                PROD.name: self.env_config(&PROD),
            },
        });
        for (key, value) in overrides.as_object().unwrap() {
            config[key] = value.clone();
        }
        fs::write(self.config_path(), config.to_string()).unwrap();
    }

    fn write_session(&self, env: &TestEnv, access: &str, expires_in: i64) {
        write_session(&self.profile, env, &session_json(env, access, expires_in));
    }

    fn run(&self, args: &[&str]) -> Output {
        let path = format!(
            "{}:{}",
            self.bin.display(),
            std::env::var("PATH").unwrap_or_default()
        );
        Command::new(BIN)
            .args(args)
            .env("PATH", path)
            .env("REMOTE_OIDC_TOKEN_CONFIG", self.config_path())
            .env_remove("FIREFOX_WORK_PROFILE_PATH")
            .output()
            .unwrap()
    }

    /// Simulate a web app renewing its session once the browser opened its URL.
    fn renew_when_opened(
        &self,
        env: &'static TestEnv,
        access: &'static str,
    ) -> thread::JoinHandle<bool> {
        let log = self.browser_log.clone();
        let profile = self.profile.clone();
        thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(15);
            while Instant::now() < deadline {
                let opened = fs::read_to_string(&log).unwrap_or_default();
                if opened.lines().any(|line| line == env.app_url) {
                    thread::sleep(Duration::from_millis(300));
                    write_session(&profile, env, &session_json(env, access, 43_200));
                    return true;
                }
                thread::sleep(Duration::from_millis(50));
            }
            false
        })
    }

    fn opened(&self) -> Vec<String> {
        fs::read_to_string(&self.browser_log)
            .unwrap_or_default()
            .lines()
            .map(str::to_owned)
            .collect()
    }

    fn remote_token(&self, env: &TestEnv) -> Option<String> {
        fs::read_to_string(self.token_dir(env).join("token"))
            .ok()
            .map(|token| token.trim().to_owned())
    }
}

#[test]
fn copies_every_environment_without_opening_browser() {
    let h = Harness::new();
    h.write_session(&DEV, "dev-token", 7230);
    h.write_session(&PROD, ACCESS_TOKEN, 7230);
    let output = h.run(&[]);
    let (out, err) = text(&output);
    assert!(output.status.success(), "{err}");
    assert_eq!(h.remote_token(&DEV).as_deref(), Some("dev-token"));
    assert_eq!(h.remote_token(&PROD).as_deref(), Some(ACCESS_TOKEN));
    assert!(h.opened().is_empty());
    for env in [&DEV, &PROD] {
        assert!(
            out.contains(&format!(
                "Copied the {} token for person@example.com to fakehost (expires in 2h 00m)",
                env.name
            )),
            "{out}"
        );
        assert!(
            out.contains(&format!(
                "export ACCESS_TOKEN=$(cat {}/token)",
                h.token_dir(env).display()
            )),
            "{out}"
        );
    }
    assert!(out.find("Copied the dev").unwrap() < out.find("Copied the prod").unwrap());
    assert!(!out.contains(ACCESS_TOKEN) && !err.contains(ACCESS_TOKEN));

    let stored: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(h.token_dir(&PROD).join("token.json")).unwrap())
            .unwrap();
    assert_eq!(stored["access_token"], ACCESS_TOKEN);
    assert_eq!(stored["issuer"], PROD.issuer);
    for secret in ["refresh_token", "id_token", "user", "profile"] {
        assert!(
            stored.get(secret).is_none(),
            "{secret} leaked to the remote"
        );
    }
    for name in ["token", "token.json"] {
        let mode = fs::metadata(h.token_dir(&PROD).join(name))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }
}

#[test]
fn env_flag_copies_only_that_environment() {
    let h = Harness::new();
    h.write_session(&DEV, "dev-token", 7230);
    h.write_session(&PROD, ACCESS_TOKEN, 7230);
    let output = h.run(&["--env", "prod"]);
    let (out, err) = text(&output);
    assert!(output.status.success(), "{err}");
    assert_eq!(h.remote_token(&PROD).as_deref(), Some(ACCESS_TOKEN));
    assert_eq!(h.remote_token(&DEV), None);
    assert!(!out.contains("Copied the dev"), "{out}");
}

#[test]
fn stale_environment_is_renewed_while_fresh_one_is_copied() {
    let h = Harness::new();
    h.write_session(&DEV, "stale", 60);
    h.write_session(&PROD, ACCESS_TOKEN, 7230);
    let renewer = h.renew_when_opened(&DEV, "renewed-dev");
    let output = h.run(&[]);
    let (out, err) = text(&output);
    assert!(renewer.join().unwrap(), "dev web app was never opened");
    assert!(output.status.success(), "{err}");
    assert_eq!(h.opened(), [DEV.app_url]);
    assert!(
        out.contains(&format!("Opened {} (dev) in fake-browser", DEV.app_url)),
        "{out}"
    );
    assert_eq!(h.remote_token(&DEV).as_deref(), Some("renewed-dev"));
    assert_eq!(h.remote_token(&PROD).as_deref(), Some(ACCESS_TOKEN));
}

#[test]
fn stale_environments_are_opened_together() {
    let h = Harness::new();
    let dev = h.renew_when_opened(&DEV, "renewed-dev");
    let prod = h.renew_when_opened(&PROD, "renewed-prod");
    let started = Instant::now();
    let output = h.run(&[]);
    assert!(dev.join().unwrap() && prod.join().unwrap());
    assert!(output.status.success(), "{}", text(&output).1);
    assert_eq!(h.opened(), [DEV.app_url, PROD.app_url]);
    assert_eq!(h.remote_token(&DEV).as_deref(), Some("renewed-dev"));
    assert_eq!(h.remote_token(&PROD).as_deref(), Some("renewed-prod"));
    assert!(started.elapsed() < Duration::from_secs(10));
}

#[test]
fn force_open_waits_for_a_newer_token() {
    let h = Harness::new();
    h.write_session(&PROD, ACCESS_TOKEN, 7200);
    let renewer = h.renew_when_opened(&PROD, "renewed-prod");
    let output = h.run(&["--env", "prod", "--force-open"]);
    assert!(renewer.join().unwrap());
    assert!(output.status.success(), "{}", text(&output).1);
    assert_eq!(h.remote_token(&PROD).as_deref(), Some("renewed-prod"));
}

#[test]
fn no_browser_reports_missing_stale_and_expired_sessions() {
    let h = Harness::new();
    let (_, err) = text(&h.run(&["--env", "prod", "--no-browser"]));
    assert!(err.contains("prod: no session found"), "{err}");
    h.write_session(&PROD, ACCESS_TOKEN, 330);
    let (_, err) = text(&h.run(&["--env", "prod", "--no-browser"]));
    assert!(
        err.contains("prod: the token in the browser expires in 0h 05m"),
        "{err}"
    );
    h.write_session(&PROD, ACCESS_TOKEN, -10);
    let output = h.run(&["--env", "prod", "--no-browser"]);
    let (_, err) = text(&output);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        err.contains("the token in the browser has expired"),
        "{err}"
    );
    assert!(h.opened().is_empty());
    assert_eq!(h.remote_token(&PROD), None);
}

#[test]
fn one_failing_environment_does_not_block_the_others() {
    let h = Harness::new();
    h.write_session(&PROD, ACCESS_TOKEN, 7230);
    let output = h.run(&["--no-browser"]);
    let (out, err) = text(&output);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(h.remote_token(&PROD).as_deref(), Some(ACCESS_TOKEN));
    assert_eq!(h.remote_token(&DEV), None);
    assert!(out.contains("Copied the prod token"), "{out}");
    assert!(
        err.contains("1 of 2 environments failed:\ndev: no session found"),
        "{err}"
    );
}

#[test]
fn times_out_when_web_app_never_renews() {
    let h = Harness::new();
    h.write_session(&PROD, ACCESS_TOKEN, 60);
    let output = h.run(&["--env", "prod", "--wait", "1"]);
    let (_, err) = text(&output);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        err.contains("prod: timed out after 1s waiting for a renewed session"),
        "{err}"
    );
    assert!(err.contains(PROD.app_url), "{err}");
}

#[test]
fn remote_failure_is_reported_with_token_redacted() {
    let h = Harness::new();
    h.write_session(&PROD, ACCESS_TOKEN, 7200);
    write_executable(
        &h.bin.join("ssh"),
        "#!/bin/sh\ncat\necho 'remote exploded' >&2\nexit 255\n",
    );
    let output = h.run(&["--env", "prod"]);
    let (_, err) = text(&output);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        err.contains("copying the token to fakehost failed"),
        "{err}"
    );
    assert!(err.contains("remote exploded"), "{err}");
    assert!(err.contains("<redacted-token>"), "{err}");
    assert!(!err.contains(ACCESS_TOKEN), "{err}");
}

#[test]
fn command_line_overrides_config() {
    let h = Harness::new();
    h.write_session(&PROD, ACCESS_TOKEN, 7200);
    let output = h.run(&["otherhost", "--env", "prod"]);
    assert!(output.status.success());
    assert!(text(&output).0.contains("to otherhost"));
    let output = h.run(&["--env", "prod", "--", "-oProxyCommand=x"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(text(&output).1.contains("invalid SSH destination"));
}

#[test]
fn config_errors_are_explained() {
    let h = Harness::new();
    let (_, err) = text(&h.run(&["--env", "staging"]));
    assert!(
        err.contains("unknown environment \"staging\"; the config defines: dev, prod"),
        "{err}"
    );

    let missing = h.root.join("missing.json");
    let (_, err) = text(&h.run(&["--config", missing.to_str().unwrap()]));
    assert!(
        err.contains(&format!("could not read config {}", missing.display())),
        "{err}"
    );

    h.write_config(serde_json::json!({"environments": {}}));
    let (_, err) = text(&h.run(&[]));
    assert!(
        err.contains("must define at least one environment"),
        "{err}"
    );

    // Configs written for the single-environment version fail loudly.
    h.write_config(serde_json::json!({"default_env": "prod"}));
    let (_, err) = text(&h.run(&[]));
    assert!(err.contains("unknown field `default_env`"), "{err}");

    fs::write(h.config_path(), "{").unwrap();
    let (_, err) = text(&h.run(&[]));
    assert!(err.contains("could not parse config"), "{err}");
}
