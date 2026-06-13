#!/usr/bin/env python3
"""Seed a sandbox HOME with synthetic Claude Code + Codex transcripts so the
`context-bar` CLI renders a realistic — but entirely fake, privacy-safe — usage
report for the demo recording. Used by scripts/record-demo.sh.

    python3 scripts/demo-seed.py /path/to/sandbox-home

Writes:
    <home>/dev/<project>/.git/            so the project label is the repo name
    <home>/.claude/projects/demo/*.jsonl  Claude assistant turns (with usage)
    <home>/.codex/sessions/YYYY/MM/DD/*.jsonl  Codex token_count events

Timestamps are relative to "now" so the data always lands inside the rolling
windows (daily / weekly / monthly). Token counts are deterministic.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone


def iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: demo-seed.py <sandbox-home>", file=sys.stderr)
        raise SystemExit(2)
    home = sys.argv[1]
    now = datetime.now(timezone.utc)

    # Projects → each gets an (empty) .git dir so project_name_from_cwd resolves
    # to the clean repo folder name rather than a parent/leaf path.
    projects = ["acme-api", "payments", "web-dashboard"]
    for p in projects:
        os.makedirs(os.path.join(home, "dev", p, ".git"), exist_ok=True)

    def cwd(p: str) -> str:
        return os.path.join(home, "dev", p)

    # ---- Claude Code transcripts (assistant turns carry the usage block) ----
    cdir = os.path.join(home, ".claude", "projects", "demo")
    os.makedirs(cdir, exist_ok=True)

    def claude_turn(days_ago: int, hours: int, project: str, model: str,
                    inp: int, out: int, cache_create: int, cache_read: int) -> str:
        ts = now - timedelta(days=days_ago, hours=hours)
        return json.dumps({
            "type": "assistant",
            "timestamp": iso(ts),
            "cwd": cwd(project),
            "message": {
                "model": model,
                "usage": {
                    "input_tokens": inp,
                    "cache_creation_input_tokens": cache_create,
                    "cache_read_input_tokens": cache_read,
                    "output_tokens": out,
                },
            },
        })

    with open(os.path.join(cdir, "session.jsonl"), "w") as f:
        for d in range(0, 14):
            # daily Sonnet work on acme-api
            f.write(claude_turn(d, 2, "acme-api", "claude-sonnet-4-5",
                                1500 + d * 35, 1100 + d * 20, 3800, 18000 + d * 600) + "\n")
            # every other day, an Opus deep-dive on payments
            if d % 2 == 0:
                f.write(claude_turn(d, 5, "payments", "claude-opus-4-8",
                                    900, 1500, 2600, 9500) + "\n")

    # ---- Codex transcripts (turn_context sets model/cwd; token_count carries usage) ----
    cxdir = os.path.join(home, ".codex", "sessions", "2026", "06", "10")
    os.makedirs(cxdir, exist_ok=True)
    with open(os.path.join(cxdir, "session.jsonl"), "w") as f:
        f.write(json.dumps({
            "type": "turn_context",
            "timestamp": iso(now),
            "payload": {"model": "gpt-5.5", "cwd": cwd("web-dashboard"), "effort": "high"},
        }) + "\n")
        for d in range(0, 11):
            ts = now - timedelta(days=d, hours=1)
            f.write(json.dumps({
                "type": "event_msg",
                "timestamp": iso(ts),
                "payload": {
                    "type": "token_count",
                    "info": {
                        "last_token_usage": {
                            "input_tokens": 7000 + d * 250,
                            "cached_input_tokens": 2500,
                            "output_tokens": 1400,
                            "reasoning_output_tokens": 500,
                        },
                        "model_context_window": 272000,
                    },
                },
            }) + "\n")

    print(home)


if __name__ == "__main__":
    main()
