# context-bar-server

Self-hosted sync backend for the [ContextBar](https://github.com/htahaozlu/context-bar)
menubar app. Aggregates per-machine AI usage rollups into one SQLite
database so the menubar can show an **"Across your Macs"** view that
combines office + home + laptop usage.

## Why

ContextBar is local-first — no telemetry, no third-party cloud. The
menubar app is the only thing that reads your `~/.claude` and `~/.codex`
directories. But if you use ContextBar on more than one Mac, you
probably want one combined view of your monthly spend, your cache
savings, your active days. That's what this server gives you — a
single URL the menubar pings every minute to deposit its own rollup
and pull everyone else's.

You run the server on any always-on box on your LAN (Raspberry Pi, NAS,
homelab, old laptop). The menubar pushes its own 30-day aggregate (no
project names, no transcripts) and gets back the same data from every
other machine that's been talking to the server.

## Run

```sh
# Build
cargo build --release -p context-bar-server

# Run on the default 0.0.0.0:7878
./target/release/context-bar-server

# Or pin the bind/db/token paths
./target/release/context-bar-server \
  --bind 0.0.0.0:7878 \
  --db /var/lib/context-bar/db.sqlite \
  --token /etc/context-bar/token
```

The first launch writes a fresh token to `~/.context-bar-server/token`
and prints it to the logs. Copy that token into the menubar app's
**Settings → General → Across your Macs** field.

To rotate, delete the token file (a new one is generated on next start)
or pass `--token-set <new-token>`.

## Endpoints

```
GET  /v1/health    { ok, version, machines }     no auth
POST /v1/ingest    { schema, machine, agents }   Bearer
GET  /v1/rollups   { ok, rollups, machines }     Bearer
```

### POST /v1/ingest

```json
{
  "schema": 2,
  "machine": "Ozgur's MacBook Pro",
  "updated_at": "2025-06-11T10:00:00Z",
  "agents": {
    "Claude": { "tokens_30d": 1234567, "cost_30d": 12.34, "subagent_tokens_30d": 100000 },
    "Codex":  { "tokens_30d":  567890, "cost_30d":  4.56, "subagent_tokens_30d":  50000 }
  }
}
```

Returns `{ "ok": true, "ingested": 2 }` on success. Existing rows for
the same `(machine, agent)` are updated using `MAX` so a clock-skewed
machine that ships a stale rollup never erases a fresher one.

### GET /v1/rollups

Returns every row in the DB:

```json
{
  "ok": true,
  "rollups": [
    { "machine": "MacBook Pro", "agent": "Claude", "tokens_30d": 1234567, "cost_30d": 12.34, ... },
    { "machine": "iMac",        "agent": "Codex",  "tokens_30d":  567890, "cost_30d":  4.56, ... }
  ],
  "machines": ["MacBook Pro", "iMac"]
}
```

The menubar app uses `machines` to render the per-machine tile in the
"Across your Macs" section of the redesigned Settings page.

## Security model

* **No TLS.** Run on a trusted LAN or put it behind a reverse proxy
  (Caddy, nginx) with Let's Encrypt. The threat model is "someone on
  my Wi-Fi snooping", not a nation-state.
* **Single static token.** Generated on first launch; rotate manually.
  For multi-user setups, run one server per user.
* **Aggregates only.** The schema only carries totals — no project
  names, no transcripts, no per-day breakdowns. The menubar app
  filters those out before sending.

## Self-test

```sh
cargo run --release -p context-bar-server --example self_test
```

Boots an in-process server on an ephemeral port, posts a synthetic
ingest, fetches the rollups, and asserts the round-trip. Exits 0 on
success.

## License

Apache-2.0 — same as the parent repo.
