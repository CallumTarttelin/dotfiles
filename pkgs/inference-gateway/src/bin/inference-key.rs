use anyhow::Result;
use clap::{Parser, Subcommand};
use inference_gateway::keys::{self, DEFAULT_REGISTRY, Key};
use serde_json::{Value, json};
use std::path::PathBuf;

#[derive(Parser)]
#[command(about = "Create, list and revoke inference gateway client keys")]
struct Args {
    #[arg(long, default_value = DEFAULT_REGISTRY)]
    registry: PathBuf,
    #[command(subcommand)]
    command: Command,
}
#[derive(Subcommand)]
enum Command {
    /// Prints the new API key once. Save it in your password manager.
    Create {
        #[arg(long)]
        name: String,
        #[arg(long = "route", default_value = "phala", value_parser = ["phala", "openai"])]
        routes: Vec<String>,
    },
    List,
    /// Blocks new requests immediately; requests already in flight may finish.
    Revoke {
        id_or_name: String,
    },
}
fn metadata(key: &Key) -> Value {
    json!({"id": key.id, "name": key.name, "routes": key.routes,
        "created_at": key.created_at, "revoked_at": key.revoked_at})
}
fn main() -> Result<()> {
    inference_gateway::private_umask();
    let args = Args::parse();
    let output = match args.command {
        Command::Create { name, routes } => {
            let (key, token) = keys::create(&args.registry, &name, routes)?;
            let mut value = metadata(&key);
            value["api_key"] = json!(token);
            value
        }
        Command::List => json!(
            keys::load(&args.registry)?
                .keys
                .iter()
                .map(metadata)
                .collect::<Vec<_>>()
        ),
        Command::Revoke { id_or_name } => metadata(&keys::revoke(&args.registry, &id_or_name)?),
    };
    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
}
