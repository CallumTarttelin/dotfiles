use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;
#[derive(Parser)]
struct Args {
    #[arg(long)]
    state_dir: PathBuf,
}
fn main() -> Result<()> {
    inference_gateway::private_umask();
    inference_gateway::archive::export(&Args::parse().state_dir)
}
