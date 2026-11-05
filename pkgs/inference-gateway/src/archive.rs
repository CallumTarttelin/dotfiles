//! Atomic journal batches -> Zstd Parquet, retaining the version-1 event schema.
use crate::journal::{Event, files_with_extension, private_dir, sync_dir};
use anyhow::{Context, Result, ensure};
use arrow_array::{ArrayRef, Int32Array, Int64Array, RecordBatch, StringArray};
use arrow_schema::{DataType, Field, Schema};
use fs2::FileExt;
use parquet::{arrow::ArrowWriter, basic::Compression, file::properties::WriterProperties};
use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::sync::Arc;
use uuid::Uuid;

fn schema() -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("schema_version", DataType::Int32, true),
        Field::new("event_id", DataType::Utf8, true),
        Field::new("request_id", DataType::Utf8, true),
        Field::new("sequence", DataType::Int64, true),
        Field::new("timestamp", DataType::Utf8, true),
        Field::new("route", DataType::Utf8, true),
        Field::new("client", DataType::Utf8, true),
        Field::new("kind", DataType::Utf8, true),
        Field::new("data_json", DataType::Utf8, true),
    ]))
}

fn record_batch(rows: &[Event]) -> Result<RecordBatch> {
    let strings = |field: fn(&Event) -> &str| -> ArrayRef {
        Arc::new(StringArray::from_iter_values(rows.iter().map(field)))
    };
    Ok(RecordBatch::try_new(
        schema(),
        vec![
            Arc::new(Int32Array::from_iter_values(
                rows.iter().map(|r| r.schema_version),
            )),
            strings(|r| &r.event_id),
            strings(|r| &r.request_id),
            Arc::new(Int64Array::from_iter_values(
                rows.iter().map(|r| r.sequence),
            )),
            strings(|r| &r.timestamp),
            strings(|r| &r.route),
            strings(|r| &r.client),
            strings(|r| &r.kind),
            strings(|r| &r.data_json),
        ],
    )?)
}

pub fn export_batch(root: &Path, batch: &Path) -> Result<()> {
    let name = batch
        .file_name()
        .and_then(|x| x.to_str())
        .context("invalid batch name")?;
    let (day, id) = name.split_once('_').context("invalid batch name")?;
    ensure!(day.len() == 10 && !id.is_empty(), "invalid batch name");
    let destination = root.join("parquet").join(format!("date={day}"));
    private_dir(&destination)?;
    sync_dir(root)?;
    sync_dir(&root.join("parquet"))?;
    sync_dir(&destination)?;
    let output = destination.join(format!("{id}.parquet"));
    // Existing output commits this entire batch, even if cleanup was interrupted.
    if !output.exists() {
        let temporary = output.with_extension("tmp");
        let file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&temporary)?;
        let properties = WriterProperties::builder()
            .set_compression(Compression::ZSTD(Default::default()))
            .set_max_row_group_row_count(Some(1024))
            .build();
        let mut writer = ArrowWriter::try_new(file, schema(), Some(properties))?;
        let (mut rows, mut size) = (Vec::new(), 0);
        for path in files_with_extension(batch, "jsonl")? {
            for line in BufReader::new(File::open(path)?).lines() {
                let line = line?;
                rows.push(serde_json::from_str::<Event>(&line)?);
                size += line.len();
                if rows.len() >= 1024 || size >= 8 * 1024 * 1024 {
                    writer.write(&record_batch(&rows)?)?;
                    writer.flush()?;
                    rows.clear();
                    size = 0;
                }
            }
        }
        if !rows.is_empty() {
            writer.write(&record_batch(&rows)?)?;
        }
        writer.close()?;
        File::open(&temporary)?.sync_all()?;
        fs::rename(&temporary, &output)?;
        sync_dir(&destination)?;
    }
    fs::remove_dir_all(batch)?;
    sync_dir(batch.parent().context("batch parent missing")?)
}

pub fn export(root: &Path) -> Result<()> {
    private_dir(root)?;
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .mode(0o600)
        .open(root.join("export.lock"))?;
    lock.lock_exclusive()?; // Same flock used by the restic wrapper.
    let batches = root.join("batches");
    private_dir(&batches)?;
    sync_dir(root)?;
    let mut pending = fs::read_dir(&batches)?.collect::<std::io::Result<Vec<_>>>()?;
    pending.sort_by_key(|e| e.path());
    for entry in pending {
        if entry.file_type()?.is_dir() {
            export_batch(root, &entry.path())?;
        }
    }
    let journals = root.join("journal");
    let mut days = BTreeMap::<String, Vec<_>>::new();
    for path in files_with_extension(&journals, "jsonl")? {
        let name = path
            .file_name()
            .and_then(|x| x.to_str())
            .context("invalid journal name")?;
        let day = name.get(..10).context("invalid journal name")?.to_owned();
        days.entry(day).or_default().push(path);
    }
    for (day, paths) in days {
        let batch = batches.join(format!("{day}_{}", Uuid::new_v4().simple()));
        private_dir(&batch)?;
        sync_dir(&batches)?;
        for path in paths {
            fs::rename(&path, batch.join(path.file_name().unwrap()))?;
        }
        sync_dir(&batch)?;
        sync_dir(&journals)?;
        export_batch(root, &batch)?;
    }
    Ok(())
}
