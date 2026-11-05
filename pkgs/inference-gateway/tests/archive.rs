use anyhow::Result;
use arrow_array::{Array, StringArray};
use fs2::FileExt;
use inference_gateway::{
    archive::{export, export_batch},
    journal::{Event, Journal, recover},
};
use parquet::{arrow::arrow_reader::ParquetRecordBatchReaderBuilder, basic::Compression};
use serde_json::{Value, json};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    time::Duration,
};

fn parquet_paths(root: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    if root.join("parquet").exists() {
        for day in fs::read_dir(root.join("parquet"))? {
            for entry in fs::read_dir(day?.path())? {
                let path = entry?.path();
                if path.extension().is_some_and(|x| x == "parquet") {
                    files.push(path);
                }
            }
        }
    }
    Ok(files)
}

#[test]
fn imports_python_journals_recovers_torn_tail_and_writes_compatible_zstd_parquet() -> Result<()> {
    let root = tempfile::tempdir()?;
    fs::create_dir(root.path().join("journal"))?;
    // This is the original Python envelope, including opaque JSON and timestamp.
    let legacy = r#"{"schema_version":1,"event_id":"legacy:0","request_id":"legacy","sequence":0,"timestamp":"2026-11-05T01:02:03.123456+00:00","route":"phala","client":"hermes","kind":"request","data_json":"{\"model\":\"deepseek-test\",\"body_base64\":\"aGVsbG8=\"}"}"#;
    let path = root.path().join("journal/2026-11-05-legacy.open");
    fs::write(&path, format!("{legacy}\n{{\"torn\":"))?;
    recover(&root.path().join("journal"))?;
    export(root.path())?;
    let files = parquet_paths(root.path())?;
    assert_eq!(files.len(), 1);
    let reader = ParquetRecordBatchReaderBuilder::try_new(File::open(&files[0])?)?;
    assert_eq!(reader.metadata().file_metadata().num_rows(), 2);
    assert!(matches!(
        reader.metadata().row_group(0).column(0).compression(),
        Compression::ZSTD(_)
    ));
    let batch = reader.build()?.next().unwrap()?;
    assert_eq!(batch.schema().fields().len(), 9);
    let strings = |name| {
        batch
            .column_by_name(name)
            .unwrap()
            .as_any()
            .downcast_ref::<StringArray>()
            .unwrap()
    };
    assert_eq!(strings("event_id").value(0), "legacy:0");
    assert_eq!(strings("event_id").value(1), "legacy:1");
    assert_eq!(
        strings("timestamp").value(0),
        "2026-11-05T01:02:03.123456+00:00"
    );
    assert_eq!(strings("kind").value(1), "recovered");
    assert_eq!(
        serde_json::from_str::<Value>(strings("data_json").value(1))?["audit_state"],
        "unavailable"
    );
    export(root.path())?;
    assert_eq!(parquet_paths(root.path())?.len(), 1);
    Ok(())
}

#[test]
fn published_batch_is_not_duplicated_when_cleanup_was_interrupted() -> Result<()> {
    let root = tempfile::tempdir()?;
    let journals = root.path().join("journal");
    let mut journal = Journal::new(&journals, "openai", "test")?;
    journal.emit("request", json!({"model": "example"}))?;
    journal.close()?;
    let original = fs::read_dir(&journals)?.next().unwrap()?.path();
    let contents = fs::read(&original)?;
    export(root.path())?;
    let output = parquet_paths(root.path())?.remove(0);
    let day = output
        .parent()
        .unwrap()
        .file_name()
        .unwrap()
        .to_str()
        .unwrap()
        .strip_prefix("date=")
        .unwrap();
    let batch = root.path().join("batches").join(format!(
        "{day}_{}",
        output.file_stem().unwrap().to_str().unwrap()
    ));
    fs::create_dir(&batch)?;
    fs::write(batch.join(original.file_name().unwrap()), contents)?;
    export(root.path())?;
    assert!(!batch.exists());
    assert_eq!(parquet_paths(root.path())?.len(), 1);
    assert_eq!(
        ParquetRecordBatchReaderBuilder::try_new(File::open(output)?)?
            .metadata()
            .file_metadata()
            .num_rows(),
        1
    );
    Ok(())
}

#[test]
fn invalid_input_keeps_its_batch_until_a_retry_succeeds() -> Result<()> {
    let root = tempfile::tempdir()?;
    let journals = root.path().join("journal");
    let mut journal = Journal::new(&journals, "phala", "test")?;
    journal.emit("request", json!({"model": "example"}))?;
    journal.close()?;
    let original = fs::read_dir(&journals)?.next().unwrap()?.path();
    let contents = fs::read(&original)?;
    fs::write(&original, b"invalid json\n")?;
    assert!(export(root.path()).is_err());
    assert!(parquet_paths(root.path())?.is_empty());
    let batch = fs::read_dir(root.path().join("batches"))?
        .next()
        .unwrap()?
        .path();
    fs::write(batch.join(original.file_name().unwrap()), contents)?;
    export(root.path())?;
    assert_eq!(parquet_paths(root.path())?.len(), 1);
    Ok(())
}

#[test]
fn exporter_waits_for_the_backup_shared_lock() -> Result<()> {
    let root = tempfile::tempdir()?;
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(root.path().join("export.lock"))?;
    FileExt::lock_shared(&lock)?;
    let path = root.path().to_owned();
    let (tx, rx) = std::sync::mpsc::channel();
    let thread = std::thread::spawn(move || {
        let result = export(&path);
        tx.send(result).unwrap();
    });
    assert!(rx.recv_timeout(Duration::from_millis(50)).is_err());
    FileExt::unlock(&lock)?;
    rx.recv_timeout(Duration::from_secs(5))??;
    thread.join().unwrap();
    Ok(())
}

#[test]
fn recovery_preserves_complete_events_with_a_partial_final_utf8_character() -> Result<()> {
    let root = tempfile::tempdir()?;
    let mut journal = Journal::new(root.path(), "phala", "test")?;
    journal.emit("request", json!({"message": "hello 🌍"}))?;
    drop(journal);
    let path = fs::read_dir(root.path())?.next().unwrap()?.path();
    OpenOptions::new()
        .append(true)
        .open(path)?
        .write_all(b"{\"partial\":\"\xf0\x9f")?;
    recover(root.path())?;
    let sealed = fs::read_dir(root.path())?.next().unwrap()?.path();
    let rows: Vec<Event> = fs::read_to_string(sealed)?
        .lines()
        .map(serde_json::from_str)
        .collect::<std::result::Result<_, _>>()?;
    assert_eq!(rows.len(), 2);
    assert_eq!(
        serde_json::from_str::<Value>(&rows[0].data_json)?["message"],
        "hello 🌍"
    );
    Ok(())
}

#[test]
fn empty_journal_directory_does_not_create_parquet() -> Result<()> {
    let root = tempfile::tempdir()?;
    export(root.path())?;
    assert!(parquet_paths(root.path())?.is_empty());
    // An empty batch left by a crash is also safe to commit and clean up.
    let batch = root.path().join("batches/2026-11-05_empty");
    fs::create_dir(&batch)?;
    export_batch(root.path(), &batch)?;
    assert!(!batch.exists());
    Ok(())
}
