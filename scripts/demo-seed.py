#!/usr/bin/env python3
"""Seed a sandbox HOME with synthetic Claude Code + Codex transcripts so the
`context-bar` CLI and the menubar app render a realistic — but entirely fake,
privacy-safe — usage report for the demo recording / marketing screenshots.
Used by scripts/record-demo.sh and scripts/capture-screenshots.sh.

    python3 scripts/demo-seed.py /path/to/sandbox-home

Writes (under <home>):
    dev/<project>/.git/                    so the project label is the repo name
    .claude/projects/demo/*.jsonl          Claude assistant turns (with usage)
    .codex/sessions/YYYY/MM/DD/*.jsonl      Codex token_count events

Timestamps are relative to "now" so the data always lands inside the rolling
windows. Token counts are deterministic (seeded), spread across ~75 days so the
Stats heatmap, tiles and top-projects all look populated.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone

DAYS = 75

# project -> list of Claude models used there (weighted by repetition)
CLAUDE_PROJECTS = {
    "acme-api": ["claude-sonnet-4-5", "claude-sonnet-4-5", "claude-opus-4-8"],
    "payments": ["claude-opus-4-8", "claude-sonnet-4-5"],
    "web-dashboard": ["claude-sonnet-4-5", "claude-haiku-4-5"],
    "infra": ["claude-sonnet-4-5"],
}
CODEX_PROJECTS = ["web-dashboard", "data-pipeline"]


def iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: demo-seed.py <sandbox-home>", file=sys.stderr)
        raise SystemExit(2)
    home = sys.argv[1]
    now = datetime.now(timezone.utc)

    projects = set(CLAUDE_PROJECTS) | set(CODEX_PROJECTS)
    for p in projects:
        os.makedirs(os.path.join(home, "dev", p, ".git"), exist_ok=True)

    def cwd(p: str) -> str:
        return os.path.join(home, "dev", p)

    # ---- Claude Code transcripts (assistant turns carry the usage block) ----
    cdir = os.path.join(home, ".claude", "projects", "demo")
    os.makedirs(cdir, exist_ok=True)

    def claude_turn(ts: datetime, project: str, model: str,
                    inp: int, out: int, cc: int, cr: int) -> str:
        return json.dumps({
            "type": "assistant",
            "timestamp": iso(ts),
            "cwd": cwd(project),
            "message": {
                "model": model,
                "usage": {
                    "input_tokens": inp,
                    "cache_creation_input_tokens": cc,
                    "cache_read_input_tokens": cr,
                    "output_tokens": out,
                },
            },
        })

    proj_names = list(CLAUDE_PROJECTS)
    with open(os.path.join(cdir, "session.jsonl"), "w") as f:
        for d in range(DAYS):
            ts_day = now - timedelta(days=d)
            weekend = ts_day.weekday() >= 5
            # weekdays busier; deterministic "activity" from the day index
            n_proj = 1 if weekend else (2 + (d % 2))
            for j in range(n_proj):
                project = proj_names[(d + j) % len(proj_names)]
                models = CLAUDE_PROJECTS[project]
                model = models[(d + j) % len(models)]
                turns = 1 + ((d + j) % 3)
                for t in range(turns):
                    ts = ts_day - timedelta(hours=2 + j * 3, minutes=t * 7)
                    inp = 1200 + ((d * 13 + j * 29 + t * 7) % 900)
                    out = 800 + ((d * 7 + t * 11) % 700)
                    cc = 2500 + ((d * 17) % 2500)
                    cr = 9000 + ((d * 23 + t * 31) % 24000)
                    f.write(claude_turn(ts, project, model, inp, out, cc, cr) + "\n")

    # ---- Codex transcripts (turn_context sets model/cwd; token_count = usage) ----
    for ci, project in enumerate(CODEX_PROJECTS):
        day_dir = now - timedelta(days=ci)
        cxdir = os.path.join(home, ".codex", "sessions",
                             f"{day_dir.year:04d}", f"{day_dir.month:02d}", f"{day_dir.day:02d}")
        os.makedirs(cxdir, exist_ok=True)
        with open(os.path.join(cxdir, f"session{ci}.jsonl"), "w") as f:
            f.write(json.dumps({
                "type": "turn_context",
                "timestamp": iso(now),
                "payload": {"model": "gpt-5.5", "cwd": cwd(project), "effort": "high"},
            }) + "\n")
            for d in range(0, DAYS, 2):  # codex active every other day
                ts = now - timedelta(days=d, hours=1 + ci)
                f.write(json.dumps({
                    "type": "event_msg",
                    "timestamp": iso(ts),
                    "payload": {
                        "type": "token_count",
                        "info": {
                            "last_token_usage": {
                                "input_tokens": 6500 + ((d * 19) % 4000),
                                "cached_input_tokens": 2200 + ((d * 7) % 1500),
                                "output_tokens": 1300 + ((d * 11) % 900),
                                "reasoning_output_tokens": 400 + ((d * 5) % 400),
                            },
                            "model_context_window": 272000,
                        },
                    },
                }) + "\n")

    # ---- LIVE sessions (turns within the last 30 min) so the popover shows an
    #      active hero + parallel sessions instead of an idle ring. Each lives in
    #      its own Claude session file so it counts as a distinct active session.
    live = [
        (3,  "acme-api",      "claude-opus-4-8",   0.34),
        (12, "payments",      "claude-sonnet-4-5", 0.61),
        (24, "web-dashboard", "claude-sonnet-4-5", 0.19),
    ]
    for project, model, fill in [(p, m, f) for (_, p, m, f) in live]:
        os.makedirs(os.path.join(home, "dev", project, ".git"), exist_ok=True)
    for mins, project, model, fill in live:
        ldir = os.path.join(home, ".claude", "projects", f"live-{project}")
        os.makedirs(ldir, exist_ok=True)
        ts = now - timedelta(minutes=mins)
        target = int(fill * 1_000_000)        # 1M-window models → ctx% ≈ fill
        # Make the session-total ≈ the context used so the hero's "X / 1.0M" line
        # agrees with the % gauge (fresh-heavy turn; cache zeroed for the demo).
        # last_input (fresh+cc+cr) == total (fresh+out) == target → the gauge %
        # and the hero "X / 1.0M" line agree exactly.
        out = max(1000, target // 25)
        with open(os.path.join(ldir, "session.jsonl"), "w") as f:
            f.write(claude_turn(ts, project, model, target - out, out, 0, out) + "\n")

    # a live Codex session too (recent token_count → Codex reads active)
    lcdir = os.path.join(home, ".codex", "sessions",
                         f"{now.year:04d}", f"{now.month:02d}", f"{now.day:02d}")
    os.makedirs(lcdir, exist_ok=True)
    with open(os.path.join(lcdir, "live.jsonl"), "w") as f:
        f.write(json.dumps({
            "type": "turn_context", "timestamp": iso(now),
            "payload": {"model": "gpt-5.5", "cwd": cwd("data-pipeline"), "effort": "high"},
        }) + "\n")
        f.write(json.dumps({
            "type": "event_msg", "timestamp": iso(now - timedelta(minutes=8)),
            "payload": {"type": "token_count", "info": {
                "last_token_usage": {"input_tokens": 118000, "cached_input_tokens": 40000,
                                     "output_tokens": 1500, "reasoning_output_tokens": 500},
                "model_context_window": 272000}},
        }) + "\n")

    print(home)


if __name__ == "__main__":
    main()
