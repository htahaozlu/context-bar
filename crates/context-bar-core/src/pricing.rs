//! Cost kernel — the API-equivalent pricing math, ported 1:1 from
//! `usage_signal.py` (the `FALLBACK_PRICING` table, model matcher, `_tiered`,
//! `turn_cost`, `turn_cache_savings`). This is the first slice of folding the
//! Python aggregator into Rust (ROADMAP E1). It is PURE — no I/O, no clock — so
//! it is pinned by a golden fixture generated from the Python (`tests/`),
//! guaranteeing byte-for-byte cost parity (see `docs/ai/COST_MODEL.md`).
//!
//! Rates are USD per token. The bundled table mirrors the LiteLLM dataset
//! ccusage uses; the live LiteLLM fetch + 24h cache (the I/O half of
//! `load_pricing`) is a later slice — until then this is the offline table,
//! which is exactly what `CONTEXTBAR_PRICING_OFFLINE=1` selects in the Python.

/// Anthropic's long-context tier threshold: tokens strictly above this in a
/// category bill at the `*_200k` rate (when the model carries one).
pub const TIER_THRESHOLD: u64 = 200_000;

/// One model's per-token rates. `None` = the category isn't billed / has no
/// tier (e.g. OpenAI models have no cache-write `cw`; flat models have no
/// `*_200k`). Mirrors the Python short-rate dict keys exactly.
#[derive(Clone, Copy, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Rate {
    // Short keys match the Python short-rate dict + the on-disk pricing cache,
    // so the Rust engine reads/writes the same `pricing.cache.json`.
    #[serde(rename = "in", default, skip_serializing_if = "Option::is_none")]
    pub input: Option<f64>,
    #[serde(rename = "out", default, skip_serializing_if = "Option::is_none")]
    pub output: Option<f64>,
    #[serde(rename = "cw", default, skip_serializing_if = "Option::is_none")]
    pub cache_write: Option<f64>,
    #[serde(rename = "cr", default, skip_serializing_if = "Option::is_none")]
    pub cache_read: Option<f64>,
    #[serde(rename = "in_200k", default, skip_serializing_if = "Option::is_none")]
    pub input_200k: Option<f64>,
    #[serde(rename = "out_200k", default, skip_serializing_if = "Option::is_none")]
    pub output_200k: Option<f64>,
    #[serde(rename = "cw_200k", default, skip_serializing_if = "Option::is_none")]
    pub cache_write_200k: Option<f64>,
    #[serde(rename = "cr_200k", default, skip_serializing_if = "Option::is_none")]
    pub cache_read_200k: Option<f64>,
}

// Constructors mirroring the three shapes in FALLBACK_PRICING.
const fn anthropic(input: f64, output: f64, cw: f64, cr: f64) -> Rate {
    Rate {
        input: Some(input),
        output: Some(output),
        cache_write: Some(cw),
        cache_read: Some(cr),
        input_200k: None,
        output_200k: None,
        cache_write_200k: None,
        cache_read_200k: None,
    }
}

#[allow(clippy::too_many_arguments)]
const fn anthropic_tiered(
    input: f64,
    output: f64,
    cw: f64,
    cr: f64,
    i2: f64,
    o2: f64,
    cw2: f64,
    cr2: f64,
) -> Rate {
    Rate {
        input: Some(input),
        output: Some(output),
        cache_write: Some(cw),
        cache_read: Some(cr),
        input_200k: Some(i2),
        output_200k: Some(o2),
        cache_write_200k: Some(cw2),
        cache_read_200k: Some(cr2),
    }
}

/// OpenAI/Codex shape: input + output + cache-read, no cache-write charge.
const fn openai(input: f64, output: f64, cr: f64) -> Rate {
    Rate {
        input: Some(input),
        output: Some(output),
        cache_write: None,
        cache_read: Some(cr),
        input_200k: None,
        output_200k: None,
        cache_write_200k: None,
        cache_read_200k: None,
    }
}

/// OpenAI shape with no published cache-read rate (e.g. `gpt-5-pro`).
const fn openai_no_cr(input: f64, output: f64) -> Rate {
    Rate {
        input: Some(input),
        output: Some(output),
        cache_write: None,
        cache_read: None,
        input_200k: None,
        output_200k: None,
        cache_write_200k: None,
        cache_read_200k: None,
    }
}

/// Bundled offline rate table (USD/token), captured from LiteLLM — verbatim
/// from `FALLBACK_PRICING` in `usage_signal.py`. Order is preserved so the
/// longest-prefix match in [`match_pricing`] is deterministic.
pub static FALLBACK_PRICING: &[(&str, Rate)] = &[
    ("claude-opus-4-8", anthropic(5e-6, 25e-6, 6.25e-6, 0.5e-6)),
    ("claude-opus-4-7", anthropic(5e-6, 25e-6, 6.25e-6, 0.5e-6)),
    ("claude-opus-4-6", anthropic(5e-6, 25e-6, 6.25e-6, 0.5e-6)),
    ("claude-opus-4-5", anthropic(5e-6, 25e-6, 6.25e-6, 0.5e-6)),
    ("claude-opus-4-1", anthropic(15e-6, 75e-6, 18.75e-6, 1.5e-6)),
    ("claude-opus-4", anthropic(15e-6, 75e-6, 18.75e-6, 1.5e-6)),
    ("claude-sonnet-4-6", anthropic(3e-6, 15e-6, 3.75e-6, 0.3e-6)),
    (
        "claude-sonnet-4-5",
        anthropic_tiered(3e-6, 15e-6, 3.75e-6, 0.3e-6, 6e-6, 22.5e-6, 7.5e-6, 0.6e-6),
    ),
    (
        "claude-sonnet-4",
        anthropic_tiered(3e-6, 15e-6, 3.75e-6, 0.3e-6, 6e-6, 22.5e-6, 7.5e-6, 0.6e-6),
    ),
    ("claude-3-7-sonnet", anthropic(3e-6, 15e-6, 3.75e-6, 0.3e-6)),
    ("claude-3-5-sonnet", anthropic(3e-6, 15e-6, 3.75e-6, 0.3e-6)),
    ("claude-haiku-4-5", anthropic(1e-6, 5e-6, 1.25e-6, 0.1e-6)),
    ("claude-3-5-haiku", anthropic(0.8e-6, 4e-6, 1e-6, 0.08e-6)),
    ("mythos", anthropic(5e-6, 25e-6, 6.25e-6, 0.5e-6)),
    ("gpt-5", openai(1.25e-6, 10e-6, 0.125e-6)),
    ("gpt-5-codex", openai(1.25e-6, 10e-6, 0.125e-6)),
    ("gpt-5-pro", openai_no_cr(15e-6, 120e-6)),
    ("gpt-5-mini", openai(0.25e-6, 2e-6, 0.025e-6)),
    ("gpt-5-nano", openai(0.05e-6, 0.4e-6, 0.005e-6)),
    ("gpt-5.1", openai(1.25e-6, 10e-6, 0.125e-6)),
    ("gpt-5.1-codex", openai(1.25e-6, 10e-6, 0.125e-6)),
    ("gpt-5.1-codex-max", openai(1.25e-6, 10e-6, 0.125e-6)),
    ("gpt-5.1-codex-mini", openai(0.25e-6, 2e-6, 0.025e-6)),
    ("gpt-5.2", openai(1.75e-6, 14e-6, 0.175e-6)),
    ("gpt-5.2-codex", openai(1.75e-6, 14e-6, 0.175e-6)),
    ("gpt-5.3-codex", openai(1.75e-6, 14e-6, 0.175e-6)),
    ("gpt-5.4", openai(2.5e-6, 15e-6, 0.25e-6)),
    ("gpt-5.4-codex", openai(2.5e-6, 15e-6, 0.25e-6)),
    ("gpt-5.4-mini", openai(0.75e-6, 4.5e-6, 0.075e-6)),
    ("gpt-5.4-nano", openai(0.2e-6, 1.25e-6, 0.02e-6)),
    ("gpt-5.4-pro", openai(30e-6, 180e-6, 3e-6)),
    ("gpt-5.5", openai(5e-6, 30e-6, 0.5e-6)),
    ("gpt-5.5-pro", openai(30e-6, 180e-6, 3e-6)),
    ("codex-mini-latest", openai(1.5e-6, 6e-6, 0.375e-6)),
    ("o4-mini", openai(1.1e-6, 4.4e-6, 0.275e-6)),
    ("o3", openai(2e-6, 8e-6, 0.5e-6)),
    ("o3-mini", openai(1.1e-6, 4.4e-6, 0.55e-6)),
];

/// Coarse family fallback, checked last — ordered, most-specific first.
/// Each entry: any of these substrings present in the (stripped) id maps to
/// the table key. Mirrors `FAMILY_FALLBACK`; the Python regexes here are plain
/// literal alternations, so substring matching is faithful.
static FAMILY_FALLBACK: &[(&[&str], &str)] = &[
    (&["opus-4-5", "opus-4-6", "opus-4-7", "opus-4-8"], "claude-opus-4-8"),
    (&["opus-4"], "claude-opus-4"),
    (&["mythos"], "mythos"),
    (&["sonnet-4"], "claude-sonnet-4-6"),
    (&["3-7-sonnet"], "claude-3-7-sonnet"),
    (&["3-5-sonnet"], "claude-3-5-sonnet"),
    (&["haiku-4"], "claude-haiku-4-5"),
    (&["3-5-haiku", "haiku"], "claude-3-5-haiku"),
    (&["gpt-5.5-pro"], "gpt-5.5-pro"),
    (&["gpt-5.5"], "gpt-5.5"),
    (&["gpt-5.4-codex"], "gpt-5.4-codex"),
    (&["gpt-5.4"], "gpt-5.4"),
    (&["gpt-5.3-codex", "gpt-5.2-codex", "gpt-5.2", "gpt-5.3"], "gpt-5.2"),
    (&["gpt-5.1-codex"], "gpt-5.1-codex"),
    (&["gpt-5.1"], "gpt-5.1"),
    (&["gpt-5-codex", "codex"], "gpt-5-codex"),
    (&["gpt-5"], "gpt-5"),
    (&["o4-mini"], "o4-mini"),
    (&["o3-mini"], "o3-mini"),
    (&["o3"], "o3"),
];

/// A resolved rate table (the bundled fallback merged with any live/cached
/// LiteLLM rates). Keyed by normalized model id.
pub type Table = std::collections::HashMap<String, Rate>;

/// The bundled offline table as a [`Table`] — the deterministic baseline that
/// `CONTEXTBAR_PRICING_OFFLINE=1` selects in the Python, and what the golden
/// tests pin against.
pub fn fallback_table() -> Table {
    FALLBACK_PRICING.iter().map(|(k, r)| (k.to_string(), *r)).collect()
}

/// Normalize a transcript model id: lowercase, strip provider prefixes, drop
/// the 1M-context tag (pricing is identical to the base model).
pub fn normalize_model(model: &str) -> String {
    let mut m = model.trim().to_ascii_lowercase();
    if m.is_empty() {
        return m;
    }
    for prefix in [
        "anthropic/",
        "anthropic.",
        "us.anthropic.",
        "eu.anthropic.",
        "apac.anthropic.",
        "openai/",
        "openrouter/",
        "claude-code/",
        "github_copilot/",
        "bedrock/",
        "vertex_ai/",
    ] {
        if let Some(rest) = m.strip_prefix(prefix) {
            m = rest.to_string();
        }
    }
    m = m.replace("[1m]", "").replace("-1m-", "-");
    if let Some(rest) = m.strip_suffix("-1m") {
        m = rest.to_string();
    }
    m
}

fn all_ascii_digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit())
}

/// `YYYY-MM-DD`.
fn is_ymd(s: &str) -> bool {
    let b = s.as_bytes();
    s.len() == 10
        && b[4] == b'-'
        && b[7] == b'-'
        && all_ascii_digits(&s[0..4])
        && all_ascii_digits(&s[5..7])
        && all_ascii_digits(&s[8..10])
}

/// If `s` ends with `-v<digits>:<digits>`, return the byte index where it
/// starts (mirrors `_VER_SUFFIX`).
fn ver_suffix_start(s: &str) -> Option<usize> {
    let pos = s.rfind("-v")?;
    let rest = &s[pos + 2..];
    let (a, b) = rest.split_once(':')?;
    if all_ascii_digits(a) && all_ascii_digits(b) {
        Some(pos)
    } else {
        None
    }
}

/// `_DATE_SUFFIX`: strip a trailing `-<date>` (8 digits or `YYYY-MM-DD`) plus an
/// optional `-v<n>:<n>` tail. No-op when no date is present.
fn strip_date_suffix(s: &str) -> &str {
    // Optional `-vN:M` tail comes AFTER the date.
    let head_end = ver_suffix_start(s).unwrap_or(s.len());
    let head = &s[..head_end];
    // Form B: -YYYY-MM-DD (11 chars).
    if head.len() >= 11 {
        let cand = &head[head.len() - 11..];
        if cand.as_bytes()[0] == b'-' && is_ymd(&cand[1..]) {
            return &s[..head.len() - 11];
        }
    }
    // Form A: -DDDDDDDD (9 chars).
    if head.len() >= 9 {
        let cand = &head[head.len() - 9..];
        if cand.as_bytes()[0] == b'-' && all_ascii_digits(&cand[1..]) {
            return &s[..head.len() - 9];
        }
    }
    s
}

/// `_VER_SUFFIX`: strip a trailing `-v<n>:<n>`.
fn strip_ver_suffix(s: &str) -> &str {
    match ver_suffix_start(s) {
        Some(i) => &s[..i],
        None => s,
    }
}

/// Resolve a transcript model id onto a rate using `table`. `None` when
/// unpriceable (cost 0 — an honest undercount, never a crash). Mirrors
/// `match_pricing(model, table)`.
pub fn match_pricing(model: &str, table: &Table) -> Option<Rate> {
    let norm = normalize_model(model);
    if norm.is_empty() {
        return None;
    }
    if let Some(r) = table.get(&norm) {
        return Some(*r);
    }
    // Strip trailing release date / bedrock version, then retry exact.
    let stripped = strip_ver_suffix(strip_date_suffix(&norm)).to_string();
    if let Some(r) = table.get(&stripped) {
        return Some(*r);
    }
    // Longest table key that is a prefix of the stripped id.
    let mut best: Option<Rate> = None;
    let mut best_len = 0usize;
    for (key, rate) in table {
        if stripped.starts_with(key.as_str()) && key.len() > best_len {
            best = Some(*rate);
            best_len = key.len();
        }
    }
    if best.is_some() {
        return best;
    }
    // Coarse family fallback.
    for (needles, key) in FAMILY_FALLBACK {
        if needles.iter().any(|n| stripped.contains(n)) {
            if let Some(r) = table.get(*key) {
                return Some(*r);
            }
        }
    }
    None
}

/// Anthropic >200K tiering for one token category (ccusage-compatible).
pub fn tiered(tokens: u64, base: Option<f64>, above: Option<f64>) -> f64 {
    let base = match base {
        Some(b) => b,
        None => return 0.0,
    };
    if tokens == 0 {
        return 0.0;
    }
    if let Some(above) = above {
        if tokens > TIER_THRESHOLD {
            return TIER_THRESHOLD as f64 * base + (tokens - TIER_THRESHOLD) as f64 * above;
        }
    }
    tokens as f64 * base
}

/// Estimated USD for one turn given its rate + token buckets. Arg order mirrors
/// the Python `turn_cost(rate, inp, cache_create, cache_read, outp)`.
pub fn turn_cost(rate: Option<&Rate>, inp: u64, cache_create: u64, cache_read: u64, outp: u64) -> f64 {
    let rate = match rate {
        Some(r) => r,
        None => return 0.0,
    };
    tiered(inp, rate.input, rate.input_200k)
        + tiered(outp, rate.output, rate.output_200k)
        + tiered(cache_create, rate.cache_write, rate.cache_write_200k)
        + tiered(cache_read, rate.cache_read, rate.cache_read_200k)
}

/// NET USD that prompt caching saved this turn (can be slightly negative on a
/// write-heavy turn). Mirrors `turn_cache_savings`.
pub fn turn_cache_savings(rate: Option<&Rate>, cache_create: u64, cache_read: u64) -> f64 {
    let rate = match rate {
        Some(r) => r,
        None => return 0.0,
    };
    let in_rate = match rate.input {
        Some(r) => r,
        None => return 0.0,
    };
    let in_200k = rate.input_200k;
    let no_cache =
        tiered(cache_create, Some(in_rate), in_200k) + tiered(cache_read, Some(in_rate), in_200k);
    let actual = tiered(cache_create, rate.cache_write, rate.cache_write_200k)
        + tiered(cache_read, rate.cache_read, rate.cache_read_200k);
    no_cache - actual
}

/// Live + cached pricing resolution (native only — needs HTTP + filesystem).
/// Mirrors the Python `load_pricing`: fresh 24h cache → live LiteLLM fetch
/// (then cache) → stale cache → bundled fallback. `CONTEXTBAR_PRICING_OFFLINE`
/// forces the offline (fallback) path.
#[cfg(not(target_arch = "wasm32"))]
pub use live::load_pricing;

#[cfg(not(target_arch = "wasm32"))]
mod live {
    use super::{fallback_table, Rate, Table};
    use std::sync::OnceLock;

    const LITELLM_URL: &str = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";
    const PRICING_TTL: u64 = 24 * 3600;
    static MEMO: OnceLock<(Table, String)> = OnceLock::new();

    fn cache_path() -> Option<std::path::PathBuf> {
        let home = std::env::var("HOME").ok()?;
        Some(std::path::PathBuf::from(home).join(".context-bar").join("pricing.cache.json"))
    }

    fn relevant(key: &str) -> bool {
        let k = key.to_ascii_lowercase();
        [
            "claude", "sonnet", "opus", "haiku", "mythos", "gpt-5", "gpt-4", "codex", "o1", "o3",
            "o4", "gemini", "glm", "zai", "deepseek", "qwen", "kimi", "moonshot", "minimax",
            "mistral", "grok", "llama",
        ]
        .iter()
        .any(|s| k.contains(s))
    }

    /// Project a LiteLLM entry onto a short [`Rate`], dropping nulls/negatives.
    fn normalize_entry(entry: &serde_json::Value) -> Option<Rate> {
        let obj = entry.as_object()?;
        let get = |k: &str| -> Option<f64> {
            obj.get(k)
                .and_then(|v| v.as_f64())
                .filter(|v| *v >= 0.0)
        };
        let rate = Rate {
            input: get("input_cost_per_token"),
            output: get("output_cost_per_token"),
            cache_write: get("cache_creation_input_token_cost"),
            cache_read: get("cache_read_input_token_cost"),
            input_200k: get("input_cost_per_token_above_200k_tokens"),
            output_200k: get("output_cost_per_token_above_200k_tokens"),
            cache_write_200k: get("cache_creation_input_token_cost_above_200k_tokens"),
            cache_read_200k: get("cache_read_input_token_cost_above_200k_tokens"),
        };
        // Need at least an input or output rate to be useful.
        if rate.input.is_some() || rate.output.is_some() {
            Some(rate)
        } else {
            None
        }
    }

    fn parse_live(raw: &serde_json::Value) -> Option<std::collections::HashMap<String, Rate>> {
        let obj = raw.as_object()?;
        let mut table = std::collections::HashMap::new();
        for (key, entry) in obj {
            if !relevant(key) {
                continue;
            }
            if let Some(rate) = normalize_entry(entry) {
                table.insert(key.to_ascii_lowercase(), rate);
            }
        }
        if table.is_empty() { None } else { Some(table) }
    }

    fn fetch_live() -> Option<std::collections::HashMap<String, Rate>> {
        let resp = ureq::get(LITELLM_URL)
            .set("User-Agent", "context-bar/usage")
            .set("Accept", "application/json")
            .timeout(std::time::Duration::from_secs(15))
            .call()
            .ok()?;
        let raw: serde_json::Value = resp.into_json().ok()?;
        parse_live(&raw)
    }

    fn now_secs() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }

    fn read_cache_table(path: &std::path::Path) -> Option<std::collections::HashMap<String, Rate>> {
        let bytes = std::fs::read(path).ok()?;
        let v: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
        let tbl = v.get("table")?.as_object()?;
        let mut out = std::collections::HashMap::new();
        for (k, rv) in tbl {
            if let Ok(rate) = serde_json::from_value::<Rate>(rv.clone()) {
                out.insert(k.clone(), rate);
            }
        }
        Some(out)
    }

    fn cache_age(path: &std::path::Path) -> Option<u64> {
        let m = std::fs::metadata(path).ok()?.modified().ok()?;
        Some(now_secs().saturating_sub(m.duration_since(std::time::UNIX_EPOCH).ok()?.as_secs()))
    }

    fn write_cache(path: &std::path::Path, live: &std::collections::HashMap<String, Rate>) {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let doc = serde_json::json!({ "timestamp": now_secs(), "table": live });
        if let Ok(bytes) = serde_json::to_vec(&doc) {
            let _ = std::fs::write(path, bytes);
        }
    }

    pub fn load_pricing() -> (Table, String) {
        if let Some(v) = MEMO.get() {
            return v.clone();
        }
        let resolved = resolve();
        let _ = MEMO.set(resolved.clone());
        resolved
    }

    fn resolve() -> (Table, String) {
        let mut base = fallback_table();
        let path = cache_path();

        // 1. Fresh on-disk cache.
        if let Some(p) = &path {
            if cache_age(p).is_some_and(|age| age < PRICING_TTL) {
                if let Some(tbl) = read_cache_table(p) {
                    base.extend(tbl);
                    return (base, "cache".to_string());
                }
            }
        }

        // 2. Live fetch (unless offline forced).
        let offline = std::env::var("CONTEXTBAR_PRICING_OFFLINE")
            .map(|v| matches!(v.to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
            .unwrap_or(false);
        if !offline {
            if let Some(live) = fetch_live() {
                base.extend(live.clone());
                if let Some(p) = &path {
                    write_cache(p, &live);
                }
                return (base, "live".to_string());
            }
        }

        // 3. Stale cache.
        if let Some(p) = &path {
            if let Some(tbl) = read_cache_table(p) {
                base.extend(tbl);
                return (base, "cache".to_string());
            }
        }

        // 4. Bundled fallback only.
        (base, "fallback".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t() -> Table {
        fallback_table()
    }

    #[test]
    fn normalize_strips_prefixes_and_1m_tag() {
        assert_eq!(normalize_model("anthropic/claude-opus-4-8"), "claude-opus-4-8");
        assert_eq!(normalize_model("claude-opus-4-8[1m]"), "claude-opus-4-8");
        assert_eq!(normalize_model("us.anthropic.claude-sonnet-4-5"), "claude-sonnet-4-5");
        assert_eq!(normalize_model("claude-sonnet-4-5-1m"), "claude-sonnet-4-5");
        assert_eq!(normalize_model("  GPT-5.1-Codex "), "gpt-5.1-codex");
    }

    #[test]
    fn date_and_version_suffix_stripping() {
        assert_eq!(strip_date_suffix("claude-opus-4-8-20260514"), "claude-opus-4-8");
        assert_eq!(strip_date_suffix("claude-opus-4-8-2026-05-14"), "claude-opus-4-8");
        assert_eq!(
            strip_ver_suffix(strip_date_suffix("claude-sonnet-4-5-20260101-v1:0")),
            "claude-sonnet-4-5"
        );
        assert_eq!(strip_ver_suffix("claude-sonnet-4-5-v1:0"), "claude-sonnet-4-5");
        // No date/ver -> unchanged.
        assert_eq!(strip_date_suffix("gpt-5.1-codex"), "gpt-5.1-codex");
    }

    #[test]
    fn match_exact_dated_and_family() {
        assert!(match_pricing("claude-opus-4-8", &t()).is_some());
        // dated variant resolves to the base.
        assert_eq!(match_pricing("claude-opus-4-8-20260514", &t()), match_pricing("claude-opus-4-8", &t()));
        // 1M tag.
        assert_eq!(match_pricing("claude-opus-4-8[1m]", &t()), match_pricing("claude-opus-4-8", &t()));
        // family fallback: unknown opus-4-7-ish id -> new flagship tier.
        assert_eq!(match_pricing("some-opus-4-7-preview", &t()), match_pricing("claude-opus-4-8", &t()));
        // unknown -> None.
        assert_eq!(match_pricing("totally-unknown-model", &t()), None);
    }

    #[test]
    fn turn_cost_matches_hand_computed() {
        // opus-4-8: in 5e-6, out 25e-6, cw 6.25e-6, cr 0.5e-6.
        let rate = match_pricing("claude-opus-4-8", &t());
        let c = turn_cost(rate.as_ref(), 1000, 2000, 3000, 4000);
        // 1000*5e-6 + 4000*25e-6 + 2000*6.25e-6 + 3000*0.5e-6
        let expect = 1000.0 * 5e-6 + 4000.0 * 25e-6 + 2000.0 * 6.25e-6 + 3000.0 * 0.5e-6;
        assert!((c - expect).abs() < 1e-12, "{c} vs {expect}");
    }

    #[test]
    fn tiering_only_applies_above_threshold_when_rate_present() {
        // sonnet-4-5 has a >200K input tier (6e-6 above).
        let rate = match_pricing("claude-sonnet-4-5", &t()).unwrap();
        let n = TIER_THRESHOLD + 100;
        let c = tiered(n, rate.input, rate.input_200k);
        let expect = TIER_THRESHOLD as f64 * 3e-6 + 100.0 * 6e-6;
        assert!((c - expect).abs() < 1e-12);
        // opus-4-8 has no tier: linear even above threshold.
        let r2 = match_pricing("claude-opus-4-8", &t()).unwrap();
        assert!((tiered(n, r2.input, r2.input_200k) - n as f64 * 5e-6).abs() < 1e-12);
    }
}
