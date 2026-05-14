#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$ROOT/dist/ContextHUD.app/Contents/MacOS/context-hud"
OUT_DIR="$ROOT/docs/images"
TMP_DIR="$ROOT/.tmp/demo-video"
MP4_OUT="$OUT_DIR/context-hud-demo.mp4"
GIF_OUT="$OUT_DIR/context-hud-demo.gif"

mkdir -p "$OUT_DIR" "$TMP_DIR"

if [[ ! -x "$APP_BIN" ]]; then
  echo "ContextHUD.app missing; building it first..."
  "$ROOT/scripts/build-menubar-app.sh"
fi

python3 - "$TMP_DIR" <<'PY'
import json
import math
import pathlib
import random
import sys
from datetime import datetime, timedelta, timezone

out_dir = pathlib.Path(sys.argv[1])
now = datetime.now(timezone.utc)

random.seed(7)

def iso(dt: datetime) -> str:
    return dt.isoformat().replace("+00:00", "Z")

def spark(base: int, variance: int, count: int):
    vals = []
    for i in range(count):
        pulse = 1.0 + 0.7 * math.exp(-((i - count * 0.45) ** 2) / (count * 0.9))
        vals.append(max(800, int((base + random.randint(-variance, variance)) * pulse)))
    return vals

def bucket_series(kind: str, values):
    if kind == "day":
        start = now.date() - timedelta(days=len(values) - 1)
        return [
            {
                "date": str(start + timedelta(days=index)),
                "tokens": value,
                "sessions": max(1, value // 18000),
            }
            for index, value in enumerate(values)
        ]
    if kind == "week":
        start = now.date() - timedelta(days=7 * (len(values) - 1))
        return [
            {
                "date": str(start + timedelta(days=7 * index)),
                "tokens": value,
                "sessions": max(1, value // 54000),
            }
            for index, value in enumerate(values)
        ]
    start_month = (now.year, now.month)
    months = []
    year, month = start_month
    for _ in range(len(values) - 1, -1, -1):
        months.append((year, month))
        month -= 1
        if month == 0:
            month = 12
            year -= 1
    months.reverse()
    return [
        {
            "date": f"{year:04d}-{month:02d}",
            "tokens": value,
            "sessions": max(1, value // 120000),
        }
        for (year, month), value in zip(months, values)
    ]

def agent_payload(
    *,
    session_5h_tokens,
    session_5h_percent,
    week_7d_tokens,
    week_7d_percent,
    active_session_tokens,
    last_model,
    last_context_window,
    last_context_pct,
    last_turn_seconds_ago,
    cwd,
    project,
    active_minutes,
    recent_project,
):
    last_turn = now - timedelta(seconds=last_turn_seconds_ago)
    started = last_turn - timedelta(minutes=active_minutes)
    day_values = spark(int(session_5h_tokens * 0.55), int(session_5h_tokens * 0.16), 28)
    week_values = spark(int(week_7d_tokens * 0.20), int(week_7d_tokens * 0.08), 8)
    month_values = spark(int(week_7d_tokens * 0.55), int(week_7d_tokens * 0.14), 6)
    return {
        "session_5h_tokens": session_5h_tokens,
        "session_5h_percent": session_5h_percent,
        "week_7d_tokens": week_7d_tokens,
        "week_7d_percent": week_7d_percent,
        "active_session_tokens": active_session_tokens,
        "last_model": last_model,
        "last_context_window": last_context_window,
        "last_context_pct": last_context_pct,
        "last_turn_at": iso(last_turn),
        "last_cwd": cwd,
        "active_session_started_at": iso(started),
        "total_tokens_30d": sum(day_values),
        "total_sessions_30d": 24,
        "by_day": bucket_series("day", day_values),
        "by_week": bucket_series("week", week_values),
        "by_month": bucket_series("month", month_values),
        "by_model": [
            {"model": last_model, "tokens": int(session_5h_tokens * 2.4), "sessions": 9},
            {"model": "fallback-model", "tokens": int(session_5h_tokens * 0.9), "sessions": 5},
        ],
        "by_project": [
            {"project": project, "tokens": int(session_5h_tokens * 2.1), "sessions": 8},
            {"project": recent_project, "tokens": int(session_5h_tokens * 0.8), "sessions": 4},
        ],
        "recent_sessions": [
            {
                "id": f"{project}-recent",
                "started_at": iso(last_turn - timedelta(minutes=65)),
                "ended_at": iso(last_turn - timedelta(minutes=8)),
                "duration_minutes": 57.0,
                "tokens": int(session_5h_tokens * 0.66),
                "model": last_model,
                "project": project,
            }
        ],
        "active_sessions": [
            {
                "id": f"{project}-active",
                "tokens": active_session_tokens,
                "started_at": iso(started),
                "last_turn_at": iso(last_turn),
                "model": last_model,
                "cwd": cwd,
                "project": project,
            }
        ],
        "session_5h_resets_at": iso(now + timedelta(hours=4, minutes=5)),
        "week_7d_resets_at": iso(now + timedelta(days=5, hours=4)),
    }

frames = [
    {
        "name": "frame-1",
        "claude": agent_payload(
            session_5h_tokens=48420,
            session_5h_percent=42.0,
            week_7d_tokens=204800,
            week_7d_percent=31.0,
            active_session_tokens=18400,
            last_model="claude-sonnet-4",
            last_context_window=200000,
            last_context_pct=34.0,
            last_turn_seconds_ago=38,
            cwd="/Users/ozlu/projeler/hususi/backend/context-hud",
            project="context-hud",
            active_minutes=27,
            recent_project="agent-sandbox",
        ),
        "codex": agent_payload(
            session_5h_tokens=14980,
            session_5h_percent=None,
            week_7d_tokens=98210,
            week_7d_percent=None,
            active_session_tokens=6920,
            last_model="gpt-5-codex",
            last_context_window=256000,
            last_context_pct=19.0,
            last_turn_seconds_ago=590,
            cwd="/Users/ozlu/projeler/playground/agent-lab",
            project="agent-lab",
            active_minutes=43,
            recent_project="sdk-notes",
        ),
    },
    {
        "name": "frame-2",
        "claude": agent_payload(
            session_5h_tokens=61240,
            session_5h_percent=54.0,
            week_7d_tokens=219900,
            week_7d_percent=34.0,
            active_session_tokens=26980,
            last_model="claude-sonnet-4",
            last_context_window=200000,
            last_context_pct=58.0,
            last_turn_seconds_ago=12,
            cwd="/Users/ozlu/projeler/hususi/backend/context-hud",
            project="context-hud",
            active_minutes=35,
            recent_project="agent-sandbox",
        ),
        "codex": agent_payload(
            session_5h_tokens=15120,
            session_5h_percent=None,
            week_7d_tokens=98910,
            week_7d_percent=None,
            active_session_tokens=7060,
            last_model="gpt-5-codex",
            last_context_window=256000,
            last_context_pct=22.0,
            last_turn_seconds_ago=545,
            cwd="/Users/ozlu/projeler/playground/agent-lab",
            project="agent-lab",
            active_minutes=44,
            recent_project="sdk-notes",
        ),
    },
    {
        "name": "frame-3",
        "claude": agent_payload(
            session_5h_tokens=61880,
            session_5h_percent=55.0,
            week_7d_tokens=221200,
            week_7d_percent=34.0,
            active_session_tokens=27320,
            last_model="claude-sonnet-4",
            last_context_window=200000,
            last_context_pct=61.0,
            last_turn_seconds_ago=155,
            cwd="/Users/ozlu/projeler/hususi/backend/context-hud",
            project="context-hud",
            active_minutes=38,
            recent_project="agent-sandbox",
        ),
        "codex": agent_payload(
            session_5h_tokens=28640,
            session_5h_percent=None,
            week_7d_tokens=123100,
            week_7d_percent=None,
            active_session_tokens=18320,
            last_model="gpt-5-codex",
            last_context_window=256000,
            last_context_pct=46.0,
            last_turn_seconds_ago=7,
            cwd="/Users/ozlu/projeler/playground/agent-lab",
            project="agent-lab",
            active_minutes=52,
            recent_project="sdk-notes",
        ),
    },
    {
        "name": "frame-4",
        "claude": agent_payload(
            session_5h_tokens=82410,
            session_5h_percent=73.0,
            week_7d_tokens=243300,
            week_7d_percent=38.0,
            active_session_tokens=39840,
            last_model="claude-sonnet-4",
            last_context_window=200000,
            last_context_pct=82.0,
            last_turn_seconds_ago=5,
            cwd="/Users/ozlu/projeler/hususi/backend/context-hud",
            project="context-hud",
            active_minutes=49,
            recent_project="agent-sandbox",
        ),
        "codex": agent_payload(
            session_5h_tokens=29110,
            session_5h_percent=None,
            week_7d_tokens=125900,
            week_7d_percent=None,
            active_session_tokens=18640,
            last_model="gpt-5-codex",
            last_context_window=256000,
            last_context_pct=49.0,
            last_turn_seconds_ago=42,
            cwd="/Users/ozlu/projeler/playground/agent-lab",
            project="agent-lab",
            active_minutes=53,
            recent_project="sdk-notes",
        ),
    },
]

for frame in frames:
    payload = {
        "source": "python3",
        "collected_at": iso(now),
        "claude": frame["claude"],
        "codex": frame["codex"],
        "others": [
            {
                "name": "Gemini CLI",
                "sessions_7d": 4,
                "sessions_today": 1,
                "tokens_7d": 38200,
                "tokens_today": 4200,
                "last_used": iso(now - timedelta(hours=6)),
                "last_model": "gemini-2.5-pro",
            }
        ],
    }
    with (out_dir / f"{frame['name']}.json").open("w", encoding="utf-8") as handle:
        json.dump(payload, handle)
PY

for json_path in "$TMP_DIR"/frame-*.json; do
  png_path="${json_path%.json}.png"
  CONTEXTHUD_HUD_PATH="$json_path" \
  CONTEXTHUD_SCREENSHOT_PATH="$png_path" \
  "$APP_BIN" >/dev/null 2>&1
done

ffmpeg -y \
  -loop 1 -t 1.8 -i "$TMP_DIR/frame-1.png" \
  -loop 1 -t 1.8 -i "$TMP_DIR/frame-2.png" \
  -loop 1 -t 1.8 -i "$TMP_DIR/frame-3.png" \
  -loop 1 -t 1.8 -i "$TMP_DIR/frame-4.png" \
  -filter_complex "\
[0:v]scale=920:-2:flags=lanczos,pad=1080:1320:(ow-iw)/2:(oh-ih)/2:color=#0f1115,format=yuva420p[v0]; \
[1:v]scale=920:-2:flags=lanczos,pad=1080:1320:(ow-iw)/2:(oh-ih)/2:color=#0f1115,format=yuva420p[v1]; \
[2:v]scale=920:-2:flags=lanczos,pad=1080:1320:(ow-iw)/2:(oh-ih)/2:color=#0f1115,format=yuva420p[v2]; \
[3:v]scale=920:-2:flags=lanczos,pad=1080:1320:(ow-iw)/2:(oh-ih)/2:color=#0f1115,format=yuva420p[v3]; \
[v0][v1]xfade=transition=fade:duration=0.35:offset=1.45[x1]; \
[x1][v2]xfade=transition=fade:duration=0.35:offset=2.90[x2]; \
[x2][v3]xfade=transition=fade:duration=0.35:offset=4.35,format=yuv420p[out]" \
  -map "[out]" \
  -r 30 \
  -movflags +faststart \
  "$MP4_OUT"

ffmpeg -y -i "$MP4_OUT" \
  -vf "fps=12,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
  "$GIF_OUT"

echo "Wrote:"
echo "  $MP4_OUT"
echo "  $GIF_OUT"
