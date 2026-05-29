//! `context-bar live` — a `ratatui` auto-refresh dashboard for the active 5h
//! block (ROADMAP B2, the cross-platform crown jewel). Renders the same
//! `context_bar::live::block_status` burn metrics the `blocks` verb prints, but
//! live: a per-agent gauge (% of limit, color-tiered) + burn rate, projected
//! total, ETA-to-limit, and a reset countdown, refreshing on an interval.
//!
//! Robustness: requires a TTY (degrades to a message otherwise); restores the
//! terminal on panic via a hook so a crash never leaves the user's shell in
//! raw/alt-screen mode.

use std::io::{self, IsTerminal};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crossterm::event::{self, Event, KeyCode, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::{Backend, CrosstermBackend};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Gauge, Paragraph};
use ratatui::{Frame, Terminal};

use context_bar::i18n::Language;
use context_bar::live::{block_status, BlockStatus, Tier};
use context_bar::report::AgentFilter;
use context_bar::usage_signal::{collect_native, AgentUsage, UsageSnapshot};

use crate::cli_report::{fmt_int, fmt_usd};

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn fmt_dur(secs: i64) -> String {
    let s = secs.max(0);
    let (h, m) = (s / 3600, (s % 3600) / 60);
    if h > 0 {
        format!("{h}h {m}m")
    } else if m > 0 {
        format!("{m}m")
    } else {
        format!("{s}s")
    }
}

fn tier_color(pct: f64) -> Color {
    match Tier::from_pct(pct) {
        Tier::Ok => Color::Green,
        Tier::Warn => Color::Yellow,
        Tier::Critical => Color::Red,
    }
}

/// Entry point for `context-bar live`. Returns once the user quits.
pub fn run(interval: Duration, agent: AgentFilter, lang: Language) -> io::Result<()> {
    if !io::stdout().is_terminal() {
        eprintln!(
            "{}",
            lang.text(
                "context-bar live needs a terminal (TTY). Use `context-bar blocks` for one-shot output.",
                "context-bar live bir terminal (TTY) gerektirir. Tek seferlik çıktı için `context-bar blocks` kullanın.",
            )
        );
        return Ok(());
    }

    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen)?;
    // Restore the terminal on panic so a crash never wedges the user's shell.
    let prev_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen);
        prev_hook(info);
    }));

    let mut terminal = Terminal::new(CrosstermBackend::new(io::stdout()))?;
    let res = run_loop(&mut terminal, interval, agent, lang);

    disable_raw_mode()?;
    execute!(io::stdout(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    res
}

fn run_loop<B: Backend>(
    terminal: &mut Terminal<B>,
    interval: Duration,
    agent: AgentFilter,
    lang: Language,
) -> io::Result<()> {
    let mut snap = collect_native();
    let mut last = Instant::now();
    loop {
        terminal.draw(|f| render(f, &snap, now_secs(), agent, lang))?;

        // Poll for keys with a short timeout so the clock + countdown stay live.
        if event::poll(Duration::from_millis(250))? {
            if let Event::Key(k) = event::read()? {
                let quit = matches!(k.code, KeyCode::Char('q') | KeyCode::Esc)
                    || (k.code == KeyCode::Char('c') && k.modifiers.contains(KeyModifiers::CONTROL));
                if quit {
                    break;
                }
                if k.code == KeyCode::Char('r') {
                    // Force an immediate refresh.
                    last = Instant::now().checked_sub(interval).unwrap_or_else(Instant::now);
                }
            }
        }
        if last.elapsed() >= interval {
            snap = collect_native();
            last = Instant::now();
        }
    }
    Ok(())
}

/// Draw one frame. Public + backend-agnostic so it can be rendered to a
/// `TestBackend` in unit tests.
pub fn render(f: &mut Frame, snap: &UsageSnapshot, now: f64, agent: AgentFilter, lang: Language) {
    let agents: [(&str, &AgentUsage); 2] = [("Claude", &snap.claude), ("Codex", &snap.codex)];
    let active: Vec<(&str, BlockStatus)> = agents
        .iter()
        .filter(|(name, _)| match agent {
            AgentFilter::All => true,
            AgentFilter::Claude => *name == "Claude",
            AgentFilter::Codex => *name == "Codex",
        })
        .filter_map(|(name, a)| block_status(a, now).map(|b| (*name, b)))
        .collect();

    // title + one box per active agent + footer.
    let mut constraints = vec![Constraint::Length(1)];
    for _ in &active {
        constraints.push(Constraint::Length(9));
    }
    if active.is_empty() {
        constraints.push(Constraint::Length(1));
    }
    constraints.push(Constraint::Min(0));
    constraints.push(Constraint::Length(1));
    let rows = Layout::vertical(constraints).split(f.area());

    let title = Line::from(vec![Span::styled(
        format!("  context-bar — {}", lang.text("live 5h block", "canlı 5s blok")),
        Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
    )]);
    f.render_widget(Paragraph::new(title), rows[0]);

    if active.is_empty() {
        f.render_widget(
            Paragraph::new(Line::from(format!(
                "  {}",
                lang.text("No active 5h block.", "Aktif 5s blok yok.")
            ))),
            rows[1],
        );
    } else {
        for (i, (name, b)) in active.iter().enumerate() {
            render_agent(f, rows[i + 1], name, b, lang);
        }
    }

    let footer = Line::from(vec![Span::styled(
        format!(
            "  {}",
            lang.text(
                "q quit · r refresh · estimated cost, not a bill",
                "q çık · r yenile · tahmini maliyet, fatura değil",
            )
        ),
        Style::default().fg(Color::DarkGray),
    )]);
    f.render_widget(Paragraph::new(footer), rows[rows.len() - 1]);
}

fn render_agent(f: &mut Frame, area: Rect, name: &str, b: &BlockStatus, lang: Language) {
    let block = Block::default().borders(Borders::ALL).title(format!(" {name} "));
    let inner = block.inner(area);
    f.render_widget(block, area);

    let parts = Layout::vertical([Constraint::Length(1), Constraint::Min(0)]).split(inner);

    // Gauge: % of account limit, color-tiered. Falls back to a label-only row
    // when the account % isn't known (no usage API / statusline).
    if let Some(pct) = b.pct_of_limit {
        let g = Gauge::default()
            .gauge_style(Style::default().fg(tier_color(pct)))
            .ratio((pct / 100.0).clamp(0.0, 1.0))
            .label(format!("{pct:.0}% {}", lang.text("of limit", "limitin")));
        f.render_widget(g, parts[0]);
    } else {
        f.render_widget(
            Paragraph::new(Line::from(lang.text("limit % unknown", "limit % bilinmiyor"))),
            parts[0],
        );
    }

    let kv = |k: &str, v: String| -> Line {
        Line::from(vec![
            Span::styled(format!("{k:<13}"), Style::default().fg(Color::Gray)),
            Span::raw(v),
        ])
    };
    let mut lines = vec![
        kv(lang.text("Tokens", "Token"), fmt_int(b.tokens)),
        kv(lang.text("Cost", "Maliyet"), fmt_usd(b.cost)),
    ];
    if let (Some(ch), Some(tpm)) = (b.burn_cost_per_hr, b.burn_tokens_per_min) {
        lines.push(kv(
            lang.text("Burn", "Yakım"),
            format!(
                "{}/{} · {} {}",
                fmt_usd(ch),
                lang.text("hr", "sa"),
                fmt_int(tpm as u64),
                lang.text("tok/min", "tok/dk")
            ),
        ));
    }
    if let Some(p) = b.projected_cost {
        lines.push(kv(lang.text("Projected", "Öngörülen"), fmt_usd(p)));
    }
    if let Some(s) = b.secs_until_reset {
        lines.push(kv(lang.text("Resets in", "Sıfırlanma"), fmt_dur(s)));
    }
    if let Some(s) = b.eta_to_limit_secs {
        lines.push(kv(lang.text("ETA to limit", "Limite tahmini"), fmt_dur(s)));
    }
    f.render_widget(Paragraph::new(lines), parts[1]);
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;

    fn agent(tokens: u64, cost: f64, pct: Option<f64>, resets: Option<&str>) -> AgentUsage {
        AgentUsage {
            session_5h_tokens: tokens,
            cost_5h: cost,
            session_5h_percent: pct,
            session_5h_resets_at: resets.map(str::to_string),
            ..Default::default()
        }
    }

    #[test]
    fn renders_without_panic_and_shows_agent() {
        let mut snap = UsageSnapshot::default();
        snap.claude = agent(150_000, 12.0, Some(40.0), None);
        let mut terminal = Terminal::new(TestBackend::new(60, 20)).unwrap();
        terminal
            .draw(|f| render(f, &snap, 1000.0, AgentFilter::All, Language::En))
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let text: String = buf.content().iter().map(|c| c.symbol()).collect();
        assert!(text.contains("Claude"), "expected Claude in frame");
        assert!(text.contains("Tokens"), "expected Tokens label");
    }

    #[test]
    fn empty_snapshot_shows_no_block() {
        let snap = UsageSnapshot::default();
        let mut terminal = Terminal::new(TestBackend::new(60, 12)).unwrap();
        terminal
            .draw(|f| render(f, &snap, 1000.0, AgentFilter::All, Language::En))
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let text: String = buf.content().iter().map(|c| c.symbol()).collect();
        assert!(text.contains("No active"), "expected empty-state message");
    }
}
