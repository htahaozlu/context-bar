# Roadmap — turning context-bar into a pro OSS project

Goal: a very professional, broadly useful open-source project that meets real user needs — reaching ccusage's audience (15k★) while keeping the premium native macOS app. Research-backed (sources inline). Batch the work; don't ship a release per change.

Verified facts that shape strategy:
- **ccusage is now a Rust project** distributed via npm (`ccusage@20.x`, `bin→dist/cli.js`, empty deps, 6 scoped `@ccusage/*` optionalDependencies). Our engine is already Rust → copy this path.
- Names are **free**: `context-bar` on crates.io AND npm (+ `@context-bar` scope). Reserve early.
- ccusage's most-screenshotted feature, **`blocks --live`** (5h-window real-time dashboard), was REMOVED in ccusage v18 but lives in the `better-ccusage` fork. A native menubar + a TUI are the right homes for it.

> **VERIFIED BLOCKER (2026-05-29, reshapes A1/A2 sequencing):** our engine currently (a) spawns `python3` on `usage_signal.py` and (b) reads the macOS-only `security` keychain for accounts. So a Linux-musl / Windows prebuilt binary is **non-functional out of the box** (stock Windows has no `python3`; keychain is darwin-only). Shipping npm/cross-platform binaries before the **Python→Rust port (E1)** + a **cross-platform credential source** would be a broken first impression — the opposite of ccusage's "single static binary" promise. Therefore **A1 (release matrix) + A2 (npx) move to 0.5.0, after the port.** 0.4.0 still reaches the cross-platform *developer* audience via `cargo install context-bar` (they have a Rust toolchain + python3) with the aggregator embedded in the binary, and **reserves** the crates.io/npm names (A0) so they aren't squatted (`docs/PUBLISHING.md`).

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

## Execution order (revised after the verified blocker above)

**0.4.0 — engine foundation + terminal CLI (DONE, in `main`):**
1. ✅ **E1 (structural half)** — workspace split: `context-bar-core` rlib + thin `context-bar` bin/extension. (The Python→Rust *fold* is the 0.5.0 half.)
2. ✅ **B1** — `daily`/`weekly`/`monthly`/`session` CLI reports (reuses the cost engine; ccusage column layout; `--json`/`--instances`/`--breakdown`/filters/bilingual).
3. ✅ self-contained binary for `cargo install` (embedded `usage_signal.py`).
4. ⏳ **A0** — reserve crates.io (`context-bar-core` + `context-bar`) + npm (`context-bar` + `@context-bar`) names. Prep + metadata done; the maintainer runs the publish per `docs/PUBLISHING.md` (needs creds; irreversible).

**0.5.0 — pure-Rust engine + real cross-platform reach (the unlock):**
5. **E1 (port half)** — fold `usage_signal.py` into `context-bar-core`, incremental + golden-test-pinned so cost fidelity can't regress. Slices:
   - ✅ **Slice 1 — cost kernel** (`core::pricing`): `FALLBACK_PRICING` + matcher + `_tiered`/`turn_cost`/`turn_cache_savings`, ported 1:1. Pinned by `tests/pricing_golden.rs` (488 model×token rows generated from the Python, byte-for-byte). DONE.
   - ✅ **Slice 2 — deterministic transforms** (`core::aggregate`): `split_logical_sessions` (5h idle gap), `bucket_aggregates` (day/week/month/model/project + day×project, LOCAL-tz END-day attribution via a fixed UTC offset, 365-day padding, 30d totals, `cost_today`, `max_session_minutes`), `project_name_from_cwd`. Pinned by `tests/aggregate_golden.rs` (synthetic events under fixed `NOW`+`TZ=UTC` → byte/field parity with the Python). DONE. Still TODO in this slice: `build_active_sessions` + `claude_context_window` (live-HUD fields) — fold in with slice 3. NOTE: bucketing uses a fixed UTC offset; DST-aware per-ts local offset is a refinement (fine for fixed-offset zones like TR; golden uses offset 0).
   - ✅ **Slice 3 — JSONL discovery + parse** (`core::collect`, native-only): `collect_claude` / `collect_codex` + `build_active_sessions` + `claude_context_window`, reusing the pricing+aggregate kernels. Validated 3 ways: `tests/collect_smoke.rs` (committed synthetic), a **codex parity review** (costUSD precedence / thinking-key scan / codex token math all faithful), and a **real-data differential** (Python online-off vs Rust on a frozen `~/.claude`+`~/.codex`, shared `NOW`/`TZ` → claude+codex match field-for-field, except one inherent non-deterministic `by_day_project` glob-order tie on equal date+cost rows). Fixed per codex: falsy-non-dict → `{}` like Python's `or {}`; banker's rounding (`round_ties_even`). The dev harness is `examples/collect_dump.rs`.
   - ✅ **Slice 4 — online/host + wiring** (DONE): `others.rs` probes (gemini/aider/zsh-history; `llm` sqlite omitted); `online.rs` statusline read + Anthropic usage API (`ureq` + cross-platform creds) + Codex transcript rate-limits (app-server JSON-RPC deferred, degrades); `pricing.rs` live LiteLLM fetch + 24h cache + dynamic `match_pricing(model,&Table)`; `collect_rust()` assembles the full snapshot (`source="rust"`); `collect_native` no longer spawns python3. Serialization confirmed compatible with Swift consumers (no struct changes needed). Second codex review applied (usage-API non-200 vs transport handling, `expiresAt` validation). End-to-end verified via menubar screenshot against a Rust-produced `context.json`.
6. ✅ **A1 — release matrix** (DONE): `release.yml` `upload-binaries` job, 6 targets (mac/linux-musl/windows), `taiki-e/upload-rust-binary-action`, on tag. **A2** — `npx context-bar` via cargo-npm: packaging + publish steps documented in `docs/PUBLISHING.md` (needs maintainer npm creds).
7. ✅ **B2 — 5h-block burn dashboard (DONE):** `core::live` (`block_status`: burn $/hr + tok/min, % of limit, ETA-to-limit, projected, reset countdown, `Tier` color) — pure + unit-tested, reusable by C1; `context-bar blocks` (one-shot per-agent panel + `--json`/`--agent`); and `context-bar live` — the `ratatui`+`crossterm` auto-refresh TUI (panic-hook terminal restore, non-tty graceful exit, `--interval`, `q`/`r` keys; render unit-tested via `TestBackend`). Not yet in a tagged release — accumulating for 0.6.0.

**Next (0.6.0):** C1 — bring the live block gauge + a user budget into the macOS popover/menubar (reuses `core::live::block_status`). Then A4 `cargo install` polish, C2/C3/C4 native, D providers (OpenCode/Gemini CLI), E2 docs site.

**0.6.0+:** B2 live dashboard; C1 native popover live gauge + budgets; A4 polish; C2/C3/C4; D providers (OpenCode, Gemini CLI); E2 docs site. Long-term: move the wasm Zed extension off `usage_signal.py` too (shell out to the `context-bar` binary) to retire Python entirely.

Keep the macOS app + cask as the premium path throughout. Don't compromise standards in `AGENT_GUIDE.md`.
