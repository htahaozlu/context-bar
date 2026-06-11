//! Tiny HTTP server. Hand-rolled (no axum/hyper) because the surface is
//! three routes and we want a single statically-linked binary with no
//! async runtime. `tiny_http` does the boring parts (thread pool, header
//! parsing, keepalive); we just write the bodies.
//!
//! ## Endpoints
//!   GET  /v1/health    → { ok, version, machines }   (no auth — for liveness checks)
//!   POST /v1/ingest    → upsert rollup payload       (Bearer auth)
//!   GET  /v1/rollups   → { ok, rollups, machines }   (Bearer auth)
//!
//! All responses are JSON. Errors are `{ "ok": false, "error": "..." }`
//! with the appropriate status code (400/401/500). Logging goes to env_logger.

use crate::db::Db;
use crate::model::{HealthResponse, IngestRequest, IngestResponse, RollupsResponse};
use serde_json::json;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tiny_http::{Header, Method, Request, Response, Server};

pub struct State {
    pub db: Arc<Db>,
    pub token: Arc<String>,
}

impl Clone for State {
    fn clone(&self) -> Self {
        Self {
            db: self.db.clone(),
            token: self.token.clone(),
        }
    }
}

const VERSION: &str = env!("CARGO_PKG_VERSION");

pub fn serve(addr: &str, state: State) -> anyhow::Result<()> {
    let server = Server::http(addr)
        .map_err(|e| anyhow::anyhow!("failed to bind {}: {}", addr, e))?;
    log::info!("context-bar-server {} listening on http://{}", VERSION, addr);

    for request in server.incoming_requests() {
        let state = state.clone();
        std::thread::spawn(move || {
            if let Err(e) = handle(request, &state) {
                log::warn!("request error: {}", e);
                // No response was sent — the connection drops. The client
                // surfaces a connect-reset, which is the documented
                // behavior for `tiny_http` when the handler bails before
                // calling `respond`.
            }
        });
    }
    Ok(())
}

/// Public seam used by the test_support module — runs a request
/// synchronously on the current thread.
pub fn serve_request(request: Request, state: &State) -> anyhow::Result<()> {
    handle(request, state)
}

fn json_header() -> Header {
    Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()
}

fn unauthorized() -> Response<std::io::Cursor<Vec<u8>>> {
    let body = json!({ "ok": false, "error": "unauthorized" }).to_string();
    Response::from_string(body)
        .with_header(json_header())
        .with_header(Header::from_bytes(&b"WWW-Authenticate"[..], &b"Bearer"[..]).unwrap())
        .with_status_code(401)
}

fn not_found(path: &str) -> Response<std::io::Cursor<Vec<u8>>> {
    let body = json!({ "ok": false, "error": "not found", "path": path }).to_string();
    Response::from_string(body)
        .with_header(json_header())
        .with_status_code(404)
}

/// Top-level dispatch. `request` is consumed on the first `respond()` we
/// successfully call.
fn handle(request: Request, state: &State) -> anyhow::Result<()> {
    let url = request.url().to_string();
    let path = url.split('?').next().unwrap_or("/").trim_end_matches('/').to_string();
    let method = request.method().clone();

    // /v1/health is intentionally unauthenticated so a watchdog / reverse
    // proxy can poll it. Returns machine count as a soft "is the DB
    // actually being used" signal.
    if method == Method::Get && path == "/v1/health" {
        let machines = state.db.machine_count().unwrap_or(0);
        let body = serde_json::to_string(&HealthResponse {
            ok: true,
            version: VERSION,
            machines,
        })?;
        request.respond(
            Response::from_string(body)
                .with_header(json_header())
                .with_status_code(200),
        )?;
        return Ok(());
    }

    // Everything else is gated by the bearer token.
    if !check_auth(&request, &state.token) {
        request.respond(unauthorized())?;
        return Ok(());
    }

    match (method, path.as_str()) {
        (Method::Post, "/v1/ingest") => handle_ingest(request, state),
        (Method::Get, "/v1/rollups") => handle_rollups(request, state),
        _ => {
            request.respond(not_found(&path))?;
            Ok(())
        }
    }
}

fn check_auth(request: &Request, expected: &str) -> bool {
    for h in request.headers() {
        if h.field.equiv("Authorization") {
            if let Some(rest) = h.value.as_str().strip_prefix("Bearer ") {
                return rest.trim() == expected;
            }
        }
    }
    false
}

fn read_body(request: &mut Request) -> anyhow::Result<String> {
    let mut s = String::new();
    std::io::Read::read_to_string(request.as_reader(), &mut s)?;
    Ok(s)
}

fn handle_ingest(mut request: Request, state: &State) -> anyhow::Result<()> {
    let body = read_body(&mut request)?;
    let payload: IngestRequest = serde_json::from_str(&body)
        .map_err(|e| anyhow::anyhow!("invalid json: {}", e))?;
    if payload.schema < 1 || payload.schema > 2 {
        return Err(anyhow::anyhow!("unsupported schema {}", payload.schema));
    }
    if payload.machine.trim().is_empty() {
        return Err(anyhow::anyhow!("machine is required"));
    }
    let now_iso = payload
        .updated_at
        .clone()
        .unwrap_or_else(now_iso8601);
    // Reject absurdly large inputs — protects against a misbehaving
    // client filling the DB. The 30-day cap is single-digit billions
    // of tokens, not 2^63.
    for (agent, p) in &payload.agents {
        if p.tokens_30d > 1_000_000_000_000 {
            return Err(anyhow::anyhow!("tokens_30d for {} too large", agent));
        }
        if !p.cost_30d.is_finite() || p.cost_30d < 0.0 || p.cost_30d > 1_000_000_000.0 {
            return Err(anyhow::anyhow!("cost_30d for {} out of range", agent));
        }
    }
    let ingested = state.db.ingest(&payload.machine, &payload.agents, &now_iso)?;
    log::info!(
        "ingest: machine={} agents={} (schema={})",
        payload.machine,
        ingested,
        payload.schema
    );
    let body = serde_json::to_string(&IngestResponse { ok: true, ingested })?;
    request.respond(
        Response::from_string(body)
            .with_header(json_header())
            .with_status_code(200),
    )?;
    Ok(())
}

fn handle_rollups(request: Request, state: &State) -> anyhow::Result<()> {
    let rows = state.db.all_rollups()?;
    let mut machines: Vec<String> = rows.iter().map(|r| r.machine.clone()).collect();
    machines.sort();
    machines.dedup();
    let body = serde_json::to_string(&RollupsResponse {
        ok: true,
        rollups: rows,
        machines,
    })?;
    request.respond(
        Response::from_string(body)
            .with_header(json_header())
            .with_status_code(200),
    )?;
    Ok(())
}

fn now_iso8601() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (year, month, day, hour, min, sec) = epoch_to_ymdhms(secs);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hour, min, sec
    )
}

fn epoch_to_ymdhms(secs: u64) -> (i32, u32, u32, u32, u32, u32) {
    // Civil-from-days algorithm by Howard Hinnant (public domain).
    let days = (secs / 86_400) as i64;
    let s_of_day = (secs % 86_400) as u32;
    let hour = s_of_day / 3600;
    let min = (s_of_day % 3600) / 60;
    let sec = s_of_day % 60;
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i32 + (era as i32) * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d, hour, min, sec)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn epoch_to_ymdhms_unix_epoch() {
        assert_eq!(epoch_to_ymdhms(0), (1970, 1, 1, 0, 0, 0));
    }

    #[test]
    fn epoch_to_ymdhms_known_dates() {
        // 2025-06-11T00:00:00Z = 1749600000
        assert_eq!(epoch_to_ymdhms(1_749_600_000), (2025, 6, 11, 0, 0, 0));
        // 2000-02-29T12:34:56Z — 2000 is a leap year, Jan 1 = 946684800
        // 31*86400 (Jan) + 28*86400 (Feb 1..=28) = 2678400 + 2419200 = 5097600
        // 12:34:56 = 45296 s
        assert_eq!(epoch_to_ymdhms(951_827_696), (2000, 2, 29, 12, 34, 56));
    }
}
