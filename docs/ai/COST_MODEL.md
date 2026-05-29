# Cost Model — verified methodology

How context-bar estimates API-equivalent cost. All numbers/behaviors below were verified against authoritative sources (Anthropic official pricing docs, ccusage/better-ccusage source, LiteLLM dataset) and a `codex` correctness review. Preserve this fidelity.

## Principle

Subscription users (Pro/Max) aren't billed per token; API-key users are. **The transcripts do NOT record which mode a session used** — Claude Code v2.1.x JSONL has no `costUSD`, `apiKeySource`, or `authType` on assistant turns; Codex `turn_context` has no billing field. So we cannot split historical usage by billing mode. Everything is shown as an **estimate** of what the metered API would charge. The UI says this plainly. Don't claim it's a bill.

## Formula (matches ccusage / better-ccusage exactly)

Per assistant turn, priced by that turn's model:
```
cost = input_tokens              * input_cost_per_token
     + output_tokens             * output_cost_per_token
     + cache_creation_tokens     * cache_creation_input_token_cost
     + cache_read_tokens         * cache_read_input_token_cost
```
- **Anthropic >200K long-context tier**, applied PER token-category: the first 200_000 tokens of a category bill at the base rate, the remainder at the `*_above_200k_tokens` rate — only when that rate exists for the model. Threshold is strictly `> 200_000`. (See `_tiered()` in `usage_signal.py`.)
- **costUSD precedence (ccusage "auto" mode):** if a transcript turn carries a top-level `costUSD`, use it verbatim; else compute from tokens. (Current Claude Code doesn't emit it, so computation is the live path — but honor it if present.)
- **Codex/OpenAI:** no cache-write charge. `input_tokens` from `last_token_usage` INCLUDES `cached_input_tokens`, so `fresh = input - cached`; `cached` bills at the cache-read rate; `output + reasoning_output` bills at the output rate.

## Rates: source of truth

Rates come from **LiteLLM's** canonical dataset (the same source ccusage uses):
`https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`
- Live fetch with a **24h on-disk cache** at `~/.context-bar/pricing.cache.json`, plus a **bundled offline fallback** table (`FALLBACK_PRICING` in `usage_signal.py`) for fully-offline machines. `CONTEXTBAR_PRICING_OFFLINE=1` forces offline. Strategy mirrors ccusage: fresh cache → live → stale cache → bundled.
- Exact LiteLLM field names: `input_cost_per_token`, `output_cost_per_token`, `cache_creation_input_token_cost`, `cache_read_input_token_cost`, and `*_above_200k_tokens` variants. Rates are **per token** (e.g. `5e-6` = $5/Mtok).
- `pricing_source` in the snapshot records `live` | `cache` | `fallback`. `pricing_is_estimate` is always true.

### Verified Anthropic rates ($/Mtok, confirmed 2026-05-29 against docs.claude.com/.../pricing)
| Model | Input | Output | 5m cache write | cache read |
|---|---|---|---|---|
| Opus 4.5 / 4.6 / 4.7 / 4.8 | $5 | $25 | $6.25 | $0.50 |
| Opus 4.0 / 4.1 | $15 | $75 | $18.75 | $1.50 |
| Sonnet 4.0 / 4.5 / 4.6 | $3 | $15 | $3.75 | $0.30 |
| Haiku 4.5 | $1 | $5 | $1.25 | $0.10 |
- Cache multipliers (confirmed): 5-min write = **1.25×** input, 1-hour write = **2×** input, cache read = **0.1×** input.
- **Long-context >200K: NO premium** for current 1M-context models (Opus 4.6/4.7/4.8, Sonnet 4.6) per the official page. LiteLLM still carries a >200K tier for **Sonnet 4.5 / 4.0** (input 2×=$6, output 1.5×=$22.5, cache-write $7.5, cache-read $0.60). We follow LiteLLM (ccusage parity, conservative); the official page now shows Sonnet 4.5 flat — documented as a deliberate, immaterial choice in code.
- Codex/GPT-5 family rates also from LiteLLM (e.g. gpt-5/5.1/5.1-codex $1.25/$10; gpt-5.2/5.3-codex $1.75/$14; gpt-5.5 $5/$30; cache-read = input/10; no cache-write).

### Model matching (`match_pricing` in `usage_signal.py`)
Resolve a transcript model id onto a rate dict: normalize (lowercase; strip provider prefixes `anthropic/`, `us.anthropic.`, etc.; strip `[1m]`/`-1m` context tag) → exact key → date/version-stripped exact (`-YYYYMMDD`, `-vN:0`) → longest table-key that is a prefix → `FAMILY_FALLBACK` regex (opus-4-5+→new tier, opus-4→legacy, sonnet-4→…, haiku→…, gpt-5.x→…). Unknown model → `None` → cost 0 (honest undercount, not a crash). Verified: resolves `claude-opus-4-8`, `claude-opus-4-8[1m]`, dated variants, `mythos`→opus-4-8 estimate.

## Aggregation & emitted fields

Per-turn metrics (`{total, cache_read, input, output, cache_creation, cost}`) accumulate into:
- `by_day` / `by_week` / `by_month` / `by_model` / `by_project` — each carries tokens, sessions, cache_read, input, output, cache_creation, cost.
- `by_day_project` — the per (day × project) cross-tab (the `better-ccusage daily --instances` view) with models[], all token buckets, cost.
- `recent_sessions` — last 20, with all buckets + cost.
- Block totals: `cost_5h`, `cost_7d` (per-turn rolling windows), `cost_today`, `total_cost_30d`, `total_input_30d`, `total_output_30d`, `cache_savings_30d` (per-turn over 30d), `active_session_cost`.
- `active_sessions[].cost`.

**Day-attribution convention:** day/week/month buckets attribute a sessionized chunk to its END day (`last_ts`) — the same convention the token stats use, so a row's tokens and cost agree. 30-day/all-time TOTALS are exact; only single-day attribution can differ from a strict per-turn split (ccusage) for a session crossing local midnight. codex confirmed the per-token formula is correct and this is the only aggregation nuance.

**Total Tokens semantics:** the Cost tab's "Total" column = input + output + cache_creation + cache_read (ccusage's "Total Tokens"). This is DISTINCT from the Stats/HUD `tokens` total (= fresh_in + output only, memory invariant). Keep both, labeled.

## Differentiators we compute (no other tracker does these)
- **Cache savings** (`cache_savings_30d`, `turn_cache_savings`): NET USD prompt caching saved vs paying full input price = `(cache_create+cache_read priced at input rate) − (actual cache write + cache read cost)`. Strongly positive for heavy reuse. Honest (can be slightly negative on a write-heavy turn).
- **Plan-value projection** (Swift): monthly run-rate (= `total_cost_30d`) vs the active Anthropic plan price (Pro $20, Max 5x $100, Max 20x $200 — verified) → "≈ $X/mo, about N× your Max 20× plan." Only shown for Claude with a detected subscription account.

## Reference
The user's design target for the daily table is `docs/ccusage.png` (a `ccusage daily` screenshot): columns Date · Agent · Models · Input · Output · Cache Create · Cache Read · Total Tokens · Cost (USD), grouped by date with All + per-agent sub-rows and a Total row. The Cost tab now mirrors this natively per-project.
