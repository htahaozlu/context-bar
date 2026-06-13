# ContextBar

<p align="center">
  <img src="logo.png" alt="ContextBar logo" width="560">
</p>

<p align="center">
  English | <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <strong>Usage and cost for Claude Code <em>and</em> Codex — together, on every surface. Local-first, no account required.</strong>
</p>

<p align="center">
  ContextBar shows where your Claude Code <strong>and</strong> Codex usage and money are going. A <strong>native macOS menubar app</strong> keeps a live gauge-dot in your menubar, an at-a-glance popover, and a five-tab detail window (Stats · Cost · Settings · Privacy · About). A <strong>cross-platform terminal CLI</strong> brings the same numbers — daily / weekly / monthly / session reports plus a live TUI — to macOS, Linux, Windows, and SSH, on a pure-Rust engine with no <code>python3</code> required. Both agents are shown side by side throughout. Cost is an <strong>estimate</strong> computed from your local transcripts × published per-model rates — it is not a bill. Everything runs locally; optional iCloud Drive sync rolls usage up across your Macs without a server.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-bar/releases/latest/download/ContextBar.dmg">
    <img src="docs/images/download-macos-cta.svg" alt="Download app for macOS" width="300">
  </a>
</p>

<p align="center">
  <strong>Prefer the terminal?</strong> <code>npx context-bar@latest daily</code> · <code>cargo install context-bar</code> — see <a href="#install">Install</a>.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-bar/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/htahaozlu/context-bar?style=flat-square&label=release&color=2F81F7">
  </a>
  <a href="https://crates.io/crates/context-bar">
    <img alt="crates.io" src="https://img.shields.io/crates/v/context-bar?style=flat-square&label=crates.io&color=E07A2B">
  </a>
  <a href="https://www.npmjs.com/package/context-bar">
    <img alt="npm" src="https://img.shields.io/npm/v/context-bar?style=flat-square&label=npm&color=CB3837">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-5DADE2?style=flat-square">
  </a>
</p>

<p align="center">
  <img alt="Platforms" src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-7DCEA0?style=flat-square">
  <img alt="Architectures" src="https://img.shields.io/badge/arch-arm64%20%7C%20x64-7DCEA0?style=flat-square">
  <img src="https://img.shields.io/github/downloads/htahaozlu/context-bar/total?style=flat-square&label=downloads" alt="Total downloads">
  <img src="https://img.shields.io/github/stars/htahaozlu/context-bar?style=flat-square" alt="Stars">
</p>

## Demo

<p align="center">
  <img src="docs/images/context-bar-cli-demo.gif" alt="ContextBar terminal CLI showing Claude Code and Codex daily usage and cost" width="100%">
</p>

The terminal CLI brings Claude Code and Codex usage and cost to any OS, including over SSH. On macOS the native menubar app keeps the same numbers always-on — a live gauge-dot, a popover, and a five-tab detail window.

## Install

ContextBar ships as two products from one release: a **native macOS app** and a **cross-platform terminal CLI**. Pick whichever fits how you work — or use both.

### macOS app — Homebrew (recommended)

The premium, native flagship: a menubar status item, a live AppKit popover, a WidgetKit widget, and a Share card. Requires macOS Ventura (13) or later.

```bash
brew install --cask htahaozlu/context-bar/context-bar
```

`brew` auto-taps `htahaozlu/homebrew-context-bar` on first install. Upgrade later with:

```bash
brew update && brew upgrade --cask htahaozlu/context-bar/context-bar
```

### Terminal CLI (macOS · Linux · Windows)

The cross-platform reach: ccusage-class usage and cost reports plus a live TUI dashboard. Pure-Rust engine — **no `python3` required**. Runs on macOS, Linux (x64/arm64, static musl), and Windows (x64/arm64), including over SSH.

**npm (no install — runs the latest):**

```bash
npx context-bar@latest daily
# also works with other package managers:
bunx context-bar daily
pnpm dlx context-bar daily
```

To install it globally:

```bash
npm install -g context-bar
```

The meta package resolves a prebuilt binary for your platform via an optional dependency (`@htahaozlu/context-bar-<os>-<cpu>`); there is no postinstall, so it works under `npm ci --ignore-scripts`.

**Cargo (crates.io):**

```bash
cargo install context-bar
```

This builds `context-bar` (and its engine, `context-bar-core`) from crates.io.

**Prebuilt binaries (GitHub releases):**

Every [release](https://github.com/htahaozlu/context-bar/releases/latest) attaches a standalone binary for six targets, each with a `.sha256` checksum:

| OS | arch | asset |
| --- | --- | --- |
| macOS | arm64 | `context-bar-aarch64-apple-darwin.tar.gz` |
| macOS | x64 | `context-bar-x86_64-apple-darwin.tar.gz` |
| Linux | arm64 | `context-bar-aarch64-unknown-linux-musl.tar.gz` |
| Linux | x64 | `context-bar-x86_64-unknown-linux-musl.tar.gz` |
| Windows | arm64 | `context-bar-aarch64-pc-windows-msvc.zip` |
| Windows | x64 | `context-bar-x86_64-pc-windows-msvc.zip` |

Download the archive for your platform, verify the checksum, unpack it, and put `context-bar` on your `PATH`. (Linux binaries are statically linked against musl, so they run on any distro.)

### Zed extension

ContextBar also ships as a [Zed](https://zed.dev) extension that adds `/hud`, `/brief`, `/hello`, and `/doctor` slash commands to the Assistant (declared in `extension.toml`). Install it from the repo as a dev extension: in Zed, **Extensions → Install Dev Extension**, then pick this repository's root.

### macOS app — direct download (DMG)

If you don't use Homebrew:

1. Download `ContextBar.dmg` from the [latest release](https://github.com/htahaozlu/context-bar/releases/latest) (universal: Apple Silicon + Intel).
2. Drag `ContextBar.app` into `Applications`.
3. Launch it. The app is **signed and notarized by Apple**, so it opens without a quarantine warning.
4. Eject and delete the DMG.

## Preview

Every surface shares one calm visual language — a warm clay signature over a neutral gray scale, with JetBrains Mono tabular numbers throughout.

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar native detail window" width="100%">
</p>

The native macOS detail window with five tabs — Stats · Cost · Settings · Privacy · About — covering both Claude Code and Codex at once.

<p align="center">
  <img src="docs/images/context-bar-menubar.png" alt="ContextBar menubar" width="400">
</p>

The menubar is a single gauge-dot: the arc is your context fill and the color ramps calm (clay) → amber → red as a limit gets close (it shows a hollow ring when idle). The project label follows the **git repository** — the origin remote name, else the repo root folder; directories that aren't in a repo read as `parent/leaf`. Click it for a popover: the active session as a hero card on top, parallel sessions below, then two limit cards (Claude and Codex). Click any session to drill into its exact context-window fill (used / free / %) and an estimated per-turn "context loaded" breakdown (CLAUDE.md, MCP, skills).

<p align="center">
  <img src="docs/images/context-bar-cost.png" alt="ContextBar Cost tab — API-equivalent value vs your plan, plus real billed spend for API-only models" width="100%">
</p>

The **Cost** tab shows two honest numbers side by side: the **API-equivalent value** of your usage against your flat plan (what the metered API *would* charge for plan models — not what you pay), and **real billed spend** for API-only models that aren't in your plan (e.g. Codex). It breaks both out per model (plan vs billed), with a 30-day trend, a daily breakdown, and cross-machine totals under **Across your Macs**. Every figure is an **estimate** from local transcripts × published rates — never a bill.

## What it does

ContextBar answers a question agent-driven developers keep asking and can't easily see: **where are my Claude Code and Codex tokens — and money — going?** It reads your local transcripts and surfaces usage and cost for both agents, side by side, on whatever surface you work from.

### Surfaces

- **Menubar app (macOS)** — a single gauge-dot in the menubar (arc = context fill, color = urgency), a popover with the active session, parallel sessions, and Claude + Codex limit cards, and a five-tab detail window (Stats · Cost · Settings · Privacy · About).
- **Terminal CLI (macOS · Linux · Windows · SSH)** — `daily` / `weekly` / `monthly` / `session` / `blocks` reports + a live TUI, on a pure-Rust engine with no `python3`.
- **Zed extension** — `/hud`, `/brief`, `/hello`, and `/doctor` slash commands for the Assistant.

### Highlights

- **Both agents together** — Claude Code and Codex everywhere, with a "Both" filter (the default) in Stats and Cost.
- **Session context drill-down** — exact context-window fill (used / free / %) plus an estimated per-turn "context loaded" breakdown (CLAUDE.md, MCP, skills). Claude's full `/context` category split lives inside Claude Code and isn't on disk, so loader sizes are clearly marked as estimates.
- **Cost done honestly** — API-equivalent **value vs your flat plan** for plan models, **real billed spend** for API-only models, per-model breakdown, 30-day trend, daily breakdown — all estimates from local transcripts × published rates.
- **AI Advisor** — bring your own OpenAI/Gemini key for usage-efficiency tips (aggregate-only, opt-in, off by default).
- **Across your Macs** — opt-in iCloud Drive sync (or a self-hosted server) rolls small per-machine summaries up into combined totals; local-first, no account required.
- **Sub-agent burn** — see how much usage went to Task / multi-agent runs.

## How it compares to ccusage

The terminal CLI renders [ccusage](https://github.com/ryoppippi/ccusage)-style `daily` / `weekly` / `monthly` / `session` / `blocks` reports for both Claude Code and Codex, on a pure-Rust engine (no `python3`). The native macOS app then adds what a passive CLI can't surface: a live gauge-dot and rolling limit cards in the menubar, a session context drill-down, an interactive cost-trend chart, and cross-machine rollups. Use the CLI anywhere; reach for the app on macOS when you want it always-on.

## Key capabilities

### Repository context generation

Each refresh writes agent-readable state into `.context-bar/`:

- `state.json`
- `brief-now.md`
- `brief-session.md`
- `brief-week.md`
- `AGENT.md`
- `hud.md`

For Claude Code compatibility, `CLAUDE.md` is mirrored at the repository root.

### CLI workflow

- `context-bar hud` refreshes the current repository and prints the HUD
- `context-bar snapshot` writes artifacts without printing the HUD
- `context-bar watch 30 .` keeps repository context fresh on an interval
- `context-bar global` builds a cross-project HUD under `~/.context-bar/`

### Native macOS app

The app reads `~/.context-bar/context.json` (`hud.json` before v0.3.13) and provides:

- a menubar gauge-dot — the arc is your context fill, the color ramps calm (clay) → amber → red as a limit approaches, and a hollow ring shows when idle. The project label follows the **git repository** (origin remote, else the repo root folder); non-git directories read as `parent/leaf`.
- an AppKit popover — the active session as a hero card on top, parallel sessions below, then two limit cards (Claude and Codex). Click any session to open its context detail.
- a session context detail — exact context-window fill (used / free / %), token composition, and an estimated per-turn "context loaded" breakdown (CLAUDE.md, MCP, skills).
- a five-tab detail window — **Stats · Cost · Settings · Privacy · About**.

### Stats tab

Activity for **both** agents (a "Both" filter, the default), with metric tiles, a year-long heatmap, token composition, top projects, insights, and a model filter.

### Cost tab — value vs. plan, plus real spend

The **Cost** tab separates two things subscription users conflate:

- **API-equivalent value vs your flat plan** — what the metered API *would* charge for the models that are covered by your plan. This is a value estimate, not money you pay.
- **Real billed spend** — actual cost for API-only models that aren't in your plan (e.g. Codex, or any model you pay per token for).
- a **per-model breakdown** (plan value vs billed spend), a **30-day trend**, a **daily breakdown**, and **Across your Macs** combined totals.
- priced **per turn by model** from published rates (input / output, cache-write ×1.25, cache-read ×0.1), with a live fetch, an on-disk cache, and a bundled offline fallback; Anthropic's prompt-cache and long-context rules are honored.
- everything is clearly labelled an **estimate** — subscription plans are not billed per token. Set `CONTEXTBAR_PRICING_OFFLINE=1` to skip the live rate fetch.

### Sub-agent (dynamic-workflow) burn

A **"via sub-agents"** stat shows how much of your usage went to Task / multi-agent runs — the burn that's easy to start and hard to see. (Anthropic reports multi-agent setups use roughly 15× the tokens of a single chat.)

### AI Advisor — bring your own key

Connect **your own** OpenAI or Gemini API key (stored in the macOS Keychain) and press **Analyze** in the Cost tab to get specific, actionable recommendations to cut cost and improve context efficiency, grounded in your numbers. Privacy-first and opt-in: only a small **aggregate summary** is sent — never transcripts, never project names — and only to the provider you chose. Off by default.

### Across your Macs

Turn on **iCloud Drive sync** in Settings on each Mac (same Apple ID) and each machine writes a small per-machine usage rollup that the others read; the Cost tab then shows your **combined cost across machines**, with a per-Mac breakdown. Prefer not to use iCloud? Point it at a self-hosted server or a folder you already sync instead. Local-first, no account required, no telemetry — just files in your own synced location.

### Desktop & Notification Center widget

ContextBar ships with a native WidgetKit extension in three sizes —
`systemSmall`, `systemMedium`, and `systemLarge`. The widget reads the same
`context.json` as the menubar via a shared App Group container
(`DQJT5BCZCM.com.htahaozlu.contextbar`), so it always reflects the active
agent, project, model, context %, rolling 5h/7d limits, and a per-agent
breakdown without any extra daemon.

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar widget preview placeholder" width="100%">
</p>

To add it:

1. Install ContextBar 0.3.12 or later and launch it once so macOS indexes
   the extension (`pluginkit -m -v -i com.htahaozlu.contextbar.widget`
   should list it).
2. Open Notification Center (click the clock) → **Edit Widgets**, or
   right-click the desktop → **Edit Widgets**.
3. Search for **ContextBar**, then drop the small / medium / large variant
   wherever you want.

The widget extension is sandboxed and signed with the App Group entitlement,
which is required by `chronod` on macOS 14+ (the previous unsandboxed bundle
was silently rejected with `Ignoring restricted or unknown extension`).
The host menubar app mirrors `~/.context-bar/context.json` into the App Group
container on every refresh so the sandboxed widget can read it.

### Share Today's HUD

The popover footer has a **Share** button (`square.and.arrow.up`) that
renders the current HUD as a PNG share card — active agent, model, context
%, 5h/7d usage, and other detected tools — masked by default so project
names are not leaked. The image is saved to a temporary path and opened in
Preview / a save dialog so you can drop it into Slack, X, or a status
thread without screenshotting and cropping.

<p align="center">
  <img src="docs/images/context-bar-screenshot-full.png" alt="ContextBar share card preview" width="100%">
</p>

Headless render (no UI) for automation:

```bash
CONTEXTBAR_SHARE_RENDER_PATH=/tmp/hud.png \
CONTEXTBAR_SHARE_MASK=1 \
/Applications/ContextBar.app/Contents/MacOS/context-bar
```

Set `CONTEXTBAR_SHARE_MASK=0` to keep real project names in the card.

If the menubar icon is hidden by overflow (Bartender, Hidden Bar, or a
crowded menubar), launching ContextBar again from Finder / Spotlight opens
the Settings window directly so you can still reach preferences.

The desktop UI is native AppKit (NSPopover + NSVisualEffectView, continuous
corner curves, SF Symbol toolbar). `detail.html` is an export artifact, not
the primary app experience.

## Usage

### Refresh the current repository

```bash
context-bar hud
```

### Write artifacts without printing the HUD

```bash
context-bar snapshot
```

### Keep repository context fresh

```bash
context-bar watch 30 .
```

### Generate the global HUD

```bash
context-bar global
context-bar watch-global 30
```

The global HUD is written to `~/.context-bar/hud.md`.

## Terminal CLI

The terminal CLI is built on the same pure-Rust cost engine that powers the macOS app (which remains the premium flagship). It runs on macOS, Linux, and Windows (arm64 + x64), needs no `python3`, works over SSH, and installs via `npx context-bar`, `cargo install context-bar`, or a prebuilt binary. Report verbs render `ccusage`-style tables for Claude Code and Codex usage.

### Report verbs

- `context-bar daily` — per-day usage + cost table (Claude + Codex), grouped with an "All" row, per-agent sub-rows, and a Total row
- `context-bar weekly` — per-ISO-week table
- `context-bar monthly` — per-month table
- `context-bar session` — recent sessions table
- `context-bar blocks` — active 5h block per agent: usage % of limit, burn rate ($/hr · tok/min), projected total, reset countdown, ETA-to-limit
- `context-bar live` — the same 5h-block burn metrics as an auto-refreshing terminal dashboard (`ratatui`): a color-tiered gauge per agent, refreshing every `--interval` seconds; `q` to quit, `r` to refresh now. Works over SSH and on Linux/Windows.

### Report flags

- `--instances` — split the daily table by project (per day × project)
- `--breakdown`, `-b` — also print a per-model breakdown table
- `--agent <claude|codex|all>` — restrict to one agent (default: `all`)
- `--since <YYYYMMDD>` / `--until <YYYYMMDD>` — inclusive date filter
- `--json` — emit the report as JSON (for piping / `jq`)
- `--offline` — skip the live pricing fetch (cached / bundled rates)
- `--lang <en|tr>` — force UI language (default: locale; tables and headers are fully bilingual EN/TR)
- `--no-color` — disable ANSI color (also auto-off when piped or `NO_COLOR` is set)

The engine verbs `hud`, `snapshot`, `global`, `claude-statusline`, `watch`, `watch-global`, and `--version` are unchanged.

### Example

```
Coding Agent Usage Report — Daily
| Date       | Agent      | Models            | Input   | Output    | Cache Create | Cache Read    | Total         | Cost (USD) |
| 2026-05-29 | All        | opus-4-8, gpt-5.5 | 937,053 | 5,372,832 | 17,259,276   | 997,890,608   | 1,021,459,769 | $746.00    |
|            |   - Claude | opus-4-8          | 652,442 | 5,336,901 | 17,259,276   | 995,772,208   | 1,019,020,827 | $742.44    |
|            |   - Codex  | gpt-5.5           | 284,611 | 35,931    | 0            | 2,118,400     | 2,438,942     | $3.56      |
| Total      |            |                   | ...     | ...       | ...          | ...           | ...           | $1,682.65  |
```

In the real terminal these are Unicode box-drawing tables via `comfy-table`. `Total` follows `ccusage`'s Total Tokens — `input + output + cache_creation + cache_read`. Costs are **estimates** computed from your local transcripts × published per-model rates (input / output, cache-write ×1.25, cache-read ×0.1), not a bill — subscription users aren't billed per token.

## Artifact layout

Each refresh writes the following files atomically:

- `.context-bar/state.json`
- `.context-bar/brief-now.md`
- `.context-bar/brief-session.md`
- `.context-bar/brief-week.md`
- `.context-bar/AGENT.md`
- `.context-bar/hud.md`
- `CLAUDE.md`

Atomic writes ensure agents do not observe partial state during refresh.

## Data sources

ContextBar combines:

- Git branch, recent commits, and worktree status
- file activity inferred from repository mtimes
- optional Claude Code statusline snapshot from `~/.context-bar/claude-statusline.json`
- Claude Code usage from `~/.claude/projects/**/*.jsonl`
- Codex CLI usage from `~/.codex/sessions/**/*.jsonl`

No external service is required for the core repository summaries. Usage aggregation relies on locally available transcripts and optional native Claude Code statusline data, parsed by a pure-Rust cross-platform engine (no `python3`).

### Claude Code parity

For Claude context percentage, the best source is Claude Code's native statusline payload. ContextBar can persist that payload locally:

```json
{
  "statusLine": {
    "type": "command",
    "command": "context-bar claude-statusline"
  }
}
```

This writes `~/.context-bar/claude-statusline.json`, which ContextBar reads as the primary Claude context source. If the snapshot is missing or stale, ContextBar falls back to transcript-based estimation.

## Packaging

The repository includes scripts for the macOS companion build:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

To include the WidgetKit extension in a direct app build:

```bash
WIDGET_BUILD=1 scripts/build-menubar-app.sh
```

`scripts/create-macos-dmg.sh` enables the widget build by default.

Artifacts:

- `dist/ContextBar.app`
- `dist/ContextBar.dmg`

## Repository layout

- `crates/context-bar-core/` core engine — git/usage signals, cost pricing, report rendering
- `crates/context-bar-server/` optional self-hosted cross-machine sync server
- `src/` Zed extension entry point + engine glue (`extension.toml` declares the slash commands)
- `src/bin/context-bar.rs` standalone CLI entry point
- `menubar/sources/` native AppKit macOS app; `menubar/widget/` WidgetKit extension
- `examples/snapshot.rs` native development harness

## Development

```bash
cargo check
cargo run --example snapshot
```

## Community

- Questions and usage help: GitHub Discussions
- Bugs and feature requests: GitHub Issues
- Contribution guide: `CONTRIBUTING.md`
- Security reporting: `SECURITY.md`

## License

Apache-2.0
