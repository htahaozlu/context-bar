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

Distributed via a Homebrew cask + GitHub Releases (DMG, notarized); the CLI also via crates.io (`cargo install context-bar`, see `docs/PUBLISHING.md`). Current version: **0.4.0** (see `CHANGELOG.md`).

## Architecture & data flow

```
~/.claude/projects/**/*.jsonl   ┐   crates/context-bar-core/src/
~/.codex/sessions/**/*.jsonl     ├─►  usage_signal.py  ──────► JSON on stdout
(transcripts, per assistant turn)┘     (Python aggregator)        │
                                                                   ▼
   usage_signal.rs (collect_native) spawns python3, parses JSON into
   typed structs (UsageSnapshot), adds `accounts` (reads ~/.claude/auth-*.json
   + keychain), caches to ~/.context-bar/usage.cache.json (300s TTL, also
   invalidated when any transcript is newer). resolve_usage_script() finds the
   .py via env override / exe-sibling / app Resources / dev source tree, else
   materializes the embedded copy to ~/.context-bar/usage_signal.py (so a
   `cargo install`ed binary is self-contained — still needs python3 on PATH).
                                                                   │
   src/bin/context-bar.rs `global` ──► writes:                     ▼
       ~/.context-bar/context.json   (serialized UsageSnapshot — the menubar reads this)
       ~/.context-bar/hud.json       (legacy alias, one release of back-compat)
       ~/.context-bar/detail.html    (standalone HTML export, src/detail_html.rs)
       ~/.context-bar/hud.md         (markdown HUD)
                                                                   │
   menubar/sources/ (Swift) reads ~/.context-bar/context.json ─────┘
       ContextSnapshot.swift parses it; PopoverViewController (menubar click)
       + DetailWindowController (tabbed window) render it.
```

**CRITICAL invariant (memory `rust_struct_mirror`):** the Python emits a JSON object; the Rust structs in `crates/context-bar-core/src/usage_signal.rs` (`UsageSnapshot`, `AgentUsage`, `TimeBucket`, `NamedBucket`, `SessionRecord`, `DailyInstance`, `ActiveSession`) must mirror the Python field names or fields are silently dropped from `context.json`. Every Rust field uses `#[serde(default)]`. When you add a field in Python, add it to the Rust struct AND (if the menubar shows it) parse it in `ContextSnapshot.swift` / the relevant Swift VC. (0.5.0 will fold the Python aggregator INTO Rust to retire this drift risk — see `ROADMAP.md` E1.)

### Key files (engine in `crates/context-bar-core/src/` unless noted)
- `usage_signal.py` (~1450 lines) — the aggregator. Scans transcripts, sessionizes (5h idle-gap splits), buckets by day/week/month/model/project, computes per-turn estimated cost (see `COST_MODEL.md`), emits `by_day`, `by_day_project`, `recent_sessions`, window totals, pricing meta. **Embedded** into the bin via `include_str!` for `cargo install`.
- `usage_signal.rs` — Rust mirror structs + `collect_native()` (native; spawns python, caches snapshot) + `collect_accounts()` (macOS keychain) + the wasm32 `collect(worktree)`.
- `report.rs` — pure aggregation behind the CLI verbs: `time_report` (daily/weekly/monthly), `instances_report`, `session_report`, `model_report` → serde-`Serialize` `Report`/`ReportRow`/`Metrics`. `Metrics::total_tokens()` = the ccusage 4-bucket Total. No terminal deps (reusable by future surfaces). Unit-tested for agent sums, filters, ISO-week labels.
- `i18n.rs` — shared `Language` (EN/TR) + `detect()` (honors `CONTEXTBAR_LANG`, then locale). Used by `detail_html` and the CLI; every user-facing string goes through `lang.text(en, tr)`.
- `detail_html.rs` — self-contained dark-theme HTML export (Today / Cost / History / Sessions / Breakdown tabs). Bilingual EN/TR via `i18n::Language`.
- `src/bin/context-bar.rs` (root crate) — CLI dispatch: report verbs `daily`/`weekly`/`monthly`/`session`/`blocks` (+ flags `--instances`/`--breakdown`/`--agent`/`--since`/`--until`/`--json`/`--offline`/`--lang`/`--no-color`) and engine verbs `hud`/`snapshot`/`global`/`watch`/`watch-global`/`claude-statusline`/`--version`. `autobins = false` (CLI is one explicit bin; `cli_report.rs` is its module).
- `src/bin/cli_report.rs` (root crate) — comfy-table rendering of a `Report`: ccusage-style tables, right-aligned thousands-grouped numbers, `$` cost, color gated on a tty + `NO_COLOR`/`--no-color`.
- `menubar/sources/` — AppKit app. Notable: `PopoverViewController` (menubar popover), `DetailWindowController` (tab window), `CostViewController` (Cost tab), `UsageViewController`, `StatsViewController`, `SettingsPanes.swift` (`GeneralSettingsViewController`, `AppearanceSettingsViewController`, `PrivacySettingsViewController`, `AboutViewController`), `ContextSnapshot.swift` (JSON→typed + formatters incl. `formatTokens`/`formatUSD`), `Models.swift`, `CommonViews.swift` (StatTileView/SparklineView/etc), `DesignTokens.swift` (Spacing/Radius/Typography/Surface), `Localization.swift` (`L10n.text(en, tr)`, `L10n.lang`).
- `Cargo.toml` — `[[bin]] context-bar`, `[lib] crate-type=["cdylib","rlib"]`, wasm32 target (`zed_extension_api`), release profile (`lto="thin"`, `strip="symbols"`). Version is the source of truth.
- `scripts/build-menubar-app.sh` — builds the universal `.app` (swiftc -O arm64+x64 lipo + cargo release engine + resources + sign). Widget is opt-in (`WIDGET_BUILD=1`).
- `.github/workflows/release.yml` — triggers on tag `v*`: derive version, build DMG, notarize, publish GitHub release (notes from `docs/releases/v<ver>.md` if present), bump in-repo cask, **sync Homebrew tap** (works automatically now — token rescoped).

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

## Current state (as of 0.4.0)
- **Workspace split (E1, done):** engine extracted to `context-bar-core`; root crate is a thin CLI bin + Zed extension re-exporting core. Native + `wasm32-wasip2` + `cargo test --workspace` (15 tests) all green; a latent wasm-build break was fixed. Menubar build/cask flow preserved (`build-menubar-app.sh` copies the .py from the new path).
- **Terminal CLI (B1, done):** `daily`/`weekly`/`monthly`/`session` ccusage-style tables from `context_bar_core::report`, bilingual, `--json`/`--instances`/`--breakdown`/`--agent`/`--since`/`--until`/`--offline`/`--lang`/`--no-color`. Engine self-contained for `cargo install` (embedded `usage_signal.py`).
- **Deferred to 0.5.0 (verified blocker):** cross-platform prebuilt binaries (A1) + `npx` (A2) + Windows wait on the Python→Rust port — the engine spawns python3 and reads the macOS-only `security` keychain, so a musl/Windows binary is non-functional today. 0.4.0 reaches the dev audience via `cargo install` (has toolchain + python3). See `ROADMAP.md`.
- Cost feature complete: per-turn LiteLLM-priced estimate, `by_day_project` daily×project breakdown, full ccusage-parity column table in the Cost tab (Input/Output/Cache+/Cache↻/Total/Cost, grouped by day, Total row), monthly plan-value projection, cache-savings line, interactive 30-day trend chart (hover tooltip), active-session cost in the popover.
- Settings IA consolidated to Apple-style: Usage·Stats·Cost (data) + General·Appearance·Privacy (settings) + About.
- See `ROADMAP.md` for what's next (distribution, TUI, terminal CLI, blocks-live dashboard, more providers).
