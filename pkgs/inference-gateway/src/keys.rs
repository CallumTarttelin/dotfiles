//! Root-managed, hash-only client keys. Atomic snapshots are reloaded per request.
use crate::journal::{now, sync_dir};
use crate::provision::digest;
use anyhow::{Context, Result, ensure};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use fs2::FileExt;
use nix::unistd::{Gid, Uid, chown};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::Path,
};
use subtle::ConstantTimeEq;
use uuid::Uuid;

pub const DEFAULT_REGISTRY: &str = "/var/lib/inference-client-keys/keys.json";

#[derive(Clone, Serialize, Deserialize)]
pub struct Key {
    pub id: String,
    pub name: String,
    pub sha256: String,
    pub routes: Vec<String>,
    pub created_at: String,
    pub revoked_at: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct Registry {
    version: u32,
    pub keys: Vec<Key>,
}

pub fn load(path: &Path) -> Result<Registry> {
    let registry: Registry = serde_json::from_slice(&fs::read(path)?)?;
    ensure!(
        registry.version == 1,
        "unsupported client-key registry version"
    );
    for key in &registry.keys {
        ensure!(
            key.sha256.len() == 64 && key.sha256.bytes().all(|b| b.is_ascii_hexdigit()),
            "invalid client-key digest"
        );
        validate_routes(&key.routes)?;
    }
    Ok(registry)
}

impl Registry {
    pub fn authenticate(&self, hashed: &str) -> Option<&Key> {
        self.keys.iter().find(|key| {
            key.revoked_at.is_none() && bool::from(hashed.as_bytes().ct_eq(key.sha256.as_bytes()))
        })
    }
}

fn lock(path: &Path) -> Result<File> {
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .mode(0o600)
        .open(path.with_extension("lock"))?;
    file.lock_exclusive()?;
    Ok(file)
}

fn save(path: &Path, registry: &Registry) -> Result<()> {
    let parent = path.parent().context("registry directory missing")?;
    let metadata = fs::metadata(parent)?;
    let temporary = path.with_extension("tmp");
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)?;
    serde_json::to_writer_pretty(&mut file, registry)?;
    file.write_all(b"\n")?;
    chown(
        &temporary,
        Some(Uid::from_raw(metadata.uid())),
        Some(Gid::from_raw(metadata.gid())),
    )?;
    file.set_permissions(fs::Permissions::from_mode(0o640))?;
    file.sync_all()?;
    fs::rename(temporary, path)?;
    sync_dir(parent)
}

pub fn initialize(path: &Path, group: Gid, bootstrap: Vec<Key>) -> Result<()> {
    let parent = path.parent().context("registry directory missing")?;
    fs::create_dir_all(parent)?;
    chown(parent, Some(Uid::current()), Some(group))?;
    fs::set_permissions(parent, fs::Permissions::from_mode(0o750))?;
    let _lock = lock(path)?;
    if path.exists() {
        let mut registry = load(path)?;
        let mut changed = false;
        for key in bootstrap {
            // Add new service identities on upgrades; never reactivate a tombstone.
            if registry.keys.iter().any(|existing| existing.id == key.id) {
                continue;
            }
            ensure!(
                !registry
                    .keys
                    .iter()
                    .any(|existing| existing.name == key.name),
                "service key name already belongs to another key: {}",
                key.name
            );
            registry.keys.push(key);
            changed = true;
        }
        if changed {
            save(path, &registry)?;
        }
    } else {
        save(
            path,
            &Registry {
                version: 1,
                keys: bootstrap,
            },
        )?;
    }
    Ok(())
}

pub fn bootstrap(id: &str, token: &str, routes: Vec<String>) -> Key {
    Key {
        id: id.into(),
        name: id.into(),
        sha256: digest(token),
        routes,
        created_at: now(),
        revoked_at: None,
    }
}

fn validate_routes(routes: &[String]) -> Result<()> {
    ensure!(
        !routes.is_empty()
            && routes
                .iter()
                .all(|r| matches!(r.as_str(), "phala" | "openai")),
        "routes must be phala or openai"
    );
    Ok(())
}

/// Returns the plaintext token exactly once to the administrative caller.
pub fn create(path: &Path, name: &str, mut routes: Vec<String>) -> Result<(Key, String)> {
    ensure!(
        !name.is_empty()
            && name.len() <= 64
            && name
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b)),
        "name must be 1–64 letters, digits, dots, underscores or hyphens"
    );
    validate_routes(&routes)?;
    routes.sort();
    routes.dedup();
    let _lock = lock(path)?;
    let mut registry = load(path)?;
    ensure!(
        !registry.keys.iter().any(|key| key.name == name),
        "key name already exists; use a new name when rotating"
    );
    let mut random = [0u8; 48];
    getrandom::fill(&mut random).map_err(|_| anyhow::anyhow!("operating system RNG failed"))?;
    let token = format!("igw_{}", URL_SAFE_NO_PAD.encode(random));
    let key = Key {
        id: Uuid::new_v4().simple().to_string(),
        name: name.into(),
        sha256: digest(&token),
        routes,
        created_at: now(),
        revoked_at: None,
    };
    registry.keys.push(key.clone());
    save(path, &registry)?;
    Ok((key, token))
}

pub fn revoke(path: &Path, id_or_name: &str) -> Result<Key> {
    let _lock = lock(path)?;
    let mut registry = load(path)?;
    let index = registry
        .keys
        .iter()
        .position(|key| key.id == id_or_name)
        .or_else(|| registry.keys.iter().position(|key| key.name == id_or_name))
        .context("client key not found")?;
    let key = &mut registry.keys[index];
    if key.revoked_at.is_none() {
        key.revoked_at = Some(now());
    }
    let result = key.clone();
    save(path, &registry)?;
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn creates_scopes_revokes_and_never_stores_plaintext() -> Result<()> {
        let root = tempfile::tempdir()?;
        let path = root.path().join("registry/keys.json");
        initialize(
            &path,
            Gid::current(),
            vec![bootstrap("hermes", "system-token", vec!["phala".into()])],
        )?;
        let (key, token) = create(&path, "laptop", vec!["phala".into()])?;
        let registry = load(&path)?;
        assert_eq!(registry.authenticate(&digest(&token)).unwrap().id, key.id);
        assert_eq!(
            registry.authenticate(&digest(&token)).unwrap().routes,
            vec!["phala"]
        );
        assert!(!fs::read_to_string(&path)?.contains(&token));
        revoke(&path, &key.id)?;
        assert!(load(&path)?.authenticate(&digest(&token)).is_none());
        revoke(&path, "hermes")?;
        initialize(
            &path,
            Gid::current(),
            vec![bootstrap("hermes", "system-token", vec!["phala".into()])],
        )?;
        assert!(load(&path)?.authenticate(&digest("system-token")).is_none());
        assert!(create(&path, "laptop", vec!["phala".into()]).is_err());
        assert!(create(&path, "bad", vec!["anything".into()]).is_err());
        assert_eq!(fs::metadata(&path)?.permissions().mode() & 0o777, 0o640);
        assert_eq!(
            fs::metadata(path.parent().unwrap())?.permissions().mode() & 0o777,
            0o750
        );
        Ok(())
    }

    #[test]
    fn concurrent_creations_do_not_lose_keys() -> Result<()> {
        let root = tempfile::tempdir()?;
        let path = root.path().join("registry/keys.json");
        initialize(&path, Gid::current(), vec![])?;
        let workers: Vec<_> = (0..8)
            .map(|i| {
                let path = path.clone();
                std::thread::spawn(move || {
                    create(&path, &format!("client-{i}"), vec!["phala".into()])
                })
            })
            .collect();
        for worker in workers {
            worker.join().unwrap()?;
        }
        assert_eq!(load(&path)?.keys.len(), 8);
        Ok(())
    }

    #[test]
    fn upgrades_add_service_keys_without_restoring_revoked_keys() -> Result<()> {
        let root = tempfile::tempdir()?;
        let path = root.path().join("registry/keys.json");
        let old = bootstrap("hermes", "private-token", vec!["phala".into()]);
        initialize(&path, Gid::current(), vec![old.clone()])?;
        revoke(&path, "hermes")?;
        let new = bootstrap("hermes-openai", "openai-token", vec!["openai".into()]);
        initialize(&path, Gid::current(), vec![old.clone(), new.clone()])?;
        let registry = load(&path)?;
        assert!(registry.authenticate(&digest("private-token")).is_none());
        assert_eq!(
            registry
                .authenticate(&digest("openai-token"))
                .unwrap()
                .routes,
            vec!["openai"]
        );
        revoke(&path, "hermes-openai")?;
        initialize(&path, Gid::current(), vec![old, new])?;
        let registry = load(&path)?;
        assert_eq!(registry.keys.len(), 2);
        assert!(registry.authenticate(&digest("openai-token")).is_none());
        Ok(())
    }
}
