//! Standalone CLI for the ContextBar engine.
//!
//! Why this exists: Zed `extension_api` 0.7 has no install-time hook and no
//! status-bar primitive, and Zed Preview's ACP agent threads do not surface
//! extension slash commands at all. So the in-Zed extension is effectively
//! one-shot. This binary makes the same engine usable without Zed at all —
//! run once to refresh `.context-bar/{hud.md,AGENT.md,state.json,...}`, or
//! run `watch` to keep the HUD live as a sidecar daemon.
//!
//! Subcommands:
//!   `hud`          — refresh artifacts in the given (or current) repo and
//!                    print the HUD to stdout
//!   `snapshot`     — same as `hud` but without printing the HUD body
//!   `watch [secs]` — loop forever, refreshing every `secs` seconds (default 30)
//!
//! Example: `context-bar watch 30 .` (or set up launchd to keep this alive).

mod cli_report;
mod live_tui;

use std::env;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

use serde_json;

use cli_report::{RenderCtx, render_blocks, render_report};
use context_bar::claude_statusline;
use context_bar::context_engine::{self, ContextSnapshot};
use context_bar::git_signal::{self, ChangeSummary, CommitSummary, GitSignals};
use context_bar::hud;
use context_bar::i18n::Language;
use context_bar::report::{self, AgentFilter, Period, ReportOptions};
use context_bar::state_writer;
use context_bar::usage_signal;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("hud");

    let exit_code = match cmd {
        "hud" => run_hud(args.get(1).map(PathBuf::from)),
        "snapshot" => run_snapshot(args.get(1).map(PathBuf::from)),
        "global" => run_global(),
        "daily" => run_report(ReportSpec::Time(Period::Daily), &args),
        "weekly" => run_report(ReportSpec::Time(Period::Weekly), &args),
        "monthly" => run_report(ReportSpec::Time(Period::Monthly), &args),
        "session" | "sessions" => run_report(ReportSpec::Session, &args),
        "blocks" => run_blocks(&args),
        "live" => run_live(&args),
        "--version" | "-V" | "version" => {
            println!("context-bar {}", env!("CARGO_PKG_VERSION"));
            0
        }
        "claude-statusline" => run_claude_statusline(args.get(1).map(PathBuf::from)),
        "watch" => {
            let secs: u64 = args
                .get(1)
                .and_then(|value| value.parse().ok())
                .unwrap_or(30);
            let root = args.get(2).map(PathBuf::from);
            run_watch(root, secs)
        }
        "watch-global" => {
            let secs: u64 = args
                .get(1)
                .and_then(|value| value.parse().ok())
                .unwrap_or(30);
            run_watch_global(secs)
        }
        "--help" | "-h" | "help" => {
            print_help();
            0
        }
        other => {
            eprintln!("unknown command: {other}");
            print_help();
            2
        }
    };

    std::process::exit(exit_code);
}

fn print_help() {
    eprintln!(
        "context-bar — usage + API-equivalent cost for AI coding agents (Claude Code, Codex CLI)\n\n\
         REPORTS:\n\
         \x20   context-bar daily      [flags]   per-day usage + cost table (Claude + Codex)\n\
         \x20   context-bar weekly     [flags]   per-ISO-week table\n\
         \x20   context-bar monthly    [flags]   per-month table\n\
         \x20   context-bar session    [flags]   recent sessions table\n\
         \x20   context-bar blocks     [flags]   active 5h block: usage %, burn rate, ETA-to-limit, projected\n\
         \x20   context-bar live       [flags]   auto-refresh 5h-block TUI dashboard (--interval N, q to quit)\n\n\
         REPORT FLAGS:\n\
         \x20   --instances            split the daily table by project (per day x project)\n\
         \x20   --breakdown, -b        also print a per-model breakdown table\n\
         \x20   --agent <claude|codex|all>   restrict to one agent (default: all)\n\
         \x20   --since <YYYYMMDD>     inclusive start date\n\
         \x20   --until <YYYYMMDD>     inclusive end date\n\
         \x20   --json                 emit the report as JSON (for piping)\n\
         \x20   --offline              skip the live pricing fetch (use cached/bundled rates)\n\
         \x20   --lang <en|tr>         force UI language (default: locale)\n\
         \x20   --no-color             disable ANSI color\n\n\
         ENGINE / HUD:\n\
         \x20   context-bar hud          [worktree_root]   refresh repo .context-bar/hud.md\n\
         \x20   context-bar snapshot     [worktree_root]   refresh full repo artifacts\n\
         \x20   context-bar global                         write ~/.context-bar/ (context.json, hud.md, detail.html)\n\
         \x20   context-bar claude-statusline [path]       read Claude Code stdin and write a native snapshot\n\
         \x20   context-bar watch        [secs] [root]     loop per-repo (default 30s)\n\
         \x20   context-bar watch-global [secs]            loop ~/.context-bar/hud.md\n\
         \x20   context-bar --version                      print version\n\n\
         Costs are estimates of what the metered API would charge — not a bill.\n"
    );
}

enum ReportSpec {
    Time(Period),
    Session,
}

/// Parsed report-verb flags.
struct CliFlags {
    json: bool,
    breakdown: bool,
    instances: bool,
    since: Option<String>,
    until: Option<String>,
    agent: AgentFilter,
    offline: bool,
    no_color: bool,
    lang: Option<Language>,
    /// Refresh seconds for `live` (default 3).
    interval: Option<u64>,
}

impl CliFlags {
    fn parse(args: &[String]) -> Result<Self, String> {
        let mut f = CliFlags {
            json: false,
            breakdown: false,
            instances: false,
            since: None,
            until: None,
            agent: AgentFilter::All,
            offline: false,
            no_color: false,
            lang: None,
            interval: None,
        };
        // Resolve a flag's value from either `--flag=value` or `--flag value`.
        let value_of = |inline: Option<&str>, args: &[String], i: &mut usize| -> Result<String, String> {
            if let Some(v) = inline {
                return Ok(v.to_string());
            }
            *i += 1;
            args.get(*i)
                .cloned()
                .ok_or_else(|| "missing value for flag".to_string())
        };

        let mut i = 0;
        while i < args.len() {
            let arg = args[i].clone();
            let (name, inline) = match arg.split_once('=') {
                Some((n, v)) => (n, Some(v)),
                None => (arg.as_str(), None),
            };
            match name {
                "--json" => f.json = true,
                "--breakdown" | "-b" => f.breakdown = true,
                "--instances" | "-i" => f.instances = true,
                "--offline" => f.offline = true,
                "--no-color" => f.no_color = true,
                "--since" => {
                    let v = value_of(inline, args, &mut i)?;
                    f.since = Some(
                        report::normalize_date_arg(&v)
                            .ok_or_else(|| format!("invalid --since date: {v} (use YYYYMMDD)"))?,
                    );
                }
                "--until" => {
                    let v = value_of(inline, args, &mut i)?;
                    f.until = Some(
                        report::normalize_date_arg(&v)
                            .ok_or_else(|| format!("invalid --until date: {v} (use YYYYMMDD)"))?,
                    );
                }
                "--agent" => {
                    let v = value_of(inline, args, &mut i)?;
                    f.agent = match v.to_ascii_lowercase().as_str() {
                        "all" => AgentFilter::All,
                        "claude" => AgentFilter::Claude,
                        "codex" => AgentFilter::Codex,
                        other => return Err(format!("invalid --agent: {other} (claude|codex|all)")),
                    };
                }
                "--lang" => {
                    let v = value_of(inline, args, &mut i)?;
                    f.lang = match v.to_ascii_lowercase().as_str() {
                        "en" => Some(Language::En),
                        "tr" => Some(Language::Tr),
                        other => return Err(format!("invalid --lang: {other} (en|tr)")),
                    };
                }
                "--interval" => {
                    let v = value_of(inline, args, &mut i)?;
                    f.interval = Some(
                        v.parse::<u64>()
                            .map_err(|_| format!("invalid --interval: {v} (seconds)"))?,
                    );
                }
                other => return Err(format!("unknown flag: {other}")),
            }
            i += 1;
        }
        Ok(f)
    }
}

fn run_report(spec: ReportSpec, args: &[String]) -> i32 {
    let flags = match CliFlags::parse(&args[1..]) {
        Ok(f) => f,
        Err(error) => {
            eprintln!("context-bar: {error}");
            return 2;
        }
    };

    if flags.offline {
        // SAFETY: single-threaded here, set before we spawn python3 (which
        // reads CONTEXTBAR_PRICING_OFFLINE to skip the live LiteLLM fetch).
        unsafe {
            std::env::set_var("CONTEXTBAR_PRICING_OFFLINE", "1");
        }
    }

    let snapshot = usage_signal::collect_native();
    if !matches!(snapshot.source.as_str(), "python3" | "rust") {
        eprintln!("context-bar: usage unavailable: {}", snapshot.source);
    }

    let opts = ReportOptions {
        since: flags.since.clone(),
        until: flags.until.clone(),
        agent: flags.agent,
    };
    let report = match spec {
        ReportSpec::Time(period) => {
            if flags.instances {
                report::instances_report(&snapshot, &opts)
            } else {
                report::time_report(&snapshot, period, &opts)
            }
        }
        ReportSpec::Session => report::session_report(&snapshot, &opts),
    };

    if flags.json {
        match serde_json::to_string_pretty(&report) {
            Ok(text) => {
                println!("{text}");
                return 0;
            }
            Err(error) => {
                eprintln!("context-bar: json serialize failed: {error}");
                return 1;
            }
        }
    }

    let lang = flags.lang.unwrap_or_else(Language::detect);
    let color = !flags.no_color
        && std::env::var_os("NO_COLOR").is_none()
        && std::io::stdout().is_terminal();
    let ctx = RenderCtx { lang, color };

    print!("{}", render_report(&report, ctx));
    if flags.breakdown {
        let by_model = report::model_report(&snapshot, &opts);
        print!("\n{}", render_report(&by_model, ctx));
    }
    0
}

fn run_blocks(args: &[String]) -> i32 {
    let flags = match CliFlags::parse(&args[1..]) {
        Ok(f) => f,
        Err(error) => {
            eprintln!("context-bar: {error}");
            return 2;
        }
    };
    if flags.offline {
        // SAFETY: single-threaded here, before any python-free collection.
        unsafe {
            std::env::set_var("CONTEXTBAR_PRICING_OFFLINE", "1");
        }
    }
    let snapshot = usage_signal::collect_native();
    if !matches!(snapshot.source.as_str(), "python3" | "rust") {
        eprintln!("context-bar: usage unavailable: {}", snapshot.source);
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);

    if flags.json {
        let blocks = serde_json::json!({
            "claude": context_bar::live::block_status(&snapshot.claude, now),
            "codex": context_bar::live::block_status(&snapshot.codex, now),
        });
        match serde_json::to_string_pretty(&blocks) {
            Ok(text) => {
                println!("{text}");
                return 0;
            }
            Err(error) => {
                eprintln!("context-bar: json serialize failed: {error}");
                return 1;
            }
        }
    }

    let lang = flags.lang.unwrap_or_else(Language::detect);
    let color = !flags.no_color
        && std::env::var_os("NO_COLOR").is_none()
        && std::io::stdout().is_terminal();
    print!(
        "{}",
        render_blocks(&snapshot, now, RenderCtx { lang, color }, flags.agent)
    );
    0
}

fn run_live(args: &[String]) -> i32 {
    let flags = match CliFlags::parse(&args[1..]) {
        Ok(f) => f,
        Err(error) => {
            eprintln!("context-bar: {error}");
            return 2;
        }
    };
    if flags.offline {
        // SAFETY: single-threaded here, before the first collection.
        unsafe {
            std::env::set_var("CONTEXTBAR_PRICING_OFFLINE", "1");
        }
    }
    let interval = Duration::from_secs(flags.interval.unwrap_or(3).max(1));
    let lang = flags.lang.unwrap_or_else(Language::detect);
    match live_tui::run(interval, flags.agent, lang) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("context-bar live: {error}");
            1
        }
    }
}

fn run_hud(root: Option<PathBuf>) -> i32 {
    match refresh(root) {
        Ok((root, snapshot)) => {
            print!("{}", hud::render(&snapshot, &snapshot.usage));
            eprintln!("\nHUD written to {}/.context-bar/hud.md", root.display());
            0
        }
        Err(error) => {
            eprintln!("hud failed: {error}");
            1
        }
    }
}

fn run_snapshot(root: Option<PathBuf>) -> i32 {
    match refresh(root) {
        Ok((root, _)) => {
            println!("artifacts refreshed in {}/.context-bar/", root.display());
            0
        }
        Err(error) => {
            eprintln!("snapshot failed: {error}");
            1
        }
    }
}

fn run_global() -> i32 {
    match refresh_global() {
        Ok(path) => {
            let body = std::fs::read_to_string(&path).unwrap_or_default();
            print!("{body}");
            eprintln!("\nHUD written to {}", path.display());
            0
        }
        Err(error) => {
            eprintln!("global hud failed: {error}");
            1
        }
    }
}

fn run_claude_statusline(path: Option<PathBuf>) -> i32 {
    match claude_statusline::write_snapshot_from_stdin(path) {
        Ok(line) => {
            print!("{line}");
            0
        }
        Err(error) => {
            eprintln!("claude-statusline failed: {error}");
            1
        }
    }
}

fn run_watch_global(secs: u64) -> i32 {
    eprintln!("context-bar watch-global: every {secs}s. Ctrl-C to stop.");
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || r.store(false, Ordering::SeqCst)).ok();
    let mut backoff_secs: u64 = 1;
    while running.load(Ordering::SeqCst) {
        match refresh_global() {
            Ok(path) => {
                eprintln!("[{}] refreshed {}", now_local(), path.display());
                backoff_secs = 1;
                thread::sleep(Duration::from_secs(secs));
            }
            Err(error) => {
                eprintln!(
                    "[{}] refresh error: {error} (backoff {}s)",
                    now_local(),
                    backoff_secs
                );
                thread::sleep(Duration::from_secs(backoff_secs));
                backoff_secs = (backoff_secs.saturating_mul(2)).min(60);
            }
        }
    }
    eprintln!("context-bar: shutdown signal received, exiting");
    0
}

fn refresh_global() -> Result<PathBuf, String> {
    use time::{OffsetDateTime, format_description::well_known::Rfc3339};

    let home = env::var("HOME").map_err(|_| "HOME not set".to_string())?;
    let dir = PathBuf::from(&home).join(".context-bar");
    std::fs::create_dir_all(&dir)
        .map_err(|error| format!("mkdir {} failed: {error}", dir.display()))?;
    let path = dir.join("hud.md");

    let usage = usage_signal::collect_native();
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "unknown".to_string());

    let mut out = String::new();
    out.push_str("# Agent HUD (global)\n\n");
    out.push_str(&format!(
        "_Updated: `{now}` · Source: `{}`_\n\n",
        usage.source
    ));
    out.push_str("| Agent | Session (5h) | Week (7d) | Context | Model | Last turn |\n");
    out.push_str("|---|---:|---:|---:|---|---|\n");
    out.push_str(&format_usage_row("Claude", &usage.claude));
    out.push_str(&format_usage_row("Codex", &usage.codex));
    if !matches!(usage.source.as_str(), "python3" | "rust") {
        out.push_str(&format!("\n> Usage unavailable: {}\n", usage.source));
    }

    std::fs::write(&path, out.as_bytes())
        .map_err(|error| format!("write {} failed: {error}", path.display()))?;

    // JSON sidecar — consumed by the menubar app for structured rendering.
    // New canonical name is `context.json`; `hud.json` written too for one
    // release so menubar apps that haven't been rebuilt keep reading.
    let json_path = dir.join("context.json");
    let json = serde_json::to_string_pretty(&usage)
        .map_err(|error| format!("serialize context.json failed: {error}"))?;
    std::fs::write(&json_path, json.as_bytes())
        .map_err(|error| format!("write {} failed: {error}", json_path.display()))?;
    let legacy_path = dir.join("hud.json");
    let _ = std::fs::write(&legacy_path, json.as_bytes());

    // Optional HTML export for direct local viewing or sharing.
    let html = context_bar::detail_html::render(&usage);
    let html_path = dir.join("detail.html");
    std::fs::write(&html_path, html.as_bytes())
        .map_err(|error| format!("write {} failed: {error}", html_path.display()))?;

    Ok(path)
}

fn format_usage_row(label: &str, usage: &context_bar::usage_signal::AgentUsage) -> String {
    let ctx = match (usage.last_context_pct, usage.last_context_window) {
        (Some(pct), Some(window)) => format!("{pct:.1}% of {}", fmt_tokens(window)),
        (Some(pct), None) => format!("{pct:.1}%"),
        _ => "—".to_string(),
    };
    let model = usage.last_model.as_deref().unwrap_or("—");
    let last = usage.last_turn_at.as_deref().unwrap_or("—");
    format!(
        "| {label} | {} | {} | {ctx} | `{model}` | {last} |\n",
        fmt_tokens(usage.session_5h_tokens),
        fmt_tokens(usage.week_7d_tokens),
    )
}

fn fmt_tokens(value: u64) -> String {
    if value >= 1_000_000 {
        format!("{:.2}M", value as f64 / 1_000_000.0)
    } else if value >= 1_000 {
        format!("{:.1}k", value as f64 / 1_000.0)
    } else {
        value.to_string()
    }
}

fn run_watch(root: Option<PathBuf>, secs: u64) -> i32 {
    eprintln!("context-bar watch: every {secs}s. Ctrl-C to stop.");
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    ctrlc::set_handler(move || r.store(false, Ordering::SeqCst)).ok();
    let mut backoff_secs: u64 = 1;
    while running.load(Ordering::SeqCst) {
        match refresh(root.clone()) {
            Ok((root, _)) => {
                eprintln!(
                    "[{}] refreshed {}/.context-bar/hud.md",
                    now_local(),
                    root.display()
                );
                backoff_secs = 1;
                thread::sleep(Duration::from_secs(secs));
            }
            Err(error) => {
                eprintln!(
                    "[{}] refresh error: {error} (backoff {}s)",
                    now_local(),
                    backoff_secs
                );
                thread::sleep(Duration::from_secs(backoff_secs));
                backoff_secs = (backoff_secs.saturating_mul(2)).min(60);
            }
        }
    }
    eprintln!("context-bar: shutdown signal received, exiting");
    0
}

fn refresh(root: Option<PathBuf>) -> Result<(PathBuf, ContextSnapshot), String> {
    let root = root
        .unwrap_or_else(|| match env::current_dir() {
            Ok(p) => p,
            Err(e) => {
                eprintln!("cwd unreadable: {e}");
                std::process::exit(2);
            }
        })
        .canonicalize()
        .map_err(|error| format!("canonicalize failed: {error}"))?;

    let git = collect_git(&root)?;
    let files = context_engine::collect_files(&root)?;
    let mut snapshot = context_engine::assemble(root.clone(), git, files)?;
    snapshot.usage = usage_signal::collect_native();
    state_writer::write(&root, &snapshot)?;
    Ok((root, snapshot))
}

fn collect_git(root: &Path) -> Result<GitSignals, String> {
    let branch = run_git(root, &["rev-parse", "--abbrev-ref", "HEAD"])
        .unwrap_or_else(|_| "HEAD".to_string())
        .trim()
        .to_string();
    let log = run_git(
        root,
        &[
            "log",
            "--since=7 days ago",
            "--max-count=40",
            "--format=%H%x09%ct%x09%s",
        ],
    )
    .unwrap_or_default();
    let recent_commits: Vec<CommitSummary> = git_signal::parse_commits(&log);
    let status = run_git(root, &["status", "--short"]).unwrap_or_default();
    let (staged, unstaged): (Vec<ChangeSummary>, Vec<ChangeSummary>) =
        git_signal::parse_status_public(&status);
    let clean = staged.is_empty() && unstaged.is_empty();
    Ok(GitSignals {
        branch,
        recent_commits,
        staged_changes: staged,
        unstaged_changes: unstaged,
        clean_worktree: clean,
    })
}

fn run_git(root: &Path, args: &[&str]) -> Result<String, String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()
        .map_err(|error| format!("git spawn failed: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    String::from_utf8(output.stdout).map_err(|error| format!("git utf8: {error}"))
}

fn now_local() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{}", secs)
}
