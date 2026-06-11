//! Request/response models. Kept tiny — every body is a flat JSON object
//! matching the shape the Swift menubar app already speaks (see
//! `menubar/sources/ServerSync.swift`).
//!
//! Schema 2 (current) — see `Rollup`. Schema 1 (legacy) is accepted on
//! ingest for one release; the `ServerSync.swift` payload in this repo
//! always speaks 2.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rollup {
    pub machine: String,
    pub agent: String,
    pub tokens_30d: u64,
    pub cost_30d: f64,
    pub subagent_tokens_30d: u64,
    pub last_seen: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestRequest {
    pub schema: u32,
    pub machine: String,
    #[serde(default)]
    pub updated_at: Option<String>,
    pub agents: std::collections::BTreeMap<String, AgentPayload>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentPayload {
    #[serde(default)]
    pub tokens_30d: u64,
    #[serde(default)]
    pub cost_30d: f64,
    #[serde(default)]
    pub subagent_tokens_30d: u64,
}

#[derive(Debug, Serialize)]
pub struct IngestResponse {
    pub ok: bool,
    pub ingested: usize,
}

#[derive(Debug, Serialize)]
pub struct RollupsResponse {
    pub ok: bool,
    pub rollups: Vec<Rollup>,
    pub machines: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub ok: bool,
    pub version: &'static str,
    pub machines: usize,
}
