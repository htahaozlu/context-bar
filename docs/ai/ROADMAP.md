# Roadmap — turning context-bar into a pro OSS project

Goal: a very professional, broadly useful open-source project that meets real user needs — reaching ccusage's audience (15k★) while keeping the premium native macOS app. Research-backed (sources inline). Batch the work; don't ship a release per change.

Verified facts that shape strategy:
- **ccusage is now a Rust project** distributed via npm (`ccusage@20.x`, `bin→dist/cli.js`, empty deps, 6 scoped `@ccusage/*` optionalDependencies). Our engine is already Rust → copy this path.
- Names are **free**: `context-bar` on crates.io AND npm (+ `@context-bar` scope). Reserve early.
- ccusage's most-screenshotted feature, **`blocks --live`** (5h-window real-time dashboard), was REMOVED in ccusage v18 but lives in the `better-ccusage` fork. A native menubar + a TUI are the right homes for it.

## EPIC A — Broad distribution (highest reach; the ccusage growth channel)

Engine is cross-platform Rust; ship it everywhere. Use the **optionalDependencies + per-platform sub-package** pattern (esbuild/biome/ccusage), NOT cargo-dist's npm fetch-on-install (breaks under `--ignore-scripts`/corporate CI).

- **A0 — Reserve names** (~15 min): publish placeholder `context-bar` to crates.io; reserve `context-bar` + `@context-bar` scope on npm.
- **A1 — Cross-platform release matrix** (~½ day): add a tag-triggered job using `taiki-e/upload-rust-binary-action` for the 6 ccusage targets `{aarch64,x86_64}-apple-darwin`, `{x86_64,aarch64}-pc-windows-msvc`, `{x86_64,aarch64}-unknown-linux-{gnu,musl}` (prefer musl for static Linux; `taiki-e/setup-cross-toolchain-action` for aarch64-linux). Keep the existing macOS DMG/cask job. Source: github.com/taiki-e/upload-rust-binary-action.
- **A2 — npm `npx context-bar`** (~½ day): run `abemedia/cargo-npm` over A1 binaries to publish the meta package + `@context-bar/context-bar-<plat>-<arch>` sub-packages (os/cpu + tiny JS spawn shim, no postinstall). Document `npx context-bar@latest`, `bunx`, `pnpm dlx` in README. This is how ccusage reached 15k★. Sources: blog.orhun.dev/packaging-rust-for-npm, sentry.engineering/blog/publishing-binaries-on-npm.
- **A4 — `cargo install context-bar`** (~1-2 hr): publish the bin crate to crates.io. Near-free once the workspace split (E1) lands.

## EPIC B — Terminal usability (CLI + TUI) — the "AI dev lives in the terminal" play

The Swift menubar stays the premium macOS surface. For Linux/Windows/SSH + the CLI-native audience, the engine needs first-class terminal output.

- **B1 — Real CLI reporting commands** (~1-2 days): make `context-bar` a proper CLI mirroring ccusage's verbs against OUR engine: `daily` (the ccusage.png table: Date · Agent · Models · Input · Output · Cache Create · Cache Read · Total · Cost, grouped + Total row), `--instances` (per-project), `weekly`, `monthly`, `session`, `blocks` (5h windows), `--breakdown` (per-model), `--since/--until`, `--json`, `--offline`. Reuse the cost logic. Pretty terminal tables (e.g. `comfy-table` or `tabled`); respect width; `--json` for piping. We already produce all the data.
- **B2 — `blocks --live` / `context-bar live` TUI** (~1-2 days, the crown jewel): a `ratatui` + `crossterm` live dashboard (cross-platform, works over SSH) showing the active 5h block: burn rate (tokens/min + $/hr), % of token limit, ETA-to-limit, projected block total, color-coded quota tiers. Reuses the engine, no FFI. This is the single most shareable feature and the cross-platform analogue of the macOS popover. Sources: ratatui.rs.
- **B3 — statusline-style compact line** (study, low effort): ccusage's `🤖 model | 💰 $session/$today/$block (time left) | 🔥 $/hr | 🧠 ctx%` is a great compact format — reuse its IA for a `context-bar statusline` and for the macOS menubar title. Three-tier color thresholds (configurable).

## EPIC C — Native macOS app: adopt the best of ccusage, our way

- **C1 — Menubar/popover live block gauge** (med): bring B2's 5h-block burn/projection into the popover as a native gauge + a menubar color shift (green→yellow→red) as a budget approaches. Pairs with a user-set token/cost budget (`-t/--token-limit max` auto-detect from highest historical block).
- **C2 — Trends** (low): weekly/monthly views (we already bucket them) as native charts; per-model `--breakdown` as a stacked bar / legend in the Cost tab.
- **C3 — Settings: full two-window split** (med, Apple HIG ideal): move the 3 data views (Usage/Stats/Cost) into the main window/popover behind an `NSSegmentedControl`, and make Settings a separate `Cmd-,` window with the `.toolbar` 3-pane controller (General/Appearance/Privacy), dim min/max, title-per-pane, restore last pane; move About to the App menu. (Today they share one 7-tab window — already much better than the prior 9.)
- **C4 — Cost modes + offline toggle** in settings (low): `auto`/`calculate`/`display` + force-offline pricing.

## EPIC D — More providers (incremental reach)

ccusage auto-detects Claude Code, Codex, OpenCode, Amp, Droid, Gemini CLI, Copilot CLI, Qwen, Kimi, etc., via env namespaces (`CODEX_HOME`, `GEMINI_DATA_DIR`, `OPENCODE_DATA_DIR`, `AMP_DATA_DIR`, …). We already do Claude + Codex + shell-history probes. Add OpenCode + Gemini CLI next (the detection scheme is directly reusable). `better-ccusage` adds GLM/Zai, Kimi/Moonshot, Minimax, Qwen-Max pricing — fold relevant keys into our pricing relevance filter (partly done).

## EPIC E — Engineering foundation

- **E1 — Workspace split** (med): `context-bar-core` crate (engine + cost/token logic, the reusable Anthropic-spec math) + thin `context-bar` bin. Enables crates.io publish + clean CLI/TUI. Long-term, fold `usage_signal.py` INTO the Rust core to kill the Python↔Rust struct-mirror drift risk (memory `rust_struct_mirror`) and drop the python3 runtime dependency. Big but high-value; do incrementally (Rust core can read transcripts directly — the logic is straightforward).
- **E2 — Docs & polish for OSS quality**: README with npx/brew/cargo install matrix + GIFs/screenshots of the TUI and Cost tab; CONTRIBUTING quickstart; a docs site (the `detail.html` styling is a good base); JSON schema for `context.json`; tests for the cost math (Rust core).

## Suggested execution order (for the long-haul session)
1. A0 reserve names (cheap, unblocks A2/A4).
2. E1 workspace split (unblocks clean CLI/TUI + crates.io).
3. B1 CLI reporting commands (immediate terminal value; reuses cost logic).
4. A1+A2 release matrix + npx (the reach unlock).
5. B2 ratatui live dashboard (the crown-jewel feature).
6. C1 native popover live gauge + budgets.
7. A4 cargo install, C2/C3/C4 polish, D providers, E2 docs.

Batch into a few meaningful releases (e.g. "0.4.0 — terminal CLI + cross-platform + npx", "0.5.0 — live dashboard"), not per-change. Keep the macOS app + cask as the premium path throughout. Don't compromise standards in `AGENT_GUIDE.md`.
