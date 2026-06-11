//! SQLite layer. Single table; one row per (machine, agent). Replaced
//! atomically on every ingest via an UPSERT.
//!
//! Schema is intentionally simple — the menubar app already aggregates
//! per-agent token / cost / sub-agent numbers locally and only ships the
//! rollup. The server has no business knowing about projects, sessions,
//! or pricing tiers.

use crate::model::Rollup;
use anyhow::{Context, Result};
use rusqlite::{params, Connection};
use std::path::Path;
use std::sync::Mutex;

pub struct Db {
    inner: Mutex<Connection>,
}

impl Db {
    pub fn open(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)
            .with_context(|| format!("failed to open DB at {:?}", path))?;
        // WAL is essential here — `GET /v1/rollups` (a reader) and the next
        // `POST /v1/ingest` (a writer) can run concurrently without the
        // default rollback journal's `SQLITE_BUSY` errors that would
        // otherwise surface in the client as random sync failures.
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")?;
        Ok(Self { inner: Mutex::new(conn) })
    }

    pub fn migrate(&self) -> Result<()> {
        let conn = self.inner.lock().unwrap();
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS rollups (
                machine              TEXT    NOT NULL,
                agent                TEXT    NOT NULL,
                tokens_30d           INTEGER NOT NULL DEFAULT 0,
                cost_30d             REAL    NOT NULL DEFAULT 0,
                subagent_tokens_30d  INTEGER NOT NULL DEFAULT 0,
                last_seen            TEXT    NOT NULL,
                PRIMARY KEY (machine, agent)
            );
            CREATE INDEX IF NOT EXISTS rollups_machine ON rollups(machine);
            "#,
        )?;
        Ok(())
    }

    /// UPSERT the whole ingest payload in one transaction. The body has
    /// already been validated as schema >= 1, so we ignore schema
    /// differences here and just take the per-agent numbers.
    pub fn ingest(
        &self,
        machine: &str,
        agents: &std::collections::BTreeMap<String, crate::model::AgentPayload>,
        now_iso: &str,
    ) -> Result<usize> {
        let mut conn = self.inner.lock().unwrap();
        let tx = conn.transaction()?;
        let mut count = 0usize;
        {
            let mut stmt = tx.prepare(
                "INSERT INTO rollups (machine, agent, tokens_30d, cost_30d, subagent_tokens_30d, last_seen)
                 VALUES (?, ?, ?, ?, ?, ?)
                 ON CONFLICT(machine, agent) DO UPDATE SET
                   tokens_30d = MAX(tokens_30d, excluded.tokens_30d),
                   cost_30d = MAX(cost_30d, excluded.cost_30d),
                   subagent_tokens_30d = MAX(subagent_tokens_30d, excluded.subagent_tokens_30d),
                   last_seen = excluded.last_seen;",
            )?;
            for (agent, p) in agents {
                stmt.execute(params![
                    machine,
                    agent,
                    p.tokens_30d,
                    p.cost_30d,
                    p.subagent_tokens_30d,
                    now_iso,
                ])?;
                count += 1;
            }
        }
        tx.commit()?;
        Ok(count)
    }

    /// Returns every row, sorted by machine then agent. The menubar app
    /// re-buckets by machine to build the per-machine tile.
    pub fn all_rollups(&self) -> Result<Vec<Rollup>> {
        let conn = self.inner.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT machine, agent, tokens_30d, cost_30d, subagent_tokens_30d, last_seen
             FROM rollups ORDER BY machine, agent;",
        )?;
        let rows = stmt
            .query_map([], |row| {
                Ok(Rollup {
                    machine: row.get(0)?,
                    agent: row.get(1)?,
                    tokens_30d: row.get(2)?,
                    cost_30d: row.get(3)?,
                    subagent_tokens_30d: row.get(4)?,
                    last_seen: Some(row.get(5)?),
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// Number of distinct machines in the DB. Used by the health probe.
    pub fn machine_count(&self) -> Result<usize> {
        let conn = self.inner.lock().unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(DISTINCT machine) FROM rollups;", [], |r| r.get(0))?;
        Ok(n as usize)
    }
}
