//! ContextBar — Zed extension entry point + engine re-exports.
//!
//! The reusable engine now lives in the `context-bar-core` crate. This crate
//! is the thin host layer: it re-exports the engine modules under their
//! historical paths (so `context_bar::usage_signal`, `crate::context_engine`,
//! … keep resolving for the CLI binary, the example, and the wasm glue below)
//! and adds the Zed extension surface.
//!
//! ## Verified
//! - Extension loads in Zed Preview.
//! - `process:exec` can shell out to `git` inside the worktree.
//! - Engine writes `.context-bar/{state.json,brief-*.md,AGENT.md}` artifacts.
//! - `run_slash_command` receives a `Worktree` and is the strongest verified
//!   hook to wire automatic refresh into.
//!
//! ## Unverified / explicitly isolated behind seams
//! - Zed has no public always-on HUD primitive yet. The HUD layer is expected
//!   to consume `state.json` directly when a hook exists.
//! - `zed_extension_api` 0.7 exposes no load-time or worktree-open hook, so
//!   the first refresh fires on the first agent interaction that reaches the
//!   extension (any slash command). After that, [`auto_refresh::refresh`]
//!   keeps the surface fresh idempotently. Once a real load hook ships, the
//!   call site moves; the function does not.
//! - Codex ACP threads in Zed Preview do not currently invoke extension slash
//!   commands. Agents are therefore expected to read `.context-bar/AGENT.md`
//!   from the filesystem (Codex/Claude conventions) until a richer
//!   automatic-context hook is verified.
//! - The seam for both cases is [`context_engine::assemble`], which takes
//!   pre-collected signals and is decoupled from `zed::Worktree`.

// Engine, re-exported under the historical module paths so existing consumers
// (`context_bar::<mod>` in the bin/example, `crate::<mod>` in the wasm glue)
// need no import changes after the workspace split.
pub use context_bar_core::{
    agent_context, context_engine, detail_html, git_signal, hud, i18n, report, state_writer,
    time_windows, usage_signal,
};

// CLI-only engine module (see context-bar-core); excluded from the wasm extension.
#[cfg(not(target_arch = "wasm32"))]
pub use context_bar_core::claude_statusline;

#[cfg(target_arch = "wasm32")]
pub mod auto_refresh;

#[cfg(target_arch = "wasm32")]
mod slash_commands;

#[cfg(target_arch = "wasm32")]
mod extension {
    use super::{auto_refresh, slash_commands};
    use zed_extension_api::{self as zed, Result};

    struct ContextHud;

    impl zed::Extension for ContextHud {
        fn new() -> Self {
            Self
        }

        fn run_slash_command(
            &self,
            command: zed::SlashCommand,
            _args: Vec<String>,
            worktree: Option<&zed::Worktree>,
        ) -> Result<zed::SlashCommandOutput> {
            // Auto-refresh runs as a side effect of any worktree-bearing
            // entry point so the agent-visible artifacts stay current without
            // the user explicitly invoking a command. Idempotent and cheap.
            if let Some(worktree) = worktree {
                auto_refresh::refresh(worktree);
            }
            slash_commands::run(command, worktree)
        }
    }

    zed::register_extension!(ContextHud);
}
