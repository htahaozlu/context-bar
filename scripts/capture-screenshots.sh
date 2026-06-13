#!/usr/bin/env bash
# Regenerate the marketing screenshots in docs/images/ from a sandbox HOME of
# SYNTHETIC (privacy-safe) data. The detail-window tabs are rendered straight
# from the view layer (bitmapImageRepForCachingDisplay) — no Screen Recording
# permission needed. The popover uses the app's own capture (CGWindowListCreate)
# which DOES need Screen Recording permission granted to ContextBar.app; if it
# isn't, that one image is skipped (everything else still regenerates).
#
#   bash scripts/capture-screenshots.sh            # dark (default)
#   APPEARANCE=light bash scripts/capture-screenshots.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO/dist/ContextBar.app/Contents/MacOS/context-bar"
CLI="$REPO/target/release/context-bar"
IMG="$REPO/docs/images"
APPEARANCE="${APPEARANCE:-dark}"

[ -x "$APP" ] || { echo "✗ build the app first: bash scripts/build-menubar-app.sh"; exit 1; }
[ -x "$CLI" ] || CLI="$APP"   # the bundled binary also serves `global`

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "dist/ContextBar.app" 2>/dev/null || true' EXIT
SB="$WORK/home"; mkdir -p "$SB"

echo "▸ Seeding sandbox HOME with synthetic data…"
python3 "$REPO/scripts/demo-seed.py" "$SB" >/dev/null
HOME="$SB" CONTEXTBAR_PRICING_OFFLINE=1 "$CLI" global >/dev/null 2>&1

# CRITICAL for privacy: the GUI app resolves the snapshot via NSHomeDirectory,
# which ignores $HOME — so HOME alone is NOT enough to sandbox it (it would read
# the user's real ~/.context-bar). CONTEXTBAR_CONTEXT_PATH overrides the read
# path; point it at the sandbox's synthetic context.json so no real project data
# can appear. Export so every child app launch inherits it. (HOME=$SB also keeps
# the on-launch engine scan inside the sandbox.)
export HOME="$SB"
export CONTEXTBAR_CONTEXT_PATH="$SB/.context-bar/context.json"
export CONTEXTBAR_PRICING_OFFLINE=1
export CONTEXTBAR_FORCE_APPEARANCE="$APPEARANCE"

shot() {  # tab-index  output-path  WxH
  pkill -f "dist/ContextBar.app" 2>/dev/null || true; sleep 0.4
  CONTEXTBAR_SCREENSHOT_PATH="$2" CONTEXTBAR_SELECT_TAB="$1" \
    CONTEXTBAR_SCREENSHOT_SIZE="$3" "$APP" >/dev/null 2>&1 &
  sleep 5
  [ -f "$2" ] && echo "  ✓ $(basename "$2")" || echo "  ✗ $(basename "$2") (not written)"
}

mkdir -p "$IMG"
echo "▸ Capturing detail-window tabs (view-render, no permission needed)…"
shot 0 "$IMG/context-bar-screenshot.png"      880x720
shot 0 "$IMG/context-bar-screenshot-full.png" 880x1580
shot 1 "$IMG/context-bar-cost.png"            880x1480

echo "▸ Capturing the menubar popover (needs Screen Recording for ContextBar.app)…"
pkill -f "dist/ContextBar.app" 2>/dev/null || true; sleep 0.4
CONTEXTBAR_POPOVER_SCREENSHOT_PATH="$IMG/context-bar-menubar.png" "$APP" >/dev/null 2>&1 &
sleep 7
pkill -f "dist/ContextBar.app" 2>/dev/null || true
echo "✓ Done. Review docs/images/."
