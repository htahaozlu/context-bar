//! Other-AI-tool probes — part of slice 4 of the Python→Rust port (ROADMAP E1).
//! Ports `probe_gemini_cli`, `probe_aider`, `probe_shell_history`, and
//! `collect_others` from `usage_signal.py`. Native-only (reads `~/.gemini`,
//! `~/.aider`, `~/.zsh_history`). The `llm` CLI sqlite probe is intentionally
//! omitted (would pull a sqlite dependency for a niche tool) — documented gap.
//!
//! These populate the menubar's "Other AI Tools" section; restoring them is a
//! prerequisite for wiring `collect_native` to the Rust engine without a
//! regression.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::aggregate::iso_utc;
use crate::usage_signal::ToolSummary;

const WIN_WEEK: f64 = 7.0 * 86400.0;
const DAY: f64 = 86400.0;

fn empty_tool(name: &str) -> ToolSummary {
    ToolSummary {
        name: name.to_string(),
        ..Default::default()
    }
}

fn mtime_secs(path: &Path) -> Option<f64> {
    let m = std::fs::metadata(path).ok()?.modified().ok()?;
    Some(m.duration_since(std::time::UNIX_EPOCH).ok()?.as_secs_f64())
}

/// Collect `*.jsonl` (and optionally `*.yaml`) under `base`, recursively,
/// de-duplicated. `max_depth` bounds recursion.
fn collect_files(base: &Path, exts: &[&str], max_depth: usize, out: &mut BTreeSet<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(base) else { return };
    for entry in entries.flatten() {
        let Ok(ft) = entry.file_type() else { continue };
        if ft.is_symlink() {
            continue;
        }
        let path = entry.path();
        if ft.is_dir() {
            if max_depth > 0 {
                collect_files(&path, exts, max_depth - 1, out);
            }
        } else if ft.is_file() {
            if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
                if exts.contains(&ext) {
                    out.insert(path);
                }
            }
        }
    }
}

/// Google Gemini CLI — `~/.gemini/` JSONL sessions.
pub fn probe_gemini_cli(home: &Path, now: f64) -> Option<ToolSummary> {
    let candidates = [
        home.join(".gemini").join("sessions"),
        home.join(".gemini"),
        home.join(".config").join("gemini").join("sessions"),
    ];
    let base = candidates.iter().find(|d| d.is_dir())?;
    let mut files = BTreeSet::new();
    collect_files(base, &["jsonl"], 8, &mut files);

    let mut out = empty_tool("Gemini");
    let mut found = false;
    for path in &files {
        let Some(mtime) = mtime_secs(path) else { continue };
        if now - mtime > WIN_WEEK {
            continue;
        }
        found = true;
        out.sessions_7d += 1;
        let today = now - mtime <= DAY;
        if today {
            out.sessions_today += 1;
        }
        let Ok(content) = std::fs::read_to_string(path) else { continue };
        for line in content.lines() {
            let Ok(obj) = serde_json::from_str::<Value>(line) else { continue };
            let u = obj
                .get("usageMetadata")
                .or_else(|| obj.get("usage"))
                .filter(|v| v.is_object());
            if let Some(u) = u {
                let total = u.get("totalTokenCount").and_then(|v| v.as_u64()).unwrap_or_else(|| {
                    let p = u.get("promptTokenCount").and_then(|v| v.as_u64()).unwrap_or(0);
                    let c = u.get("candidatesTokenCount").and_then(|v| v.as_u64()).unwrap_or(0);
                    p + c
                });
                out.tokens_7d += total;
                if today {
                    out.tokens_today += total;
                }
            }
            if out.last_used.is_none() {
                if let Some(ts) = obj
                    .get("timestamp")
                    .or_else(|| obj.get("createTime"))
                    .and_then(|v| v.as_str())
                {
                    out.last_used = Some(ts.to_string());
                }
            }
            if out.last_model.is_none() {
                if let Some(m) = obj.get("model").and_then(|v| v.as_str()) {
                    out.last_model = Some(m.to_string());
                }
            }
        }
    }
    if found {
        Some(out)
    } else {
        None
    }
}

/// Aider — recent activity under `~/.aider/`.
pub fn probe_aider(home: &Path, now: f64) -> Option<ToolSummary> {
    let dir = home.join(".aider");
    if !dir.is_dir() {
        return None;
    }
    let mut files = BTreeSet::new();
    collect_files(&dir, &["jsonl", "yaml"], 8, &mut files);

    let mut recent: Vec<f64> = Vec::new();
    for path in &files {
        if let Some(mtime) = mtime_secs(path) {
            if now - mtime <= WIN_WEEK {
                recent.push(mtime);
            }
        }
    }
    if recent.is_empty() {
        return None;
    }
    recent.sort_by(|a, b| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));
    let mut out = empty_tool("Aider");
    out.sessions_7d = recent.len() as u64;
    out.sessions_today = recent.iter().filter(|&&m| now - m <= DAY).count() as u64;
    out.last_used = Some(iso_utc(recent[0]));
    Some(out)
}

/// AI CLIs detected in zsh history (binary, display-name).
const HISTORY_TOOLS: &[(&str, &str)] = &[
    ("aider", "Aider"),
    ("sgpt", "ShellGPT"),
    ("mods", "Mods"),
    ("fabric", "Fabric"),
    ("tgpt", "tGPT"),
    ("continue", "Continue"),
    ("copilot", "Copilot CLI"),
    ("gemini", "Gemini"),
    ("deepseek", "DeepSeek"),
    ("qwen", "Qwen"),
    ("minimax", "MiniMax"),
];

/// Scan the tail of `~/.zsh_history` (extended format) for AI CLI invocations in
/// the last 7 days.
pub fn probe_shell_history(home: &Path, now: f64) -> Vec<ToolSummary> {
    let path = home.join(".zsh_history");
    if !path.exists() {
        return Vec::new();
    }
    let cutoff = now - WIN_WEEK;
    // (display) -> (count, last_ts). Preserve first-seen order like Python's defaultdict.
    let mut order: Vec<&str> = Vec::new();
    let mut counts: std::collections::HashMap<&str, (u64, i64)> = Default::default();

    let bytes = match read_tail(&path, 2 * 1024 * 1024) {
        Some(b) => b,
        None => return Vec::new(),
    };
    let content = String::from_utf8_lossy(&bytes);
    let mut ts: Option<i64> = None;
    for line in content.lines() {
        let cmd: String;
        if let Some(rest) = line.strip_prefix(": ") {
            // ": <begin>:<elapsed>;<command>"
            if let Some((meta, c)) = rest.split_once(';') {
                // meta = "<begin>:<elapsed>"; ts = first field.
                ts = meta.split(':').next().and_then(|s| s.trim().parse::<i64>().ok());
                cmd = c.trim().to_string();
            } else {
                cmd = String::new();
            }
        } else {
            cmd = line.trim().to_string();
            // ts carries over from the previous timestamped line.
        }
        let Some(t) = ts else { continue };
        if (t as f64) < cutoff {
            continue;
        }
        for (binary, display) in HISTORY_TOOLS {
            if cmd == *binary
                || cmd.starts_with(&format!("{binary} "))
                || cmd.starts_with(&format!("{binary}\t"))
            {
                let e = counts.entry(display).or_insert_with(|| {
                    order.push(display);
                    (0, 0)
                });
                e.0 += 1;
                if t > e.1 {
                    e.1 = t;
                }
            }
        }
    }
    let mut results = Vec::new();
    for display in order {
        let (count, last_ts) = counts[display];
        if count == 0 {
            continue;
        }
        let mut t = empty_tool(display);
        t.sessions_7d = count;
        t.sessions_today = 0; // not tracked at daily granularity from history
        if last_ts > 0 {
            t.last_used = Some(iso_utc(last_ts as f64));
        }
        results.push(t);
    }
    results
}

/// Read up to `max` trailing bytes of a file.
fn read_tail(path: &Path, max: u64) -> Option<Vec<u8>> {
    use std::io::{Read, Seek, SeekFrom};
    let mut f = std::fs::File::open(path).ok()?;
    let size = f.metadata().ok()?.len();
    let start = size.saturating_sub(max);
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    Some(buf)
}

/// Aggregate all other-tool probes (mirrors `collect_others`): gemini + aider
/// (+ llm, omitted) then shell-history (deduped by lowercased name), sorted by
/// `last_used` descending.
pub fn collect_others(home: &Path, now: f64) -> Vec<ToolSummary> {
    let mut tools: Vec<ToolSummary> = Vec::new();
    if let Some(t) = probe_gemini_cli(home, now) {
        tools.push(t);
    }
    if let Some(t) = probe_aider(home, now) {
        tools.push(t);
    }
    let mut existing: BTreeSet<String> = tools.iter().map(|t| t.name.to_lowercase()).collect();
    for t in probe_shell_history(home, now) {
        let key = t.name.to_lowercase();
        if !existing.contains(&key) {
            existing.insert(key);
            tools.push(t);
        }
    }
    // Sort by last_used desc; None sorts last (Python uses "" for missing).
    tools.sort_by(|a, b| {
        b.last_used
            .clone()
            .unwrap_or_default()
            .cmp(&a.last_used.clone().unwrap_or_default())
    });
    tools
}
