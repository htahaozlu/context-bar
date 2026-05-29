//! Committed regression test for the slice-4 other-tool probes
//! (`probe_shell_history`, `probe_gemini_cli`). Synthetic fixtures with
//! hand-computed expectations — the live machine often has no such tools, so
//! the real-data diff alone can't exercise these.

use std::fs;

use context_bar_core::others::{collect_others, probe_gemini_cli, probe_shell_history};

#[test]
fn shell_history_counts_ai_tools_within_window() {
    let home = std::env::temp_dir().join(format!("cb_hist_{}", std::process::id()));
    let _ = fs::remove_dir_all(&home);
    fs::create_dir_all(&home).unwrap();
    let now = 1_780_000_000.0_f64; // cutoff = now - 7d = 1_779_395_200
    let hist = "\
: 1779999000:0;aider fix the bug
: 1779998000:0;sgpt \"hello\"
: 1779000000:0;mods old-and-excluded
: 1779999500:0;ls -la
: 1779999600:0;aider
";
    fs::write(home.join(".zsh_history"), hist).unwrap();

    let tools = probe_shell_history(&home, now);
    let by: std::collections::HashMap<_, _> =
        tools.iter().map(|t| (t.name.as_str(), t)).collect();
    // mods is older than 7d -> excluded; ls is not an AI tool.
    assert_eq!(tools.len(), 2, "got {:?}", tools.iter().map(|t| &t.name).collect::<Vec<_>>());
    assert_eq!(by["Aider"].sessions_7d, 2);
    assert_eq!(by["ShellGPT"].sessions_7d, 1);
    assert!(by["Aider"].last_used.is_some());
    assert!(!by.contains_key("Mods"));

    let _ = fs::remove_dir_all(&home);
}

#[test]
fn gemini_probe_sums_usage_metadata() {
    let home = std::env::temp_dir().join(format!("cb_gem_{}", std::process::id()));
    let _ = fs::remove_dir_all(&home);
    let dir = home.join(".gemini/sessions");
    fs::create_dir_all(&dir).unwrap();
    let body = format!(
        "{}\n{}\n",
        serde_json::json!({"usageMetadata": {"totalTokenCount": 100}, "timestamp": "2026-05-28T10:00:00Z", "model": "gemini-2.0"}),
        serde_json::json!({"usage": {"promptTokenCount": 10, "candidatesTokenCount": 5}}),
    );
    fs::write(dir.join("s.jsonl"), body).unwrap();

    // now = real time so the freshly-written file is within the 7d window.
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs_f64();
    let t = probe_gemini_cli(&home, now).expect("gemini probe should find the file");
    assert_eq!(t.name, "Gemini");
    assert_eq!(t.sessions_7d, 1);
    assert_eq!(t.tokens_7d, 115); // 100 + (10 + 5)
    assert_eq!(t.last_model.as_deref(), Some("gemini-2.0"));
    assert_eq!(t.last_used.as_deref(), Some("2026-05-28T10:00:00Z"));

    // collect_others includes it.
    let all = collect_others(&home, now);
    assert!(all.iter().any(|x| x.name == "Gemini"));

    let _ = fs::remove_dir_all(&home);
}
