#!/usr/bin/env bash
# Publish context-bar to npm: six per-platform packages
# (@context-bar/context-bar-<os>-<cpu>, each carrying one prebuilt binary with
# os/cpu set so npm installs only the matching one) then the meta `context-bar`
# package (a JS launcher + optionalDependencies on the six). No postinstall.
#
# Inputs (env): VERSION (e.g. 0.6.0), BIN_DIR (dir with <triple>/context-bar[.exe]).
# Requires: node + npm authed via NODE_AUTH_TOKEN. Idempotent: an
# already-published version is tolerated so re-runs don't fail the release.
set -euo pipefail

VERSION="${VERSION:?set VERSION}"
BIN_DIR="${BIN_DIR:?set BIN_DIR}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"

# triple:os:cpu — os/cpu use Node's process.platform/process.arch values.
TARGETS=(
  "aarch64-apple-darwin:darwin:arm64"
  "x86_64-apple-darwin:darwin:x64"
  "aarch64-unknown-linux-musl:linux:arm64"
  "x86_64-unknown-linux-musl:linux:x64"
  "aarch64-pc-windows-msvc:win32:arm64"
  "x86_64-pc-windows-msvc:win32:x64"
)

publish_dir() {
  local out
  if out="$( cd "$1" && npm publish --access public 2>&1 )"; then
    echo "$out"
    return 0
  fi
  echo "$out"
  # Tolerate ONLY "this exact version is already published" so re-runs are
  # idempotent; any other error (auth, scope, network) fails the release.
  if echo "$out" | grep -qiE 'cannot publish over|previously published|already published|E409|409 Conflict'; then
    echo "  ($1 already published at this version — tolerated)"
    return 0
  fi
  echo "::error::npm publish failed for $1" >&2
  return 1
}

# 1. Platform packages FIRST, so the meta's optionalDependencies resolve.
for entry in "${TARGETS[@]}"; do
  IFS=: read -r triple os cpu <<< "$entry"
  ext=""; [[ "$os" == "win32" ]] && ext=".exe"
  src="$BIN_DIR/$triple/context-bar$ext"
  if [[ ! -f "$src" ]]; then
    echo "::warning::missing binary $src — skipping @context-bar/context-bar-$os-$cpu"
    continue
  fi
  pkg="$WORK/$os-$cpu"
  mkdir -p "$pkg/bin"
  cp "$src" "$pkg/bin/context-bar$ext"
  [[ "$os" != "win32" ]] && chmod 0755 "$pkg/bin/context-bar$ext"
  [[ -f "$ROOT/LICENSE" ]] && cp "$ROOT/LICENSE" "$pkg/LICENSE"
  cat > "$pkg/package.json" <<JSON
{
  "name": "context-bar-$os-$cpu",
  "version": "$VERSION",
  "description": "context-bar prebuilt binary ($os $cpu).",
  "license": "Apache-2.0",
  "repository": "github:htahaozlu/context-bar",
  "os": ["$os"],
  "cpu": ["$cpu"],
  "files": ["bin", "LICENSE"]
}
JSON
  publish_dir "$pkg"
done

# 2. Meta package (the `bin` users invoke; resolves the platform binary).
meta="$WORK/meta"
mkdir -p "$meta/dist"
cp "$ROOT/npm/cli.js" "$meta/dist/cli.js"
[[ -f "$ROOT/LICENSE" ]] && cp "$ROOT/LICENSE" "$meta/LICENSE"
[[ -f "$ROOT/README.md" ]] && cp "$ROOT/README.md" "$meta/README.md"
cat > "$meta/package.json" <<JSON
{
  "name": "context-bar",
  "version": "$VERSION",
  "description": "Usage + API-equivalent cost for AI coding agents (Claude Code, Codex CLI). Terminal CLI + live 5h-block dashboard.",
  "license": "Apache-2.0",
  "repository": "github:htahaozlu/context-bar",
  "homepage": "https://github.com/htahaozlu/context-bar",
  "keywords": ["claude", "codex", "usage", "cost", "tokens", "ccusage", "cli"],
  "type": "module",
  "bin": { "context-bar": "dist/cli.js" },
  "files": ["dist", "LICENSE", "README.md"],
  "optionalDependencies": {
    "context-bar-darwin-arm64": "$VERSION",
    "context-bar-darwin-x64": "$VERSION",
    "context-bar-linux-arm64": "$VERSION",
    "context-bar-linux-x64": "$VERSION",
    "context-bar-win32-arm64": "$VERSION",
    "context-bar-win32-x64": "$VERSION"
  }
}
JSON
publish_dir "$meta"

echo "npm publish complete for context-bar@$VERSION"
