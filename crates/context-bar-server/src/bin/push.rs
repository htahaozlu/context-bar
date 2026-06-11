//! One-shot CLI to push this machine's current rollup to a server. Useful
//! for cron jobs or for testing the pipeline without the menubar app
//! running.
//!
//! Reads the same `~/.context-bar/context.json` the menubar reads,
//! extracts the 30-day per-agent totals, and POSTs them to the server
//! given by `--url`. Requires `--token` for the Bearer header.

use anyhow::{Context, Result};
use clap::Parser;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "context-bar-push", about = "Push this Mac's rollup to a context-bar-server")]
struct Args {
    /// Server base URL (e.g. http://home.local:7878)
    #[arg(short = 'u', long)]
    url: String,

    /// Bearer token
    #[arg(short = 't', long)]
    token: String,

    /// Override the snapshot path
    #[arg(long)]
    snapshot: Option<PathBuf>,

    /// Print the body that would be sent, then exit
    #[arg(short = 'n', long)]
    dry_run: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let path = args.snapshot.clone().unwrap_or_else(|| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        PathBuf::from(home).join(".context-bar").join("context.json")
    });
    let data = std::fs::read(&path).with_context(|| format!("read snapshot {:?}", path))?;
    let root: Value =
        serde_json::from_slice(&data).with_context(|| format!("parse snapshot {:?}", path))?;

    let mut agents = BTreeMap::new();
    for (key, name) in [("claude", "Claude"), ("codex", "Codex")] {
        let Some(a) = root.get(key).and_then(|v| v.as_object()) else {
            continue;
        };
        let t = a
            .get("total_tokens_30d")
            .and_then(|v| v.as_u64())
            .or_else(|| {
                a.get("total_tokens_30d")
                    .and_then(|v| v.as_f64())
                    .map(|f| f as u64)
            })
            .unwrap_or(0);
        let c = a
            .get("total_cost_30d")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let s = a
            .get("subagent_tokens_30d")
            .and_then(|v| v.as_u64())
            .or_else(|| {
                a.get("subagent_tokens_30d")
                    .and_then(|v| v.as_f64())
                    .map(|f| f as u64)
            })
            .unwrap_or(0);
        if t == 0 && c == 0.0 && s == 0 {
            continue;
        }
        agents.insert(
            name.to_string(),
            json!({ "tokens_30d": t, "cost_30d": c, "subagent_tokens_30d": s }),
        );
    }

    if agents.is_empty() {
        eprintln!("snapshot has no agents with 30-day data; nothing to push");
        std::process::exit(2);
    }

    let host = hostname();
    let body = json!({
        "schema": 2,
        "machine": host,
        "updated_at": now_iso8601(),
        "agents": agents,
    });
    let serialized = serde_json::to_string_pretty(&body)?;

    if args.dry_run {
        println!("{}", serialized);
        return Ok(());
    }

    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(8))
        .build()?;
    let url = format!("{}/v1/ingest", args.url.trim_end_matches('/'));
    let resp = client
        .post(&url)
        .bearer_auth(&args.token)
        .header("Content-Type", "application/json")
        .body(serialized)
        .send()
        .with_context(|| format!("POST {}", url))?;
    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        anyhow::bail!("server returned {}: {}", status, text);
    }
    println!("ok — {}", text);
    Ok(())
}

fn hostname() -> String {
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .unwrap_or_else(|_| "unknown".into())
}

fn now_iso8601() -> String {
    use time::format_description::well_known::Rfc3339;
    time::OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}
