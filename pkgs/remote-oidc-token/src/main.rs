use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use anyhow::{Context, Result};
use clap::Parser;
use remote_oidc_token::{CONFIG_ENV, Config, Options, default_config_path, run};

/// Copy an OIDC web app's access token from the work browser to a remote machine.
///
/// Hosts, browser profile, login issuer and storage locations come from a JSON
/// config file (see --config). On the remote, the token is stored in the
/// environment's token_dir as `token` (raw) and `token.json`.
#[derive(Parser)]
#[command(name = "remote-oidc-token", version)]
struct Cli {
    /// SSH destination (default: `host` from the config)
    host: Option<String>,
    /// Config file (default: $XDG_CONFIG_HOME/remote-oidc-token/config.json)
    #[arg(long, env = CONFIG_ENV, value_name = "PATH")]
    config: Option<PathBuf>,
    /// Copy only this environment from the config (default: every environment)
    #[arg(long, value_name = "NAME")]
    env: Option<String>,
    /// Firefox profile holding the web app session
    #[arg(long, env = "FIREFOX_WORK_PROFILE_PATH", value_name = "PATH")]
    profile: Option<PathBuf>,
    /// Browser used to open the web app for renewal
    #[arg(long, value_name = "EXECUTABLE")]
    browser: Option<String>,
    /// Never open the web app; fail if the token is missing or stale
    #[arg(long, conflicts_with = "force_open")]
    no_browser: bool,
    /// Open the web app and wait for a newer token even if the current one is fresh
    #[arg(long)]
    force_open: bool,
    /// Minimum remaining lifetime before the web app is opened to renew the token
    #[arg(long, value_name = "SECONDS")]
    min_valid: Option<u64>,
    /// How long to wait for the web app to renew the session
    #[arg(long, value_name = "SECONDS", value_parser = clap::value_parser!(u64).range(1..))]
    wait: Option<u64>,
}

fn options(cli: Cli) -> Result<Options> {
    let config_path = cli
        .config
        .or_else(default_config_path)
        .context("no config path: pass --config or set REMOTE_OIDC_TOKEN_CONFIG")?;
    let config = Config::load(&config_path)?;
    let mut opts = Options::from_config(&config, cli.env.as_deref())?;
    if let Some(host) = cli.host {
        opts.host = host;
    }
    if let Some(profile) = cli.profile {
        opts.profile = profile;
    }
    if let Some(browser) = cli.browser {
        opts.browser = browser;
    }
    if let Some(min_valid) = cli.min_valid {
        opts.min_valid = min_valid;
    }
    if let Some(wait) = cli.wait {
        opts.wait = Duration::from_secs(wait);
    }
    opts.no_browser = cli.no_browser;
    opts.force_open = cli.force_open;
    Ok(opts)
}

fn main() -> ExitCode {
    let result = options(Cli::parse()).and_then(|opts| run(&opts, &mut std::io::stdout()));
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("remote-oidc-token: {error:#}");
            ExitCode::FAILURE
        }
    }
}
