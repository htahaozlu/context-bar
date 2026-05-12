# Context Pilot

Context Pilot generates persistent repository context for coding agents and exposes a lightweight usage HUD for Claude Code and Codex CLI. It started as a Zed extension experiment, but the current product surface is broader: a reusable context engine, a CLI, agent-readable artifacts, and an optional macOS menubar companion.

## What it does

- Writes project artifacts under `.context-pilot/`
- Produces a stable `AGENT.md` brief for local coding agents
- Mirrors the same brief to `CLAUDE.md` for Claude Code compatibility
- Summarizes repository activity across `now`, `session`, and `week` windows
- Builds a usage HUD from local Claude Code and Codex CLI transcripts
- Works through both a Zed extension surface and a standalone CLI

## Artifact layout

Each refresh writes the following files:

- `.context-pilot/state.json`
- `.context-pilot/brief-now.md`
- `.context-pilot/brief-session.md`
- `.context-pilot/brief-week.md`
- `.context-pilot/AGENT.md`
- `.context-pilot/hud.md`
- `CLAUDE.md`

Writes are atomic, so agents do not observe partial files mid-refresh.

## Installation

### CLI

```bash
cargo install --path .
```

### Zed dev extension

1. Open the Extensions view in Zed.
2. Choose `Install Dev Extension`.
3. Select this repository.
4. If needed, grant `process:exec` under `granted_extension_capabilities`.

## Usage

### Refresh the current repository

```bash
context-pilot hud
```

### Write all artifacts without printing the HUD

```bash
context-pilot snapshot
```

### Keep repository artifacts fresh

```bash
context-pilot watch 30 .
```

### Generate the global HUD

```bash
context-pilot global
context-pilot watch-global 30
```

The global HUD is written to `~/.context-pilot/hud.md`. Pin that file in Zed if you want a persistent cross-project tab.

## macOS app and DMG

The repository includes packaging scripts for the optional menubar companion:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

This produces:

- `dist/Context Pilot Bar.app`
- `dist/Context-Pilot-Bar.dmg`

The DMG includes a short install note that tells users to drag the app into `Applications`, launch it once, then eject and delete the DMG.

## How the data is collected

Context Pilot combines:

- Git branch, recent commits, and worktree status
- File activity inferred from repository mtimes
- Claude Code usage from `~/.claude/projects/**/*.jsonl`
- Codex CLI usage from `~/.codex/sessions/**/*.jsonl`

No external service is required for the core repository summaries. Usage aggregation relies on locally available transcript data and `python3`.

## Current constraints

- Zed `extension_api` `0.7` does not expose a load-time worktree hook.
- Zed does not yet expose a persistent HUD primitive for extensions.
- Agent auto-injection is file-based today; agents read `.context-pilot/AGENT.md` or `CLAUDE.md`.

Because of those limits, the CLI is the most reliable always-on surface today.

## Repository layout

- `src/` core engine, artifact rendering, Zed integration, and usage aggregation
- `src/bin/context-pilot.rs` standalone CLI entry point
- `menubar/context-pilot-bar.swift` optional macOS menubar companion
- `examples/snapshot.rs` native development harness

## Development

```bash
cargo check
cargo run --example snapshot
```

## License

Apache-2.0
