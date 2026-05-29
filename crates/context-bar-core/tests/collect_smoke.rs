//! Committed regression test for slice 3 (`collect_claude` / `collect_codex`):
//! writes tiny synthetic transcripts to a temp HOME and asserts the extracted
//! token buckets + cost match hand-computed values. Runs in CI without Python
//! (the full byte-for-byte parity is validated separately against the Python on
//! real data; this guards the parse logic against regressions).

use std::fs;
use std::path::PathBuf;

use context_bar_core::collect::{collect_claude, collect_codex};
use context_bar_core::pricing::{fallback_table, match_pricing, turn_cost};
use time::format_description::well_known::Rfc3339;

fn epoch(rfc3339: &str) -> f64 {
    time::OffsetDateTime::parse(rfc3339, &Rfc3339)
        .unwrap()
        .unix_timestamp_nanos() as f64
        / 1e9
}

fn write(path: PathBuf, body: &str) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, body).unwrap();
}

#[test]
fn collect_claude_extracts_buckets_and_cost() {
    let home = std::env::temp_dir().join(format!("cb_claude_{}", std::process::id()));
    let _ = fs::remove_dir_all(&home);
    let ts = "2026-05-28T10:00:00.000Z";
    let line = serde_json::json!({
        "type": "assistant",
        "timestamp": ts,
        "cwd": "/work/alpha",
        "message": {
            "model": "claude-opus-4-8",
            "usage": {
                "input_tokens": 100,
                "cache_creation_input_tokens": 200,
                "cache_read_input_tokens": 1000,
                "output_tokens": 50
            }
        }
    });
    write(
        home.join(".claude/projects/alpha/sess.jsonl"),
        &line.to_string(),
    );

    let now = epoch(ts) + 300.0; // 5 minutes later — within all windows
    let out = collect_claude(&home, now, &fallback_table());

    // total = fresh_in + output = 150.
    assert_eq!(out.session_5h_tokens, 150);
    assert_eq!(out.week_7d_tokens, 150);
    assert_eq!(out.cache_read_tokens_5h, 1000);
    assert_eq!(out.total_tokens_30d, 150);
    assert_eq!(out.total_input_30d, 100);
    assert_eq!(out.total_output_30d, 50);

    let want_cost = turn_cost(match_pricing("claude-opus-4-8", &fallback_table()).as_ref(), 100, 200, 1000, 50);
    assert!((out.total_cost_30d - want_cost).abs() < 1e-9, "cost {} vs {}", out.total_cost_30d, want_cost);

    assert_eq!(out.recent_sessions.len(), 1);
    let r = &out.recent_sessions[0];
    assert_eq!(r.id, "sess");
    assert_eq!(r.model, "claude-opus-4-8");
    assert_eq!(r.project, "alpha");
    assert_eq!(r.input, 100);
    assert_eq!(r.output, 50);
    assert_eq!(r.cache_creation, 200);
    assert_eq!(r.cache_read, 1000);
    assert_eq!(r.started_at, "2026-05-28T10:00:00Z");

    let _ = fs::remove_dir_all(&home);
}

#[test]
fn collect_codex_subtracts_cached_input_and_bills_reasoning() {
    let home = std::env::temp_dir().join(format!("cb_codex_{}", std::process::id()));
    let _ = fs::remove_dir_all(&home);
    let ts = "2026-05-28T10:00:00.000Z";
    let ctx = serde_json::json!({
        "type": "turn_context",
        "payload": { "model": "gpt-5.5", "cwd": "/work/beta" }
    });
    let tok = serde_json::json!({
        "type": "event_msg",
        "timestamp": ts,
        "payload": {
            "type": "token_count",
            "info": {
                "model_context_window": 400000,
                "last_token_usage": {
                    "input_tokens": 1000,
                    "cached_input_tokens": 800,
                    "output_tokens": 50,
                    "reasoning_output_tokens": 10
                }
            }
        }
    });
    write(
        home.join(".codex/sessions/2026/05/sess.jsonl"),
        &format!("{}\n{}\n", ctx, tok),
    );

    let now = epoch(ts) + 300.0;
    let out = collect_codex(&home, now, &fallback_table());

    // fresh_in = 1000 - 800 = 200; billed_out = 50 + 10 = 60; total = 260.
    assert_eq!(out.session_5h_tokens, 260);
    assert_eq!(out.cache_read_tokens_5h, 800);
    assert_eq!(out.total_input_30d, 200);
    assert_eq!(out.total_output_30d, 60);

    let want_cost = turn_cost(match_pricing("gpt-5.5", &fallback_table()).as_ref(), 200, 0, 800, 60);
    assert!((out.total_cost_30d - want_cost).abs() < 1e-9);

    let r = &out.recent_sessions[0];
    assert_eq!(r.model, "gpt-5.5");
    assert_eq!(r.project, "beta");
    assert_eq!(r.cache_creation, 0);
    assert_eq!(out.last_context_window, Some(400_000));

    let _ = fs::remove_dir_all(&home);
}

#[test]
fn null_usage_records_zero_event_not_skipped() {
    // A Claude assistant turn with null usage must still produce a session
    // (Python's `usage or {}`), so it can act as a session boundary.
    let home = std::env::temp_dir().join(format!("cb_null_{}", std::process::id()));
    let _ = fs::remove_dir_all(&home);
    let l1 = serde_json::json!({
        "type": "assistant", "timestamp": "2026-05-28T10:00:00.000Z", "cwd": "/w",
        "message": {"model": "claude-opus-4-8", "usage": serde_json::Value::Null}
    });
    let l2 = serde_json::json!({
        "type": "assistant", "timestamp": "2026-05-28T10:01:00.000Z", "cwd": "/w",
        "message": {"model": "claude-opus-4-8", "usage": {"input_tokens": 10, "output_tokens": 5}}
    });
    write(
        home.join(".claude/projects/w/s.jsonl"),
        &format!("{}\n{}\n", l1, l2),
    );
    let now = epoch("2026-05-28T10:01:00.000Z") + 60.0;
    let out = collect_claude(&home, now, &fallback_table());
    // One session, two turns; tokens from the non-null turn only (15).
    assert_eq!(out.recent_sessions.len(), 1);
    assert_eq!(out.total_tokens_30d, 15);
    // started_at is the FIRST (null-usage) turn — proving it was recorded.
    assert_eq!(out.recent_sessions[0].started_at, "2026-05-28T10:00:00Z");
    let _ = fs::remove_dir_all(&home);
}
