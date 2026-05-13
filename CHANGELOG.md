# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, adapted for the current release workflow.

## [0.1.4] - 2026-05-13

### Added

- In-app update check via GitHub Releases API with download/release-notes/later actions.
- Live menubar title preview in Settings → Menubar.
- Drag-and-drop reordering for title fields with explicit ⠿ handle and per-field show checkbox.

### Improved

- Apple-style Preferences UI: borderless grouped sections, sentence-case titles, right-aligned info values.
- About hero redesigned: 360×120 horizontal logo, centered app name, version, and description.
- Usage panel header now shows agent name (Claude vs Codex), model, and project explicitly.
- Replaced misleading "1.2M of 258.4k" context subtitle with model window size only.
- Removed redundant ContextHUD header block at the top of the menubar dropdown.
- README restructured: install section moved to the top; Zed extension references removed.

## [0.1.3] - 2026-05-13

### Added

- Homebrew Cask (`Casks/context-hud.rb`) and release-workflow automation that bumps version + sha256 on every tag.

### Improved

- Menubar dropdown header no longer shows the version line; version remains in Settings → About.
- Reset timers render `6d 3h` (or `6g 3sa` in Turkish) instead of `149h` for spans ≥ 24h.

## [0.1.0] - 2026-05-12

Initial ContextHUD release.

### Added

- Local-first repository context generation under `.context-hud/`
- Stable agent-facing outputs including `AGENT.md`, `CLAUDE.md`, and rolling markdown briefs
- CLI commands for `hud`, `snapshot`, `watch`, `global`, and `watch-global`
- Native macOS menubar companion app built with AppKit
- Native usage window for Claude Code and Codex with compact stats and rolling usage views
- Markdown and JSON artifacts for both human and tool consumption
- DMG packaging scripts for the macOS app
- GitHub Actions release workflow for tagged builds

### Improved

- Product naming and repository presentation aligned under `ContextHUD`
- README upgraded to a more product-oriented structure
- GitHub repository metadata updated for release distribution

### Notes

- The macOS companion app is optional; the CLI is the most reliable always-on surface today.
- Repository summaries are local-first and do not require a hosted backend.

