import AppKit
import Foundation
import SQLite3

/// SQLite-backed local storage. Replaces the previous JSON-snapshot + flat
/// UserDefaults approach with a single, transactional store that lives at
/// `~/.context-bar/context-bar.sqlite`. Holds three domains:
///
///   1. **Settings** — every user preference (theme, language, separator,
///      display chips, ticks, incidents, budget, sync folder, AI provider,
///      AI keychain material, …). Stored as `(key TEXT, value TEXT)` so
///      adding a setting never requires a migration.
///
///   2. **Usage rollups** — local 30-day aggregates per machine. Each row
///      records per-agent token / cost / sub-agent totals plus a `last_seen`
///      timestamp. New rows overwrite older ones for the same `(machine,
///      agent)` so the table never grows past `M × A`.
///
///   3. **Sync state** — the last time we pushed to / pulled from the
///      self-hosted server (`server_url`, `last_pushed_at`,
///      `last_pulled_at`, `last_sync_status`). Used by the Status view in
///      the redesigned Settings → Across your Macs group.
///
/// All access is funneled through one serial queue so the Swift UI can call
/// from any thread without locks. The engine writes the JSON snapshot it
/// already produces (engine output, never modified by us) so a user with
/// a half-broken store can still inspect `context.json` directly — DB is
/// additive, not a hard dependency.

final class LocalStore {
    static let shared = LocalStore()
    static let snapshotPath = ContextSnapshot.resolveSnapshotPath

    private let queue = DispatchQueue(label: "com.htahaozlu.contextbar.localstore", qos: .userInitiated)
    private var db: OpaquePointer?
    private let dbURL: URL

    /// Lazy init: opens (and migrates) the DB on first use so launching the
    /// menubar app on a brand-new machine never blocks on disk I/O.
    init() {
        let home = NSHomeDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent(".context-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("context-bar.sqlite")
        queue.sync { openLocked(); migrateLocked() }
    }
    deinit { if let db { sqlite3_close(db) } }

    // MARK: - open / migrate

    private func openLocked() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            // Treat the open as a soft failure — every operation in this file
            // no-ops when `db` is nil so a corrupted store file cannot crash
            // the menubar app. The next launch will try again and re-create.
            db = nil
            return
        }
        // WAL = concurrent readers (UI thread) + one writer (engine tick)
        // without the global `SQLITE_BUSY` that the default rollback journal
        // would surface under burst writes.
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
    }

    private func migrateLocked() {
        guard db != nil else { return }
        let schema = """
        CREATE TABLE IF NOT EXISTS settings (
            key   TEXT PRIMARY KEY,
            value TEXT
        );
        CREATE TABLE IF NOT EXISTS usage_rollups (
            machine            TEXT NOT NULL,
            agent              TEXT NOT NULL,
            tokens_30d         INTEGER NOT NULL DEFAULT 0,
            cost_30d           REAL    NOT NULL DEFAULT 0,
            subagent_tokens_30d INTEGER NOT NULL DEFAULT 0,
            last_seen          TEXT,
            PRIMARY KEY (machine, agent)
        );
        CREATE TABLE IF NOT EXISTS sync_state (
            id                 INTEGER PRIMARY KEY CHECK (id = 1),
            server_url         TEXT,
            last_pushed_at     TEXT,
            last_pulled_at     TEXT,
            last_status        TEXT,
            last_message       TEXT
        );
        CREATE TABLE IF NOT EXISTS ai_runs (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            ran_at        TEXT NOT NULL,
            provider      TEXT,
            summary_json  TEXT,
            tips          TEXT
        );
        """
        if sqlite3_exec(db, schema, nil, nil, nil) != SQLITE_OK {
            // Migration failure is non-fatal; the store just stays empty.
            return
        }
        // Seed the single-row sync_state table the first time the DB is
        // created so callers can `UPDATE` without an `INSERT OR IGNORE`
        // dance in every read path.
        sqlite3_exec(db, "INSERT OR IGNORE INTO sync_state (id) VALUES (1);", nil, nil, nil)
        // One-shot: import any pre-existing settings from UserDefaults so
        // the redesign does not require every user to re-pick their theme
        // and separator on first launch after the upgrade.
        seedFromUserDefaultsLocked()
    }

    private func seedFromUserDefaultsLocked() {
        let migrationFlag = "LocalStore.seeded.v2"
        let d = UserDefaults.standard
        if d.bool(forKey: migrationFlag) { return }
        d.set(true, forKey: migrationFlag)
        let dfl = d.dictionaryRepresentation()
        let mapping: [(String, String)] = [
            ("theme", "theme"),
            ("separator", "separator"),
            ("displayItems", "displayItems"),
            ("language", "language"),
            ("displayPrefs.resetStyle", "resetStyle"),
            ("displayPrefs.tickMarks", "tickMarks"),
            ("displayPrefs.criticalBg", "criticalBg"),
            ("displayPrefs.incidents", "incidents"),
            ("displayPrefs.confetti", "confetti"),
            ("displayPrefs.redactPaths", "redactPaths"),
            ("displayPrefs.maskShareProjects", "maskShareProjects"),
            ("displayPrefs.monthlyBudgetUSD", "monthlyBudgetUSD"),
            ("displayPrefs.syncFolder", "syncFolder"),
            ("displayPrefs.aiProvider", "aiProvider"),
        ]
        for (k, v) in mapping {
            if let any = dfl[k] {
                putLocked(key: v, value: any)
            }
        }
    }

    // MARK: - settings

    enum Setting: String {
        case theme, separator, displayItems, language
        case resetStyle, tickMarks, criticalBg, incidents, confetti
        case redactPaths, maskShareProjects
        case monthlyBudgetUSD, syncFolder, aiProvider
    }

    /// Read a setting. Coerces to the requested type. Falls back to `UserDefaults`
    /// (then `nil`) when the row is missing — lets the migration co-exist with
    /// the old code path during the rollout.
    func get<T>(_ key: Setting, as type: T.Type) -> T? {
        var result: T? = nil
        queue.sync {
            if let v = readLocked(key: key.rawValue) { result = coerce(v, to: type) }
        }
        return result
    }

    func put(_ key: Setting, value: Any) {
        queue.sync { putLocked(key: key.rawValue, value: value) }
    }

    private func readLocked(key: String) -> Any? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM settings WHERE key=?;", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let raw = sqlite3_column_text(stmt, 0)
        let s = raw.map { String(cString: $0) } ?? ""
        return unstringify(s)
    }

    private func putLocked(key: String, value: Any) {
        guard let db else { return }
        let s = stringify(value)
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT INTO settings (key, value) VALUES (?, ?) "
                + "ON CONFLICT(key) DO UPDATE SET value=excluded.value;", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, s, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    /// Stringify values for the TEXT column. Doubles and ints keep their
    /// `Double(_:)` / `Int(_:)` round-trip so reading is symmetric. Arrays
    /// and dicts are JSON-encoded.
    private func stringify(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let b as Bool: return b ? "1" : "0"
        case let i as Int: return "I:\(i)"
        case let d as Double: return "D:\(d)"
        case let arr as [Any]:
            if let d = try? JSONSerialization.data(withJSONObject: arr, options: [.fragmentsAllowed]) {
                return "J:" + (String(data: d, encoding: .utf8) ?? "[]")
            }
            return "[]"
        default:
            return "\(v)"
        }
    }

    private func unstringify(_ s: String) -> Any {
        if s.hasPrefix("I:") { return Int(s.dropFirst(2)) ?? 0 }
        if s.hasPrefix("D:") { return Double(s.dropFirst(2)) ?? 0 }
        if s == "1" { return true }
        if s == "0" { return false }
        if s.hasPrefix("J:") {
            let j = String(s.dropFirst(2))
            if let d = j.data(using: .utf8),
               let any = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) {
                return any
            }
        }
        return s
    }

    private func coerce<T>(_ any: Any, to type: T.Type) -> T? {
        switch type {
        case is String.Type: return any as? T
        case is Bool.Type:   return (any as? Bool) as? T
        case is Int.Type:    return (any as? Int) as? T
        case is Double.Type:
            if let d = any as? Double { return d as? T }
            if let i = any as? Int { return Double(i) as? T }
            if let s = any as? String, let d = Double(s) { return d as? T }
            return nil
        default: return any as? T
        }
    }

    // MARK: - usage rollups

    struct Rollup {
        let machine: String
        let agent: String
        let tokens30d: UInt64
        let cost30d: Double
        let subagent30d: UInt64
        let lastSeen: Date?
    }

    func upsertRollup(machine: String, agent: String,
                      tokens30d: UInt64, cost30d: Double, subagent30d: UInt64) {
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO usage_rollups (machine, agent, tokens_30d, cost_30d, subagent_tokens_30d, last_seen)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(machine, agent) DO UPDATE SET
                tokens_30d=excluded.tokens_30d,
                cost_30d=excluded.cost_30d,
                subagent_tokens_30d=excluded.subagent_tokens_30d,
                last_seen=excluded.last_seen;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, machine, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, agent, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, Int64(tokens30d))
            sqlite3_bind_double(stmt, 4, cost30d)
            sqlite3_bind_int64(stmt, 5, Int64(subagent30d))
            let now = LocalStore.iso8601(Date())
            sqlite3_bind_text(stmt, 6, now, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
    }

    func allRollups() -> [Rollup] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db,
                    "SELECT machine, agent, tokens_30d, cost_30d, subagent_tokens_30d, last_seen "
                    + "FROM usage_rollups ORDER BY machine, agent;", -1, &stmt, nil) == SQLITE_OK else { return [] }
            var out: [Rollup] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let m = String(cString: sqlite3_column_text(stmt, 0))
                let a = String(cString: sqlite3_column_text(stmt, 1))
                let t = UInt64(sqlite3_column_int64(stmt, 2))
                let c = sqlite3_column_double(stmt, 3)
                let s = UInt64(sqlite3_column_int64(stmt, 4))
                let seen = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
                out.append(Rollup(machine: m, agent: a, tokens30d: t, cost30d: c,
                                  subagent30d: s, lastSeen: LocalStore.parseISO(seen)))
            }
            return out
        }
    }

    /// Read the rollups for THIS machine from `context.json` and upsert
    /// them. Called by the engine tick so the DB has its own copy —
    /// ServerSync then mirrors them upstream.
    func ingestLocalSnapshot() {
        let path = LocalStore.snapshotPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let machine = MachineSync.machineName
        for (key, name) in [("claude", "Claude"), ("codex", "Codex")] {
            guard let a = root[key] as? [String: Any] else { continue }
            let t = (a["total_tokens_30d"] as? UInt64)
                ?? (a["total_tokens_30d"] as? Int).map(UInt64.init)
                ?? UInt64((a["total_tokens_30d"] as? Double) ?? 0)
            let c = (a["total_cost_30d"] as? Double) ?? 0
            let s = (a["subagent_tokens_30d"] as? UInt64)
                ?? (a["subagent_tokens_30d"] as? Int).map(UInt64.init)
                ?? UInt64((a["subagent_tokens_30d"] as? Double) ?? 0)
            upsertRollup(machine: machine, agent: name,
                         tokens30d: t, cost30d: c, subagent30d: s)
        }
    }

    // MARK: - sync state

    struct SyncStatus {
        let serverURL: String?
        let lastPushedAt: Date?
        let lastPulledAt: Date?
        let lastStatus: String?
        let lastMessage: String?
    }

    func getSyncStatus() -> SyncStatus {
        queue.sync {
            guard let db else {
                return SyncStatus(serverURL: nil, lastPushedAt: nil, lastPulledAt: nil,
                                  lastStatus: nil, lastMessage: nil)
            }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT server_url, last_pushed_at, last_pulled_at, last_status, last_message FROM sync_state WHERE id=1;",
                                     -1, &stmt, nil) == SQLITE_OK else {
                return SyncStatus(serverURL: nil, lastPushedAt: nil, lastPulledAt: nil,
                                  lastStatus: nil, lastMessage: nil)
            }
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return SyncStatus(serverURL: nil, lastPushedAt: nil, lastPulledAt: nil,
                                  lastStatus: nil, lastMessage: nil)
            }
            func s(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            return SyncStatus(
                serverURL: s(0),
                lastPushedAt: LocalStore.parseISO(s(1)),
                lastPulledAt: LocalStore.parseISO(s(2)),
                lastStatus: s(3),
                lastMessage: s(4)
            )
        }
    }

    func updateSyncStatus(serverURL: String? = nil,
                          pushedAt: Date? = nil,
                          pulledAt: Date? = nil,
                          status: String? = nil,
                          message: String? = nil) {
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            UPDATE sync_state SET
                server_url=COALESCE(?, server_url),
                last_pushed_at=COALESCE(?, last_pushed_at),
                last_pulled_at=COALESCE(?, last_pulled_at),
                last_status=COALESCE(?, last_status),
                last_message=COALESCE(?, last_message)
            WHERE id=1;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            func bind(_ i: Int32, _ v: String?) {
                if let v { sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT) }
                else { sqlite3_bind_null(stmt, i) }
            }
            bind(1, serverURL)
            bind(2, pushedAt.map { LocalStore.iso8601($0) })
            bind(3, pulledAt.map { LocalStore.iso8601($0) })
            bind(4, status)
            bind(5, message)
            _ = sqlite3_step(stmt)
        }
    }

    // MARK: - AI runs

    func saveAIRun(provider: String?, summary: String, tips: String) {
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "INSERT INTO ai_runs (ran_at, provider, summary_json, tips) VALUES (?, ?, ?, ?);"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, LocalStore.iso8601(Date()), -1, SQLITE_TRANSIENT)
            if let p = provider { sqlite3_bind_text(stmt, 2, p, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 2) }
            sqlite3_bind_text(stmt, 3, summary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, tips, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
    }

    func lastAIRun() -> (ranAt: Date, provider: String?, tips: String)? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT ran_at, provider, tips FROM ai_runs ORDER BY id DESC LIMIT 1;",
                                     -1, &stmt, nil) == SQLITE_OK else { return nil }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let ran = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
            let prov = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let tips = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            guard let r = LocalStore.parseISO(ran) else { return nil }
            return (r, prov, tips)
        }
    }

    // MARK: - small date helpers

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func iso8601(_ d: Date) -> String { isoFmt.string(from: d) }
    static func parseISO(_ s: String?) -> Date? { s.flatMap { isoFmt.date(from: $0) } }
}

// SQLite C-style string lifetime helper: tells SQLite to copy the bound
// string into its own memory, so the Swift `String` can be released as soon
// as the binding call returns.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
