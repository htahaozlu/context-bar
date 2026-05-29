//! Terminal rendering for the `daily` / `weekly` / `monthly` / `session` /
//! `--instances` / `--breakdown` report verbs. Reads the engine's
//! [`context_bar::report::Report`] and prints a ccusage-style table.
//!
//! Numbers are right-aligned with thousands separators; cost is `$X,XXX.XX`.
//! Color is applied only to a real terminal (and never when `NO_COLOR` is set
//! or `--no-color` is passed), so piped/`--json` output stays clean.

use comfy_table::{Attribute, Cell, CellAlignment, Color, ContentArrangement, Table, presets};

use context_bar::i18n::Language;
use context_bar::live::{block_status, Tier};
use context_bar::report::{AgentFilter, Report, ReportKind, ReportRow, RowKind};
use context_bar::usage_signal::{AgentUsage, UsageSnapshot};

/// Rendering knobs resolved once from the environment + flags.
#[derive(Clone, Copy)]
pub struct RenderCtx {
    pub lang: Language,
    pub color: bool,
}

/// Full textual output for a report: heading + table + disclaimer footer.
pub fn render_report(report: &Report, ctx: RenderCtx) -> String {
    let lang = ctx.lang;
    let mut out = String::new();

    out.push_str(&heading(report.kind, lang));
    out.push('\n');

    if report.rows.is_empty() {
        out.push_str(lang.text(
            "No usage found in this range.\n",
            "Bu aralıkta kullanım bulunamadı.\n",
        ));
        return out;
    }

    let table = match report.kind {
        ReportKind::Daily | ReportKind::Weekly | ReportKind::Monthly => time_table(report, ctx),
        ReportKind::Instances => instances_table(report, ctx),
        ReportKind::Session => session_table(report, ctx),
        ReportKind::Model => model_table(report, ctx),
    };
    out.push_str(&table.to_string());
    out.push('\n');
    out.push_str(&footer(report, lang));
    out
}

fn heading(kind: ReportKind, lang: Language) -> String {
    let what = match kind {
        ReportKind::Daily => lang.text("Daily", "Günlük"),
        ReportKind::Weekly => lang.text("Weekly", "Haftalık"),
        ReportKind::Monthly => lang.text("Monthly", "Aylık"),
        ReportKind::Instances => lang.text("Daily by project", "Projeye göre günlük"),
        ReportKind::Session => lang.text("Recent sessions", "Yakın oturumlar"),
        ReportKind::Model => lang.text("By model", "Modele göre"),
    };
    format!(
        "{} — {}",
        lang.text("Coding Agent Usage Report", "Kodlama Ajanı Kullanım Raporu"),
        what
    )
}

fn footer(report: &Report, lang: Language) -> String {
    let src = report.pricing_source.as_deref().unwrap_or("fallback");
    if report.pricing_is_estimate {
        format!(
            "{} · {}: {}\n",
            lang.text(
                "Estimated API-equivalent cost — not a bill",
                "Tahmini API-eşdeğeri maliyet — fatura değil",
            ),
            lang.text("pricing", "fiyatlandırma"),
            src,
        )
    } else {
        String::new()
    }
}

// ---- per-kind tables ------------------------------------------------------

fn time_table(report: &Report, ctx: RenderCtx) -> Table {
    let lang = ctx.lang;
    let period_col = match report.kind {
        ReportKind::Weekly => lang.text("Week", "Hafta"),
        ReportKind::Monthly => lang.text("Month", "Ay"),
        _ => lang.text("Date", "Tarih"),
    };
    let mut table = base_table(ctx);
    table.set_header(header_cells(
        ctx,
        &[
            period_col,
            lang.text("Agent", "Ajan"),
            lang.text("Models", "Modeller"),
            lang.text("Input", "Girdi"),
            lang.text("Output", "Çıktı"),
            lang.text("Cache Create", "Önbellek +"),
            lang.text("Cache Read", "Önbellek Oku"),
            lang.text("Total", "Toplam"),
            lang.text("Cost (USD)", "Maliyet (USD)"),
        ],
    ));

    for row in &report.rows {
        // Period label only on group/all rows; blank on per-agent sub-rows.
        let label = if row.kind == RowKind::Sub {
            String::new()
        } else {
            row.label.clone()
        };
        let agent = if row.kind == RowKind::Sub {
            format!("  - {}", row.sublabel)
        } else {
            row.sublabel.clone()
        };
        let mut cells = vec![
            Cell::new(label),
            agent_cell(&agent, row.kind, ctx),
            Cell::new(models_join(&row.models)),
        ];
        cells.extend(metric_cells(row, ctx));
        table.add_row(cells);
    }
    add_total_row(&mut table, report, ctx, 3, 9);
    right_align(&mut table, &[3, 4, 5, 6, 7, 8]);
    table
}

fn instances_table(report: &Report, ctx: RenderCtx) -> Table {
    let lang = ctx.lang;
    let mut table = base_table(ctx);
    table.set_header(header_cells(
        ctx,
        &[
            lang.text("Date", "Tarih"),
            lang.text("Project", "Proje"),
            lang.text("Models", "Modeller"),
            lang.text("Input", "Girdi"),
            lang.text("Output", "Çıktı"),
            lang.text("Cache Create", "Önbellek +"),
            lang.text("Cache Read", "Önbellek Oku"),
            lang.text("Total", "Toplam"),
            lang.text("Cost (USD)", "Maliyet (USD)"),
        ],
    ));
    for row in &report.rows {
        let mut cells = vec![
            Cell::new(&row.label),
            Cell::new(&row.sublabel),
            Cell::new(models_join(&row.models)),
        ];
        cells.extend(metric_cells(row, ctx));
        table.add_row(cells);
    }
    add_total_row(&mut table, report, ctx, 3, 9);
    right_align(&mut table, &[3, 4, 5, 6, 7, 8]);
    table
}

fn session_table(report: &Report, ctx: RenderCtx) -> Table {
    let lang = ctx.lang;
    let mut table = base_table(ctx);
    table.set_header(header_cells(
        ctx,
        &[
            lang.text("Started", "Başlangıç"),
            lang.text("Session", "Oturum"),
            lang.text("Model", "Model"),
            lang.text("Dur", "Süre"),
            lang.text("Input", "Girdi"),
            lang.text("Output", "Çıktı"),
            lang.text("Cache Create", "Önbellek +"),
            lang.text("Cache Read", "Önbellek Oku"),
            lang.text("Total", "Toplam"),
            lang.text("Cost (USD)", "Maliyet (USD)"),
        ],
    ));
    for row in &report.rows {
        let mut cells = vec![
            Cell::new(&row.label),
            Cell::new(&row.sublabel),
            Cell::new(models_join(&row.models)),
            Cell::new(&row.extra).set_alignment(CellAlignment::Right),
        ];
        cells.extend(metric_cells(row, ctx));
        table.add_row(cells);
    }
    add_total_row(&mut table, report, ctx, 4, 10);
    right_align(&mut table, &[3, 4, 5, 6, 7, 8, 9]);
    table
}

fn model_table(report: &Report, ctx: RenderCtx) -> Table {
    let lang = ctx.lang;
    let mut table = base_table(ctx);
    table.set_header(header_cells(
        ctx,
        &[
            lang.text("Model", "Model"),
            lang.text("Input", "Girdi"),
            lang.text("Output", "Çıktı"),
            lang.text("Cache Create", "Önbellek +"),
            lang.text("Cache Read", "Önbellek Oku"),
            lang.text("Total", "Toplam"),
            lang.text("Cost (USD)", "Maliyet (USD)"),
        ],
    ));
    for row in &report.rows {
        let mut cells = vec![Cell::new(short_model(&row.label))];
        cells.extend(metric_cells(row, ctx));
        table.add_row(cells);
    }
    add_total_row(&mut table, report, ctx, 1, 7);
    right_align(&mut table, &[1, 2, 3, 4, 5, 6]);
    table
}

// ---- cell helpers ---------------------------------------------------------

fn base_table(_ctx: RenderCtx) -> Table {
    let mut table = Table::new();
    table.load_preset(presets::UTF8_FULL);
    table.set_content_arrangement(ContentArrangement::Dynamic);
    table
}

fn header_cells(ctx: RenderCtx, labels: &[&str]) -> Vec<Cell> {
    labels
        .iter()
        .map(|l| {
            let mut c = Cell::new(l);
            if ctx.color {
                c = c.add_attribute(Attribute::Bold).fg(Color::Cyan);
            }
            c
        })
        .collect()
}

/// The four token buckets + total + cost, as right-aligned cells.
fn metric_cells(row: &ReportRow, ctx: RenderCtx) -> Vec<Cell> {
    let m = &row.metrics;
    let cost = cost_cell(m.cost, ctx);
    vec![
        Cell::new(fmt_int(m.input)),
        Cell::new(fmt_int(m.output)),
        Cell::new(fmt_int(m.cache_creation)),
        Cell::new(fmt_int(m.cache_read)),
        Cell::new(fmt_int(m.total_tokens())),
        cost,
    ]
}

fn agent_cell(agent: &str, kind: RowKind, ctx: RenderCtx) -> Cell {
    let mut c = Cell::new(agent);
    if ctx.color && kind == RowKind::Group {
        c = c.add_attribute(Attribute::Bold);
    }
    c
}

fn cost_cell(cost: f64, ctx: RenderCtx) -> Cell {
    let mut c = Cell::new(fmt_usd(cost)).set_alignment(CellAlignment::Right);
    if ctx.color {
        c = c.fg(Color::Green);
    }
    c
}

/// Append the grand-total row. `label_col` is the column index where "Total"
/// goes; `ncols` is the total column count.
fn add_total_row(table: &mut Table, report: &Report, ctx: RenderCtx, label_col: usize, ncols: usize) {
    let lang = ctx.lang;
    let m = &report.total;
    let mut cells: Vec<Cell> = Vec::with_capacity(ncols);
    for i in 0..label_col {
        if i == 0 {
            let mut c = Cell::new(lang.text("Total", "Toplam"));
            if ctx.color {
                c = c.add_attribute(Attribute::Bold);
            }
            cells.push(c);
        } else {
            cells.push(Cell::new(""));
        }
    }
    // The numeric tail (input, output, cache+, cache-read, total, cost).
    let nums = [
        fmt_int(m.input),
        fmt_int(m.output),
        fmt_int(m.cache_creation),
        fmt_int(m.cache_read),
        fmt_int(m.total_tokens()),
    ];
    for n in nums {
        let mut c = Cell::new(n).set_alignment(CellAlignment::Right);
        if ctx.color {
            c = c.add_attribute(Attribute::Bold);
        }
        cells.push(c);
    }
    let mut cost = Cell::new(fmt_usd(m.cost)).set_alignment(CellAlignment::Right);
    if ctx.color {
        cost = cost.add_attribute(Attribute::Bold).fg(Color::Green);
    }
    cells.push(cost);
    debug_assert_eq!(cells.len(), ncols);
    table.add_row(cells);
}

fn right_align(table: &mut Table, cols: &[usize]) {
    for &i in cols {
        if let Some(col) = table.column_mut(i) {
            col.set_cell_alignment(CellAlignment::Right);
        }
    }
}

// ---- formatting -----------------------------------------------------------

fn models_join(models: &[String]) -> String {
    if models.is_empty() {
        return "—".to_string();
    }
    let mut short: Vec<String> = models.iter().map(|m| short_model(m)).collect();
    short.dedup();
    short.join("\n")
}

/// Strip provider prefixes + the `claude-` family prefix for a compact label.
pub fn short_model(model: &str) -> String {
    if model == "<synthetic>" {
        return "(unknown)".to_string();
    }
    let mut m = model.trim();
    for p in [
        "anthropic/",
        "openai/",
        "google/",
        "us.anthropic.",
        "us.",
        "eu.anthropic.",
    ] {
        if let Some(rest) = m.strip_prefix(p) {
            m = rest;
        }
    }
    m.strip_prefix("claude-").unwrap_or(m).to_string()
}

/// Group an integer with comma thousands separators: 1463971070 -> 1,463,971,070.
pub fn fmt_int(n: u64) -> String {
    let s = n.to_string();
    let bytes = s.as_bytes();
    let len = bytes.len();
    let mut out = String::with_capacity(len + len / 3);
    for (i, ch) in bytes.iter().enumerate() {
        // Comma before any position where the count of remaining digits is a
        // positive multiple of 3. `len - i` is always >= 1 here, so no underflow.
        if i != 0 && (len - i) % 3 == 0 {
            out.push(',');
        }
        out.push(*ch as char);
    }
    out
}

/// `$1,234.56`. Negative values (rare, on write-heavy cache turns) keep the sign.
pub fn fmt_usd(c: f64) -> String {
    let neg = c < 0.0;
    let cents = (c.abs() * 100.0).round() as u64;
    let dollars = cents / 100;
    let rem = cents % 100;
    format!("{}${}.{:02}", if neg { "-" } else { "" }, fmt_int(dollars), rem)
}

// ---- blocks (live 5h window) ----------------------------------------------

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

fn tier_color(t: Tier) -> Color {
    match t {
        Tier::Ok => Color::Green,
        Tier::Warn => Color::Yellow,
        Tier::Critical => Color::Red,
    }
}

/// A 10-cell bar for a 0..100 percent.
fn pct_bar(pct: f64) -> String {
    let filled = ((pct / 10.0).round() as usize).min(10);
    format!("{}{}", "█".repeat(filled), "░".repeat(10 - filled))
}

/// Render the active 5h-block burn panel(s). One-shot (the `--live`
/// auto-refresh TUI builds on the same `block_status`).
pub fn render_blocks(snap: &UsageSnapshot, now: f64, ctx: RenderCtx, agent: AgentFilter) -> String {
    let lang = ctx.lang;
    let mut out = String::new();
    out.push_str(&format!(
        "{}\n\n",
        lang.text("Active 5h block", "Aktif 5s blok")
    ));

    let agents: &[(&str, &AgentUsage)] = &[("Claude", &snap.claude), ("Codex", &snap.codex)];
    let mut shown = 0;
    for (name, a) in agents {
        let include = match agent {
            AgentFilter::All => true,
            AgentFilter::Claude => *name == "Claude",
            AgentFilter::Codex => *name == "Codex",
        };
        if !include {
            continue;
        }
        let Some(b) = block_status(a, now) else { continue };
        shown += 1;

        let row = |k: &str, v: String| format!("  {:<14}{}\n", k, v);

        out.push_str(&format!("{name}\n"));
        if let Some(pct) = b.pct_of_limit {
            let line = format!("{}  {pct:.0}% {}", pct_bar(pct), lang.text("of limit", "limitin"));
            let line = if ctx.color {
                ansi(&line, tier_color(Tier::from_pct(pct)))
            } else {
                line
            };
            out.push_str(&row(lang.text("Usage", "Kullanım"), line));
        }
        out.push_str(&row(lang.text("Tokens", "Token"), fmt_int(b.tokens)));
        out.push_str(&row(lang.text("Cost", "Maliyet"), fmt_usd(b.cost)));
        if let (Some(ch), Some(tpm)) = (b.burn_cost_per_hr, b.burn_tokens_per_min) {
            out.push_str(&row(
                lang.text("Burn", "Yakım"),
                format!("{}/{} · {} {}", fmt_usd(ch), lang.text("hr", "sa"), fmt_int(tpm as u64), lang.text("tok/min", "tok/dk")),
            ));
        }
        if let Some(p) = b.projected_cost {
            out.push_str(&row(
                lang.text("Projected", "Öngörülen"),
                format!("{} {}", fmt_usd(p), lang.text("(if rate holds)", "(hız sürerse)")),
            ));
        }
        if let Some(s) = b.secs_until_reset {
            out.push_str(&row(lang.text("Resets in", "Sıfırlanma"), fmt_dur(s)));
        }
        if let Some(s) = b.eta_to_limit_secs {
            out.push_str(&row(lang.text("ETA to limit", "Limite tahmini"), fmt_dur(s)));
        }
        out.push('\n');
    }
    if shown == 0 {
        out.push_str(lang.text("No active 5h block.\n", "Aktif 5s blok yok.\n"));
    }
    out
}

/// Wrap text in an ANSI fg color (used for the gauge; gated by the caller).
fn ansi(text: &str, color: Color) -> String {
    let code = match color {
        Color::Green => "32",
        Color::Yellow => "33",
        Color::Red => "31",
        Color::Cyan => "36",
        _ => "0",
    };
    format!("\x1b[{code}m{text}\x1b[0m")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thousands_grouping() {
        assert_eq!(fmt_int(0), "0");
        assert_eq!(fmt_int(12), "12");
        assert_eq!(fmt_int(999), "999");
        assert_eq!(fmt_int(1000), "1,000");
        assert_eq!(fmt_int(1463971070), "1,463,971,070");
    }

    #[test]
    fn usd_formatting() {
        assert_eq!(fmt_usd(0.0), "$0.00");
        assert_eq!(fmt_usd(2823.09), "$2,823.09");
        assert_eq!(fmt_usd(-1.5), "-$1.50");
    }

    #[test]
    fn duration_formatting() {
        assert_eq!(fmt_dur(0), "0s");
        assert_eq!(fmt_dur(45), "45s");
        assert_eq!(fmt_dur(90), "1m");
        assert_eq!(fmt_dur(3661), "1h 1m");
        assert_eq!(fmt_dur(-5), "0s");
    }

    #[test]
    fn percent_bar_cells() {
        assert_eq!(pct_bar(0.0), "░░░░░░░░░░");
        assert_eq!(pct_bar(100.0), "██████████");
        assert_eq!(pct_bar(25.0).chars().filter(|&c| c == '█').count(), 3); // 2.5→3
    }

    #[test]
    fn model_shortening() {
        assert_eq!(short_model("claude-opus-4-8"), "opus-4-8");
        assert_eq!(short_model("anthropic/claude-sonnet-4-6"), "sonnet-4-6");
        assert_eq!(short_model("gpt-5.1-codex"), "gpt-5.1-codex");
    }
}
