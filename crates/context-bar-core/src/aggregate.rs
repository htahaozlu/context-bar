//! Deterministic transforms — slice 2 of folding `usage_signal.py` into Rust
//! (ROADMAP E1). Ported 1:1 from `empty_metrics`/`_add_metrics`,
//! `split_logical_sessions`, `_empty_bucket`/`_accumulate`, `bucket_aggregates`,
//! and `project_name_from_cwd`. Pure given (events, NOW, UTC offset) — pinned by
//! a golden fixture generated from the Python (`tests/aggregate_golden.rs`).
//!
//! Day/week/month bucketing uses a fixed UTC offset (seconds east of UTC). The
//! Python uses the system local tz via `astimezone()`; for fixed-offset zones
//! (e.g. Türkiye, permanent UTC+3) that is identical, and the golden pins it
//! with `TZ=UTC` / offset 0. DST-aware per-timestamp offsets are a later
//! refinement (would need a tz database); documented in COST_MODEL/ROADMAP.

use time::{Date, OffsetDateTime, UtcOffset};

use crate::usage_signal::{DailyInstance, NamedBucket, SessionRecord, TimeBucket};

/// Idle gap (seconds) that splits one transcript file into logical sessions —
/// matches Claude's 5h window, which resets 5h after the *first* turn.
pub const SESSION_IDLE_GAP: f64 = 5.0 * 3600.0;
/// 30-day rolling window in seconds.
pub const WIN_30D: f64 = 30.0 * 86400.0;

/// Per-turn token buckets + estimated cost. `total` is the stats token total
/// (fresh_in + output) the parser computes; the four buckets feed the cost view.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct TurnMetrics {
    pub total: u64,
    pub cache_read: u64,
    pub input: u64,
    pub output: u64,
    pub cache_creation: u64,
    pub cost: f64,
}

impl TurnMetrics {
    fn add(&mut self, m: &TurnMetrics) {
        self.total += m.total;
        self.cache_read += m.cache_read;
        self.input += m.input;
        self.output += m.output;
        self.cache_creation += m.cache_creation;
        self.cost += m.cost;
    }
}

/// One transcript file's per-turn events plus its resolved model/cwd.
#[derive(Clone, Debug, Default)]
pub struct FileEvents {
    pub model: Option<String>,
    pub cwd: Option<String>,
    /// (epoch seconds, metrics) — sorted by ts inside [`split_logical_sessions`].
    pub events: Vec<(f64, TurnMetrics)>,
}

/// A logical session chunk that feeds [`bucket_aggregates`].
#[derive(Clone, Debug)]
pub struct Session {
    pub tokens: u64,
    pub cache_read: u64,
    pub input: u64,
    pub output: u64,
    pub cache_creation: u64,
    pub cost: f64,
    pub last_ts: f64,
    pub first_ts: f64,
    pub model: Option<String>,
    pub cwd: Option<String>,
}

/// `project_name_from_cwd`: basename of the cwd, or `—` when absent.
pub fn project_name_from_cwd(cwd: Option<&str>) -> String {
    match cwd {
        None => "—".to_string(),
        Some(c) if c.is_empty() => "—".to_string(),
        Some(c) => {
            let trimmed = c.trim_end_matches('/');
            let base = trimmed.rsplit('/').next().unwrap_or("");
            if base.is_empty() {
                c.to_string()
            } else {
                base.to_string()
            }
        }
    }
}

/// `basename(path)` with the final extension removed (mirrors
/// `os.path.basename(path).rsplit(".", 1)[0]`).
fn session_base_id(path: &str) -> String {
    let base = path.trim_end_matches('/').rsplit('/').next().unwrap_or(path);
    match base.rsplit_once('.') {
        Some((stem, _ext)) if !stem.is_empty() => stem.to_string(),
        _ => base.to_string(),
    }
}

// Python's round() is banker's rounding (ties to even); mirror it so the
// rounded cost/duration values are byte-identical.
fn round6(x: f64) -> f64 {
    (x * 1e6).round_ties_even() / 1e6
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round_ties_even() / 10.0
}

/// Format an epoch-seconds value as a UTC ISO8601 string ending in `Z`.
/// Subsecond is emitted as 6 digits only when nonzero (mirrors Python's
/// `datetime.fromtimestamp(ts, tz=utc).isoformat().replace("+00:00","Z")`).
pub fn iso_utc(ts: f64) -> String {
    let whole = ts.floor() as i64;
    let micros = ((ts - ts.floor()) * 1_000_000.0).round() as i64;
    let (whole, micros) = if micros >= 1_000_000 {
        (whole + 1, 0)
    } else {
        (whole, micros)
    };
    let dt = OffsetDateTime::from_unix_timestamp(whole)
        .unwrap_or(OffsetDateTime::UNIX_EPOCH)
        .to_offset(UtcOffset::UTC);
    let base = format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
        dt.year(),
        u8::from(dt.month()),
        dt.day(),
        dt.hour(),
        dt.minute(),
        dt.second(),
    );
    if micros == 0 {
        format!("{base}Z")
    } else {
        format!("{base}.{micros:06}Z")
    }
}

/// Local civil date/labels for an epoch second at a fixed UTC offset.
fn local_dt(ts: f64, offset: UtcOffset) -> OffsetDateTime {
    OffsetDateTime::from_unix_timestamp(ts.floor() as i64)
        .unwrap_or(OffsetDateTime::UNIX_EPOCH)
        .to_offset(offset)
}

fn day_key(dt: OffsetDateTime) -> String {
    format!("{:04}-{:02}-{:02}", dt.year(), u8::from(dt.month()), dt.day())
}

fn week_key(dt: OffsetDateTime) -> String {
    let (iso_year, week, _) = dt.to_iso_week_date();
    format!("{iso_year}-W{week:02}")
}

fn month_key(dt: OffsetDateTime) -> String {
    format!("{:04}-{:02}", dt.year(), u8::from(dt.month()))
}

/// Insertion-ordered string-keyed accumulator, so a later stable sort
/// reproduces Python's dict-insertion-order tie-breaking exactly.
#[derive(Default)]
struct OrderedBuckets {
    order: Vec<String>,
    idx: std::collections::HashMap<String, usize>,
    buckets: Vec<Bucket>,
}

#[derive(Clone, Default)]
struct Bucket {
    tokens: u64,
    sessions: u64,
    cache_read: u64,
    input: u64,
    output: u64,
    cache_creation: u64,
    cost: f64,
}

impl Bucket {
    fn accumulate(&mut self, s: &Session) {
        self.tokens += s.tokens;
        self.sessions += 1;
        self.cache_read += s.cache_read;
        self.input += s.input;
        self.output += s.output;
        self.cache_creation += s.cache_creation;
        self.cost += s.cost;
    }
}

impl OrderedBuckets {
    fn entry(&mut self, key: &str) -> &mut Bucket {
        if let Some(&i) = self.idx.get(key) {
            return &mut self.buckets[i];
        }
        let i = self.buckets.len();
        self.idx.insert(key.to_string(), i);
        self.order.push(key.to_string());
        self.buckets.push(Bucket::default());
        &mut self.buckets[i]
    }
}

/// Result of [`bucket_aggregates`] — mirrors the snapshot's aggregate fields.
#[derive(Clone, Debug, Default)]
pub struct Buckets {
    pub total_tokens_30d: u64,
    pub total_sessions_30d: u64,
    pub total_cost_30d: f64,
    pub total_input_30d: u64,
    pub total_output_30d: u64,
    pub cost_today: f64,
    pub max_session_minutes: f64,
    pub by_day: Vec<TimeBucket>,
    pub by_week: Vec<TimeBucket>,
    pub by_month: Vec<TimeBucket>,
    pub by_model: Vec<NamedBucket>,
    pub by_project: Vec<NamedBucket>,
    pub by_day_project: Vec<DailyInstance>,
}

/// Split each file's events into logical sessions on the 5h idle gap, returning
/// `(sessions, recent)` — sessions feed [`bucket_aggregates`], recent feeds
/// `recent_sessions`. `files` is iterated in its existing order (use a
/// `BTreeMap` for determinism). Mirrors `split_logical_sessions`.
pub fn split_logical_sessions(
    files: &std::collections::BTreeMap<String, FileEvents>,
) -> (Vec<Session>, Vec<SessionRecord>) {
    let mut sessions = Vec::new();
    let mut recent = Vec::new();

    for (path, fe) in files {
        let mut events = fe.events.clone();
        events.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        if events.is_empty() {
            continue;
        }
        // Split into chunks: a new chunk starts when an event is more than
        // SESSION_IDLE_GAP after the current chunk's FIRST turn.
        let mut chunks: Vec<Vec<(f64, TurnMetrics)>> = Vec::new();
        let mut cur: Vec<(f64, TurnMetrics)> = vec![events[0]];
        let mut session_start = events[0].0;
        for &nxt in &events[1..] {
            if nxt.0 - session_start > SESSION_IDLE_GAP {
                chunks.push(std::mem::take(&mut cur));
                cur = vec![nxt];
                session_start = nxt.0;
            } else {
                cur.push(nxt);
            }
        }
        chunks.push(cur);

        let base_id = session_base_id(path);
        let multi = chunks.len() > 1;
        for (i, chunk) in chunks.iter().enumerate() {
            let first_ts = chunk[0].0;
            let last_ts = chunk[chunk.len() - 1].0;
            let mut agg = TurnMetrics::default();
            for (_, m) in chunk {
                agg.add(m);
            }
            sessions.push(Session {
                tokens: agg.total,
                cache_read: agg.cache_read,
                input: agg.input,
                output: agg.output,
                cache_creation: agg.cache_creation,
                cost: agg.cost,
                last_ts,
                first_ts,
                model: fe.model.clone(),
                cwd: fe.cwd.clone(),
            });
            recent.push(SessionRecord {
                id: if multi {
                    format!("{base_id}#{}", i + 1)
                } else {
                    base_id.clone()
                },
                started_at: iso_utc(first_ts),
                ended_at: iso_utc(last_ts),
                duration_minutes: round1((last_ts - first_ts) / 60.0),
                tokens: agg.total,
                cache_read: agg.cache_read,
                input: agg.input,
                output: agg.output,
                cache_creation: agg.cache_creation,
                cost: round6(agg.cost),
                model: fe.model.clone().unwrap_or_else(|| "—".to_string()),
                project: project_name_from_cwd(fe.cwd.as_deref()),
            });
        }
    }
    (sessions, recent)
}

#[allow(clippy::too_many_arguments)]
fn time_bucket(date: String, b: &Bucket) -> TimeBucket {
    TimeBucket {
        date,
        tokens: b.tokens,
        sessions: b.sessions,
        input: b.input,
        output: b.output,
        cache_creation: b.cache_creation,
        cache_read: b.cache_read,
        cost: round6(b.cost),
    }
}

fn named_bucket(model: String, b: &Bucket) -> NamedBucket {
    NamedBucket {
        model,
        tokens: b.tokens,
        sessions: b.sessions,
        input: b.input,
        output: b.output,
        cache_creation: b.cache_creation,
        cache_read: b.cache_read,
        cost: round6(b.cost),
    }
}

/// Stable top-N by tokens descending (ties keep insertion order).
fn take_by_tokens(buckets: &OrderedBuckets, n: usize) -> Vec<(String, Bucket)> {
    let mut items: Vec<(String, Bucket)> = buckets
        .order
        .iter()
        .enumerate()
        .map(|(i, k)| (k.clone(), buckets.buckets[i].clone()))
        .collect();
    items.sort_by(|a, b| b.1.tokens.cmp(&a.1.tokens));
    items.truncate(n);
    items
}

/// Stable top-N by key string descending (for by_week / by_month).
fn take_by_key(buckets: &OrderedBuckets, n: usize) -> Vec<(String, Bucket)> {
    let mut items: Vec<(String, Bucket)> = buckets
        .order
        .iter()
        .enumerate()
        .map(|(i, k)| (k.clone(), buckets.buckets[i].clone()))
        .collect();
    items.sort_by(|a, b| b.0.cmp(&a.0));
    items.truncate(n);
    items
}

/// Roll sessions into day/week/month/model/project buckets + the day×project
/// cross-tab + 30d totals. `now` is epoch seconds; `offset` is the fixed local
/// UTC offset. Mirrors `bucket_aggregates` (days=365, weeks=52, months=24,
/// instance_days=30, instance_rows=200).
pub fn bucket_aggregates(sessions: &[Session], now: f64, offset: UtcOffset) -> Buckets {
    let mut by_day = OrderedBuckets::default();
    let mut by_week = OrderedBuckets::default();
    let mut by_month = OrderedBuckets::default();
    let mut by_model = OrderedBuckets::default();
    let mut by_project = OrderedBuckets::default();
    // (day, project) -> (bucket, ordered models). Keep insertion order.
    let mut dp_order: Vec<(String, String)> = Vec::new();
    let mut dp_idx: std::collections::HashMap<(String, String), usize> = Default::default();
    let mut dp_buckets: Vec<Bucket> = Vec::new();
    let mut dp_models: Vec<Vec<String>> = Vec::new();

    let mut total30: u64 = 0;
    let mut sessions30: u64 = 0;
    let mut cost30: f64 = 0.0;
    let mut input30: u64 = 0;
    let mut output30: u64 = 0;
    let cutoff30 = now - WIN_30D;
    let today_key = day_key(local_dt(now, offset));

    for s in sessions {
        let ts = s.last_ts;
        let dt = local_dt(ts, offset);
        let day = day_key(dt);
        let week = week_key(dt);
        let month = month_key(dt);
        let proj = project_name_from_cwd(s.cwd.as_deref());

        by_day.entry(&day).accumulate(s);
        by_week.entry(&week).accumulate(s);
        by_month.entry(&month).accumulate(s);
        if let Some(model) = &s.model {
            if !model.is_empty() {
                by_model.entry(model).accumulate(s);
            }
        }
        by_project.entry(&proj).accumulate(s);

        // Per (day × project) cross-tab, scoped to the recent 30-day window.
        if now - ts <= 30.0 * 86400.0 {
            let key = (day.clone(), proj.clone());
            let i = match dp_idx.get(&key) {
                Some(&i) => i,
                None => {
                    let i = dp_buckets.len();
                    dp_idx.insert(key.clone(), i);
                    dp_order.push(key.clone());
                    dp_buckets.push(Bucket::default());
                    dp_models.push(Vec::new());
                    i
                }
            };
            dp_buckets[i].accumulate(s);
            if let Some(model) = &s.model {
                if !model.is_empty() && !dp_models[i].contains(model) {
                    dp_models[i].push(model.clone());
                }
            }
        }

        if ts >= cutoff30 {
            total30 += s.tokens;
            sessions30 += 1;
            cost30 += s.cost;
            input30 += s.input;
            output30 += s.output;
        }
    }

    // by_day: pad every calendar day in the 365-day window, newest first.
    let today_local = local_dt(now, offset);
    let today_date = today_local.date();
    let mut padded_day = Vec::with_capacity(365);
    for i in 0..365i64 {
        let d: Date = today_date.saturating_sub(time::Duration::days(i));
        let key = format!("{:04}-{:02}-{:02}", d.year(), u8::from(d.month()), d.day());
        match by_day.idx.get(&key) {
            Some(&j) => padded_day.push(time_bucket(key.clone(), &by_day.buckets[j])),
            None => padded_day.push(time_bucket(key.clone(), &Bucket::default())),
        }
    }

    let by_week_out = take_by_key(&by_week, 52)
        .into_iter()
        .map(|(k, b)| time_bucket(k, &b))
        .collect();
    let by_month_out = take_by_key(&by_month, 24)
        .into_iter()
        .map(|(k, b)| time_bucket(k, &b))
        .collect();
    let by_model_out = take_by_tokens(&by_model, 20)
        .into_iter()
        .map(|(k, b)| named_bucket(k, &b))
        .collect();
    let by_project_out = take_by_tokens(&by_project, 20)
        .into_iter()
        .map(|(k, b)| named_bucket(k, &b))
        .collect();

    // by_day_project: newest day first, within a day by cost desc; cap 200.
    let mut instances: Vec<DailyInstance> = dp_order
        .iter()
        .enumerate()
        .map(|(i, (day, proj))| {
            let b = &dp_buckets[i];
            let mut models = dp_models[i].clone();
            models.sort();
            DailyInstance {
                date: day.clone(),
                project: proj.clone(),
                models,
                tokens: b.tokens,
                sessions: b.sessions,
                input: b.input,
                output: b.output,
                cache_creation: b.cache_creation,
                cache_read: b.cache_read,
                cost: round6(b.cost),
            }
        })
        .collect();
    // Python: sort(key=(date, cost), reverse=True) — a single stable sort with a
    // composite key, descending on both.
    instances.sort_by(|a, b| {
        b.date
            .cmp(&a.date)
            .then(b.cost.partial_cmp(&a.cost).unwrap_or(std::cmp::Ordering::Equal))
    });
    instances.truncate(200);

    // Longest single session across all history (minutes).
    let mut max_session_minutes = 0.0f64;
    for s in sessions {
        let dur = (s.last_ts - s.first_ts) / 60.0;
        if dur > max_session_minutes {
            max_session_minutes = dur;
        }
    }

    let cost_today = by_day
        .idx
        .get(&today_key)
        .map(|&j| by_day.buckets[j].cost)
        .unwrap_or(0.0);

    Buckets {
        total_tokens_30d: total30,
        total_sessions_30d: sessions30,
        total_cost_30d: round6(cost30),
        total_input_30d: input30,
        total_output_30d: output30,
        cost_today: round6(cost_today),
        max_session_minutes: round1(max_session_minutes),
        by_day: padded_day,
        by_week: by_week_out,
        by_month: by_month_out,
        by_model: by_model_out,
        by_project: by_project_out,
        by_day_project: instances,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn project_name_basename_rules() {
        assert_eq!(project_name_from_cwd(None), "—");
        assert_eq!(project_name_from_cwd(Some("")), "—");
        assert_eq!(project_name_from_cwd(Some("/a/b/c")), "c");
        assert_eq!(project_name_from_cwd(Some("/a/b/c/")), "c");
        assert_eq!(project_name_from_cwd(Some("/")), "/");
    }

    #[test]
    fn session_id_strips_extension() {
        assert_eq!(session_base_id("/x/y/abc.jsonl"), "abc");
        assert_eq!(session_base_id("/x/y/a.b.jsonl"), "a.b");
        assert_eq!(session_base_id("noext"), "noext");
    }

    #[test]
    fn idle_gap_splits_from_first_turn() {
        let mut files = std::collections::BTreeMap::new();
        let m = TurnMetrics { total: 10, input: 5, output: 5, ..Default::default() };
        files.insert(
            "/p/s.jsonl".to_string(),
            FileEvents {
                model: Some("claude-opus-4-8".into()),
                cwd: Some("/home/proj".into()),
                // t=0, t=1h (same session, <5h from start), t=6h (new session).
                events: vec![(0.0, m), (3600.0, m), (6.0 * 3600.0, m)],
            },
        );
        let (sessions, recent) = split_logical_sessions(&files);
        assert_eq!(sessions.len(), 2);
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].id, "s#1");
        assert_eq!(sessions[0].tokens, 20); // first two turns
        assert_eq!(sessions[1].tokens, 10);
    }
}
