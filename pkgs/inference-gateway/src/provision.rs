//! Root-only runtime credential generation. Nix sees paths, never token values.
use crate::journal::{private_dir, sync_dir};
use anyhow::{Context, Result, ensure};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use nix::unistd::{Gid, Uid, User, chown};
use serde::Deserialize;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

#[derive(Deserialize)]
pub struct Spec {
    pub credentials_dir: PathBuf,
    pub runtime_dir: PathBuf,
    pub phala_key_file: PathBuf,
    #[serde(default)]
    pub client_registry_file: Option<PathBuf>,
    pub operator: String,
    pub model: String,
}

pub fn digest(token: &str) -> String {
    format!("{:x}", Sha256::digest(token.as_bytes()))
}

fn write_owned(path: &Path, contents: &[u8], owner: (Uid, Gid)) -> Result<()> {
    let temporary = path.with_extension("tmp");
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)?;
    file.write_all(contents)?;
    file.sync_all()?;
    chown(&temporary, Some(owner.0), Some(owner.1))?;
    fs::set_permissions(&temporary, fs::Permissions::from_mode(0o400))?;
    fs::rename(&temporary, path)?;
    sync_dir(path.parent().context("runtime directory missing")?)
}

pub fn provision(spec: &Spec) -> Result<()> {
    provision_with_users(spec, |name| {
        let user =
            User::from_name(name)?.with_context(|| format!("service user {name} not found"))?;
        Ok((user.uid, user.gid))
    })
}

fn provision_with_users(spec: &Spec, user: impl Fn(&str) -> Result<(Uid, Gid)>) -> Result<()> {
    private_dir(&spec.credentials_dir)?;
    fs::create_dir_all(&spec.runtime_dir)?;
    fs::set_permissions(&spec.runtime_dir, fs::Permissions::from_mode(0o755))?;
    let mut tokens = BTreeMap::new();
    for name in ["hermes", "hermes-openai", "personal", "cliproxyapi"] {
        let path = spec.credentials_dir.join(name);
        if !path.exists() {
            let mut random = [0u8; 48];
            getrandom::fill(&mut random)
                .map_err(|_| anyhow::anyhow!("operating system RNG failed"))?;
            let temporary = path.with_extension("tmp");
            let mut file = OpenOptions::new()
                .create(true)
                .truncate(true)
                .write(true)
                .mode(0o600)
                .open(&temporary)?;
            file.write_all(URL_SAFE_NO_PAD.encode(random).as_bytes())?;
            file.sync_all()?;
            fs::rename(&temporary, &path)?;
            sync_dir(&spec.credentials_dir)?;
        }
        let token = fs::read_to_string(path)?.trim().to_owned();
        ensure!(
            !token.is_empty() && !token.chars().any(char::is_whitespace),
            "invalid persisted gateway token"
        );
        tokens.insert(name, token);
    }
    let phala = fs::read_to_string(&spec.phala_key_file)?.trim().to_owned();
    ensure!(
        !phala.is_empty() && !phala.chars().any(char::is_whitespace),
        "expected a nonempty raw Phala API key without whitespace"
    );
    if let Some(path) = &spec.client_registry_file {
        crate::keys::initialize(
            path,
            user("inference-gateway")?.1,
            vec![
                crate::keys::bootstrap("hermes", &tokens["hermes"], vec!["phala".into()]),
                crate::keys::bootstrap(
                    "hermes-openai",
                    &tokens["hermes-openai"],
                    vec!["openai".into()],
                ),
                crate::keys::bootstrap(
                    "personal",
                    &tokens["personal"],
                    vec!["phala".into(), "openai".into()],
                ),
            ],
        )?;
    }
    let config = json!({
        "client_keys_file": spec.client_registry_file,
        "clients": {
            "hermes": {"sha256": digest(&tokens["hermes"]), "routes": ["phala"]},
            "hermes-openai": {"sha256": digest(&tokens["hermes-openai"]), "routes": ["openai"]},
            "personal": {"sha256": digest(&tokens["personal"]), "routes": ["phala", "openai"]}
        },
        "routes": {
            "phala": {"url": "http://127.0.0.1:4180/v1", "token": phala, "models": [spec.model]},
            "openai": {"url": "http://127.0.0.1:8317/v1", "token": tokens["cliproxyapi"]}
        },
        "pap_control": "http://127.0.0.1:4183"
    });
    write_owned(
        &spec.runtime_dir.join("gateway.json"),
        &serde_json::to_vec(&config)?,
        user("inference-gateway")?,
    )?;
    write_owned(
        &spec.runtime_dir.join("hermes.env"),
        format!("OPENAI_API_KEY={}\n", tokens["hermes"]).as_bytes(),
        user("hermes")?,
    )?;
    write_owned(
        &spec.runtime_dir.join("hermes-openai.env"),
        format!("NIXIE_OPENAI_API_KEY={}\n", tokens["hermes-openai"]).as_bytes(),
        user("hermes")?,
    )?;
    write_owned(
        &spec.runtime_dir.join("personal-token"),
        format!("{}\n", tokens["personal"]).as_bytes(),
        user(&spec.operator)?,
    )?;
    let cpa = json!({
        "config-version": 8,
        "server": {"host": "127.0.0.1", "port": 8317},
        "access": {"api-keys": [tokens["cliproxyapi"]]},
        "oauth": {"auth-dir": "/var/lib/cliproxyapi/auth"},
        "management": {"secret-key": "", "disable-control-panel": true},
        "observability": {"logs": {"request-log": false, "debug": false}}
    });
    write_owned(
        &spec.runtime_dir.join("cliproxyapi.yaml"),
        &serde_json::to_vec(&cpa)?,
        user("cliproxyapi")?,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_existing_tokens_and_private_runtime_files() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let spec = Spec {
            credentials_dir: temp.path().join("credentials"),
            runtime_dir: temp.path().join("runtime"),
            phala_key_file: temp.path().join("phala-key"),
            client_registry_file: Some(temp.path().join("keys/keys.json")),
            operator: "operator".into(),
            model: "deepseek-test".into(),
        };
        private_dir(&spec.credentials_dir)?;
        fs::write(
            spec.credentials_dir.join("personal"),
            "existing-personal-token\n",
        )?;
        fs::write(&spec.phala_key_file, "phala-test-key\n")?;
        let users = |_: &str| Ok((Uid::current(), Gid::current()));
        provision_with_users(&spec, users)?;
        let first = fs::read(spec.runtime_dir.join("gateway.json"))?;
        provision_with_users(&spec, users)?;
        assert_eq!(first, fs::read(spec.runtime_dir.join("gateway.json"))?);
        assert_eq!(
            fs::read_to_string(spec.runtime_dir.join("personal-token"))?,
            "existing-personal-token\n"
        );
        for name in [
            "gateway.json",
            "hermes.env",
            "hermes-openai.env",
            "personal-token",
            "cliproxyapi.yaml",
        ] {
            assert_eq!(
                fs::metadata(spec.runtime_dir.join(name))?
                    .permissions()
                    .mode()
                    & 0o777,
                0o400
            );
        }
        let config: serde_json::Value = serde_json::from_slice(&first)?;
        assert_eq!(
            config["clients"]["personal"]["sha256"],
            digest("existing-personal-token")
        );
        assert_eq!(config["routes"]["phala"]["token"], "phala-test-key");
        let openai_env = fs::read_to_string(spec.runtime_dir.join("hermes-openai.env"))?;
        let openai_token = openai_env
            .trim()
            .strip_prefix("NIXIE_OPENAI_API_KEY=")
            .unwrap();
        assert_ne!(openai_token, "existing-personal-token");
        assert_eq!(
            config["clients"]["hermes-openai"]["sha256"],
            digest(openai_token)
        );
        assert_eq!(
            config["clients"]["hermes-openai"]["routes"],
            json!(["openai"])
        );
        let registry = crate::keys::load(spec.client_registry_file.as_ref().unwrap())?;
        assert_eq!(
            registry
                .authenticate(&digest("existing-personal-token"))
                .unwrap()
                .name,
            "personal"
        );
        crate::keys::revoke(spec.client_registry_file.as_ref().unwrap(), "personal")?;
        provision_with_users(&spec, users)?;
        assert!(
            crate::keys::load(spec.client_registry_file.as_ref().unwrap())?
                .authenticate(&digest("existing-personal-token"))
                .is_none()
        );
        assert!(
            !fs::read_to_string(spec.runtime_dir.join("hermes.env"))?.contains("phala-test-key")
        );
        Ok(())
    }
}
