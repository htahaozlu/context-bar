//! Tabular usage/cost reports built from a [`UsageSnapshot`].
//!
//! This is the data layer behind the terminal CLI's `daily` / `weekly` /
//! `monthly` / `session` / `--instances` / `--breakdown` verbs (and reusable
//! by any other surface). It does no rendering and pulls in no terminal
//! crates — it only reshapes the engine's already-priced buckets into rows.
//!
//! Cost-model note (see `docs/ai/COST_MODEL.md`): the **Total** column here is
//! ccusage's "Total Tokens" = `input + output + cache_creation + cache_read`,
//! which is DISTINCT from the Stats/HUD `tokens` total (`fresh_in + output`).
//! Per-row `cost` is the engine's per-turn estimate, summed; we never re-price.

use serde::Serialize;

use crate::usage_signal::{AgentUsage, DailyInstance, SessionRecord, TimeBucket, UsageSnapshot};

/// Which agents to include.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum AgentFilter {
    #[default]
    All,
    Claude,
    Codex,
}

impl AgentFilter {
    fn includes_claude(self) -> bool {
        matches!(self, AgentFilter::All | AgentFilter::Claude)
    }
    fn includes_codex(self) -> bool {
        matches!(self, AgentFilter::All | AgentFilter::Codex)
    }
}

/// Time grouping for [`time_report`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Period {
    Daily,
    Weekly,
    Monthly,
}

/// Filtering options shared by the report builders.
#[derive(Debug, Clone, Default)]
pub struct ReportOptions {
    /// Inclusive lower bound, normalized `YYYY-MM-DD` (or `None`).
    pub since: Option<String>,
    /// Inclusive upper bound, normalized `YYYY-MM-DD` (or `None`).
    pub until: Option<String>,
    pub agent: AgentFilter,
}

/// Role of a row in the rendered table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RowKind {
    /// A period's aggregate ("All" across agents), or a standalone row.
    Group,
    /// A per-agent breakdown nested under a Group row.
    Sub,
    /// The grand-total row.
    Total,
}

/// The four token buckets plus derived total and cost. Accumulates cleanly.
#[derive(Debug, Clone, Default, Serialize)]
pub struct Metrics {
    pub input: u64,
    pub output: u64,
    pub cache_creation: u64,
    pub cache_read: u64,
    pub cost: f64,
}

impl Metrics {
    fn add_bucket(&mut self, b: &TimeBucket) {
        self.input += b.input;
        self.output += b.output;
        self.cache_creation += b.cache_creation;
        self.cache_read += b.cache_read;
        self.cost += b.cost;
    }
    fn add(&mut self, other: &Metrics) {
        self.input += other.input;
        self.output += other.output;
        self.cache_creation += other.cache_creation;
        self.cache_read += other.cache_read;
        self.cost += other.cost;
    }
    /// ccusage "Total Tokens": all four buckets.
    pub fn total_tokens(&self) -> u64 {
        self.input + self.output + self.cache_creation + self.cache_read
    }
    fn is_empty(&self) -> bool {
        self.input == 0
            && self.output == 0
            && self.cache_creation == 0
            && self.cache_read == 0
            && self.cost == 0.0
    }
}

/// One rendered row. Columns are selected per [`ReportKind`] by the renderer.
#[derive(Debug, Clone, Serialize)]
pub struct ReportRow {
    /// Primary group label: date / `YYYY-Www` / `YYYY-MM` / session id.
    pub label: String,
    /// Secondary label: agent ("All"/"Claude"/"Codex"), project, or model.
    pub sublabel: String,
    /// Model ids relevant to this row (already de-synthetic'd), for the
    /// Models column. Empty when not applicable.
    pub models: Vec<String>,
    /// Free-form extra cell (e.g. session start time, duration). Empty if unused.
    pub extra: String,
    #[serde(flatten)]
    pub metrics: Metrics,
    pub kind: RowKind,
}

/// What flavor of report this is — drives column selection in the renderer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ReportKind {
    Daily,
    Weekly,
    Monthly,
    Instances,
    Session,
    Model,
}

/// A complete report: rows + grand total + pricing provenance.
#[derive(Debug, Clone, Serialize)]
pub struct Report {
    pub kind: ReportKind,
    pub rows: Vec<ReportRow>,
    pub total: Metrics,
    pub pricing_source: Option<String>,
    pub pricing_is_estimate: bool,
}

// ---- date helpers ---------------------------------------------------------

/// Normalize a user date arg (`YYYYMMDD` or `YYYY-MM-DD`) to `YYYY-MM-DD`.
pub fn normalize_date_arg(s: &str) -> Option<String> {
    let digits: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() == 8 {
        Some(format!("{}-{}-{}", &digits[0..4], &digits[4..6], &digits[6..8]))
    } else {
        None
    }
}

fn month_key(date: &str) -> String {
    date.get(0..7).unwrap_or(date).to_string()
}

/// ISO-week label `YYYY-Www`, matching the engine's `by_week` keys.
fn iso_week_key(date: &str) -> Option<String> {
    let mut it = date.split('-');
    let y: i32 = it.next()?.parse().ok()?;
    let m: u8 = it.next()?.parse().ok()?;
    let d: u8 = it.next()?.parse().ok()?;
    let month = time::Month::try_from(m).ok()?;
    let date = time::Date::from_calendar_date(y, month, d).ok()?;
    let (iso_year, week, _) = date.to_iso_week_date();
    Some(format!("{iso_year}-W{week:02}"))
}

/// Map a daily date to the key of the given period.
fn period_key(period: Period, date: &str) -> String {
    match period {
        Period::Daily => date.to_string(),
        Period::Weekly => iso_week_key(date).unwrap_or_else(|| date.to_string()),
        Period::Monthly => month_key(date),
    }
}

/// Does a daily date fall within the inclusive [since, until] window?
fn date_in_range(date: &str, opts: &ReportOptions) -> bool {
    if let Some(s) = &opts.since {
        if date < s.as_str() {
            return false;
        }
    }
    if let Some(u) = &opts.until {
        if date > u.as_str() {
            return false;
        }
    }
    true
}

/// Range check for an aggregated period label, by mapping the since/until
/// bounds into the same period space (so a week/month row survives if it
/// overlaps the window).
fn period_in_range(period: Period, label: &str, opts: &ReportOptions) -> bool {
    if let Some(s) = &opts.since {
        if label < period_key(period, s).as_str() {
            return false;
        }
    }
    if let Some(u) = &opts.until {
        if label > period_key(period, u).as_str() {
            return false;
        }
    }
    true
}

fn clean_models(models: &[String]) -> Vec<String> {
    models
        .iter()
        .filter(|m| !m.is_empty() && m.as_str() != "<synthetic>")
        .cloned()
        .collect()
}

fn merge_models(into: &mut Vec<String>, more: &[String]) {
    for m in more {
        if !into.contains(m) {
            into.push(m.clone());
        }
    }
}

/// date/period-key -> set of model ids, from an agent's `by_day_project`.
fn models_by_period(
    instances: &[DailyInstance],
    period: Period,
    opts: &ReportOptions,
) -> std::collections::BTreeMap<String, Vec<String>> {
    let mut map: std::collections::BTreeMap<String, Vec<String>> = Default::default();
    for inst in instances {
        if !date_in_range(&inst.date, opts) {
            continue;
        }
        let key = period_key(period, &inst.date);
        let entry = map.entry(key).or_default();
        merge_models(entry, &clean_models(&inst.models));
    }
    map
}

// ---- builders -------------------------------------------------------------

/// Which engine bucket list to read for an agent at a given period.
fn agent_buckets(a: &AgentUsage, period: Period) -> &[TimeBucket] {
    match period {
        Period::Daily => &a.by_day,
        Period::Weekly => &a.by_week,
        Period::Monthly => &a.by_month,
    }
}

/// Build a daily/weekly/monthly report: per-period "All" rows with per-agent
/// sub-rows, sorted chronologically, ending in a grand-total row.
pub fn time_report(snap: &UsageSnapshot, period: Period, opts: &ReportOptions) -> Report {
    let kind = match period {
        Period::Daily => ReportKind::Daily,
        Period::Weekly => ReportKind::Weekly,
        Period::Monthly => ReportKind::Monthly,
    };

    // period label -> (claude metrics, codex metrics)
    let mut periods: std::collections::BTreeMap<String, (Metrics, Metrics)> = Default::default();
    if opts.agent.includes_claude() {
        for b in agent_buckets(&snap.claude, period) {
            if !period_in_range(period, &b.date, opts) {
                continue;
            }
            periods.entry(b.date.clone()).or_default().0.add_bucket(b);
        }
    }
    if opts.agent.includes_codex() {
        for b in agent_buckets(&snap.codex, period) {
            if !period_in_range(period, &b.date, opts) {
                continue;
            }
            periods.entry(b.date.clone()).or_default().1.add_bucket(b);
        }
    }

    // Only collect models for the agents the filter includes, so an "All" row
    // under e.g. `--agent codex` never lists Claude-only models.
    let claude_models = if opts.agent.includes_claude() {
        models_by_period(&snap.claude.by_day_project, period, opts)
    } else {
        Default::default()
    };
    let codex_models = if opts.agent.includes_codex() {
        models_by_period(&snap.codex.by_day_project, period, opts)
    } else {
        Default::default()
    };

    let mut rows = Vec::new();
    let mut total = Metrics::default();

    for (label, (claude, codex)) in &periods {
        let mut all = Metrics::default();
        all.add(claude);
        all.add(codex);
        if all.is_empty() {
            continue;
        }

        let mut all_models = claude_models.get(label).cloned().unwrap_or_default();
        merge_models(&mut all_models, &codex_models.get(label).cloned().unwrap_or_default());

        rows.push(ReportRow {
            label: label.clone(),
            sublabel: "All".to_string(),
            models: all_models,
            extra: String::new(),
            metrics: all.clone(),
            kind: RowKind::Group,
        });
        if opts.agent.includes_claude() && !claude.is_empty() {
            rows.push(ReportRow {
                label: label.clone(),
                sublabel: "Claude".to_string(),
                models: claude_models.get(label).cloned().unwrap_or_default(),
                extra: String::new(),
                metrics: claude.clone(),
                kind: RowKind::Sub,
            });
        }
        if opts.agent.includes_codex() && !codex.is_empty() {
            rows.push(ReportRow {
                label: label.clone(),
                sublabel: "Codex".to_string(),
                models: codex_models.get(label).cloned().unwrap_or_default(),
                extra: String::new(),
                metrics: codex.clone(),
                kind: RowKind::Sub,
            });
        }
        total.add(&all);
    }

    Report {
        kind,
        rows,
        total,
        pricing_source: snap.pricing_source.clone(),
        pricing_is_estimate: snap.pricing_is_estimate,
    }
}

/// Per (date × project) report — the `better-ccusage daily --instances` view.
pub fn instances_report(snap: &UsageSnapshot, opts: &ReportOptions) -> Report {
    let mut rows = Vec::new();
    let mut total = Metrics::default();

    let mut push_agent = |agent_label: &str, insts: &[DailyInstance]| {
        for inst in insts {
            if !date_in_range(&inst.date, opts) {
                continue;
            }
            let m = Metrics {
                input: inst.input,
                output: inst.output,
                cache_creation: inst.cache_creation,
                cache_read: inst.cache_read,
                cost: inst.cost,
            };
            if m.is_empty() {
                continue;
            }
            total.add(&m);
            rows.push(ReportRow {
                label: inst.date.clone(),
                sublabel: format!("{} · {}", agent_label, inst.project),
                models: clean_models(&inst.models),
                extra: String::new(),
                metrics: m,
                kind: RowKind::Group,
            });
        }
    };
    if opts.agent.includes_claude() {
        push_agent("Claude", &snap.claude.by_day_project);
    }
    if opts.agent.includes_codex() {
        push_agent("Codex", &snap.codex.by_day_project);
    }

    rows.sort_by(|a, b| a.label.cmp(&b.label).then(a.sublabel.cmp(&b.sublabel)));

    Report {
        kind: ReportKind::Instances,
        rows,
        total,
        pricing_source: snap.pricing_source.clone(),
        pricing_is_estimate: snap.pricing_is_estimate,
    }
}

/// Recent-sessions report (both agents merged, newest first).
pub fn session_report(snap: &UsageSnapshot, opts: &ReportOptions) -> Report {
    let mut rows = Vec::new();
    let mut total = Metrics::default();

    let mut collect = |agent_label: &str, sessions: &[SessionRecord]| {
        for s in sessions {
            // recent_sessions carry full timestamps; filter by the date part.
            let day = s.ended_at.get(0..10).unwrap_or("");
            if !day.is_empty() && !date_in_range(day, opts) {
                continue;
            }
            let m = Metrics {
                input: s.input,
                output: s.output,
                cache_creation: s.cache_creation,
                cache_read: s.cache_read,
                cost: s.cost,
            };
            total.add(&m);
            rows.push(ReportRow {
                label: s.started_at.get(0..16).unwrap_or(&s.started_at).replace('T', " "),
                sublabel: format!("{} · {}", agent_label, s.project),
                models: clean_models(std::slice::from_ref(&s.model)),
                extra: format!("{:.0}m", s.duration_minutes),
                metrics: m,
                kind: RowKind::Group,
            });
        }
    };
    if opts.agent.includes_claude() {
        collect("Claude", &snap.claude.recent_sessions);
    }
    if opts.agent.includes_codex() {
        collect("Codex", &snap.codex.recent_sessions);
    }

    // Newest first.
    rows.sort_by(|a, b| b.label.cmp(&a.label));

    Report {
        kind: ReportKind::Session,
        rows,
        total,
        pricing_source: snap.pricing_source.clone(),
        pricing_is_estimate: snap.pricing_is_estimate,
    }
}

/// Per-model breakdown (global, both agents merged by model id).
pub fn model_report(snap: &UsageSnapshot, opts: &ReportOptions) -> Report {
    let mut by_model: std::collections::BTreeMap<String, Metrics> = Default::default();
    let mut add = |buckets: &[crate::usage_signal::NamedBucket]| {
        for b in buckets {
            let e = by_model.entry(b.model.clone()).or_default();
            e.input += b.input;
            e.output += b.output;
            e.cache_creation += b.cache_creation;
            e.cache_read += b.cache_read;
            e.cost += b.cost;
        }
    };
    if opts.agent.includes_claude() {
        add(&snap.claude.by_model);
    }
    if opts.agent.includes_codex() {
        add(&snap.codex.by_model);
    }

    let mut total = Metrics::default();
    let mut rows: Vec<ReportRow> = by_model
        .into_iter()
        .filter(|(_, m)| !m.is_empty())
        .map(|(model, m)| {
            total.add(&m);
            ReportRow {
                label: model.clone(),
                sublabel: String::new(),
                models: vec![model],
                extra: String::new(),
                metrics: m,
                kind: RowKind::Group,
            }
        })
        .collect();
    // Highest cost first.
    rows.sort_by(|a, b| {
        b.metrics
            .cost
            .partial_cmp(&a.metrics.cost)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    Report {
        kind: ReportKind::Model,
        rows,
        total,
        pricing_source: snap.pricing_source.clone(),
        pricing_is_estimate: snap.pricing_is_estimate,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bucket(date: &str, input: u64, output: u64, cc: u64, cr: u64, cost: f64) -> TimeBucket {
        TimeBucket {
            date: date.to_string(),
            tokens: input + output,
            sessions: 1,
            input,
            output,
            cache_creation: cc,
            cache_read: cr,
            cost,
        }
    }

    fn snap_with(claude_day: Vec<TimeBucket>, codex_day: Vec<TimeBucket>) -> UsageSnapshot {
        let mut s = UsageSnapshot::default();
        s.claude.by_day = claude_day;
        s.codex.by_day = codex_day;
        s.pricing_is_estimate = true;
        s
    }

    #[test]
    fn total_tokens_is_all_four_buckets() {
        let m = Metrics {
            input: 10,
            output: 20,
            cache_creation: 5,
            cache_read: 100,
            cost: 1.0,
        };
        assert_eq!(m.total_tokens(), 135);
    }

    #[test]
    fn daily_all_row_sums_agents_and_totals_match() {
        let snap = snap_with(
            vec![bucket("2026-05-13", 100, 200, 10, 1000, 2.5)],
            vec![bucket("2026-05-13", 50, 60, 0, 500, 1.0)],
        );
        let r = time_report(&snap, Period::Daily, &ReportOptions::default());
        // One period -> All + Claude + Codex.
        assert_eq!(r.rows.len(), 3);
        let all = &r.rows[0];
        assert_eq!(all.sublabel, "All");
        assert_eq!(all.metrics.input, 150);
        assert_eq!(all.metrics.output, 260);
        assert_eq!(all.metrics.cache_read, 1500);
        assert!((all.metrics.cost - 3.5).abs() < 1e-9);
        // Grand total equals the single period's All row.
        assert_eq!(r.total.total_tokens(), all.metrics.total_tokens());
        assert!((r.total.cost - 3.5).abs() < 1e-9);
    }

    #[test]
    fn agent_filter_drops_codex() {
        let snap = snap_with(
            vec![bucket("2026-05-13", 100, 200, 10, 1000, 2.5)],
            vec![bucket("2026-05-13", 50, 60, 0, 500, 1.0)],
        );
        let opts = ReportOptions {
            agent: AgentFilter::Claude,
            ..Default::default()
        };
        let r = time_report(&snap, Period::Daily, &opts);
        // All + Claude only.
        assert_eq!(r.rows.len(), 2);
        assert!((r.total.cost - 2.5).abs() < 1e-9);
    }

    #[test]
    fn since_until_filters_dates() {
        let snap = snap_with(
            vec![
                bucket("2026-05-12", 10, 10, 0, 0, 1.0),
                bucket("2026-05-13", 10, 10, 0, 0, 1.0),
                bucket("2026-05-14", 10, 10, 0, 0, 1.0),
            ],
            vec![],
        );
        let opts = ReportOptions {
            since: Some("2026-05-13".into()),
            until: Some("2026-05-13".into()),
            ..Default::default()
        };
        let r = time_report(&snap, Period::Daily, &opts);
        // Only the 13th survives -> All + Claude.
        assert_eq!(r.rows.len(), 2);
        assert!((r.total.cost - 1.0).abs() < 1e-9);
    }

    #[test]
    fn agent_filter_excludes_other_agents_models() {
        let mut snap = snap_with(
            vec![bucket("2026-05-13", 10, 10, 0, 0, 1.0)],
            vec![bucket("2026-05-13", 10, 10, 0, 0, 1.0)],
        );
        snap.claude.by_day_project = vec![DailyInstance {
            date: "2026-05-13".into(),
            models: vec!["claude-opus-4-8".into()],
            ..Default::default()
        }];
        snap.codex.by_day_project = vec![DailyInstance {
            date: "2026-05-13".into(),
            models: vec!["gpt-5.5".into()],
            ..Default::default()
        }];
        let opts = ReportOptions {
            agent: AgentFilter::Codex,
            ..Default::default()
        };
        let r = time_report(&snap, Period::Daily, &opts);
        let all = &r.rows[0];
        assert_eq!(all.sublabel, "All");
        assert_eq!(all.models, vec!["gpt-5.5".to_string()]);
    }

    #[test]
    fn normalize_date_arg_accepts_both_forms() {
        assert_eq!(normalize_date_arg("20260513").as_deref(), Some("2026-05-13"));
        assert_eq!(normalize_date_arg("2026-05-13").as_deref(), Some("2026-05-13"));
        assert_eq!(normalize_date_arg("nope"), None);
    }

    #[test]
    fn iso_week_key_matches_engine_format() {
        // 2026-05-29 falls in ISO week 22 (matches the engine's by_week labels).
        assert_eq!(iso_week_key("2026-05-29").as_deref(), Some("2026-W22"));
    }
}
