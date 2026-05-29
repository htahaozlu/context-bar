//! context-bar-core — the cross-platform engine.
//!
//! Everything reusable across the surfaces lives here: transcript reading,
//! the cost/token model, session/window bucketing, the agent-context
//! assembler, and the HUD/HTML renderers. The crate is platform-free at the
//! type/parse/assemble layer; the host-coupled bits (process spawning, the
//! macOS keychain, the on-disk snapshot cache, and the wasm32 `Worktree`
//! collectors) sit behind `cfg(target_arch)` gates inside their modules.
//!
//! Consumers:
//! - the `context-bar` CLI/menubar engine (native) calls
//!   [`usage_signal::collect_native`], [`context_engine::assemble`],
//!   [`state_writer::write`], [`hud::render`], [`detail_html::render`];
//! - the Zed extension (wasm32) reuses the same types and calls the
//!   `Worktree`-backed collectors (`git_signal::collect`,
//!   `usage_signal::collect`, `context_engine::ContextEngine::generate`).
//!
//! The seam that keeps the engine decoupled from any host is
//! [`context_engine::assemble`], which takes pre-collected signals.

pub mod agent_context;
pub mod aggregate;
// CLI-only: reads Claude Code's statusline payload from stdin. Not built for
// the wasm Zed extension, which has no statusline hook.
#[cfg(not(target_arch = "wasm32"))]
pub mod claude_statusline;
// Native-only pure-Rust transcript collector (reads ~/.claude, ~/.codex).
#[cfg(not(target_arch = "wasm32"))]
pub mod collect;
pub mod context_engine;
pub mod detail_html;
pub mod git_signal;
pub mod hud;
pub mod i18n;
pub mod pricing;
pub mod report;
pub mod state_writer;
pub mod time_windows;
pub mod usage_signal;
