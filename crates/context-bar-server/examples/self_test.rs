//! End-to-end self-test: bootstrap a temp server, POST an ingest, GET the
//! rollups back, assert the data round-trips. Exits 0 on success.
//!
//!     $ cargo run --release -p context-bar-server --example self_test

use context_bar_server::test_support as ts;
use std::time::Duration;

fn main() -> anyhow::Result<()> {
    let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .try_init();

    // Pick an ephemeral port so two test runs (or two parallel CI jobs)
    // don't collide.
    let bind = "127.0.0.1:0".to_string();
    let server = ts::spawn(&bind)?;
    let base = server.base_url();
    let token = server.token();
    eprintln!("server up at {} (token={})", base, token);

    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()?;

    // Health is unauthenticated.
    let h: serde_json::Value = client.get(format!("{}/v1/health", base)).send()?.json()?;
    assert_eq!(h["ok"], serde_json::Value::Bool(true), "health: {}", h);

    // Ingest.
    let body = serde_json::json!({
        "schema": 2,
        "machine": "test-mac",
        "updated_at": "2025-06-11T10:00:00Z",
        "agents": {
            "Claude": { "tokens_30d": 12345, "cost_30d": 1.23, "subagent_tokens_30d": 100 },
            "Codex":  { "tokens_30d": 6789,  "cost_30d": 0.45, "subagent_tokens_30d": 50 }
        }
    });
    let r = client
        .post(format!("{}/v1/ingest", base))
        .bearer_auth(&token)
        .json(&body)
        .send()?;
    assert!(r.status().is_success(), "ingest failed: {} {:?}", r.status(), r.text());
    let v: serde_json::Value = r.json()?;
    assert_eq!(v["ok"], serde_json::Value::Bool(true));
    assert_eq!(v["ingested"], serde_json::Value::Number(2.into()));

    // Rollups.
    let r: serde_json::Value = client
        .get(format!("{}/v1/rollups", base))
        .bearer_auth(&token)
        .send()?
        .json()?;
    assert_eq!(r["ok"], serde_json::Value::Bool(true));
    let arr = r["rollups"].as_array().unwrap();
    assert_eq!(arr.len(), 2, "expected 2 rollups, got {}", arr.len());
    let machines = r["machines"].as_array().unwrap();
    assert!(machines.iter().any(|m| m == "test-mac"));

    // No-auth → 401.
    let r = client.get(format!("{}/v1/rollups", base)).send()?;
    assert_eq!(r.status(), reqwest::StatusCode::UNAUTHORIZED);

    // Wrong-auth → 401.
    let r = client
        .get(format!("{}/v1/rollups", base))
        .bearer_auth("wrong-token")
        .send()?;
    assert_eq!(r.status(), reqwest::StatusCode::UNAUTHORIZED);

    println!("OK — round-trip passed");
    server.cleanup();
    Ok(())
}
