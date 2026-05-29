//! 5h-block burn status — the engine half of the live dashboard (ROADMAP B2)
//! and the native popover gauge (C1). Pure: derives burn rate, % of limit,
//! ETA-to-limit, and a projected block total from a snapshot + a clock.
//!
//! Our 5h window is ROLLING (the oldest turn ages out), not a fixed aligned
//! block, so "projected total" and "ETA" are honest estimates of the current
//! trajectory, not guarantees. `resets_at` is the oldest in-window turn + 5h
//! (when the window first frees), which we use to recover the window start.

use crate::aggregate::parse_iso;
use crate::usage_signal::AgentUsage;

/// Length of the rolling session window, seconds (5h).
pub const WIN_SESSION_SECS: f64 = 5.0 * 3600.0;

/// Burn snapshot for one agent's active 5h window.
#[derive(Clone, Debug, Default, PartialEq, serde::Serialize)]
pub struct BlockStatus {
    pub tokens: u64,
    pub cost: f64,
    pub cache_read: u64,
    /// Account utilization % of the 5h limit (from the usage API / statusline).
    pub pct_of_limit: Option<f64>,
    pub resets_at: Option<String>,
    /// Seconds until the window frees (clamped ≥ 0).
    pub secs_until_reset: Option<i64>,
    /// Hours elapsed since the window's oldest turn (0..=5).
    pub elapsed_hr: Option<f64>,
    /// Spend rate over the elapsed window, USD/hour.
    pub burn_cost_per_hr: Option<f64>,
    /// Token rate over the elapsed window, tokens/minute.
    pub burn_tokens_per_min: Option<f64>,
    /// Projected window cost if the current rate holds to window end.
    pub projected_cost: Option<f64>,
    /// Seconds until the account limit is hit at the current %/hour, if known.
    pub eta_to_limit_secs: Option<i64>,
}

/// Compute the active-block burn status for an agent, or `None` when the 5h
/// window is empty (no active block).
pub fn block_status(agent: &AgentUsage, now: f64) -> Option<BlockStatus> {
    if agent.session_5h_tokens == 0 && agent.cost_5h <= 0.0 {
        return None;
    }

    let mut s = BlockStatus {
        tokens: agent.session_5h_tokens,
        cost: agent.cost_5h,
        cache_read: agent.cache_read_tokens_5h,
        pct_of_limit: agent.session_5h_percent,
        resets_at: agent.session_5h_resets_at.clone(),
        ..Default::default()
    };

    // Recover the window start from resets_at (= oldest-in-window turn + 5h).
    if let Some(reset_ts) = agent.session_5h_resets_at.as_deref().and_then(|r| parse_iso(Some(r))) {
        let secs_until = (reset_ts - now).round() as i64;
        s.secs_until_reset = Some(secs_until.max(0));

        let window_start = reset_ts - WIN_SESSION_SECS;
        let elapsed = (now - window_start).clamp(0.0, WIN_SESSION_SECS);
        if elapsed > 0.0 {
            let elapsed_hr = elapsed / 3600.0;
            s.elapsed_hr = Some(elapsed_hr);
            s.burn_cost_per_hr = Some(agent.cost_5h / elapsed_hr);
            s.burn_tokens_per_min = Some(agent.session_5h_tokens as f64 / (elapsed / 60.0));

            // Projection: keep the current rate for the remainder of the window.
            let remaining_hr = (WIN_SESSION_SECS - elapsed) / 3600.0;
            s.projected_cost = Some(agent.cost_5h + s.burn_cost_per_hr.unwrap() * remaining_hr);

            // ETA to the account limit from the current utilization rate.
            if let Some(pct) = agent.session_5h_percent {
                if pct > 0.0 && pct < 100.0 {
                    let pct_per_hr = pct / elapsed_hr;
                    if pct_per_hr > 0.0 {
                        let hrs_to_100 = (100.0 - pct) / pct_per_hr;
                        s.eta_to_limit_secs = Some((hrs_to_100 * 3600.0).round() as i64);
                    }
                }
            }
        }
    }

    Some(s)
}

/// Quota tier for color-coding a gauge (green < 50% ≤ yellow < 80% ≤ red).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tier {
    Ok,
    Warn,
    Critical,
}

impl Tier {
    pub fn from_pct(pct: f64) -> Tier {
        if pct >= 80.0 {
            Tier::Critical
        } else if pct >= 50.0 {
            Tier::Warn
        } else {
            Tier::Ok
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn agent(tokens: u64, cost: f64, pct: Option<f64>, resets_at: Option<&str>) -> AgentUsage {
        AgentUsage {
            session_5h_tokens: tokens,
            cost_5h: cost,
            session_5h_percent: pct,
            session_5h_resets_at: resets_at.map(str::to_string),
            ..Default::default()
        }
    }

    #[test]
    fn empty_block_is_none() {
        assert!(block_status(&agent(0, 0.0, None, None), 1_000.0).is_none());
    }

    #[test]
    fn burn_and_projection_from_elapsed() {
        // Window resets at t=18000 (5h). now=9000 → started at 0, elapsed 2.5h.
        let now = 9000.0;
        let resets = crate::aggregate::iso_utc(18000.0);
        let a = agent(150_000, 10.0, Some(40.0), Some(&resets));
        let s = block_status(&a, now).unwrap();
        assert_eq!(s.secs_until_reset, Some(9000));
        let eh = s.elapsed_hr.unwrap();
        assert!((eh - 2.5).abs() < 1e-6, "elapsed {eh}");
        // burn = $10 / 2.5h = $4/hr.
        assert!((s.burn_cost_per_hr.unwrap() - 4.0).abs() < 1e-6);
        // projected = 10 + 4 * 2.5 (remaining) = 20.
        assert!((s.projected_cost.unwrap() - 20.0).abs() < 1e-6);
        // tokens/min = 150000 / 150min = 1000.
        assert!((s.burn_tokens_per_min.unwrap() - 1000.0).abs() < 1e-6);
        // pct 40 over 2.5h → 16%/hr → 60% left → 3.75h → 13500s.
        assert_eq!(s.eta_to_limit_secs, Some(13500));
    }

    #[test]
    fn no_reset_still_reports_totals() {
        let s = block_status(&agent(500, 1.0, None, None), 100.0).unwrap();
        assert_eq!(s.tokens, 500);
        assert!(s.burn_cost_per_hr.is_none());
        assert!(s.secs_until_reset.is_none());
    }

    #[test]
    fn tiers() {
        assert_eq!(Tier::from_pct(10.0), Tier::Ok);
        assert_eq!(Tier::from_pct(60.0), Tier::Warn);
        assert_eq!(Tier::from_pct(95.0), Tier::Critical);
    }
}
