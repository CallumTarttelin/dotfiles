use anyhow::Result;
use clap::Parser;
use inference_gateway::{
    gateway::{Config, application},
    private_umask,
};
use std::{net::Ipv4Addr, path::PathBuf, time::Duration};
use tokio_util::sync::CancellationToken;
use tracing_subscriber::{
    fmt::{FmtContext, FormatEvent, FormatFields, format::Writer},
    registry::LookupSpan,
};

struct JournalFormat;
impl<S, N> FormatEvent<S, N> for JournalFormat
where
    S: tracing::Subscriber + for<'a> LookupSpan<'a>,
    N: for<'a> FormatFields<'a> + 'static,
{
    fn format_event(
        &self,
        ctx: &FmtContext<'_, S, N>,
        mut writer: Writer<'_>,
        event: &tracing::Event<'_>,
    ) -> std::fmt::Result {
        // journald parses this prefix; a textual "ERROR" on stdout is otherwise INFO.
        writer.write_str(match *event.metadata().level() {
            tracing::Level::ERROR => "<3>",
            tracing::Level::WARN => "<4>",
            tracing::Level::INFO => "<6>",
            _ => "<7>",
        })?;
        tracing_subscriber::fmt::format().format_event(ctx, writer, event)
    }
}

#[derive(Parser)]
struct Args {
    #[arg(long)]
    config: PathBuf,
    #[arg(long)]
    state_dir: PathBuf,
    #[arg(long, default_value_t = 8090)]
    port: u16,
}

async fn signal() {
    let mut terminate =
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).unwrap();
    tokio::select! { _ = tokio::signal::ctrl_c() => {}, _ = terminate.recv() => {} }
}

fn main() -> Result<()> {
    private_umask();
    tracing_subscriber::fmt()
        .with_env_filter("inference_gateway=info")
        .with_ansi(false)
        .event_format(JournalFormat)
        .init();
    let args = Args::parse();
    let config: Config = serde_json::from_slice(&std::fs::read(args.config)?)?;
    let (router, runtime) = application(config, &args.state_dir)?;
    tokio::runtime::Runtime::new()?.block_on(async {
        let listener = tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, args.port)).await?;
        let shutdown = CancellationToken::new();
        let trigger = shutdown.clone();
        tokio::spawn(async move {
            signal().await;
            trigger.cancel();
        });
        let server = axum::serve(listener, router)
            .with_graceful_shutdown(shutdown.clone().cancelled_owned())
            .into_future();
        tokio::pin!(server);
        tokio::select! {
            result = &mut server => { result?; },
            _ = shutdown.cancelled() => {
                match tokio::time::timeout(Duration::from_secs(100), &mut server).await {
                    Ok(result) => result?,
                    Err(_) => runtime.cancel(),
                }
            }
        }
        runtime.finish().await;
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::Write,
        sync::{Arc, Mutex},
    };
    #[derive(Clone, Default)]
    struct Buffer(Arc<Mutex<Vec<u8>>>);
    impl Write for Buffer {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for Buffer {
        type Writer = Self;
        fn make_writer(&'a self) -> Self {
            self.clone()
        }
    }
    #[test]
    fn emits_journal_priorities_without_binary_ansi_fields() {
        let buffer = Buffer::default();
        let subscriber = tracing_subscriber::fmt()
            .with_ansi(false)
            .event_format(JournalFormat)
            .with_writer(buffer.clone())
            .finish();
        tracing::subscriber::with_default(subscriber, || {
            tracing::error!("audit failed");
            tracing::warn!("retrying");
            tracing::info!("ready");
        });
        let output = String::from_utf8(buffer.0.lock().unwrap().clone()).unwrap();
        let lines: Vec<_> = output.lines().collect();
        assert_eq!(lines.len(), 3);
        for (line, priority) in lines.iter().zip(["<3>", "<4>", "<6>"]) {
            assert!(line.starts_with(priority));
        }
        assert!(!output.contains('\x1b'));
    }
}
