//! Version-1 JSONL journals, compatible with the original Python gateway.
use anyhow::{Context, Result};
use chrono::{SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Seek, SeekFrom, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone, Serialize, Deserialize)]
pub struct Event {
    pub schema_version: i32,
    pub event_id: String,
    pub request_id: String,
    pub sequence: i64,
    pub timestamp: String,
    pub route: String,
    pub client: String,
    pub kind: String,
    pub data_json: String,
}

pub fn now() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Micros, false)
}

pub fn private_dir(path: &Path) -> Result<()> {
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(path)?;
    Ok(())
}

pub fn sync_dir(path: &Path) -> Result<()> {
    File::open(path)?.sync_all()?;
    Ok(())
}

pub fn files_with_extension(root: &Path, extension: &str) -> Result<Vec<PathBuf>> {
    if !root.exists() {
        return Ok(vec![]);
    }
    let mut files = Vec::new();
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        if entry.file_type()?.is_file() && entry.path().extension().is_some_and(|x| x == extension)
        {
            files.push(entry.path());
        }
    }
    files.sort();
    Ok(files)
}

pub struct Journal {
    root: PathBuf,
    path: PathBuf,
    file: Option<File>,
    pub request_id: String,
    route: String,
    client: String,
    sequence: i64,
}

impl Journal {
    pub fn new(root: &Path, route: &str, client: &str) -> Result<Self> {
        private_dir(root)?;
        let request_id = Uuid::new_v4().simple().to_string();
        let path = root.join(format!("{}-{request_id}.open", &now()[..10]));
        let file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .open(&path)?;
        sync_dir(root)?;
        Ok(Self {
            root: root.into(),
            path,
            file: Some(file),
            request_id,
            route: route.into(),
            client: client.into(),
            sequence: 0,
        })
    }

    pub fn emit(&mut self, kind: &str, data: Value) -> Result<()> {
        let event = Event {
            schema_version: 1,
            event_id: format!("{}:{}", self.request_id, self.sequence),
            request_id: self.request_id.clone(),
            sequence: self.sequence,
            timestamp: now(),
            route: self.route.clone(),
            client: self.client.clone(),
            kind: kind.into(),
            data_json: serde_json::to_string(&data)?,
        };
        let file = self.file.as_mut().context("journal is closed")?;
        // One buffer prevents an intervening error leaving an unseparated JSON value.
        let mut bytes = serde_json::to_vec(&event)?;
        bytes.push(b'\n');
        file.write_all(&bytes)?;
        file.sync_all()?;
        self.sequence += 1;
        Ok(())
    }

    pub fn close(&mut self) -> Result<()> {
        if self.file.take().is_some() {
            fs::rename(&self.path, self.path.with_extension("jsonl"))?;
            sync_dir(&self.root)?;
        }
        Ok(())
    }
}

/// Disk operations run on Tokio's blocking pool, rather than its network workers.
#[derive(Clone)]
pub struct AsyncJournal {
    inner: Arc<Mutex<Journal>>,
    pub request_id: String,
}

impl AsyncJournal {
    pub async fn new(root: PathBuf, route: String, client: String) -> Result<Self> {
        let journal =
            tokio::task::spawn_blocking(move || Journal::new(&root, &route, &client)).await??;
        let request_id = journal.request_id.clone();
        Ok(Self {
            inner: Arc::new(Mutex::new(journal)),
            request_id,
        })
    }

    pub async fn emit(&self, kind: &str, data: Value) -> Result<()> {
        let inner = self.inner.clone();
        let kind = kind.to_owned();
        tokio::task::spawn_blocking(move || inner.lock().unwrap().emit(&kind, data)).await??;
        Ok(())
    }

    pub async fn close(&self) -> Result<()> {
        let inner = self.inner.clone();
        tokio::task::spawn_blocking(move || inner.lock().unwrap().close()).await??;
        Ok(())
    }
}

pub fn recover(root: &Path) -> Result<()> {
    private_dir(root)?;
    for path in files_with_extension(root, "open")? {
        let mut file = OpenOptions::new().read(true).write(true).open(&path)?;
        let mut reader = BufReader::new(&file);
        let (mut valid_end, mut last) = (0u64, None::<Event>);
        loop {
            let mut line = Vec::new();
            let len = reader.read_until(b'\n', &mut line)?;
            if len == 0 || line.last() != Some(&b'\n') {
                break;
            }
            let Ok(event) = serde_json::from_slice::<Event>(&line) else {
                break;
            };
            last = Some(event);
            valid_end += len as u64;
        }
        drop(reader);
        file.set_len(valid_end)?;
        file.seek(SeekFrom::Start(valid_end))?;
        if let Some(mut event) = last {
            event.sequence += 1;
            event.event_id = format!("{}:{}", event.request_id, event.sequence);
            event.timestamp = now();
            event.kind = "recovered".into();
            event.data_json = json!({
                "audit_state": if event.route == "phala" {"unavailable"} else {"not_applicable"},
                "reason": "unclean shutdown; request or audit may be incomplete"
            })
            .to_string();
            serde_json::to_writer(&mut file, &event)?;
            file.write_all(b"\n")?;
        }
        file.sync_all()?;
        drop(file);
        fs::rename(&path, path.with_extension("jsonl"))?;
    }
    sync_dir(root)
}
