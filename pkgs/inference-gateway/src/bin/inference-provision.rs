use anyhow::Result;
use clap::Parser;
use inference_gateway::provision::{Spec, provision};
use std::path::PathBuf;
#[derive(Parser)]
struct Args {
    spec: PathBuf,
}
fn main() -> Result<()> {
    inference_gateway::private_umask();
    let spec: Spec = serde_json::from_slice(&std::fs::read(Args::parse().spec)?)?;
    provision(&spec)
}
