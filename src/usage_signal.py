"""Aggregate Claude Code + Codex CLI token usage across all projects.

Stdout: single JSON document. Layout:

  {
    "claude":  AgentBlock,
    "codex":   AgentBlock,
    "collected_at": ISO8601,
    "source": "python3"
  }

AgentBlock contains:
  - Live HUD fields (used by ~/.context-bar/context.json):
      session_5h_tokens, week_7d_tokens, active_session_tokens,
      active_session_file, last_turn_input_tokens, last_turn_output_tokens,
      last_model, last_context_window, last_context_pct, last_turn_at,
      last_cwd, active_session_started_at
  - Aggregates for the detail page:
      total_tokens_30d, total_sessions_30d,
      by_day:   [{date, tokens, sessions}]   (last 30 days)
      by_week:  [{week, tokens, sessions}]   (last 12 ISO weeks)
      by_month: [{month, tokens, sessions}]  (last 12 months)
      by_model: [{model, tokens, sessions}]  (all-time within scanned files)
      by_project:[{project, tokens, sessions}]
      recent_sessions: last 20 sessions {id, started_at, ended_at,
                       duration_minutes, tokens, model, project}

Why python3: aggregating dozens of multi-MB JSONL files from the wasm32
extension sandbox in pure Rust would duplicate logic python3 ships natively.
"""

import glob
import json
import os
import re
import select
import shutil
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from urllib import request

NOW = time.time()
WIN_SESSION = 5 * 3600
WIN_WEEK = 7 * 86400
WIN_30D = 30 * 86400
# History window for streaks / longest streak / heatmap. Files older than this
# are skipped during scan; aggregates pad calendar days inside this window.
WIN_HIST = 365 * 86400
# Idle gap that splits a single .jsonl into multiple logical sessions. Matches
# the 5h rolling window Claude uses to reset session metrics in its own UI.
SESSION_IDLE_GAP = 5 * 3600
# A session is "active" if its last turn is within this window. 30 min covers
# slow human-in-the-loop pauses without surfacing stale sessions as live.
ACTIVE_WINDOW = 30 * 60
CACHE_TTL_OK = 5 * 60
CACHE_TTL_ERR = 15
STATUSLINE_TTL = 12 * 3600

# ── Cost estimation ───────────────────────────────────────────────────────────
# We surface an *estimated* per-token cost so subscription users can see what
# their usage would bill on the metered API. Method mirrors ccusage /
# better-ccusage exactly (the tools this view replicates):
#   cost = input*input_rate + output*output_rate
#        + cache_creation*cache_write_rate + cache_read*cache_read_rate
# applied per turn (so the model that produced each turn is priced correctly),
# with Anthropic's >200K long-context tier applied per token-category when the
# model carries an `*_above_200k_tokens` rate (Sonnet 4.5 does; the current 1M
# models — Opus 4.6/4.7/4.8, Sonnet 4.6 — bill flat, so their tier rates are
# absent). Rates come from LiteLLM's canonical dataset (same source ccusage
# uses), fetched live with a 24h disk cache and a bundled offline fallback.
LITELLM_PRICING_URL = (
    "https://raw.githubusercontent.com/BerriAI/litellm/main/"
    "model_prices_and_context_window.json"
)
PRICING_TTL = 24 * 3600
TIER_THRESHOLD = 200_000

# Bundled fallback rates (USD per token), captured from the LiteLLM dataset.
# Used only when the live fetch fails and no fresh cache exists, so a fully
# offline machine still reports sensible costs. Keys mirror LiteLLM model keys;
# the matcher below resolves dated / suffixed transcript model ids onto these.
# Fields: in=input, out=output, cw=cache write (5m), cr=cache read, and the
# optional *_200k variants for the >200K tier.
FALLBACK_PRICING = {
    # Claude — Opus 4.5+ share the lower flagship tier ($5/$25); 4.1/4.0 are
    # the legacy high tier ($15/$75).
    "claude-opus-4-8": {"in": 5e-6, "out": 25e-6, "cw": 6.25e-6, "cr": 0.5e-6},
    "claude-opus-4-7": {"in": 5e-6, "out": 25e-6, "cw": 6.25e-6, "cr": 0.5e-6},
    "claude-opus-4-6": {"in": 5e-6, "out": 25e-6, "cw": 6.25e-6, "cr": 0.5e-6},
    "claude-opus-4-5": {"in": 5e-6, "out": 25e-6, "cw": 6.25e-6, "cr": 0.5e-6},
    "claude-opus-4-1": {"in": 15e-6, "out": 75e-6, "cw": 18.75e-6, "cr": 1.5e-6},
    "claude-opus-4": {"in": 15e-6, "out": 75e-6, "cw": 18.75e-6, "cr": 1.5e-6},
    # Sonnet 4.6 bills flat. Sonnet 4.5 / 4.0 carry a >200K tier in the LiteLLM
    # dataset (ccusage's source) so we keep it here for parity and as a
    # conservative estimate. Note: Anthropic's live pricing page (2026-05) shows
    # Sonnet 4.5 at flat $3/$15 with no >200K row, so the tier may be historical;
    # online runs follow whatever LiteLLM currently publishes.
    "claude-sonnet-4-6": {"in": 3e-6, "out": 15e-6, "cw": 3.75e-6, "cr": 0.3e-6},
    "claude-sonnet-4-5": {
        "in": 3e-6, "out": 15e-6, "cw": 3.75e-6, "cr": 0.3e-6,
        "in_200k": 6e-6, "out_200k": 22.5e-6, "cw_200k": 7.5e-6, "cr_200k": 0.6e-6,
    },
    "claude-sonnet-4": {
        "in": 3e-6, "out": 15e-6, "cw": 3.75e-6, "cr": 0.3e-6,
        "in_200k": 6e-6, "out_200k": 22.5e-6, "cw_200k": 7.5e-6, "cr_200k": 0.6e-6,
    },
    "claude-3-7-sonnet": {"in": 3e-6, "out": 15e-6, "cw": 3.75e-6, "cr": 0.3e-6},
    "claude-3-5-sonnet": {"in": 3e-6, "out": 15e-6, "cw": 3.75e-6, "cr": 0.3e-6},
    "claude-haiku-4-5": {"in": 1e-6, "out": 5e-6, "cw": 1.25e-6, "cr": 0.1e-6},
    "claude-3-5-haiku": {"in": 0.8e-6, "out": 4e-6, "cw": 1e-6, "cr": 0.08e-6},
    # Mythos preview has no published per-token row; price as the current
    # flagship (Opus 4.8) — an estimate, flagged as such by pricing_is_estimate.
    "mythos": {"in": 5e-6, "out": 25e-6, "cw": 6.25e-6, "cr": 0.5e-6},
    # OpenAI / Codex — no cache-write charge (cw absent); cached input billed at
    # the read rate.
    "gpt-5": {"in": 1.25e-6, "out": 10e-6, "cr": 0.125e-6},
    "gpt-5-codex": {"in": 1.25e-6, "out": 10e-6, "cr": 0.125e-6},
    "gpt-5-pro": {"in": 15e-6, "out": 120e-6},
    "gpt-5-mini": {"in": 0.25e-6, "out": 2e-6, "cr": 0.025e-6},
    "gpt-5-nano": {"in": 0.05e-6, "out": 0.4e-6, "cr": 0.005e-6},
    "gpt-5.1": {"in": 1.25e-6, "out": 10e-6, "cr": 0.125e-6},
    "gpt-5.1-codex": {"in": 1.25e-6, "out": 10e-6, "cr": 0.125e-6},
    "gpt-5.1-codex-max": {"in": 1.25e-6, "out": 10e-6, "cr": 0.125e-6},
    "gpt-5.1-codex-mini": {"in": 0.25e-6, "out": 2e-6, "cr": 0.025e-6},
    "gpt-5.2": {"in": 1.75e-6, "out": 14e-6, "cr": 0.175e-6},
    "gpt-5.2-codex": {"in": 1.75e-6, "out": 14e-6, "cr": 0.175e-6},
    "gpt-5.3-codex": {"in": 1.75e-6, "out": 14e-6, "cr": 0.175e-6},
    "gpt-5.4": {"in": 2.5e-6, "out": 15e-6, "cr": 0.25e-6},
    "gpt-5.4-codex": {"in": 2.5e-6, "out": 15e-6, "cr": 0.25e-6},
    "gpt-5.4-mini": {"in": 0.75e-6, "out": 4.5e-6, "cr": 0.075e-6},
    "gpt-5.4-nano": {"in": 0.2e-6, "out": 1.25e-6, "cr": 0.02e-6},
    "gpt-5.4-pro": {"in": 30e-6, "out": 180e-6, "cr": 3e-6},
    "gpt-5.5": {"in": 5e-6, "out": 30e-6, "cr": 0.5e-6},
    "gpt-5.5-pro": {"in": 30e-6, "out": 180e-6, "cr": 3e-6},
    "codex-mini-latest": {"in": 1.5e-6, "out": 6e-6, "cr": 0.375e-6},
    "o4-mini": {"in": 1.1e-6, "out": 4.4e-6, "cr": 0.275e-6},
    "o3": {"in": 2e-6, "out": 8e-6, "cr": 0.5e-6},
    "o3-mini": {"in": 1.1e-6, "out": 4.4e-6, "cr": 0.55e-6},
}

# Coarse family fallback for model ids that resolve to no exact / dated key.
# Checked last. Order matters: more specific patterns first.
FAMILY_FALLBACK = [
    (re.compile(r"opus-4-(?:5|6|7|8)"), "claude-opus-4-8"),
    (re.compile(r"opus-4"), "claude-opus-4"),
    (re.compile(r"mythos"), "mythos"),
    (re.compile(r"sonnet-4"), "claude-sonnet-4-6"),
    (re.compile(r"3-7-sonnet"), "claude-3-7-sonnet"),
    (re.compile(r"3-5-sonnet"), "claude-3-5-sonnet"),
    (re.compile(r"haiku-4"), "claude-haiku-4-5"),
    (re.compile(r"3-5-haiku|haiku"), "claude-3-5-haiku"),
    (re.compile(r"gpt-5\.5-pro"), "gpt-5.5-pro"),
    (re.compile(r"gpt-5\.5"), "gpt-5.5"),
    (re.compile(r"gpt-5\.4-codex"), "gpt-5.4-codex"),
    (re.compile(r"gpt-5\.4"), "gpt-5.4"),
    (re.compile(r"gpt-5\.3-codex|gpt-5\.2-codex|gpt-5\.2|gpt-5\.3"), "gpt-5.2"),
    (re.compile(r"gpt-5\.1-codex"), "gpt-5.1-codex"),
    (re.compile(r"gpt-5\.1"), "gpt-5.1"),
    (re.compile(r"gpt-5-codex|codex"), "gpt-5-codex"),
    (re.compile(r"gpt-5"), "gpt-5"),
    (re.compile(r"o4-mini"), "o4-mini"),
    (re.compile(r"o3-mini"), "o3-mini"),
    (re.compile(r"o3"), "o3"),
]

_DATE_SUFFIX = re.compile(r"-(?:\d{8}|\d{4}-\d{2}-\d{2})(?:-v\d+:\d+)?$")
_VER_SUFFIX = re.compile(r"-v\d+:\d+$")
_PRICING_CACHE = None  # memoized (table, source) per process


def pricing_cache_path():
    home = os.environ.get("HOME", "")
    if not home:
        return None
    return os.path.join(home, ".context-bar", "pricing.cache.json")


def _normalize_litellm_entry(entry):
    """Project a LiteLLM model entry onto our short rate dict, dropping nulls."""
    if not isinstance(entry, dict):
        return None
    out = {}
    mapping = {
        "in": "input_cost_per_token",
        "out": "output_cost_per_token",
        "cw": "cache_creation_input_token_cost",
        "cr": "cache_read_input_token_cost",
        "in_200k": "input_cost_per_token_above_200k_tokens",
        "out_200k": "output_cost_per_token_above_200k_tokens",
        "cw_200k": "cache_creation_input_token_cost_above_200k_tokens",
        "cr_200k": "cache_read_input_token_cost_above_200k_tokens",
    }
    for short, key in mapping.items():
        v = entry.get(key)
        if isinstance(v, (int, float)) and v >= 0:
            out[short] = float(v)
    # Need at least an input or output rate to be useful.
    if "in" in out or "out" in out:
        return out
    return None


def _pricing_is_relevant(key):
    k = key.lower()
    return any(s in k for s in (
        "claude", "sonnet", "opus", "haiku", "mythos",
        "gpt-5", "gpt-4", "codex", "o1", "o3", "o4", "gemini",
        # Other coding-agent backends the app surfaces or users may route to.
        "glm", "zai", "deepseek", "qwen", "kimi", "moonshot",
        "minimax", "mistral", "grok", "llama",
    ))


def fetch_litellm_pricing():
    """Fetch + filter the LiteLLM rate dataset. Returns short-rate table or None."""
    req = request.Request(
        LITELLM_PRICING_URL,
        headers={"User-Agent": "context-bar/usage", "Accept": "application/json"},
    )
    try:
        with request.urlopen(req, timeout=15) as resp:
            if getattr(resp, "status", 200) != 200:
                return None
            raw = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None
    if not isinstance(raw, dict):
        return None
    table = {}
    for key, entry in raw.items():
        if not _pricing_is_relevant(key):
            continue
        norm = _normalize_litellm_entry(entry)
        if norm:
            table[key.lower()] = norm
    return table or None


def load_pricing():
    """(table, source) where source ∈ {live, cache, fallback}. Memoized per run.

    Strategy mirrors ccusage: fresh 24h cache → live LiteLLM fetch (then cache)
    → stale cache → bundled fallback. The bundled table is merged underneath so
    a partial live dataset never loses coverage of a known family.
    """
    global _PRICING_CACHE
    if _PRICING_CACHE is not None:
        return _PRICING_CACHE

    base = dict(FALLBACK_PRICING)
    path = pricing_cache_path()
    now = time.time()

    # 1. Fresh on-disk cache.
    if path and os.path.exists(path):
        try:
            age = now - os.path.getmtime(path)
            if age < PRICING_TTL:
                with open(path, "r", encoding="utf-8") as fh:
                    cached = json.load(fh)
                if isinstance(cached, dict) and cached.get("table"):
                    base.update(cached["table"])
                    _PRICING_CACHE = (base, "cache")
                    return _PRICING_CACHE
        except Exception:
            pass

    # 2. Live fetch (and refresh cache) — unless offline mode is forced.
    offline = os.environ.get("CONTEXTBAR_PRICING_OFFLINE", "").lower() in ("1", "true", "yes")
    live = None if offline else fetch_litellm_pricing()
    if live:
        base.update(live)
        if path:
            try:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as fh:
                    json.dump({"timestamp": int(now), "table": live}, fh)
            except Exception:
                pass
        _PRICING_CACHE = (base, "live")
        return _PRICING_CACHE

    # 3. Stale cache (network down but we fetched successfully before).
    if path and os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                cached = json.load(fh)
            if isinstance(cached, dict) and cached.get("table"):
                base.update(cached["table"])
                _PRICING_CACHE = (base, "cache")
                return _PRICING_CACHE
        except Exception:
            pass

    # 4. Bundled fallback only.
    _PRICING_CACHE = (base, "fallback")
    return _PRICING_CACHE


def normalize_model(model):
    if not model:
        return ""
    m = str(model).lower().strip()
    for prefix in (
        "anthropic/", "anthropic.", "us.anthropic.", "eu.anthropic.",
        "apac.anthropic.", "openai/", "openrouter/", "claude-code/",
        "github_copilot/", "bedrock/", "vertex_ai/",
    ):
        if m.startswith(prefix):
            m = m[len(prefix):]
    # Drop a 1M-context tag — pricing is identical to the base model.
    m = m.replace("[1m]", "").replace("-1m-", "-")
    if m.endswith("-1m"):
        m = m[:-3]
    return m


def match_pricing(model, table):
    """Resolve a transcript model id onto a rate dict. None when unpriceable."""
    norm = normalize_model(model)
    if not norm:
        return None
    if norm in table:
        return table[norm]
    # Strip a trailing release date / bedrock version, then retry exact.
    stripped = _VER_SUFFIX.sub("", _DATE_SUFFIX.sub("", norm))
    if stripped in table:
        return table[stripped]
    # Longest table key that is a prefix of the (stripped) model id — handles
    # ids more specific than any catalog key, e.g. claude-opus-4-8-<date>.
    best, best_len = None, 0
    for key, rate in table.items():
        if stripped.startswith(key) and len(key) > best_len:
            best, best_len = rate, len(key)
    if best is not None:
        return best
    # Coarse family fallback.
    for pattern, key in FAMILY_FALLBACK:
        if pattern.search(stripped) and key in table:
            return table[key]
    return None


def _tiered(tokens, base, above):
    """Anthropic >200K tiering for one token category (ccusage-compatible)."""
    if not tokens or tokens <= 0 or base is None:
        return 0.0
    if above is not None and tokens > TIER_THRESHOLD:
        return TIER_THRESHOLD * base + (tokens - TIER_THRESHOLD) * above
    return tokens * base


def turn_cost(rate, inp, cache_create, cache_read, outp):
    """Estimated USD for one turn given its rate dict and token buckets."""
    if not rate:
        return 0.0
    return (
        _tiered(inp, rate.get("in"), rate.get("in_200k"))
        + _tiered(outp, rate.get("out"), rate.get("out_200k"))
        + _tiered(cache_create, rate.get("cw"), rate.get("cw_200k"))
        + _tiered(cache_read, rate.get("cr"), rate.get("cr_200k"))
    )


def turn_cache_savings(rate, cache_create, cache_read):
    """USD that prompt caching saved on this turn — the NET benefit, not a gross
    figure. Without caching, the cache_creation + cache_read tokens would each
    be billed as fresh input; with caching we instead pay the write premium on
    creates plus the cheap (0.1x) reads. savings = (no-cache cost) − (actual
    cache cost). Can be slightly negative on a turn that writes more cache than
    it reuses, but is strongly positive once a cached prefix is re-read."""
    if not rate:
        return 0.0
    in_rate = rate.get("in")
    if in_rate is None:
        return 0.0
    in_200k = rate.get("in_200k")
    no_cache = _tiered(cache_create, in_rate, in_200k) + _tiered(cache_read, in_rate, in_200k)
    actual = (_tiered(cache_create, rate.get("cw"), rate.get("cw_200k"))
              + _tiered(cache_read, rate.get("cr"), rate.get("cr_200k")))
    return no_cache - actual


def empty_metrics():
    return {
        "total": 0, "cache_read": 0, "input": 0, "output": 0,
        "cache_creation": 0, "cost": 0.0,
    }


def _add_metrics(dst, m):
    dst["total"] += m["total"]
    dst["cache_read"] += m["cache_read"]
    dst["input"] += m["input"]
    dst["output"] += m["output"]
    dst["cache_creation"] += m["cache_creation"]
    dst["cost"] += m["cost"]


def parse_iso(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def empty_block():
    return {
        # live HUD
        "session_5h_tokens": 0,
        "session_5h_percent": None,
        "cache_read_tokens_5h": 0,
        "week_7d_tokens": 0,
        "week_7d_percent": None,
        "cache_read_tokens_7d": 0,
        "cache_read_tokens_30d": 0,
        "active_session_tokens": 0,
        "active_session_file": None,
        "active_session_started_at": None,
        "last_turn_input_tokens": 0,
        "last_turn_output_tokens": 0,
        "last_model": None,
        "last_context_window": None,
        "last_context_pct": None,
        "last_turn_at": None,
        "last_cwd": None,
        # aggregates
        "total_tokens_30d": 0,
        "total_sessions_30d": 0,
        # Estimated API-equivalent cost (USD). See pricing section: these are
        # estimates for subscription users, not billed amounts.
        "cost_5h": 0.0,
        "cost_7d": 0.0,
        "cost_today": 0.0,
        "total_cost_30d": 0.0,
        "total_input_30d": 0,
        "total_output_30d": 0,
        # Net USD prompt caching saved over the 30d window (differentiator).
        "cache_savings_30d": 0.0,
        "by_day": [],
        "by_week": [],
        "by_month": [],
        "by_model": [],
        "by_project": [],
        # Per (day × project) rows — the `better-ccusage daily --instances` view.
        "by_day_project": [],
        "recent_sessions": [],
        "active_sessions": [],
        # When the rolling 5h / 7d usage windows next free up — the timestamp
        # of the oldest in-window turn plus the window length.
        "session_5h_resets_at": None,
        "week_7d_resets_at": None,
    }


def usage_cache_path():
    home = os.environ.get("HOME", "")
    if not home:
        return None
    return os.path.join(home, ".context-bar", "usage_api_cache.json")


def claude_statusline_path():
    override = os.environ.get("CONTEXTBAR_CLAUDE_STATUSLINE_PATH")
    if override:
        return override
    home = os.environ.get("HOME", "")
    if not home:
        return None
    return os.path.join(home, ".context-bar", "claude-statusline.json")


def load_usage_cache():
    path = usage_cache_path()
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def save_usage_cache(payload):
    path = usage_cache_path()
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
    except Exception:
        pass


def read_claude_credentials():
    home = os.environ.get("HOME", "")
    if not home:
        return None
    now_ms = int(time.time() * 1000)

    raw = None
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if out.returncode == 0:
            raw = out.stdout.strip()
    except Exception:
        raw = None

    if raw:
        try:
            data = json.loads(raw)
            oauth = data.get("claudeAiOauth") or {}
            token = oauth.get("accessToken")
            expires_at = oauth.get("expiresAt")
            if token and (expires_at is None or expires_at > now_ms):
                return token
        except Exception:
            if raw.startswith("sk-ant"):
                return raw

    credentials_path = os.path.join(home, ".claude", ".credentials.json")
    if not os.path.exists(credentials_path):
        return None
    try:
        with open(credentials_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        oauth = data.get("claudeAiOauth") or {}
        token = oauth.get("accessToken")
        expires_at = oauth.get("expiresAt")
        if token and (expires_at is None or expires_at > now_ms):
            return token
    except Exception:
        return None
    return None


def fetch_claude_usage_api():
    cached = load_usage_cache()
    now = int(time.time())
    if cached:
        ts = int(cached.get("timestamp", 0) or 0)
        ttl = CACHE_TTL_OK if cached.get("ok") else CACHE_TTL_ERR
        if ts > 0 and now - ts < ttl:
            return cached.get("data")

    token = read_claude_credentials()
    if not token:
        save_usage_cache({"timestamp": now, "ok": False, "data": None})
        return None

    req = request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.1",
        },
    )
    try:
        with request.urlopen(req, timeout=15) as resp:
            if resp.status != 200:
                save_usage_cache({"timestamp": now, "ok": False, "data": None})
                return None
            payload = json.loads(resp.read().decode("utf-8"))
            save_usage_cache({"timestamp": now, "ok": True, "data": payload})
            return payload
    except Exception:
        fallback = cached.get("data") if cached else None
        save_usage_cache({"timestamp": now, "ok": False, "data": fallback})
        return fallback


def parse_usage_percent(value):
    # Anthropic's `utilization` can transiently exceed 100% right before reset.
    # Surface that overrun (capped at 200% to keep UI sane) instead of silently
    # clamping to 100, which would hide the real state.
    if isinstance(value, (int, float)):
        return round(max(0.0, min(200.0, float(value))), 1)
    return None


def _write_json_line(proc, payload):
    try:
        proc.stdin.write(json.dumps(payload) + "\n")
        proc.stdin.flush()
        return True
    except Exception:
        return False


def fetch_codex_rate_limits_app_server(timeout=12):
    """Read live Codex quota state through the local Codex app-server.

    Codex transcripts only receive `rate_limits` when a Codex turn streams a
    token_count event. The account/rateLimits/read app-server method is the
    same local path Codex UI uses for its balance panel, so a ContextBar
    refresh can update quota without needing a new Codex assistant turn.
    """
    exe = shutil.which("codex")
    if not exe:
        return None
    try:
        proc = subprocess.Popen(
            [exe, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except Exception:
        return None

    try:
        init = {
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {"name": "contextbar", "version": "0"},
                "capabilities": None,
            },
        }
        req = {"id": 2, "method": "account/rateLimits/read", "params": None}
        if not _write_json_line(proc, init) or not _write_json_line(proc, req):
            return None

        deadline = time.time() + timeout
        while time.time() < deadline:
            if proc.stdout is None:
                return None
            ready, _, _ = select.select([proc.stdout], [], [], max(0.0, deadline - time.time()))
            if not ready:
                break
            line = proc.stdout.readline()
            if not line:
                break
            try:
                msg = json.loads(line)
            except Exception:
                continue
            if msg.get("id") != 2:
                continue
            result = msg.get("result") or {}
            by_id = result.get("rateLimitsByLimitId") or {}
            if isinstance(by_id, dict) and isinstance(by_id.get("codex"), dict):
                return by_id.get("codex")
            if isinstance(result.get("rateLimits"), dict):
                return result.get("rateLimits")
            return None
    finally:
        try:
            if proc.stdin:
                proc.stdin.close()
        except Exception:
            pass
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
    return None


def _epoch_to_iso(value):
    if not isinstance(value, (int, float)):
        return None
    if value <= NOW:
        return None
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def parse_codex_rate_limit_window(window):
    if not isinstance(window, dict):
        return (None, None)
    pct = parse_usage_percent(window.get("usedPercent"))
    if pct is None:
        pct = parse_usage_percent(window.get("used_percent"))
    resets = _epoch_to_iso(window.get("resetsAt"))
    if resets is None:
        resets = _epoch_to_iso(window.get("resets_at"))
    return (pct, resets)


def apply_codex_rate_limits(out, snapshot):
    if not isinstance(snapshot, dict):
        return out
    primary = snapshot.get("primary") or {}
    secondary = snapshot.get("secondary") or {}
    pct, resets = parse_codex_rate_limit_window(primary)
    if pct is not None:
        out["session_5h_percent"] = pct
    if resets:
        out["session_5h_resets_at"] = resets
    pct, resets = parse_codex_rate_limit_window(secondary)
    if pct is not None:
        out["week_7d_percent"] = pct
    if resets:
        out["week_7d_resets_at"] = resets
    return out


def apply_claude_usage_api(out):
    payload = fetch_claude_usage_api()
    if not isinstance(payload, dict):
        return out
    five = payload.get("five_hour") or {}
    seven = payload.get("seven_day") or {}
    out["session_5h_percent"] = parse_usage_percent(five.get("utilization"))
    out["week_7d_percent"] = parse_usage_percent(seven.get("utilization"))
    if five.get("resets_at"):
        out["session_5h_resets_at"] = five.get("resets_at")
    if seven.get("resets_at"):
        out["week_7d_resets_at"] = seven.get("resets_at")
    return out


def load_claude_statusline_snapshot():
    path = claude_statusline_path()
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
    except Exception:
        return None
    ts = parse_iso(payload.get("updated_at"))
    if ts is None:
        try:
            ts = os.path.getmtime(path)
        except OSError:
            ts = None
    if ts is None or NOW - ts > STATUSLINE_TTL:
        return None
    payload["_timestamp"] = ts
    return payload


def build_active_sessions(per_session):
    """Return list of session dicts where last_ts is within ACTIVE_WINDOW."""
    actives = []
    for path, s in per_session.items():
        if NOW - s["last_ts"] > ACTIVE_WINDOW:
            continue
        # Per-session context window — explicit override (Codex), or derived
        # from model (Claude). Falls back to None when neither is known.
        window = s.get("last_window")
        if not window:
            try:
                window = claude_context_window(
                    s.get("model"),
                    observed_max=int(s.get("max_ctx", 0) or 0),
                    betas=list(s.get("betas") or []),
                )
            except Exception:
                window = None
        last_input = int(s.get("last_input", 0) or 0)
        context_pct = None
        if window and last_input > 0:
            context_pct = round(min(200.0, last_input / window * 100.0), 1)
        actives.append({
            "id": os.path.basename(path).rsplit(".", 1)[0],
            "tokens": s["tokens"],
            "started_at": datetime.fromtimestamp(s["first_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "last_turn_at": datetime.fromtimestamp(s["last_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "model": s["model"],
            "cwd": s["cwd"],
            "project": project_name_from_cwd(s["cwd"]),
            "context_pct": context_pct,
            "context_window": window,
            "last_input_tokens": last_input,
        })
    actives.sort(key=lambda x: x["last_turn_at"], reverse=True)
    return actives


def claude_context_window(model, observed_max=0, betas=None):
    # Env override for power users who know their window.
    env = os.environ.get("CONTEXTBAR_CONTEXT_WINDOW")
    if env:
        try:
            return int(env)
        except ValueError:
            pass
    if model:
        m = model.lower()
        # Explicit 1M tag — most reliable signal.
        if "[1m]" in m or "-1m" in m:
            return 1_000_000
        # Claude Code defaults for models that ship with the 1M context beta
        # enabled. These match the variants CC actually requests; without the
        # statusline hook the JSONL drops the [1m] suffix, so we use the
        # model family to fill in. Haiku stays at 200K.
        if "haiku" in m:
            return 200_000
        if ("opus-4-7" in m or "opus-4-6" in m
                or "sonnet-4-7" in m or "sonnet-4-6" in m
                or "sonnet-4-5" in m or "mythos" in m):
            return 1_000_000
    # Beta header recorded in transcript (Anthropic 1M context beta).
    if betas:
        for b in betas:
            bl = str(b).lower()
            if "context-1m" in bl or "1m-2025" in bl:
                return 1_000_000
    # Adaptive fallback: a turn whose context already exceeds 200K can only
    # have happened on the 1M variant. Snap to 1M so % is meaningful.
    if observed_max and observed_max > 200_000:
        return 1_000_000
    return 200_000


def parse_claude_rate_limit_window(rate_limits, *keys):
    if not isinstance(rate_limits, dict):
        return (None, None)
    current = rate_limits
    for key in keys:
        current = current.get(key) if isinstance(current, dict) else None
    if not isinstance(current, dict):
        return (None, None)
    pct = parse_usage_percent(current.get("used_percentage"))
    if pct is None:
        pct = parse_usage_percent(current.get("utilization"))
    if pct is None:
        pct = parse_usage_percent(current.get("used_percent"))
    resets = current.get("resets_at")
    if isinstance(resets, (int, float)):
        resets = datetime.fromtimestamp(resets, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    elif not isinstance(resets, str):
        resets = None
    return (pct, resets)


def apply_claude_statusline_snapshot(out):
    snap = load_claude_statusline_snapshot()
    if not isinstance(snap, dict):
        return out

    # Statusline snapshot is authoritative for live context fields — it is
    # what Claude itself displays. Transcript scan picks the newest assistant
    # turn across all JSONL files (including subagent transcripts with large
    # cache_read totals), which can wildly inflate last_context_pct. Trust
    # the snapshot whenever it is fresh (TTL-checked in loader).
    ctx = snap.get("context_window") or {}
    current_usage = ctx.get("current_usage") or {}

    input_total = ctx.get("total_input_tokens")
    if input_total is None and isinstance(current_usage, dict):
        input_total = (
            int(current_usage.get("input_tokens", 0) or 0)
            + int(current_usage.get("cache_creation_input_tokens", 0) or 0)
            + int(current_usage.get("cache_read_input_tokens", 0) or 0)
        )
    output_total = ctx.get("total_output_tokens")
    if output_total is None and isinstance(current_usage, dict):
        output_total = int(current_usage.get("output_tokens", 0) or 0)

    model = snap.get("model") or {}
    workspace = snap.get("workspace") or {}
    cwd = workspace.get("current_dir") or snap.get("cwd")
    model_id = model.get("id") or model.get("display_name")
    used_pct = parse_usage_percent(ctx.get("used_percentage"))
    window = ctx.get("context_window_size")
    if window is not None:
        try:
            window = int(window)
        except Exception:
            window = None

    out["last_turn_at"] = snap.get("updated_at") or out.get("last_turn_at")
    if model_id:
        out["last_model"] = model_id
    if cwd:
        out["last_cwd"] = cwd
    if input_total is not None:
        out["last_turn_input_tokens"] = int(input_total or 0)
    if output_total is not None:
        out["last_turn_output_tokens"] = int(output_total or 0)
    if window:
        out["last_context_window"] = window
    if used_pct is not None:
        out["last_context_pct"] = used_pct

    rate_limits = snap.get("rate_limits") or {}
    for keyset, pct_key, reset_key in [
        (("five_hour",), "session_5h_percent", "session_5h_resets_at"),
        (("seven_day",), "week_7d_percent", "week_7d_resets_at"),
        (("primary",), "session_5h_percent", "session_5h_resets_at"),
        (("secondary",), "week_7d_percent", "week_7d_resets_at"),
    ]:
        pct, resets = parse_claude_rate_limit_window(rate_limits, *keyset)
        if pct is not None:
            out[pct_key] = pct
        if resets:
            out[reset_key] = resets
    return out


def project_name_from_cwd(cwd):
    if not cwd:
        return "—"
    return os.path.basename(cwd.rstrip("/")) or cwd


def _empty_bucket():
    return {
        "tokens": 0, "sessions": 0, "cache_read": 0,
        "input": 0, "output": 0, "cache_creation": 0, "cost": 0.0,
    }


def _accumulate(bucket, s, cache_read):
    bucket["tokens"] += s["tokens"]
    bucket["sessions"] += 1
    bucket["cache_read"] += cache_read
    bucket["input"] += int(s.get("input", 0) or 0)
    bucket["output"] += int(s.get("output", 0) or 0)
    bucket["cache_creation"] += int(s.get("cache_creation", 0) or 0)
    bucket["cost"] += float(s.get("cost", 0.0) or 0.0)


def bucket_aggregates(per_session, days=365, weeks=52, months=24,
                      instance_days=30, instance_rows=200):
    """Roll a list of session records into time buckets.

    Bucketing uses the LOCAL timezone so "most active day" and streaks line up
    with what a human reading their calendar would see. A logical session is
    attributed to its END day (last_ts) — the same convention the token stats
    have always used, so a row's tokens and cost agree. 30-day/all-time TOTALS
    are exact; only single-day attribution can differ from a strict per-turn
    split (ccusage) for a session that crosses local midnight. `by_day` is padded
    with zero-token entries for every calendar day inside the history window
    so consumers can compute streaks by walking the array without first
    filling in missing dates themselves. Each bucket also carries the cost +
    token-category split (input/output/cache_creation/cache_read) used by the
    cost view; `by_day_project` is the per (day × project) cross-tab that
    replicates `better-ccusage daily --instances`.
    """
    by_day = defaultdict(_empty_bucket)
    by_week = defaultdict(_empty_bucket)
    by_month = defaultdict(_empty_bucket)
    by_model = defaultdict(_empty_bucket)
    by_project = defaultdict(_empty_bucket)
    by_day_project = {}  # (day, project) -> bucket + models set

    total30 = 0
    sessions30 = 0
    cost30 = 0.0
    input30 = 0
    output30 = 0
    cutoff30 = NOW - WIN_30D
    today_key = datetime.fromtimestamp(NOW).astimezone().strftime("%Y-%m-%d")

    for s in per_session:
        ts = s["last_ts"]
        if ts is None:
            continue
        cache_read = int(s.get("cache_read", 0) or 0)
        dt = datetime.fromtimestamp(ts).astimezone()
        day = dt.strftime("%Y-%m-%d")
        iy, iw, _ = dt.isocalendar()
        week = f"{iy}-W{iw:02d}"
        month = dt.strftime("%Y-%m")
        proj = project_name_from_cwd(s["cwd"])

        _accumulate(by_day[day], s, cache_read)
        _accumulate(by_week[week], s, cache_read)
        _accumulate(by_month[month], s, cache_read)
        if s["model"]:
            _accumulate(by_model[s["model"]], s, cache_read)
        _accumulate(by_project[proj], s, cache_read)

        # Per-day-per-project cross-tab, scoped to the recent instance window.
        if NOW - ts <= instance_days * 86400:
            key = (day, proj)
            entry = by_day_project.get(key)
            if entry is None:
                entry = {"bucket": _empty_bucket(), "models": set()}
                by_day_project[key] = entry
            _accumulate(entry["bucket"], s, cache_read)
            if s["model"]:
                entry["models"].add(s["model"])

        if ts >= cutoff30:
            total30 += s["tokens"]
            sessions30 += 1
            cost30 += float(s.get("cost", 0.0) or 0.0)
            input30 += int(s.get("input", 0) or 0)
            output30 += int(s.get("output", 0) or 0)

    today_local = datetime.fromtimestamp(NOW).astimezone().date()
    padded_day = []
    for i in range(days):
        d = today_local - timedelta(days=i)
        key = d.strftime("%Y-%m-%d")
        rec = by_day.get(key) or _empty_bucket()
        padded_day.append({
            "date": key,
            "tokens": rec["tokens"],
            "sessions": rec["sessions"],
            "cache_read": rec["cache_read"],
            "input": rec["input"],
            "output": rec["output"],
            "cache_creation": rec["cache_creation"],
            "cost": round(rec["cost"], 6),
        })

    def take(d, key_name, n, sort_key=None):
        items = []
        for k, v in d.items():
            v = dict(v)
            v["cost"] = round(v["cost"], 6)
            items.append({key_name: k, **v})
        if sort_key:
            items.sort(key=sort_key, reverse=True)
        else:
            items.sort(key=lambda x: x["tokens"], reverse=True)
        return items[:n]

    # Per (day × project) rows: newest day first, within a day by cost desc.
    instances = []
    for (day, proj), entry in by_day_project.items():
        b = entry["bucket"]
        instances.append({
            "date": day,
            "project": proj,
            "models": sorted(entry["models"]),
            "tokens": b["tokens"],
            "sessions": b["sessions"],
            "input": b["input"],
            "output": b["output"],
            "cache_creation": b["cache_creation"],
            "cache_read": b["cache_read"],
            "cost": round(b["cost"], 6),
        })
    instances.sort(key=lambda r: (r["date"], r["cost"]), reverse=True)
    instances = instances[:instance_rows]

    # Longest single session across the whole scanned history (minutes).
    # Computed here so it isn't capped to recent_sessions (last 20).
    max_session_minutes = 0.0
    for s in per_session:
        if s.get("first_ts") is None or s.get("last_ts") is None:
            continue
        dur = (s["last_ts"] - s["first_ts"]) / 60.0
        if dur > max_session_minutes:
            max_session_minutes = dur

    today_bucket = by_day.get(today_key) or _empty_bucket()
    return {
        "total_tokens_30d": total30,
        "total_sessions_30d": sessions30,
        "total_cost_30d": round(cost30, 6),
        "total_input_30d": input30,
        "total_output_30d": output30,
        "cost_today": round(today_bucket["cost"], 6),
        "max_session_minutes": round(max_session_minutes, 1),
        "by_day": padded_day,
        "by_week": take(by_week, "week", weeks, sort_key=lambda x: x["week"]),
        "by_month": take(by_month, "month", months, sort_key=lambda x: x["month"]),
        "by_model": take(by_model, "model", 20),
        "by_project": take(by_project, "project", 20),
        "by_day_project": instances,
    }


def split_logical_sessions(per_session):
    """Split each file's events into sub-sessions on idle gaps.

    Returns (sessions, recent) where sessions feeds bucket_aggregates and
    recent feeds recent_sessions. A "logical session" ends when an event's
    timestamp exceeds session_start + SESSION_IDLE_GAP — matching Claude's
    5h window, which resets 5h after the *first* turn (not after the most
    recent turn). This keeps historical splits consistent with the live
    `session_5h_resets_at` math.
    """
    sessions = []
    recent = []
    for path, s in per_session.items():
        events = sorted(s.get("events") or [], key=lambda e: e[0])
        if not events:
            continue
        # Events are (ts, metrics) where metrics carries the token-category
        # split + estimated cost for that turn.
        chunks = []
        cur = [events[0]]
        session_start = events[0][0]
        for nxt in events[1:]:
            if nxt[0] - session_start > SESSION_IDLE_GAP:
                chunks.append(cur)
                cur = [nxt]
                session_start = nxt[0]
            else:
                cur.append(nxt)
        chunks.append(cur)
        base_id = os.path.basename(path).rsplit(".", 1)[0]
        for i, chunk in enumerate(chunks):
            first_ts = chunk[0][0]
            last_ts = chunk[-1][0]
            agg = empty_metrics()
            for _, m in chunk:
                _add_metrics(agg, m)
            sessions.append({
                "tokens": agg["total"], "cache_read": agg["cache_read"],
                "input": agg["input"], "output": agg["output"],
                "cache_creation": agg["cache_creation"], "cost": agg["cost"],
                "last_ts": last_ts, "first_ts": first_ts,
                "model": s["model"], "cwd": s["cwd"],
            })
            recent.append({
                "id": base_id if len(chunks) == 1 else f"{base_id}#{i + 1}",
                "started_at": datetime.fromtimestamp(first_ts, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
                "ended_at": datetime.fromtimestamp(last_ts, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
                "duration_minutes": round((last_ts - first_ts) / 60.0, 1),
                "tokens": agg["total"],
                "cache_read": agg["cache_read"],
                "input": agg["input"],
                "output": agg["output"],
                "cache_creation": agg["cache_creation"],
                "cost": round(agg["cost"], 6),
                "model": s["model"] or "—",
                "project": project_name_from_cwd(s["cwd"]),
            })
    return sessions, recent


def collect_claude():
    out = empty_block()
    home = os.environ.get("HOME", "")
    if not home:
        return out
    pricing_table, _ = load_pricing()
    last_ts = 0.0
    per_session = {}  # path -> {first_ts, last_ts, tokens, model, cwd}
    session_5h_oldest = None  # oldest turn ts within last 5h
    week_7d_oldest = None     # oldest turn ts within last 7d
    # Tracks the most recent assistant turn from a *foreground* transcript
    # (i.e. not a subagent). Used to pick last_context_pct so subagent
    # transcripts with huge cache_read totals don't inflate the live %.
    foreground_last = {"ts": 0.0, "data": None}
    process_cwd = os.environ.get("PWD") or os.getcwd()

    for path in glob.glob(os.path.join(home, ".claude", "projects", "*", "*.jsonl")):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_30D and NOW - mtime > WIN_WEEK:
            # skip very old for speed; still allow 30d scan above
            pass
        if NOW - mtime > WIN_HIST:
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if '"usage"' not in line or '"assistant"' not in line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    if obj.get("type") != "assistant":
                        continue
                    msg = obj.get("message") or {}
                    if not isinstance(msg, dict):
                        continue
                    usage = msg.get("usage") or {}
                    if not isinstance(usage, dict):
                        continue
                    # Fresh-work view (ccusage convention) —
                    # total = input + cache_creation + output (+ thinking).
                    # Excludes cache_read which is billed at 0.1× but
                    # multiplies across turns (each turn re-reads the entire
                    # cached prefix) and would dominate human-readable totals
                    # by orders of magnitude. `cache_read_tokens` is emitted
                    # separately so a future cost view can multiply by 0.1×.
                    # `inp` (context-window view) keeps all three input
                    # buckets — output isn't part of the live window.
                    fresh_in = int(usage.get("input_tokens", 0) or 0)
                    cache_create = int(usage.get("cache_creation_input_tokens", 0) or 0)
                    cache_read = int(usage.get("cache_read_input_tokens", 0) or 0)
                    outp = int(usage.get("output_tokens", 0) or 0)
                    # Extended-thinking / reasoning output tokens. Anthropic
                    # transcripts may surface these under varying keys; treat
                    # any field whose name suggests thinking/reasoning output
                    # as billable output (parallel to codex path).
                    for k, v in usage.items():
                        if not isinstance(v, (int, float)):
                            continue
                        kl = k.lower()
                        if kl in ("input_tokens", "output_tokens",
                                  "cache_creation_input_tokens",
                                  "cache_read_input_tokens"):
                            continue
                        if (("thinking" in kl and "token" in kl)
                                or kl == "reasoning_output_tokens"
                                or kl == "output_thinking_tokens"):
                            outp += int(v or 0)
                    inp = fresh_in + cache_create + cache_read  # context-window view
                    # Display "total" matches Claude's /usage screen — fresh
                    # input + output only. cache_creation is excluded because
                    # /usage doesn't surface it under "Total tokens" (it
                    # multiplies wildly across turns and would not match what
                    # users see in their Anthropic UI). cache_read tracked
                    # separately so the cost view can still bill it.
                    total = fresh_in + outp
                    # Estimated API-equivalent cost for this turn. Honor a
                    # precomputed costUSD on the row when present (ccusage "auto"
                    # mode); otherwise price the four token buckets by model.
                    turn_model = msg.get("model")
                    rate = match_pricing(turn_model, pricing_table)
                    precomputed = obj.get("costUSD")
                    if isinstance(precomputed, (int, float)):
                        cost = float(precomputed)
                    else:
                        cost = turn_cost(rate, fresh_in, cache_create, cache_read, outp)
                    cache_saved = turn_cache_savings(rate, cache_create, cache_read)
                    metrics = {
                        "total": total, "cache_read": cache_read,
                        "input": fresh_in, "output": outp,
                        "cache_creation": cache_create, "cost": cost,
                    }
                    ts = parse_iso(obj.get("timestamp")) or mtime
                    age = NOW - ts

                    sess = per_session.setdefault(path, {
                        "first_ts": ts, "last_ts": 0, "tokens": 0,
                        "cache_read": 0, "cost": 0.0,
                        "model": msg.get("model"), "cwd": obj.get("cwd"),
                        "last_input": 0,
                        "max_ctx": 0,
                        "betas": set(),
                        "events": [],
                    })
                    sess["first_ts"] = min(sess["first_ts"], ts)
                    if ts >= sess["last_ts"]:
                        sess["last_ts"] = ts
                        sess["last_input"] = inp
                    sess["tokens"] += total
                    sess["cache_read"] += cache_read
                    sess["cost"] += cost
                    sess["events"].append((ts, metrics))
                    if inp > sess["max_ctx"]:
                        sess["max_ctx"] = inp
                    # Collect betas if recorded anywhere on the JSONL row.
                    for src in (obj, msg):
                        b = src.get("betas") if isinstance(src, dict) else None
                        if isinstance(b, list):
                            for item in b:
                                sess["betas"].add(str(item))
                    if msg.get("model"):
                        sess["model"] = msg.get("model")
                    if obj.get("cwd"):
                        sess["cwd"] = obj.get("cwd")

                    if age <= WIN_WEEK:
                        out["week_7d_tokens"] += total
                        out["cache_read_tokens_7d"] += cache_read
                        out["cost_7d"] += cost
                        if week_7d_oldest is None or ts < week_7d_oldest:
                            week_7d_oldest = ts
                    if age <= WIN_SESSION:
                        out["session_5h_tokens"] += total
                        out["cache_read_tokens_5h"] += cache_read
                        out["cost_5h"] += cost
                        if session_5h_oldest is None or ts < session_5h_oldest:
                            session_5h_oldest = ts
                    if age <= WIN_30D:
                        out["cache_read_tokens_30d"] += cache_read
                        out["cache_savings_30d"] += cache_saved

                    # Subagent transcripts (Task tool) link to a parent and
                    # often carry huge cache_read totals that don't reflect
                    # the foreground session's window fill. Skip them when
                    # picking the "latest turn" for live context %.
                    is_subagent = bool(
                        obj.get("parentUuid")
                        or obj.get("parent_tool_use_id")
                        or msg.get("parentUuid")
                        or msg.get("parent_tool_use_id")
                    )
                    if ts > last_ts:
                        last_ts = ts
                        out["last_turn_input_tokens"] = inp
                        out["last_turn_output_tokens"] = outp
                        out["last_model"] = msg.get("model")
                        out["last_turn_at"] = obj.get("timestamp")
                        out["last_cwd"] = obj.get("cwd")
                        out["active_session_file"] = path

                    if not is_subagent and ts > foreground_last["ts"]:
                        foreground_last = {
                            "ts": ts,
                            "data": {
                                "model": msg.get("model"),
                                "cwd": obj.get("cwd"),
                                "inp": inp,
                                "outp": outp,
                                "timestamp": obj.get("timestamp"),
                                "path": path,
                                "max_ctx": sess["max_ctx"],
                                "betas": list(sess["betas"]),
                            },
                        }
        except OSError:
            continue

    if out["active_session_file"]:
        s = per_session.get(out["active_session_file"])
        if s:
            out["active_session_tokens"] = s["tokens"]
            out["active_session_started_at"] = datetime.fromtimestamp(
                s["first_ts"], tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")

    # Pick last_context_pct from the foreground transcript. Prefer a session
    # whose cwd matches the process cwd (or $PWD); otherwise fall back to the
    # most-recent non-subagent transcript captured above. The statusline
    # snapshot (applied later) still wins when fresh.
    fg = foreground_last["data"]
    cwd_match = None
    if process_cwd:
        cwd_last_ts = 0.0
        for path, s in per_session.items():
            if s.get("cwd") == process_cwd and s.get("last_ts", 0) > cwd_last_ts:
                cwd_last_ts = s["last_ts"]
                cwd_match = (path, s)
    if cwd_match:
        path, s = cwd_match
        model = s.get("model")
        window = claude_context_window(
            model,
            observed_max=s.get("max_ctx", 0),
            betas=list(s.get("betas") or []),
        )
        inp = int(s.get("last_input", 0) or 0)
        out["last_model"] = model or out["last_model"]
        out["last_cwd"] = s.get("cwd") or out["last_cwd"]
        out["last_turn_input_tokens"] = inp
        out["last_context_window"] = window
        out["last_context_pct"] = (
            round(min(200.0, inp / window * 100.0), 2) if window else None
        )
    elif fg:
        window = claude_context_window(
            fg.get("model"),
            observed_max=int(fg.get("max_ctx", 0) or 0),
            betas=fg.get("betas") or [],
        )
        inp = int(fg.get("inp", 0) or 0)
        out["last_model"] = fg.get("model") or out["last_model"]
        out["last_cwd"] = fg.get("cwd") or out["last_cwd"]
        out["last_turn_input_tokens"] = inp
        out["last_turn_output_tokens"] = int(fg.get("outp", 0) or 0)
        out["last_turn_at"] = fg.get("timestamp") or out["last_turn_at"]
        out["last_context_window"] = window
        out["last_context_pct"] = (
            round(min(200.0, inp / window * 100.0), 2) if window else None
        )

    # Split each .jsonl into logical sessions on idle gaps > SESSION_IDLE_GAP
    # so a file left open across days doesn't show up as one giant session.
    sessions, recent = split_logical_sessions(per_session)
    out.update(bucket_aggregates(sessions))
    recent.sort(key=lambda r: r["ended_at"], reverse=True)
    out["recent_sessions"] = recent[:20]
    out["active_sessions"] = build_active_sessions(per_session)
    if session_5h_oldest is not None:
        ts = session_5h_oldest + WIN_SESSION
        out["session_5h_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    if week_7d_oldest is not None:
        ts = week_7d_oldest + WIN_WEEK
        out["week_7d_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    out["cost_5h"] = round(out["cost_5h"], 6)
    out["cost_7d"] = round(out["cost_7d"], 6)
    out["cache_savings_30d"] = round(out["cache_savings_30d"], 6)
    out = apply_claude_statusline_snapshot(out)
    return apply_claude_usage_api(out)


def collect_codex():
    out = empty_block()
    home = os.environ.get("HOME", "")
    if not home:
        return out
    pricing_table, _ = load_pricing()
    last_ts = 0.0
    per_session = {}
    session_5h_oldest = None
    week_7d_oldest = None
    latest_rate_ts = 0.0
    latest_rate_limits = None

    for path in glob.glob(
        os.path.join(home, ".codex", "sessions", "**", "*.jsonl"), recursive=True
    ):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_HIST:
            continue
        current_model = None
        current_cwd = None
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if '"token_count"' not in line and '"turn_context"' not in line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    t = obj.get("type")
                    payload = obj.get("payload") or {}
                    if t == "turn_context" and isinstance(payload, dict):
                        current_model = payload.get("model") or current_model
                        current_cwd = payload.get("cwd") or current_cwd
                        continue
                    if t != "event_msg" or not isinstance(payload, dict):
                        continue
                    if payload.get("type") != "token_count":
                        continue
                    # rate_limits is present alongside info (may be null info)
                    rl = payload.get("rate_limits")
                    if isinstance(rl, dict):
                        ts_rl = parse_iso(obj.get("timestamp")) or mtime
                        if ts_rl > latest_rate_ts:
                            latest_rate_ts = ts_rl
                            latest_rate_limits = rl
                    info = payload.get("info") or {}
                    if not isinstance(info, dict):
                        continue
                    last_use = info.get("last_token_usage") or {}
                    if not isinstance(last_use, dict):
                        continue
                    inp_raw = int(last_use.get("input_tokens", 0) or 0)
                    cached = int(last_use.get("cached_input_tokens", 0) or 0)
                    outp = int(last_use.get("output_tokens", 0) or 0)
                    reasoning = int(last_use.get("reasoning_output_tokens", 0) or 0)
                    # input_tokens includes cached_input_tokens — subtract to
                    # avoid counting the same cached prefix every turn.
                    fresh_in = max(0, inp_raw - cached)
                    inp = inp_raw  # context-window view (full prompt)
                    billed_out = outp + reasoning  # reasoning bills as output
                    total = fresh_in + billed_out  # consumed view
                    # OpenAI has no cache-write charge; cached input bills at the
                    # read rate, reasoning at the output rate.
                    rate = match_pricing(current_model, pricing_table)
                    cost = turn_cost(rate, fresh_in, 0, cached, billed_out)
                    cache_saved = turn_cache_savings(rate, 0, cached)
                    metrics = {
                        "total": total, "cache_read": cached,
                        "input": fresh_in, "output": billed_out,
                        "cache_creation": 0, "cost": cost,
                    }
                    window = info.get("model_context_window")
                    ts = parse_iso(obj.get("timestamp")) or mtime
                    age = NOW - ts

                    sess = per_session.setdefault(path, {
                        "first_ts": ts, "last_ts": 0, "tokens": 0,
                        "cache_read": 0, "cost": 0.0,
                        "model": current_model, "cwd": current_cwd,
                        "last_input": 0, "last_window": window,
                        "events": [],
                    })
                    sess["first_ts"] = min(sess["first_ts"], ts)
                    if ts >= sess["last_ts"]:
                        sess["last_ts"] = ts
                        sess["last_input"] = inp
                        if window:
                            sess["last_window"] = window
                    sess["tokens"] += total
                    sess["cache_read"] += cached
                    sess["cost"] += cost
                    sess["events"].append((ts, metrics))
                    if current_model:
                        sess["model"] = current_model
                    if current_cwd:
                        sess["cwd"] = current_cwd

                    if age <= WIN_WEEK:
                        out["week_7d_tokens"] += total
                        out["cache_read_tokens_7d"] += cached
                        out["cost_7d"] += cost
                        if week_7d_oldest is None or ts < week_7d_oldest:
                            week_7d_oldest = ts
                    if age <= WIN_SESSION:
                        out["session_5h_tokens"] += total
                        out["cache_read_tokens_5h"] += cached
                        out["cost_5h"] += cost
                        if session_5h_oldest is None or ts < session_5h_oldest:
                            session_5h_oldest = ts
                    if age <= WIN_30D:
                        out["cache_read_tokens_30d"] += cached
                        out["cache_savings_30d"] += cache_saved

                    if ts > last_ts:
                        last_ts = ts
                        out["last_turn_input_tokens"] = inp
                        out["last_turn_output_tokens"] = outp
                        out["last_model"] = current_model
                        out["last_turn_at"] = obj.get("timestamp")
                        out["last_cwd"] = current_cwd
                        out["active_session_file"] = path
                        out["last_context_window"] = int(window) if window else None
                        if window:
                            out["last_context_pct"] = round(min(200.0, inp / int(window) * 100.0), 2)
        except OSError:
            continue

    if out["active_session_file"]:
        s = per_session.get(out["active_session_file"])
        if s:
            out["active_session_tokens"] = s["tokens"]
            out["active_session_started_at"] = datetime.fromtimestamp(
                s["first_ts"], tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")

    sessions, recent = split_logical_sessions(per_session)
    out.update(bucket_aggregates(sessions))
    recent.sort(key=lambda r: r["ended_at"], reverse=True)
    out["recent_sessions"] = recent[:20]
    out["active_sessions"] = build_active_sessions(per_session)
    if session_5h_oldest is not None:
        ts = session_5h_oldest + WIN_SESSION
        out["session_5h_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    if week_7d_oldest is not None:
        ts = week_7d_oldest + WIN_WEEK
        out["week_7d_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    out["cost_5h"] = round(out["cost_5h"], 6)
    out["cost_7d"] = round(out["cost_7d"], 6)
    out["cache_savings_30d"] = round(out["cache_savings_30d"], 6)
    out = apply_codex_rate_limits(out, latest_rate_limits)
    out = apply_codex_rate_limits(out, fetch_codex_rate_limits_app_server())
    return out


# ── Additional AI tool probes ─────────────────────────────────────────────────

def empty_tool(name):
    return {
        "name": name,
        "sessions_7d": 0,
        "sessions_today": 0,
        "tokens_7d": 0,
        "tokens_today": 0,
        "last_used": None,
        "last_model": None,
    }


def probe_llm_cli():
    """Simon Willison's 'llm' CLI — ~/.config/io.datasette.llm/logs.db"""
    try:
        import sqlite3
    except ImportError:
        return None
    db = os.path.expanduser("~/.config/io.datasette.llm/logs.db")
    if not os.path.exists(db):
        return None
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        cur = conn.cursor()
        rows = cur.execute(
            """SELECT datetime_utc,
                      COALESCE(input_tokens,0)+COALESCE(output_tokens,0),
                      model
               FROM responses
               WHERE datetime_utc >= datetime('now','-7 days')
               ORDER BY datetime_utc DESC LIMIT 2000"""
        ).fetchall()
        conn.close()
    except Exception:
        return None
    if not rows:
        return None
    out = empty_tool("LLM")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    session_days, today_count = set(), 0
    for (dt_utc, tokens, model) in rows:
        if dt_utc:
            day = dt_utc[:10]
            session_days.add(day)
            if day == today:
                today_count += 1
                out["tokens_today"] += tokens or 0
        out["tokens_7d"] += tokens or 0
        if out["last_used"] is None:
            out["last_used"] = dt_utc
            out["last_model"] = model
    out["sessions_7d"] = len(session_days)
    out["sessions_today"] = today_count
    return out


def probe_gemini_cli():
    """Google Gemini CLI — ~/.gemini/ JSONL sessions"""
    home = os.environ.get("HOME", "")
    if not home:
        return None
    candidates = [
        os.path.join(home, ".gemini", "sessions"),
        os.path.join(home, ".gemini"),
        os.path.join(home, ".config", "gemini", "sessions"),
    ]
    base = next((d for d in candidates if os.path.isdir(d)), None)
    if not base:
        return None
    out = empty_tool("Gemini")
    found = False
    for path in glob.glob(os.path.join(base, "**", "*.jsonl"), recursive=True) + \
                glob.glob(os.path.join(base, "*.jsonl")):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_WEEK:
            continue
        found = True
        out["sessions_7d"] += 1
        if NOW - mtime <= 86400:
            out["sessions_today"] += 1
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    u = obj.get("usageMetadata") or obj.get("usage") or {}
                    if isinstance(u, dict):
                        total = int(u.get("totalTokenCount") or
                                    (int(u.get("promptTokenCount", 0) or 0) +
                                     int(u.get("candidatesTokenCount", 0) or 0)))
                        out["tokens_7d"] += total
                        if NOW - mtime <= 86400:
                            out["tokens_today"] += total
                    if out["last_used"] is None:
                        ts = obj.get("timestamp") or obj.get("createTime")
                        if ts:
                            out["last_used"] = ts
                    if not out["last_model"]:
                        out["last_model"] = obj.get("model")
        except OSError:
            continue
    return out if found else None


def probe_aider():
    """Aider — check ~/.aider/ for recent activity (no full home scan)."""
    home = os.environ.get("HOME", "")
    if not home:
        return None
    aider_dir = os.path.join(home, ".aider")
    if not os.path.isdir(aider_dir):
        return None
    found_paths = []
    # Check only within ~/.aider/ — safe, bounded directory
    for path in glob.glob(os.path.join(aider_dir, "**", "*.jsonl"), recursive=True) + \
                glob.glob(os.path.join(aider_dir, "*.jsonl")) + \
                glob.glob(os.path.join(aider_dir, "**", "*.yaml"), recursive=True):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime <= WIN_WEEK:
            found_paths.append((mtime, path))
    if not found_paths:
        return None
    found_paths.sort(reverse=True)
    out = empty_tool("Aider")
    out["sessions_7d"] = len(found_paths)
    out["sessions_today"] = sum(1 for (m, _) in found_paths if NOW - m <= 86400)
    latest_mtime, _ = found_paths[0]
    out["last_used"] = datetime.fromtimestamp(latest_mtime, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    return out


# Shell history AI tool detection
_HISTORY_TOOLS = [
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
]


def probe_shell_history():
    """Scan ~/.zsh_history (extended format) for AI CLI invocations in last 7 days."""
    home = os.environ.get("HOME", "")
    if not home:
        return []
    hist_path = os.path.join(home, ".zsh_history")
    if not os.path.exists(hist_path):
        return []
    cutoff = NOW - WIN_WEEK
    counts = defaultdict(lambda: {"count": 0, "last_ts": 0})
    try:
        with open(hist_path, "rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            fh.seek(max(0, size - 2 * 1024 * 1024))
            content = fh.read().decode("utf-8", errors="replace")
        ts = None
        for line in content.splitlines():
            if line.startswith(": "):
                parts = line.split(";", 1)
                if len(parts) == 2:
                    try:
                        ts = int(parts[0].split(":")[1])
                    except Exception:
                        ts = None
                    cmd = parts[1].strip()
                else:
                    cmd = ""
            else:
                cmd = line.strip()
                # no timestamp available for this line
            if ts is None or ts < cutoff:
                continue
            for binary, display in _HISTORY_TOOLS:
                if cmd == binary or cmd.startswith(binary + " ") or cmd.startswith(binary + "\t"):
                    counts[display]["count"] += 1
                    if ts > counts[display]["last_ts"]:
                        counts[display]["last_ts"] = ts
    except Exception:
        return []
    results = []
    for display, data in counts.items():
        if data["count"] == 0:
            continue
        t = empty_tool(display)
        t["sessions_7d"] = data["count"]
        t["sessions_today"] = 0  # not tracked at daily granularity from history
        if data["last_ts"]:
            t["last_used"] = datetime.fromtimestamp(data["last_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z")
        results.append(t)
    return results


def collect_others():
    tools = []
    for probe_fn in [probe_llm_cli, probe_gemini_cli, probe_aider]:
        try:
            result = probe_fn()
        except Exception:
            result = None
        if result is not None:
            tools.append(result)
    existing = {t["name"].lower() for t in tools}
    try:
        for t in probe_shell_history():
            if t["name"].lower() not in existing:
                tools.append(t)
                existing.add(t["name"].lower())
    except Exception:
        pass
    tools.sort(key=lambda t: t["last_used"] or "", reverse=True)
    return tools


def main():
    _, pricing_source = load_pricing()
    snap = {
        "claude": collect_claude(),
        "codex": collect_codex(),
        "others": collect_others(),
        "collected_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "python3",
        # Cost numbers are estimates (subscription users aren't billed per
        # token); pricing_source records where the rate table came from.
        "pricing_source": pricing_source,
        "pricing_is_estimate": True,
    }
    sys.stdout.write(json.dumps(snap))


if __name__ == "__main__":
    main()
