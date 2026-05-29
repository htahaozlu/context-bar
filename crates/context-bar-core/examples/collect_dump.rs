//! Dev harness: dump the pure-Rust `collect_claude`/`collect_codex` snapshot as
//! JSON, for differential validation against the Python aggregator. Reads HOME
//! and an optional fixed `CONTEXTBAR_NOW` (epoch seconds) so both sides share a
//! clock. Not shipped — used by the slice-3 parity check.

use std::path::PathBuf;

fn main() {
    let home = PathBuf::from(std::env::var("HOME").expect("HOME"));
    let now: f64 = std::env::var("CONTEXTBAR_NOW")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or_else(|| {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs_f64()
        });

    let claude = context_bar_core::collect::collect_claude(&home, now);
    let codex = context_bar_core::collect::collect_codex(&home, now);
    let others = context_bar_core::others::collect_others(&home, now);
    let out = serde_json::json!({ "claude": claude, "codex": codex, "others": others });
    println!("{}", serde_json::to_string(&out).unwrap());
}
