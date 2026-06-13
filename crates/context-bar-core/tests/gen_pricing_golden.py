#!/usr/bin/env python3
"""Regenerate tests/fixtures/pricing_golden.json from usage_signal.py.

The Rust cost kernel (`context_bar_core::pricing`) is pinned to this fixture,
which is in turn driven by the Python reference functions — so Rust == Python
byte-for-byte. Run after any deliberate, reviewed change to `match_pricing`,
`turn_cost`, `turn_cache_savings`, or `FALLBACK_PRICING`:

    python3 crates/context-bar-core/tests/gen_pricing_golden.py

Token combos exercise the split cache buckets (5m @ 1.25x, 1h @ 2x input) and
the >200K tier for each.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")
sys.path.insert(0, SRC)

import usage_signal as us  # noqa: E402

# Matched models (every FALLBACK_PRICING key) plus normalization / date-suffix /
# family / unmatched edge cases. Mirrors the prior fixture coverage + Fable 5.
MODELS = [
    "claude-fable-5", "claude-fable-5-20260101", "anthropic/claude-fable-5",
    "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5",
    "claude-opus-4-1", "claude-opus-4", "claude-sonnet-4-6", "claude-sonnet-4-5",
    "claude-sonnet-4", "claude-3-7-sonnet", "claude-3-5-sonnet", "claude-haiku-4-5",
    "claude-3-5-haiku", "mythos", "gpt-5", "gpt-5-codex", "gpt-5-pro", "gpt-5-mini",
    "gpt-5-nano", "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini",
    "gpt-5.2", "gpt-5.2-codex", "gpt-5.3-codex", "gpt-5.4", "gpt-5.4-codex",
    "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro", "gpt-5.5", "gpt-5.5-pro",
    "codex-mini-latest", "o4-mini", "o3", "o3-mini", "",
    "claude-opus-4-8[1m]", "anthropic/claude-opus-4-8", "claude-opus-4-8-20260514",
    "claude-opus-4-8-2026-05-14", "us.anthropic.claude-sonnet-4-5",
    "claude-sonnet-4-5-v1:0", "claude-sonnet-4-5-20260101-v1:0", "claude-sonnet-4-5-1m",
    "openai/gpt-5.1-codex", "github_copilot/gpt-5.4", "foo-opus-4-7-preview",
    "some-sonnet-4-thing", "weird-haiku-x", "gpt-5.3-codex-max", "codex-something",
    "o3-pro", "o4-mini-high", "totally-unknown-model", "MiniMax-M2.7", "glm-5.1",
    "<synthetic>", "claude-3-5-sonnet-20241022", "mythos-preview",
]

# (inp, cache_create_5m, cache_create_1h, cache_read, outp)
COMBOS = [
    (0, 0, 0, 0, 0),
    (1000, 2000, 0, 3000, 4000),
    (1000, 1500, 500, 3000, 4000),
    (0, 0, 0, 0, 250000),
    (123, 456, 0, 789, 1011),
    (123, 300, 156, 789, 1011),
    (199999, 1, 0, 1, 1),
    (200001, 0, 0, 0, 0),
    (250000, 0, 0, 0, 0),
    (0, 250000, 0, 0, 0),
    (0, 0, 250000, 0, 0),
    (300000, 150000, 150000, 300000, 300000),
]


def main():
    table = dict(us.FALLBACK_PRICING)
    rows = []
    for model in MODELS:
        rate = us.match_pricing(model, table)
        matched = rate is not None
        for inp, cc5, cc1, cr, outp in COMBOS:
            rows.append({
                "model": model,
                "inp": inp,
                "cache_create_5m": cc5,
                "cache_create_1h": cc1,
                "cache_read": cr,
                "outp": outp,
                "matched": matched,
                "cost": us.turn_cost(rate, inp, cc5, cc1, cr, outp),
                "savings": us.turn_cache_savings(rate, cc5, cc1, cr),
            })
    doc = {
        "note": "Generated from usage_signal.py FALLBACK_PRICING (offline). "
                "Pins Rust core::pricing parity. cache_create split into 5m "
                "(1.25x) + 1h (2x input). Regen: tests/gen_pricing_golden.py",
        "count": len(rows),
        "rows": rows,
    }
    out = os.path.join(HERE, "fixtures", "pricing_golden.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")
    print(f"wrote {len(rows)} rows -> {out}")


if __name__ == "__main__":
    main()
