#!/usr/bin/env bash
# Generate docs/images/context-bar-cli-demo.gif — a real `context-bar` CLI run
# recorded with vhs, driven by a sandbox HOME of SYNTHETIC (privacy-safe)
# Claude Code + Codex transcripts.
#
# Repeatable, not ad-hoc: edit scripts/demo.tape (the script) or
# scripts/demo-seed.py (the sample data), then re-run this.
#
# Requires:
#   - vhs     https://github.com/charmbracelet/vhs   (brew install vhs)
#   - ffmpeg  (brew install ffmpeg)
#   - the context-bar CLI built locally (cargo build --release --bin context-bar,
#     or a built dist/ContextBar.app).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "✗ missing: $1 — $2"; exit 1; }; }
need vhs "brew install vhs"
need ffmpeg "brew install ffmpeg"
need python3 "install Python 3"

BIN="$REPO/target/release/context-bar"
[ -x "$BIN" ] || BIN="$REPO/dist/ContextBar.app/Contents/MacOS/context-bar"
[ -x "$BIN" ] || { echo "✗ CLI not built — run: cargo build --release --bin context-bar"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SANDBOX_HOME="$WORK/home"
BINDIR="$WORK/bin"
mkdir -p "$SANDBOX_HOME" "$BINDIR"
ln -sf "$BIN" "$BINDIR/context-bar"

echo "▸ Seeding a sandbox HOME with synthetic Claude Code + Codex transcripts…"
python3 "$REPO/scripts/demo-seed.py" "$SANDBOX_HOME" >/dev/null

echo "▸ Recording with vhs…"
cd "$WORK"
HOME="$SANDBOX_HOME" PATH="$BINDIR:$PATH" CONTEXTBAR_PRICING_OFFLINE=1 NO_COLOR= \
  vhs "$REPO/scripts/demo.tape"

mkdir -p "$REPO/docs/images"
cp "$WORK/context-bar-cli-demo.gif" "$REPO/docs/images/context-bar-cli-demo.gif"
echo "✓ Wrote docs/images/context-bar-cli-demo.gif"
