//! Pure-Rust transcript collection — slice 3 of folding `usage_signal.py` into
//! Rust (ROADMAP E1). Ports `collect_claude` / `collect_codex` (JSONL discovery,
//! per-turn token extraction, rolling windows, last-turn + active-session
//! fields, context-window heuristic) and `build_active_sessions` /
//! `claude_context_window`, reusing the golden-pinned `pricing` + `aggregate`
//! kernels.
//!
//! Native-only: it reads `~/.claude` / `~/.codex` from disk (the wasm Zed
//! extension stays on the Python sidecar, which escapes its sandbox via a
//! full-perms subprocess). Online enrichments — the Anthropic usage API, Codex
//! app-server rate limits, the LiteLLM live-pricing fetch, statusline snapshot,
//! and the other-tool probes — are NOT yet ported here; the deterministic
//! transcript path (token totals, buckets, sessions, cost) is, and is validated
//! field-for-field against the Python (offline) on real data.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::aggregate::{
    bucket_aggregates, iso_utc, project_name_from_cwd, split_logical_sessions, Buckets, FileEvents,
    TurnMetrics,
};
use crate::pricing::{match_pricing, turn_cache_savings, turn_cost};
use crate::usage_signal::{ActiveSession, AgentUsage};

const WIN_SESSION: f64 = 5.0 * 3600.0;
const WIN_WEEK: f64 = 7.0 * 86400.0;
const WIN_30D: f64 = 30.0 * 86400.0;
const WIN_HIST: f64 = 365.0 * 86400.0;
const ACTIVE_WINDOW: f64 = 30.0 * 60.0;

/// Per-transcript-file accumulator (mirrors the Python `per_session[path]`).
#[derive(Default, Clone)]
struct PerFile {
    first_ts: f64,
    last_ts: f64,
    tokens: u64,
    cache_read: u64,
    cost: f64,
    model: Option<String>,
    cwd: Option<String>,
    last_input: u64,
    max_ctx: u64,
    last_window: Option<u64>,
    betas: Vec<String>,
    events: Vec<(f64, TurnMetrics)>,
    seeded: bool,
}

// ---- small JSON helpers (mirror Python int(x or 0)) -----------------------

fn num_u64(v: &Value, key: &str) -> u64 {
    match v.get(key) {
        Some(Value::Number(n)) => n
            .as_u64()
            .or_else(|| n.as_f64().map(|f| if f > 0.0 { f as u64 } else { 0 }))
            .unwrap_or(0),
        _ => 0,
    }
}

fn str_field(v: &Value, key: &str) -> Option<String> {
    v.get(key).and_then(|x| x.as_str()).map(str::to_string)
}

fn parse_iso(value: Option<&str>) -> Option<f64> {
    let s = value?;
    if s.is_empty() {
        return None;
    }
    use time::format_description::well_known::Rfc3339;
    time::OffsetDateTime::parse(s, &Rfc3339)
        .ok()
        .map(|dt| dt.unix_timestamp_nanos() as f64 / 1e9)
}

fn mtime_secs(path: &Path) -> Option<f64> {
    let meta = std::fs::metadata(path).ok()?;
    let modified = meta.modified().ok()?;
    let dur = modified.duration_since(std::time::UNIX_EPOCH).ok()?;
    Some(dur.as_secs_f64())
}

fn round6(x: f64) -> f64 {
    (x * 1e6).round_ties_even() / 1e6
}

/// Round a context-window percentage to `digits` places (banker's rounding,
/// matching Python's `round()`), clamped to 200% like the Python.
fn round_pct(value: f64, digits: i32) -> f64 {
    let f = 10f64.powi(digits);
    (value.min(200.0) * f).round_ties_even() / f
}

/// Python's `x or {}` then `isinstance(x, dict)`: a dict (incl. empty) is used;
/// any *falsy* non-dict (None/False/0/""/[]) becomes `{}` (a zero-metric event
/// still recorded — its ts is a session boundary); a *truthy* non-dict is
/// skipped. Returns `None` to signal "skip this turn".
fn obj_or_empty<'a>(v: Option<&'a Value>, empty: &'a Value) -> Option<&'a Value> {
    match v {
        Some(o) if o.is_object() => Some(o),
        None | Some(Value::Null) | Some(Value::Bool(false)) => Some(empty),
        Some(Value::Number(n)) if n.as_f64() == Some(0.0) => Some(empty),
        Some(Value::String(s)) if s.is_empty() => Some(empty),
        Some(Value::Array(a)) if a.is_empty() => Some(empty),
        Some(_) => None,
    }
}

/// Claude context-window heuristic (mirrors `claude_context_window`).
pub fn claude_context_window(model: Option<&str>, observed_max: u64, betas: &[String]) -> Option<u64> {
    if let Ok(env) = std::env::var("CONTEXTBAR_CONTEXT_WINDOW") {
        if let Ok(n) = env.trim().parse::<u64>() {
            return Some(n);
        }
    }
    if let Some(model) = model {
        let m = model.to_ascii_lowercase();
        if m.contains("[1m]") || m.contains("-1m") {
            return Some(1_000_000);
        }
        if m.contains("haiku") {
            return Some(200_000);
        }
        if m.contains("opus-4-7")
            || m.contains("opus-4-6")
            || m.contains("sonnet-4-7")
            || m.contains("sonnet-4-6")
            || m.contains("sonnet-4-5")
            || m.contains("mythos")
        {
            return Some(1_000_000);
        }
    }
    for b in betas {
        let bl = b.to_ascii_lowercase();
        if bl.contains("context-1m") || bl.contains("1m-2025") {
            return Some(1_000_000);
        }
    }
    if observed_max > 200_000 {
        return Some(1_000_000);
    }
    Some(200_000)
}

/// `build_active_sessions`: sessions whose last turn is within ACTIVE_WINDOW.
fn build_active_sessions(per_session: &BTreeMap<String, PerFile>, now: f64) -> Vec<ActiveSession> {
    let mut actives: Vec<ActiveSession> = Vec::new();
    for (path, s) in per_session {
        if now - s.last_ts > ACTIVE_WINDOW {
            continue;
        }
        let window = match s.last_window {
            Some(w) if w > 0 => Some(w),
            _ => claude_context_window(s.model.as_deref(), s.max_ctx, &s.betas),
        };
        let last_input = s.last_input;
        let context_pct = match window {
            Some(w) if w > 0 && last_input > 0 => {
                Some(round_pct(last_input as f64 / w as f64 * 100.0, 1))
            }
            _ => None,
        };
        actives.push(ActiveSession {
            id: session_id(path),
            tokens: s.tokens,
            cost: round6(s.cost),
            started_at: Some(iso_utc(s.first_ts)),
            last_turn_at: Some(iso_utc(s.last_ts)),
            model: s.model.clone(),
            cwd: s.cwd.clone(),
            project: Some(project_name_from_cwd(s.cwd.as_deref())),
            context_pct,
            context_window: window,
            last_input_tokens: last_input,
        });
    }
    // Newest last_turn_at first (string sort matches Python's ISO compare).
    actives.sort_by(|a, b| b.last_turn_at.cmp(&a.last_turn_at));
    actives
}

fn session_id(path: &str) -> String {
    let base = path.trim_end_matches('/').rsplit('/').next().unwrap_or(path);
    match base.rsplit_once('.') {
        Some((stem, _)) if !stem.is_empty() => stem.to_string(),
        _ => base.to_string(),
    }
}

/// Recursively collect `*.jsonl` files under `dir`. `max_depth` bounds recursion
/// (Claude: 1 level under projects/<proj>/; Codex: deep under sessions/).
fn walk_jsonl(dir: &Path, max_depth: usize, out: &mut Vec<PathBuf>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let Ok(ft) = entry.file_type() else { continue };
        if ft.is_symlink() {
            continue;
        }
        let path = entry.path();
        if ft.is_dir() {
            if max_depth > 0 {
                walk_jsonl(&path, max_depth - 1, out);
            }
        } else if ft.is_file() && path.extension().and_then(|s| s.to_str()) == Some("jsonl") {
            out.push(path);
        }
    }
}

/// Apply the engine's aggregate buckets onto an [`AgentUsage`].
fn apply_buckets(out: &mut AgentUsage, b: Buckets) {
    out.total_tokens_30d = b.total_tokens_30d;
    out.total_sessions_30d = b.total_sessions_30d;
    out.total_cost_30d = b.total_cost_30d;
    out.total_input_30d = b.total_input_30d;
    out.total_output_30d = b.total_output_30d;
    out.cost_today = b.cost_today;
    out.max_session_minutes = b.max_session_minutes;
    out.by_day = b.by_day;
    out.by_week = b.by_week;
    out.by_month = b.by_month;
    out.by_model = b.by_model;
    out.by_project = b.by_project;
    out.by_day_project = b.by_day_project;
}

/// Build `FileEvents` (for sessionization) from the per-file accumulators,
/// preserving the BTreeMap key order.
fn to_file_events(per_session: &BTreeMap<String, PerFile>) -> BTreeMap<String, FileEvents> {
    per_session
        .iter()
        .map(|(path, s)| {
            (
                path.clone(),
                FileEvents {
                    model: s.model.clone(),
                    cwd: s.cwd.clone(),
                    events: s.events.clone(),
                },
            )
        })
        .collect()
}

fn finish(
    mut out: AgentUsage,
    per_session: BTreeMap<String, PerFile>,
    now: f64,
    session_5h_oldest: Option<f64>,
    week_7d_oldest: Option<f64>,
) -> AgentUsage {
    if let Some(file) = &out.active_session_file {
        if let Some(s) = per_session.get(file) {
            out.active_session_tokens = s.tokens;
            out.active_session_cost = round6(s.cost);
            out.active_session_started_at = Some(iso_utc(s.first_ts));
        }
    }

    let files = to_file_events(&per_session);
    let (sessions, mut recent) = split_logical_sessions(&files);
    apply_buckets(&mut out, bucket_aggregates(&sessions, now, local_offset()));
    // Newest ended first; cap 20.
    recent.sort_by(|a, b| b.ended_at.cmp(&a.ended_at));
    recent.truncate(20);
    out.recent_sessions = recent;
    out.active_sessions = build_active_sessions(&per_session, now);

    if let Some(o) = session_5h_oldest {
        out.session_5h_resets_at = Some(iso_utc(o + WIN_SESSION));
    }
    if let Some(o) = week_7d_oldest {
        out.week_7d_resets_at = Some(iso_utc(o + WIN_WEEK));
    }
    out.cost_5h = round6(out.cost_5h);
    out.cost_7d = round6(out.cost_7d);
    out.cache_savings_30d = round6(out.cache_savings_30d);
    out
}

/// Fixed local UTC offset. The Python uses the system local tz; for fixed-offset
/// zones this is identical. Falls back to UTC if the offset can't be read.
fn local_offset() -> time::UtcOffset {
    time::OffsetDateTime::now_local()
        .map(|dt| dt.offset())
        .unwrap_or(time::UtcOffset::UTC)
}

/// Port of `collect_claude`. Deterministic transcript path only.
pub fn collect_claude(home: &Path, now: f64) -> AgentUsage {
    let mut out = AgentUsage::default();
    let mut per_session: BTreeMap<String, PerFile> = BTreeMap::new();
    let mut last_ts = 0.0f64;
    let mut session_5h_oldest: Option<f64> = None;
    let mut week_7d_oldest: Option<f64> = None;
    // (ts, model, cwd, inp, outp, timestamp, path, max_ctx, betas) for the
    // most recent *foreground* (non-subagent) turn.
    let mut fg: Option<ForegroundTurn> = None;
    let process_cwd = std::env::var("PWD")
        .ok()
        .or_else(|| std::env::current_dir().ok().map(|p| p.display().to_string()));

    let projects = home.join(".claude").join("projects");
    let mut files = Vec::new();
    walk_jsonl(&projects, 1, &mut files);
    files.sort();

    for path in &files {
        let Some(mtime) = mtime_secs(path) else { continue };
        if now - mtime > WIN_HIST {
            continue;
        }
        let Ok(content) = std::fs::read_to_string(path) else { continue };
        let path_s = path.display().to_string();
        for line in content.lines() {
            if !line.contains("\"usage\"") || !line.contains("\"assistant\"") {
                continue;
            }
            let Ok(obj) = serde_json::from_str::<Value>(line) else { continue };
            if obj.get("type").and_then(|t| t.as_str()) != Some("assistant") {
                continue;
            }
            let Some(msg) = obj.get("message").filter(|m| m.is_object()) else { continue };
            // Python: `usage = msg.get("usage") or {}` then isinstance(dict).
            let empty = Value::Object(serde_json::Map::new());
            let Some(usage) = obj_or_empty(msg.get("usage"), &empty) else { continue };

            let fresh_in = num_u64(usage, "input_tokens");
            let cache_create = num_u64(usage, "cache_creation_input_tokens");
            let cache_read = num_u64(usage, "cache_read_input_tokens");
            let mut outp = num_u64(usage, "output_tokens");
            // Extended-thinking / reasoning output under varying keys.
            if let Some(map) = usage.as_object() {
                for (k, v) in map {
                    if !v.is_number() {
                        continue;
                    }
                    let kl = k.to_ascii_lowercase();
                    if matches!(
                        kl.as_str(),
                        "input_tokens"
                            | "output_tokens"
                            | "cache_creation_input_tokens"
                            | "cache_read_input_tokens"
                    ) {
                        continue;
                    }
                    if (kl.contains("thinking") && kl.contains("token"))
                        || kl == "reasoning_output_tokens"
                        || kl == "output_thinking_tokens"
                    {
                        outp += v.as_u64().or_else(|| v.as_f64().map(|f| f.max(0.0) as u64)).unwrap_or(0);
                    }
                }
            }
            let inp = fresh_in + cache_create + cache_read;
            let total = fresh_in + outp;

            let turn_model = str_field(msg, "model");
            let rate = match_pricing(turn_model.as_deref().unwrap_or(""));
            let cost = match obj.get("costUSD") {
                Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0),
                _ => turn_cost(rate.as_ref(), fresh_in, cache_create, cache_read, outp),
            };
            let cache_saved = turn_cache_savings(rate.as_ref(), cache_create, cache_read);
            let metrics = TurnMetrics {
                total,
                cache_read,
                input: fresh_in,
                output: outp,
                cache_creation: cache_create,
                cost,
            };
            let ts = parse_iso(obj.get("timestamp").and_then(|t| t.as_str())).unwrap_or(mtime);
            let age = now - ts;

            let sess = per_session.entry(path_s.clone()).or_default();
            if !sess.seeded {
                sess.first_ts = ts;
                sess.model = str_field(msg, "model");
                sess.cwd = str_field(&obj, "cwd");
                sess.seeded = true;
            }
            sess.first_ts = sess.first_ts.min(ts);
            if ts >= sess.last_ts {
                sess.last_ts = ts;
                sess.last_input = inp;
            }
            sess.tokens += total;
            sess.cache_read += cache_read;
            sess.cost += cost;
            sess.events.push((ts, metrics));
            if inp > sess.max_ctx {
                sess.max_ctx = inp;
            }
            for src in [&obj, msg] {
                if let Some(arr) = src.get("betas").and_then(|b| b.as_array()) {
                    for item in arr {
                        let sval = match item {
                            Value::String(s) => s.clone(),
                            other => other.to_string(),
                        };
                        if !sess.betas.contains(&sval) {
                            sess.betas.push(sval);
                        }
                    }
                }
            }
            if let Some(m) = str_field(msg, "model") {
                sess.model = Some(m);
            }
            if let Some(c) = str_field(&obj, "cwd") {
                sess.cwd = Some(c);
            }

            if age <= WIN_WEEK {
                out.week_7d_tokens += total;
                out.cache_read_tokens_7d += cache_read;
                out.cost_7d += cost;
                if week_7d_oldest.is_none_or(|o| ts < o) {
                    week_7d_oldest = Some(ts);
                }
            }
            if age <= WIN_SESSION {
                out.session_5h_tokens += total;
                out.cache_read_tokens_5h += cache_read;
                out.cost_5h += cost;
                if session_5h_oldest.is_none_or(|o| ts < o) {
                    session_5h_oldest = Some(ts);
                }
            }
            if age <= WIN_30D {
                out.cache_read_tokens_30d += cache_read;
                out.cache_savings_30d += cache_saved;
            }

            let is_subagent = obj.get("parentUuid").is_some_and(truthy)
                || obj.get("parent_tool_use_id").is_some_and(truthy)
                || msg.get("parentUuid").is_some_and(truthy)
                || msg.get("parent_tool_use_id").is_some_and(truthy);

            if ts > last_ts {
                last_ts = ts;
                out.last_turn_input_tokens = inp;
                out.last_turn_output_tokens = outp;
                out.last_model = str_field(msg, "model");
                out.last_turn_at = str_field(&obj, "timestamp");
                out.last_cwd = str_field(&obj, "cwd");
                out.active_session_file = Some(path_s.clone());
            }
            if !is_subagent && fg.as_ref().is_none_or(|f| ts > f.ts) {
                fg = Some(ForegroundTurn {
                    ts,
                    model: str_field(msg, "model"),
                    cwd: str_field(&obj, "cwd"),
                    inp,
                    outp,
                    timestamp: str_field(&obj, "timestamp"),
                    max_ctx: sess.max_ctx,
                    betas: sess.betas.clone(),
                });
            }
        }
    }

    // last_context_pct: prefer a session whose cwd matches the process cwd,
    // else the most-recent foreground turn.
    let mut cwd_match: Option<PerFile> = None;
    if let Some(pcwd) = &process_cwd {
        let mut best_ts = 0.0;
        for s in per_session.values() {
            if s.cwd.as_deref() == Some(pcwd.as_str()) && s.last_ts > best_ts {
                best_ts = s.last_ts;
                cwd_match = Some(s.clone());
            }
        }
    }
    if let Some(s) = cwd_match {
        let window = claude_context_window(s.model.as_deref(), s.max_ctx, &s.betas);
        let inp = s.last_input;
        out.last_model = s.model.clone().or(out.last_model);
        out.last_cwd = s.cwd.clone().or(out.last_cwd);
        out.last_turn_input_tokens = inp;
        out.last_context_window = window;
        out.last_context_pct = window.map(|w| round_pct(inp as f64 / w as f64 * 100.0, 2));
    } else if let Some(f) = fg {
        let window = claude_context_window(f.model.as_deref(), f.max_ctx, &f.betas);
        out.last_model = f.model.or(out.last_model);
        out.last_cwd = f.cwd.or(out.last_cwd);
        out.last_turn_input_tokens = f.inp;
        out.last_turn_output_tokens = f.outp;
        out.last_turn_at = f.timestamp.or(out.last_turn_at);
        out.last_context_window = window;
        out.last_context_pct = window.map(|w| round_pct(f.inp as f64 / w as f64 * 100.0, 2));
    }

    finish(out, per_session, now, session_5h_oldest, week_7d_oldest)
}

struct ForegroundTurn {
    ts: f64,
    model: Option<String>,
    cwd: Option<String>,
    inp: u64,
    outp: u64,
    timestamp: Option<String>,
    max_ctx: u64,
    betas: Vec<String>,
}

fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::String(s) => !s.is_empty(),
        Value::Number(n) => n.as_f64().map(|f| f != 0.0).unwrap_or(true),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

/// Port of `collect_codex`. Deterministic transcript path only.
pub fn collect_codex(home: &Path, now: f64) -> AgentUsage {
    let mut out = AgentUsage::default();
    let mut per_session: BTreeMap<String, PerFile> = BTreeMap::new();
    let mut last_ts = 0.0f64;
    let mut session_5h_oldest: Option<f64> = None;
    let mut week_7d_oldest: Option<f64> = None;

    let sessions_dir = home.join(".codex").join("sessions");
    let mut files = Vec::new();
    walk_jsonl(&sessions_dir, 8, &mut files);
    files.sort();

    for path in &files {
        let Some(mtime) = mtime_secs(path) else { continue };
        if now - mtime > WIN_HIST {
            continue;
        }
        let Ok(content) = std::fs::read_to_string(path) else { continue };
        let path_s = path.display().to_string();
        let mut current_model: Option<String> = None;
        let mut current_cwd: Option<String> = None;

        for line in content.lines() {
            if !line.contains("\"token_count\"") && !line.contains("\"turn_context\"") {
                continue;
            }
            let Ok(obj) = serde_json::from_str::<Value>(line) else { continue };
            let t = obj.get("type").and_then(|x| x.as_str());
            let payload = match obj.get("payload") {
                Some(p) if p.is_object() => p,
                _ => continue,
            };
            if t == Some("turn_context") {
                if let Some(m) = str_field(payload, "model") {
                    current_model = Some(m);
                }
                if let Some(c) = str_field(payload, "cwd") {
                    current_cwd = Some(c);
                }
                continue;
            }
            if t != Some("event_msg") {
                continue;
            }
            if payload.get("type").and_then(|x| x.as_str()) != Some("token_count") {
                continue;
            }
            // Python: `info = payload.get("info") or {}` and
            // `last_use = info.get("last_token_usage") or {}` — a dict (incl.
            // empty) or any falsy value yields {} and STILL records a
            // zero-metric event (its ts is a session-split boundary); a truthy
            // non-dict is skipped.
            let empty = Value::Object(serde_json::Map::new());
            let Some(info) = obj_or_empty(payload.get("info"), &empty) else { continue };
            let Some(last_use) = obj_or_empty(info.get("last_token_usage"), &empty) else { continue };
            let inp_raw = num_u64(last_use, "input_tokens");
            let cached = num_u64(last_use, "cached_input_tokens");
            let outp = num_u64(last_use, "output_tokens");
            let reasoning = num_u64(last_use, "reasoning_output_tokens");
            let fresh_in = inp_raw.saturating_sub(cached);
            let inp = inp_raw;
            let billed_out = outp + reasoning;
            let total = fresh_in + billed_out;

            let rate = match_pricing(current_model.as_deref().unwrap_or(""));
            let cost = turn_cost(rate.as_ref(), fresh_in, 0, cached, billed_out);
            let cache_saved = turn_cache_savings(rate.as_ref(), 0, cached);
            let metrics = TurnMetrics {
                total,
                cache_read: cached,
                input: fresh_in,
                output: billed_out,
                cache_creation: 0,
                cost,
            };
            let window = info.get("model_context_window").and_then(|w| w.as_u64());
            let ts = parse_iso(obj.get("timestamp").and_then(|x| x.as_str())).unwrap_or(mtime);
            let age = now - ts;

            let sess = per_session.entry(path_s.clone()).or_default();
            if !sess.seeded {
                sess.first_ts = ts;
                sess.model = current_model.clone();
                sess.cwd = current_cwd.clone();
                sess.last_window = window;
                sess.seeded = true;
            }
            sess.first_ts = sess.first_ts.min(ts);
            if ts >= sess.last_ts {
                sess.last_ts = ts;
                sess.last_input = inp;
                if window.is_some() {
                    sess.last_window = window;
                }
            }
            sess.tokens += total;
            sess.cache_read += cached;
            sess.cost += cost;
            sess.events.push((ts, metrics));
            if current_model.is_some() {
                sess.model = current_model.clone();
            }
            if current_cwd.is_some() {
                sess.cwd = current_cwd.clone();
            }

            if age <= WIN_WEEK {
                out.week_7d_tokens += total;
                out.cache_read_tokens_7d += cached;
                out.cost_7d += cost;
                if week_7d_oldest.is_none_or(|o| ts < o) {
                    week_7d_oldest = Some(ts);
                }
            }
            if age <= WIN_SESSION {
                out.session_5h_tokens += total;
                out.cache_read_tokens_5h += cached;
                out.cost_5h += cost;
                if session_5h_oldest.is_none_or(|o| ts < o) {
                    session_5h_oldest = Some(ts);
                }
            }
            if age <= WIN_30D {
                out.cache_read_tokens_30d += cached;
                out.cache_savings_30d += cache_saved;
            }

            if ts > last_ts {
                last_ts = ts;
                out.last_turn_input_tokens = inp;
                out.last_turn_output_tokens = outp;
                out.last_model = current_model.clone();
                out.last_turn_at = str_field(&obj, "timestamp");
                out.last_cwd = current_cwd.clone();
                out.active_session_file = Some(path_s.clone());
                out.last_context_window = window;
                if let Some(w) = window {
                    if w > 0 {
                        out.last_context_pct = Some(round_pct(inp as f64 / w as f64 * 100.0, 2));
                    }
                }
            }
        }
    }

    finish(out, per_session, now, session_5h_oldest, week_7d_oldest)
}
