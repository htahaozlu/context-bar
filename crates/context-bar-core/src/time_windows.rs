use std::time::Duration;

#[derive(Clone, Copy, Debug)]
pub struct TimeWindow {
    pub label: &'static str,
    pub duration: Duration,
}

impl TimeWindow {
    pub const fn new(label: &'static str, duration: Duration) -> Self {
        Self { label, duration }
    }
}

pub const NOW_WINDOW: TimeWindow = TimeWindow::new("now", Duration::from_secs(15 * 60));
pub const SESSION_WINDOW: TimeWindow =
    TimeWindow::new("session", Duration::from_secs(5 * 60 * 60));
pub const WEEK_WINDOW: TimeWindow =
    TimeWindow::new("week", Duration::from_secs(7 * 24 * 60 * 60));
