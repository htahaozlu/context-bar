# Agent Guide — context-bar

High-signal brief for an AI coding agent working on this repo. Read this + `COST_MODEL.md` + `ROADMAP.md` before doing substantial work. Dense by design.

## What this project is

`context-bar` (app brand: **ContextBar**, repo `htahaozlu/context-bar`, Apache-2.0) is a local-first usage HUD for AI coding agents (Claude Code + Codex CLI, extensible to more). It reads transcript files on disk and surfaces token usage, rolling quota windows, and **estimated API-equivalent cost** — without any external service for the core.

**Cargo workspace (since 0.4.0):**
- **`context-bar-core`** (`crates/context-bar-core/`) — the cross-platform engine rlib: transcript reading, the cost/token model, session/window bucketing, the agent-context assembler, HUD/HTML/`report` renderers, shared `i18n`. Platform-coupled bits (process spawn, macOS keychain, snapshot cache, wasm32 `Worktree` collectors) sit behind `cfg(target_arch)` gates inside their modules.
- **`context-bar`** (root crate) — a thin layer that re-exports the engine (`pub use context_bar_core::*` so historical `context_bar::<mod>` paths still resolve) and adds two surfaces: the **`[[bin]] context-bar`** terminal CLI (`src/bin/`) and the **Zed extension** (`[lib] crate-type=["cdylib","rlib"]`, `src/lib.rs` + `src/{slash_commands,auto_refresh}.rs`, wasm32). The root crate is the workspace root (keeps `[profile.release]` + the `version` literal here; `extension.toml` must stay adjacent for Zed to compile the cdylib).

Product surfaces:
- **Terminal CLI** (`context-bar daily|weekly|monthly|session …`, since 0.4.0) — ccusage-style tables built from `context_bar_core::report` on top of the same cost engine. Bilingual, color-aware. The CLI is self-contained for `cargo install` (the python aggregator is embedded; see below).
- **Native macOS menubar app** (`menubar/sources/`, AppKit/Swift) — reads `~/.context-bar/context.json` and renders the popover + a detail window (Usage / Stats / Cost / General / Appearance / Privacy / About).

Distributed via a Homebrew cask + GitHub Releases (DMG, notarized + cross-platform CLI binaries for macOS/Linux-musl/Windows); the CLI also via crates.io (`cargo install context-bar`) + npm (`npx context-bar`, see `docs/PUBLISHING.md`). Current version: **0.5.0** (see `CHANGELOG.md`).

## Architecture & data flow

**Since 0.5.0 the native engine is PURE RUST — no `python3`.** `usage_signal.py` survives only for the wasm Zed extension (which shells out to escape its sandbox).

```
~/.claude/projects/**/*.jsonl   ┐   crates/context-bar-core/src/collect.rs
~/.codex/sessions/**/*.jsonl     ├─►  collect_claude_enriched / collect_codex_enriched
(transcripts, per assistant turn)┘        │  read JSONL directly, extract per-turn metrics,
                                          │  price via pricing.rs (live LiteLLM + 24h cache),
                                          │  sessionize+bucket via aggregate.rs, then overlay
                                          │  online.rs (statusline / usage-API % / codex limits)
                                          ▼
   usage_signal.rs collect_rust() assembles UsageSnapshot { claude, codex,
   others (others.rs probes), accounts (collect_accounts: ~/.claude/auth-*.json
   + mac keychain), collected_at, source="rust", pricing_source, estimate=true }.
   collect_native() caches it to ~/.context-bar/usage.cache.json (300s TTL,
   invalidated when any transcript is newer).
                                                                   │
   src/bin/context-bar.rs `global` ──► writes:                     ▼
       ~/.context-bar/context.json   (serialized UsageSnapshot — the menubar reads this)
       ~/.context-bar/detail.html    (standalone HTML export, detail_html.rs)
       ~/.context-bar/hud.md / hud.json
                                                                   │
   menubar/sources/ (Swift) reads ~/.context-bar/context.json ─────┘
       ContextSnapshot.swift parses it; PopoverViewController + DetailWindowController render.
```

**Serialization parity:** the Rust `UsageSnapshot` serializes keys the Swift app already reads — `by_day_project`→`date`/`project`, `by_month`→`date` (Swift accepts `date`‖`month`), `active_sessions`→`project`/`model`. `by_week`/`by_project` raw JSON isn't consumed by Swift. The Python↔Rust struct-mirror DRIFT RISK is retired for native (one Rust source of truth); only the wasm path still rides the Python schema via `#[serde(default)]` + `alias`.

### Key files (engine in `crates/context-bar-core/src/` unless noted)
- `collect.rs` (native) — `collect_claude`/`collect_codex` (pure deterministic transcript parse → token extraction → buckets) + `*_enriched` wrappers (add online overlays). Validated field-for-field vs the Python on real data (offline differential) + codex-reviewed.
- `pricing.rs` — the cost kernel (`Rate`, `FALLBACK_PRICING`, `match_pricing(model,&Table)`, `tiered`/`turn_cost`/`turn_cache_savings`) + native `load_pricing` (live LiteLLM fetch via `ureq` → 24h `pricing.cache.json` → fallback). Golden-pinned to the Python (`tests/pricing_golden.rs`, 488 rows byte-for-byte).
- `aggregate.rs` — `split_logical_sessions` (5h idle gap) + `bucket_aggregates` (day/week/month/model/project + day×project, local-tz END-day attribution, 365-day padding, 30d totals) + `iso_utc`/`parse_iso`. Golden-pinned (`tests/aggregate_golden.rs`). Uses `round_ties_even` to match Python's `round()`.
- `online.rs` (native) — best-effort overlays: statusline snapshot read, Anthropic usage API (`ureq` + creds: mac keychain → `~/.claude/.credentials.json`), Codex transcript rate-limits. Each degrades to a no-op offline.
- `others.rs` (native) — `collect_others`: gemini-cli / aider / zsh-history AI-tool probes (`llm` sqlite probe omitted).
- `usage_signal.rs` — the `UsageSnapshot`/`AgentUsage`/… structs (still serde mirrors) + `collect_rust()` (assembles the pure-Rust snapshot) + `collect_native()` (caches it) + `collect_accounts()`. The wasm32 `collect(worktree)` still `include_str!`s + runs `usage_signal.py`.
- `usage_signal.py` (~1450 lines) — the legacy aggregator, now ONLY the wasm Zed extension's data source (shells out to escape the sandbox). The Rust port mirrors it 1:1; keep them in sync until the wasm path also moves to the Rust binary (future).
- `report.rs` — pure aggregation behind the CLI verbs: `time_report` (daily/weekly/monthly), `instances_report`, `session_report`, `model_report` → serde-`Serialize` `Report`/`ReportRow`/`Metrics`. `Metrics::total_tokens()` = the ccusage 4-bucket Total. No terminal deps (reusable by future surfaces). Unit-tested for agent sums, filters, ISO-week labels.
- `i18n.rs` — shared `Language` (EN/TR) + `detect()` (honors `CONTEXTBAR_LANG`, then locale). Used by `detail_html` and the CLI; every user-facing string goes through `lang.text(en, tr)`.
- `detail_html.rs` — self-contained dark-theme HTML export (Today / Cost / History / Sessions / Breakdown tabs). Bilingual EN/TR via `i18n::Language`.
- `src/bin/context-bar.rs` (root crate) — CLI dispatch: report verbs `daily`/`weekly`/`monthly`/`session`/`blocks` (+ flags `--instances`/`--breakdown`/`--agent`/`--since`/`--until`/`--json`/`--offline`/`--lang`/`--no-color`) and engine verbs `hud`/`snapshot`/`global`/`watch`/`watch-global`/`claude-statusline`/`--version`. `autobins = false` (CLI is one explicit bin; `cli_report.rs` is its module).
- `src/bin/cli_report.rs` (root crate) — comfy-table rendering of a `Report`: ccusage-style tables, right-aligned thousands-grouped numbers, `$` cost, color gated on a tty + `NO_COLOR`/`--no-color`.
- `menubar/sources/` — AppKit app. Notable: `PopoverViewController` (menubar popover), `DetailWindowController` (tab window), `CostViewController` (Cost tab), `UsageViewController`, `StatsViewController`, `SettingsPanes.swift` (`GeneralSettingsViewController`, `AppearanceSettingsViewController`, `PrivacySettingsViewController`, `AboutViewController`), `ContextSnapshot.swift` (JSON→typed + formatters incl. `formatTokens`/`formatUSD`), `Models.swift`, `CommonViews.swift` (StatTileView/SparklineView/etc), `DesignTokens.swift` (Spacing/Radius/Typography/Surface), `Localization.swift` (`L10n.text(en, tr)`, `L10n.lang`).
- `Cargo.toml` — `[[bin]] context-bar`, `[lib] crate-type=["cdylib","rlib"]`, wasm32 target (`zed_extension_api`), release profile (`lto="thin"`, `strip="symbols"`). Version is the source of truth.
- `scripts/build-menubar-app.sh` — builds the universal `.app` (swiftc -O arm64+x64 lipo + cargo release engine + resources + sign). Widget is opt-in (`WIDGET_BUILD=1`).
- `.github/workflows/release.yml` — triggers on tag `v*`: `build-macos-release` (DMG + notarize + GitHub release + cask bump + tap sync) and `upload-binaries` (matrix: 6 targets via `taiki-e/upload-rust-binary-action` — mac/linux-musl/windows — attached to the same release). Release notes from `docs/releases/v<ver>.md` if present.

## Build & verify

- Rust: `cargo build`, `cargo test --workspace` (**use `--workspace`** — the engine tests live in `context-bar-core`; a bare `cargo test` only runs the root crate and reports 0). `cargo build --release`.
- Zed extension (wasm32): `cargo build --target wasm32-wasip2 -p context-bar --lib` — the extension is gated `cfg(target_arch="wasm32")`; native-only items (`collect_native`, `claude_statusline`, keychain) must stay behind `cfg(not(wasm32))` or the wasm build breaks.
- Terminal CLI smoke: `./target/debug/context-bar daily --since <YYYYMMDD>` (and `--json`, `--lang tr`). Reports build from `collect_native()`, not the daemon's `context.json`, so no daemon race.
- Swift type-check (fast, no bundle): `xcrun --sdk macosx swiftc -typecheck -target arm64-apple-macos13.0 menubar/sources/*.swift`.
- Swift single-arch binary: same with `-O ... -o /tmp/bin` (no `-typecheck`).
- Run the engine: `./target/debug/context-bar global` writes `~/.context-bar/`.
- Python: `python3 -m py_compile crates/context-bar-core/src/usage_signal.py`; run with `CONTEXTBAR_PRICING_OFFLINE=1 python3 crates/context-bar-core/src/usage_signal.py` (skips the live LiteLLM fetch — fast, deterministic).

### Headless screenshot verification (no human needed)
The Swift app honors env vars to render + capture a tab to PNG, then quit:
- `CONTEXTBAR_SCREENSHOT_PATH=/tmp/x.png` — capture the detail window then terminate.
- `CONTEXTBAR_SELECT_TAB=N` — which tab (0=Usage,1=Stats,2=Cost,3=General,4=Appearance,5=Privacy,6=About).
- `CONTEXTBAR_SCREENSHOT_SIZE=WxH` — size the window (marketing/verification only).
- `CONTEXTBAR_CONTEXT_PATH=/path/to/snapshot.json` — read a specific snapshot (isolate from the live daemon).
- `CONTEXTBAR_DEBUG_HOVER=N` — force the cost trend chart's hover tooltip on day index N (verify hover rendering).
Pattern: build binary → run with these envs via `subprocess` → `Read` the PNG. Always verify interactive/visual changes with a real-data screenshot — a real-data capture caught an Auto-Layout crash that an empty-state screenshot missed.

## Environment gotchas (memory-backed, will bite you)

1. **RTK hook corrupts text-tool output** (memory `rtk_output_unreliable`). The user's global RTK ("Rust Token Killer") rewrites/caches Bash commands; `grep`/`strings`/`cat` returned stale/fabricated results that disagreed with the file, and an explicitly-invoked binary appeared to run (`exit 0`) but didn't regenerate its output (cached). **Ground-truth via Python**: `open(path).read()` for files, `open(bin,"rb").read()` for binary symbol checks, `subprocess.run([...])` to actually execute (bypasses RTK's Bash rewriting). The `python3 - <<'PY' … PY` heredoc pattern is reliable.
2. **A running daemon/menubar app overwrites `~/.context-bar/context.json`** every ~30s with whatever engine it embeds. If you regenerate it manually then read it, the daemon may have clobbered it. For verification, point `CONTEXTBAR_CONTEXT_PATH` at a private snapshot you control, or copy `context.json` immediately after writing.
3. **Snapshot cache**: `collect_native()` reuses `~/.context-bar/usage.cache.json` for 300s. Delete it to force a fresh Python run when testing engine changes.

## Coding standards & conventions

- **Match surrounding code**: comment density, naming, idiom. Comments explain *why*, not *what*.
- **Bilingual UI**: every user-facing string is `L10n.text("English", "Türkçe")` (Swift) or `lang.text("English","Türkçe")` (Rust `detail_html.rs`). Never ship a one-language string.
- **Native macOS / Apple HIG**: tabular figures for numbers, right-align numerics, system semantic colors (auto light/dark), `DesignTokens` Spacing/Radius/Typography/Surface, SF Symbols for tab icons, "minimize the number of settings."
- **Token-total invariant** (memory `stats_token_formula`): the Stats/HUD "tokens" total is `fresh_in + outp` only — never re-add `cache_creation`. The Cost tab's "Total Tokens" column is different (all four buckets, ccusage parity) — keep these distinct and labeled.
- **Commits** (user global rule): Conventional Commits, subject only, one line ≤72 chars, no body, no `Co-Authored-By`/"Generated with" trailer. Never amend unless asked. Commit directly to `main` (this repo's established flow).
- **Releases** (memory `release_flow`): bump `Cargo.toml` + add `CHANGELOG.md` section + `docs/releases/v<ver>.md` → `cargo build` (sync lock) → commit → **push `main` BEFORE the tag** (pushing the tag first while main is behind fires two workflow runs) → `git tag v<ver>` → push tag. Workflow does DMG+notarize+release+cask+tap automatically. Don't release every change — batch (per user).
- **Secrets**: `AuthKey_*.p8` and `dist/` are gitignored; never commit them. Verify `git status` before committing; add specific files, not `-A`.
- **Use codex** (`codex:codex-rescue` agent) for deep correctness/analysis passes when useful; it confirmed the cost formula. Note it can hang — don't hard-block on it; extract its substantive finding and proceed.

## Current state (as of 0.5.0)
- **Workspace split (E1):** engine in `context-bar-core`; root crate = thin CLI bin + Zed extension re-exporting core.
- **Terminal CLI (B1):** `daily`/`weekly`/`monthly`/`session` ccusage-style tables, bilingual, full flag set.
- **PURE-RUST ENGINE (E1 port, done in 0.5.0):** `usage_signal.py` fully ported to Rust (`pricing` + `aggregate` + `collect` + `online` + `others`); `collect_native` no longer spawns python3. Validated by golden fixtures (pricing 488-row + aggregate), two codex parity reviews, and a real-data differential (frozen `~/.claude`+`~/.codex`, field-for-field). The `.py` remains only for the wasm Zed extension. **This unblocked A1.**
- **Cross-platform binaries (A1, done):** `.github/workflows/release.yml` builds 6 targets (mac arm64/x64, linux-musl arm64/x64, windows arm64/x64) via `taiki-e/upload-rust-binary-action` on tag. `cargo test --workspace` ~30 tests + `wasm32-wasip2` lib all green.
- **A2 (`npx context-bar`):** packaging documented in `docs/PUBLISHING.md` (cargo-npm); publish needs the maintainer's npm creds.
- **Next:** B2 (`ratatui` live 5h-block dashboard) — the crown-jewel cross-platform feature; C1 native popover gauge + budgets; D more providers. See `ROADMAP.md`.
- Cost feature complete: per-turn LiteLLM-priced estimate, `by_day_project` daily×project breakdown, full ccusage-parity column table in the Cost tab (Input/Output/Cache+/Cache↻/Total/Cost, grouped by day, Total row), monthly plan-value projection, cache-savings line, interactive 30-day trend chart (hover tooltip), active-session cost in the popover.
- Settings IA consolidated to Apple-style: Usage·Stats·Cost (data) + General·Appearance·Privacy (settings) + About.
- See `ROADMAP.md` for what's next (distribution, TUI, terminal CLI, blocks-live dashboard, more providers).
