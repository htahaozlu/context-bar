//! `context-bar-server` — self-hosted sync backend for the ContextBar
//! menubar app.
//!
//! ## Why this exists
//! The user owns multiple Macs (e.g. office + home) and wants their 30-day
//! usage rollups combined into a single "Across your Macs" view in the
//! menubar. The app is local-first (no third-party cloud), so the only
//! acceptable way to combine data is a server the user already controls —
//! a Raspberry Pi, a NAS, a homelab box, etc.
//!
//! ## What it does
//! 1. Each Mac `POST`s its per-machine rollup once a minute (or on demand).
//!    The server atomically upserts the row in its SQLite DB.
//! 2. Any Mac can `GET` every other Mac's rollup. The menubar app merges
//!    these into the local DB to power the combined-view tile.
//! 3. A static Bearer token guards both endpoints. The token is generated
//!    on first launch and printed to the logs (and saved to a file the
//!    user can read).
//!
//! ## What it explicitly does NOT do
//!  * No TLS — the server is meant to be on a LAN. Front it with a
//!    reverse proxy + Let's Encrypt if you want remote access.
//!  * No multi-user / no per-user data — the rollup is an aggregate.
//!    Nothing in the schema is attributable to a human.
//!  * No retention policy beyond the SQLite file — `DELETE FROM rollups
//!    WHERE last_seen < ?` is left to the operator (or a cron job).
//!
//! ## Run
//!     $ cargo run --release -p context-bar-server -- --bind 0.0.0.0:7878

use clap::Parser;
use context_bar_server::{auth, db, http};
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Parser, Debug)]
#[command(name = "context-bar-server", version, about, long_about = None)]
struct Args {
    /// Address:port to bind. Default 0.0.0.0:7878 (all interfaces).
    #[arg(long, default_value = "0.0.0.0:7878")]
    bind: String,

    /// Path to the SQLite database. Default ~/.context-bar-server/db.sqlite.
    /// The directory is created on first run.
    #[arg(long, value_parser = clap::value_parser!(PathBuf), default_value_os_t = default_db_path())]
    db: PathBuf,

    /// Path to the token file. Default ~/.context-bar-server/token.
    /// The token is generated on first run and never overwritten.
    #[arg(long, value_parser = clap::value_parser!(PathBuf), default_value_os_t = default_token_path())]
    token: PathBuf,

    /// Override the stored token with this value. Useful for restoring a
    /// token from backup or rotating. Skips the file write.
    #[arg(long)]
    token_set: Option<String>,
}

fn default_db_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".context-bar-server").join("db.sqlite")
}
fn default_token_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".context-bar-server").join("token")
}

fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    let args = Args::parse();

    if let Some(parent) = args.db.parent() {
        std::fs::create_dir_all(parent)?;
    }
    if let Some(parent) = args.token.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Token bootstrap — first launch writes a fresh token to disk; subsequent
    // launches reuse the same one so the user only has to paste it into the
    // menubar app once. `--token-set` lets an operator rotate without
    // touching the file directly.
    let token = if let Some(t) = args.token_set.as_deref() {
        t.to_string()
    } else if args.token.exists() {
        std::fs::read_to_string(&args.token)?.trim().to_string()
    } else {
        let t = auth::generate_token();
        std::fs::write(&args.token, &t)?;
        log::info!("Generated new token (saved to {:?})", args.token);
        log::info!("Token: {}", t);
        t
    };
    if token.len() < 16 {
        anyhow::bail!("Refusing to start: token too short (min 16 chars). Pass --token-set to override.");
    }

    let db = Arc::new(db::Db::open(&args.db)?);
    db.migrate()?;
    log::info!("DB ready at {:?}", args.db);
    log::info!("Listening on http://{}", args.bind);

    let state = http::State { db, token: Arc::new(token) };
    http::serve(&args.bind, state)
}
