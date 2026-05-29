# Kickoff prompt — long-haul build-out (run in ultracode)

Paste the block below into a fresh ultracode session at the repo root
(`/Users/ozlu/projeler/hususi/backend/context-hud`). It hands off the full
plan via the in-repo docs so the new session starts with high signal.

---

You are continuing the long-haul development of **context-bar**, turning it into a
top-tier, broadly-useful open-source project. Work autonomously and exhaustively
(ultracode): plan with workflows, fan out research/implementation, verify hard.
Do NOT ask me to confirm routine decisions — use your judgment and `codex`
(`codex:codex-rescue`) for deep correctness/analysis where useful. Batch the work
into a few meaningful releases; do NOT cut a release per change.

FIRST, read these in-repo briefs (they encode everything already analyzed/verified
— architecture, the verified cost model, the research-backed roadmap, standards,
and environment gotchas). Treat them as ground truth and keep them updated as you go:
- `docs/ai/AGENT_GUIDE.md`  — architecture, data flow, build/verify, gotchas, standards
- `docs/ai/COST_MODEL.md`   — verified pricing/cost methodology (don't regress this)
- `docs/ai/ROADMAP.md`      — the prioritized build-out plan (epics A–E) with sources
- `docs/ccusage.png`        — the daily-table design target

MISSION: execute the roadmap to make context-bar reach ccusage's audience while
keeping the premium native macOS app. Suggested order (see ROADMAP for detail):
1. A0 — reserve `context-bar` on crates.io + npm (+ `@context-bar` scope).
2. E1 — split into `context-bar-core` (engine + cost/token logic) + thin `context-bar` bin; begin folding `usage_signal.py` logic into the Rust core to kill Python↔Rust struct drift.
3. B1 — first-class terminal CLI: `daily`/`--instances`/`weekly`/`monthly`/`session`/`blocks`/`--breakdown`/`--json`/`--offline`, reusing the cost logic, with clean terminal tables (the `docs/ccusage.png` layout).
4. A1+A2 — cross-platform release matrix (`taiki-e/upload-rust-binary-action`, 6 targets, musl Linux) + `npx context-bar` via the optionalDependencies/per-platform sub-package pattern (`cargo-npm`; NOT cargo-dist fetch-on-install).
5. B2 — `context-bar live` ratatui+crossterm TUI: the 5h-block burn dashboard (burn rate, % of limit, ETA-to-limit, projected total) — the crown-jewel cross-platform feature.
6. C1 — bring the live block gauge + a user budget into the macOS popover/menubar.
7. A4 `cargo install`, C2/C3/C4 native polish, D more providers (OpenCode, Gemini CLI), E2 OSS docs/README/GIFs/tests.

HARD CONSTRAINTS (from AGENT_GUIDE — do not violate):
- Keep the macOS app + Homebrew cask as the premium path; don't break them.
- Bilingual EN/TR for every user-facing string; native macOS HIG; match surrounding code.
- Preserve cost-model fidelity (COST_MODEL.md): LiteLLM rates, the formula, >200K tiering, model matching, the `total = fresh_in + outp` Stats invariant vs the cost-tab all-buckets "Total".
- Rust structs must mirror Python JSON fields (or fields drop); `#[serde(default)]` everywhere.
- VERIFY everything: `cargo build`/`cargo test`, `swiftc -typecheck`, and real-data screenshots via the `CONTEXTBAR_SCREENSHOT_PATH`/`SELECT_TAB`/`SIZE`/`DEBUG_HOVER`/`CONTEXTBAR_CONTEXT_PATH` envs. RTK corrupts `grep`/`strings`/cached binary runs — ground-truth via Python `subprocess`/file reads (heredoc pattern). A running daemon overwrites `~/.context-bar/context.json` — use a private snapshot for captures.
- Commits: Conventional Commits, one line ≤72 chars, no body/attribution, directly to `main`. Releases: bump Cargo.toml + CHANGELOG + `docs/releases/v<ver>.md`, push `main` BEFORE the tag, then push the tag (the workflow does DMG/notarize/release/cask/tap). Batch releases (e.g. 0.4.0 = terminal CLI + cross-platform + npx; 0.5.0 = live dashboard).
- Never commit secrets (`AuthKey_*.p8`, `dist/`).

Begin by reading the three briefs, then produce a concrete execution plan for the
first release (target ~0.4.0: A0 + E1 + B1 + A1/A2), and start implementing.
Keep the briefs updated as the architecture evolves.
