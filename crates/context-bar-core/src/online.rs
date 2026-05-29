//! Online / host enrichments — the final slice-4 piece of the Python→Rust port.
//! Ports the statusline-snapshot overlay, the Anthropic usage API (account 5h/7d
//! %), Codex transcript rate-limits, and cross-platform credential discovery
//! (`~/.claude/.credentials.json`; macOS keychain). All best-effort: each
//! degrades to a no-op offline / without credentials, exactly like the Python.
//! Native-only (HTTP + subprocess + filesystem).

use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::aggregate::{iso_utc, parse_iso};
use crate::usage_signal::AgentUsage;

const STATUSLINE_TTL: f64 = 12.0 * 3600.0;
const CACHE_TTL_OK: u64 = 5 * 60;
const CACHE_TTL_ERR: u64 = 15;

fn round1(x: f64) -> f64 {
    (x * 10.0).round_ties_even() / 10.0
}

/// `parse_usage_percent`: a number clamped to [0,200], rounded to 1 dp; else None.
pub fn parse_usage_percent(v: Option<&Value>) -> Option<f64> {
    v.and_then(|x| x.as_f64()).map(|f| round1(f.clamp(0.0, 200.0)))
}

fn num_u64(v: &Value, key: &str) -> Option<u64> {
    v.get(key)
        .and_then(|x| x.as_u64().or_else(|| x.as_f64().map(|f| f.max(0.0) as u64)))
}

// ---- Claude statusline snapshot -------------------------------------------

fn statusline_path(home: &Path) -> PathBuf {
    if let Ok(o) = std::env::var("CONTEXTBAR_CLAUDE_STATUSLINE_PATH") {
        if !o.is_empty() {
            return PathBuf::from(o);
        }
    }
    home.join(".context-bar").join("claude-statusline.json")
}

fn load_statusline(home: &Path, now: f64) -> Option<Value> {
    let path = statusline_path(home);
    let bytes = std::fs::read(&path).ok()?;
    let payload: Value = serde_json::from_slice(&bytes).ok()?;
    let ts = parse_iso(payload.get("updated_at").and_then(|v| v.as_str())).or_else(|| {
        std::fs::metadata(&path)
            .ok()?
            .modified()
            .ok()?
            .duration_since(std::time::UNIX_EPOCH)
            .ok()
            .map(|d| d.as_secs_f64())
    });
    let ts = ts?;
    if now - ts > STATUSLINE_TTL {
        return None;
    }
    Some(payload)
}

/// Navigate `rate_limits` by `keys`, returning (percent, resets_at) — mirrors
/// `parse_claude_rate_limit_window`.
fn parse_claude_rate_limit_window(rate_limits: &Value, keys: &[&str]) -> (Option<f64>, Option<String>) {
    let mut cur = rate_limits;
    for k in keys {
        match cur.get(k) {
            Some(v) if v.is_object() => cur = v,
            _ => return (None, None),
        }
    }
    if !cur.is_object() {
        return (None, None);
    }
    let pct = parse_usage_percent(cur.get("used_percentage"))
        .or_else(|| parse_usage_percent(cur.get("utilization")))
        .or_else(|| parse_usage_percent(cur.get("used_percent")));
    let resets = match cur.get("resets_at") {
        Some(Value::Number(n)) => n
            .as_f64()
            .map(|secs| iso_utc(secs)),
        Some(Value::String(s)) => Some(s.clone()),
        _ => None,
    };
    (pct, resets)
}

/// Overlay the statusline snapshot (authoritative for live context fields when
/// fresh). Mirrors `apply_claude_statusline_snapshot`.
pub fn apply_claude_statusline(out: &mut AgentUsage, home: &Path, now: f64) {
    let Some(snap) = load_statusline(home, now) else { return };
    let empty = Value::Object(Default::default());
    let ctx = snap.get("context_window").unwrap_or(&empty);
    let current_usage = ctx.get("current_usage").unwrap_or(&empty);

    let input_total = num_u64(ctx, "total_input_tokens").or_else(|| {
        if current_usage.is_object() {
            Some(
                num_u64(current_usage, "input_tokens").unwrap_or(0)
                    + num_u64(current_usage, "cache_creation_input_tokens").unwrap_or(0)
                    + num_u64(current_usage, "cache_read_input_tokens").unwrap_or(0),
            )
        } else {
            None
        }
    });
    let output_total = num_u64(ctx, "total_output_tokens").or_else(|| {
        if current_usage.is_object() {
            Some(num_u64(current_usage, "output_tokens").unwrap_or(0))
        } else {
            None
        }
    });

    let model = snap.get("model").unwrap_or(&empty);
    let workspace = snap.get("workspace").unwrap_or(&empty);
    let cwd = workspace
        .get("current_dir")
        .and_then(|v| v.as_str())
        .or_else(|| snap.get("cwd").and_then(|v| v.as_str()));
    let model_id = model
        .get("id")
        .and_then(|v| v.as_str())
        .or_else(|| model.get("display_name").and_then(|v| v.as_str()));
    let used_pct = parse_usage_percent(ctx.get("used_percentage"));
    let window = num_u64(ctx, "context_window_size");

    if let Some(u) = snap.get("updated_at").and_then(|v| v.as_str()) {
        out.last_turn_at = Some(u.to_string());
    }
    if let Some(m) = model_id {
        out.last_model = Some(m.to_string());
    }
    if let Some(c) = cwd {
        out.last_cwd = Some(c.to_string());
    }
    if let Some(it) = input_total {
        out.last_turn_input_tokens = it;
    }
    if let Some(ot) = output_total {
        out.last_turn_output_tokens = ot;
    }
    if let Some(w) = window {
        out.last_context_window = Some(w);
    }
    if let Some(p) = used_pct {
        out.last_context_pct = Some(p);
    }

    let rate_limits = snap.get("rate_limits").unwrap_or(&empty);
    for (keys, is_five) in [
        (&["five_hour"][..], true),
        (&["seven_day"][..], false),
        (&["primary"][..], true),
        (&["secondary"][..], false),
    ] {
        let (pct, resets) = parse_claude_rate_limit_window(rate_limits, keys);
        if let Some(p) = pct {
            if is_five {
                out.session_5h_percent = Some(p);
            } else {
                out.week_7d_percent = Some(p);
            }
        }
        if let Some(r) = resets {
            if is_five {
                out.session_5h_resets_at = Some(r);
            } else {
                out.week_7d_resets_at = Some(r);
            }
        }
    }
}

// ---- Anthropic usage API (account limits %) -------------------------------

fn now_ms(now: f64) -> i64 {
    (now * 1000.0) as i64
}

fn token_from_oauth(data: &Value, now_ms: i64) -> Option<String> {
    let oauth = data.get("claudeAiOauth")?;
    let token = oauth.get("accessToken").and_then(|v| v.as_str())?;
    if token.is_empty() {
        return None;
    }
    // Python: `token and (expiresAt is None or expiresAt > now_ms)`. A present
    // non-numeric expiresAt raises in Python (→ rejected), so: missing/null →
    // accept; numeric → must be in the future; anything else → reject.
    match oauth.get("expiresAt") {
        None | Some(Value::Null) => Some(token.to_string()),
        Some(v) => match v.as_f64() {
            Some(e) if e > now_ms as f64 => Some(token.to_string()),
            _ => None,
        },
    }
}

/// Read the Claude OAuth token: macOS keychain first, then
/// `~/.claude/.credentials.json` (cross-platform). Mirrors `read_claude_credentials`.
fn read_claude_credentials(home: &Path, now: f64) -> Option<String> {
    let now_ms = now_ms(now);
    // macOS keychain (no-op / error elsewhere).
    if let Ok(out) = std::process::Command::new("security")
        .args(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        .output()
    {
        if out.status.success() {
            let raw = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if let Ok(data) = serde_json::from_str::<Value>(&raw) {
                if let Some(t) = token_from_oauth(&data, now_ms) {
                    return Some(t);
                }
            } else if raw.starts_with("sk-ant") {
                return Some(raw);
            }
        }
    }
    let path = home.join(".claude").join(".credentials.json");
    let bytes = std::fs::read(&path).ok()?;
    let data: Value = serde_json::from_slice(&bytes).ok()?;
    token_from_oauth(&data, now_ms)
}

fn usage_cache_path(home: &Path) -> PathBuf {
    home.join(".context-bar").join("usage_api_cache.json")
}

fn now_secs(now: f64) -> u64 {
    now.max(0.0) as u64
}

fn fetch_claude_usage_api(home: &Path, now: f64) -> Option<Value> {
    let cache = usage_cache_path(home);
    let cached: Option<Value> = std::fs::read(&cache)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok());
    if let Some(c) = &cached {
        let ts = c.get("timestamp").and_then(|v| v.as_u64()).unwrap_or(0);
        let ttl = if c.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            CACHE_TTL_OK
        } else {
            CACHE_TTL_ERR
        };
        if ts > 0 && now_secs(now).saturating_sub(ts) < ttl {
            return c.get("data").filter(|d| !d.is_null()).cloned();
        }
    }

    let write_cache = |ok: bool, data: &Value| {
        if let Some(parent) = cache.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let doc = serde_json::json!({"timestamp": now_secs(now), "ok": ok, "data": data});
        if let Ok(bytes) = serde_json::to_vec(&doc) {
            let _ = std::fs::write(&cache, bytes);
        }
    };

    let Some(token) = read_claude_credentials(home, now) else {
        write_cache(false, &Value::Null);
        return None;
    };

    // Prior good payload, kept as a fallback on transport/body errors (mirrors
    // the Python `except` branch).
    let fallback = cached
        .as_ref()
        .and_then(|c| c.get("data"))
        .filter(|d| !d.is_null())
        .cloned();

    let resp = ureq::get("https://api.anthropic.com/api/oauth/usage")
        .set("Authorization", &format!("Bearer {token}"))
        .set("anthropic-beta", "oauth-2025-04-20")
        .set("User-Agent", "claude-code/2.1")
        .timeout(std::time::Duration::from_secs(15))
        .call();
    match resp {
        Ok(r) => match r.into_json::<Value>() {
            Ok(payload) => {
                write_cache(true, &payload);
                Some(payload)
            }
            // 2xx with an unparseable body — Python's `except` keeps prior data.
            Err(_) => {
                write_cache(false, fallback.as_ref().unwrap_or(&Value::Null));
                fallback
            }
        },
        // Non-2xx response — Python's `status != 200` returns None + null cache.
        Err(ureq::Error::Status(_, _)) => {
            write_cache(false, &Value::Null);
            None
        }
        // Transport/network error — Python's `except` keeps prior data.
        Err(_) => {
            write_cache(false, fallback.as_ref().unwrap_or(&Value::Null));
            fallback
        }
    }
}

/// Overlay account 5h/7d utilization from the Anthropic usage API. Mirrors
/// `apply_claude_usage_api`.
pub fn apply_claude_usage_api(out: &mut AgentUsage, home: &Path, now: f64) {
    let Some(payload) = fetch_claude_usage_api(home, now) else { return };
    if !payload.is_object() {
        return;
    }
    let empty = Value::Object(Default::default());
    let five = payload.get("five_hour").unwrap_or(&empty);
    let seven = payload.get("seven_day").unwrap_or(&empty);
    out.session_5h_percent = parse_usage_percent(five.get("utilization"));
    out.week_7d_percent = parse_usage_percent(seven.get("utilization"));
    if let Some(r) = five.get("resets_at").and_then(|v| v.as_str()) {
        out.session_5h_resets_at = Some(r.to_string());
    }
    if let Some(r) = seven.get("resets_at").and_then(|v| v.as_str()) {
        out.week_7d_resets_at = Some(r.to_string());
    }
}

// ---- Codex rate limits (from transcript) ----------------------------------

fn epoch_to_iso(v: Option<&Value>, now: f64) -> Option<String> {
    let secs = v?.as_f64()?;
    if secs <= now {
        return None;
    }
    Some(iso_utc(secs))
}

fn parse_codex_rate_limit_window(window: &Value, now: f64) -> (Option<f64>, Option<String>) {
    if !window.is_object() {
        return (None, None);
    }
    let pct = parse_usage_percent(window.get("usedPercent"))
        .or_else(|| parse_usage_percent(window.get("used_percent")));
    let resets = epoch_to_iso(window.get("resetsAt"), now)
        .or_else(|| epoch_to_iso(window.get("resets_at"), now));
    (pct, resets)
}

/// Apply Codex rate-limit windows (primary→5h, secondary→7d). Mirrors
/// `apply_codex_rate_limits`.
pub fn apply_codex_rate_limits(out: &mut AgentUsage, snapshot: &Value, now: f64) {
    if !snapshot.is_object() {
        return;
    }
    let empty = Value::Object(Default::default());
    let (pct, resets) = parse_codex_rate_limit_window(snapshot.get("primary").unwrap_or(&empty), now);
    if let Some(p) = pct {
        out.session_5h_percent = Some(p);
    }
    if let Some(r) = resets {
        out.session_5h_resets_at = Some(r);
    }
    let (pct, resets) =
        parse_codex_rate_limit_window(snapshot.get("secondary").unwrap_or(&empty), now);
    if let Some(p) = pct {
        out.week_7d_percent = Some(p);
    }
    if let Some(r) = resets {
        out.week_7d_resets_at = Some(r);
    }
}
