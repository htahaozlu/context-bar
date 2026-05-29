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
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rate {
    pub input: Option<f64>,
    pub output: Option<f64>,
    pub cache_write: Option<f64>,
    pub cache_read: Option<f64>,
    pub input_200k: Option<f64>,
    pub output_200k: Option<f64>,
    pub cache_write_200k: Option<f64>,
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

/// Look up a key in the fallback table (exact).
fn table_get(key: &str) -> Option<Rate> {
    FALLBACK_PRICING
        .iter()
        .find(|(k, _)| *k == key)
        .map(|(_, r)| *r)
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

/// Resolve a transcript model id onto a rate. `None` when unpriceable
/// (cost 0 — an honest undercount, never a crash). Mirrors `match_pricing`.
pub fn match_pricing(model: &str) -> Option<Rate> {
    let norm = normalize_model(model);
    if norm.is_empty() {
        return None;
    }
    if let Some(r) = table_get(&norm) {
        return Some(r);
    }
    // Strip trailing release date / bedrock version, then retry exact.
    let stripped = strip_ver_suffix(strip_date_suffix(&norm)).to_string();
    if let Some(r) = table_get(&stripped) {
        return Some(r);
    }
    // Longest table key that is a prefix of the stripped id.
    let mut best: Option<Rate> = None;
    let mut best_len = 0usize;
    for (key, rate) in FALLBACK_PRICING {
        if stripped.starts_with(key) && key.len() > best_len {
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
            if let Some(r) = table_get(key) {
                return Some(r);
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

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(match_pricing("claude-opus-4-8").is_some());
        // dated variant resolves to the base.
        assert_eq!(match_pricing("claude-opus-4-8-20260514"), match_pricing("claude-opus-4-8"));
        // 1M tag.
        assert_eq!(match_pricing("claude-opus-4-8[1m]"), match_pricing("claude-opus-4-8"));
        // family fallback: unknown opus-4-7-ish id -> new flagship tier.
        assert_eq!(match_pricing("some-opus-4-7-preview"), match_pricing("claude-opus-4-8"));
        // unknown -> None.
        assert_eq!(match_pricing("totally-unknown-model"), None);
    }

    #[test]
    fn turn_cost_matches_hand_computed() {
        // opus-4-8: in 5e-6, out 25e-6, cw 6.25e-6, cr 0.5e-6.
        let rate = match_pricing("claude-opus-4-8");
        let c = turn_cost(rate.as_ref(), 1000, 2000, 3000, 4000);
        // 1000*5e-6 + 4000*25e-6 + 2000*6.25e-6 + 3000*0.5e-6
        let expect = 1000.0 * 5e-6 + 4000.0 * 25e-6 + 2000.0 * 6.25e-6 + 3000.0 * 0.5e-6;
        assert!((c - expect).abs() < 1e-12, "{c} vs {expect}");
    }

    #[test]
    fn tiering_only_applies_above_threshold_when_rate_present() {
        // sonnet-4-5 has a >200K input tier (6e-6 above).
        let rate = match_pricing("claude-sonnet-4-5").unwrap();
        let n = TIER_THRESHOLD + 100;
        let c = tiered(n, rate.input, rate.input_200k);
        let expect = TIER_THRESHOLD as f64 * 3e-6 + 100.0 * 6e-6;
        assert!((c - expect).abs() < 1e-12);
        // opus-4-8 has no tier: linear even above threshold.
        let r2 = match_pricing("claude-opus-4-8").unwrap();
        assert!((tiered(n, r2.input, r2.input_200k) - n as f64 * 5e-6).abs() < 1e-12);
    }
}
