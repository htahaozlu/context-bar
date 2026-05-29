import AppKit
import Foundation

/// Reads the engine-produced `~/.context-bar/context.json` snapshot and turns it
/// into typed `Agent` / `ActiveSession` / `ToolSummary` values for the UI.
/// Static helpers on this type also handle formatting (tokens, durations,
/// reset text) and the traffic-light context color used across panels.
final class ContextSnapshot {
    let path: String
    let usageCachePath: String
    init() {
        let env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let primary = env["CONTEXTBAR_CONTEXT_PATH"]
            ?? env["CONTEXTBAR_HUD_PATH"]
            ?? "\(home)/.context-bar/context.json"
        // One-release back-compat: if the new file is missing but the legacy
        // `hud.json` is still around (engine not yet rebuilt), read that.
        let fm = FileManager.default
        if fm.fileExists(atPath: primary) {
            self.path = primary
        } else {
            let legacy = "\(home)/.context-bar/hud.json"
            self.path = fm.fileExists(atPath: legacy) ? legacy : primary
        }
        self.usageCachePath = env["CONTEXTBAR_USAGE_CACHE_PATH"] ?? "\(home)/.context-bar/usage_api_cache.json"
    }

    /// Resolves the snapshot path the same way `ContextSnapshot()` does —
    /// prefers `context.json`, falls back to legacy `hud.json`. Shared with
    /// panels that read the file directly (UsageViewController, StatsViewController).
    static func resolveSnapshotPath() -> String {
        let env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let primary = env["CONTEXTBAR_CONTEXT_PATH"]
            ?? env["CONTEXTBAR_HUD_PATH"]
            ?? "\(home)/.context-bar/context.json"
        let fm = FileManager.default
        if fm.fileExists(atPath: primary) { return primary }
        let legacy = "\(home)/.context-bar/hud.json"
        return fm.fileExists(atPath: legacy) ? legacy : primary
    }

    func load() -> (active: Agent?, all: [Agent], others: [ToolSummary]) {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, [], [])
        }

        let claude = parse(root["claude"] as? [String: Any], name: "Claude", overlay: parseClaudeUsageCache())
        let codex = parse(root["codex"] as? [String: Any], name: "Codex")
        let all = [claude, codex].compactMap { $0 }
        let active = all.max(by: {
            ($0.lastTurn ?? .distantPast) < ($1.lastTurn ?? .distantPast)
        })
        let others = parseOthers(root["others"] as? [[String: Any]])
        return (active, all, others)
    }

    private func parseOthers(_ raw: [[String: Any]]?) -> [ToolSummary] {
        guard let raw else { return [] }
        return raw.compactMap { obj in
            guard let name = obj["name"] as? String, !name.isEmpty else { return nil }
            return ToolSummary(
                name: name,
                sessions7d: obj["sessions_7d"] as? Int ?? 0,
                tokens7d: u64(obj["tokens_7d"]),
                lastUsed: obj["last_used"] as? String,
                lastModel: obj["last_model"] as? String
            )
        }
    }

    private func parseClaudeUsageCache() -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: usageCachePath)),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["data"] as? [String: Any]
        else {
            return nil
        }
        return payload
    }

    /// Coerce a JSON value (NSNumber or numeric string) into UInt64. Handles
    /// the JSONSerialization quirk where small ints come back as `Int` but
    /// large counts (≥ 2^63) come back as `Double` inside an NSNumber.
    private func u64(_ v: Any?) -> UInt64 {
        guard let v else { return 0 }
        if let n = v as? UInt64 { return n }
        if let n = v as? Int64, n >= 0 { return UInt64(n) }
        if let n = v as? Int, n >= 0 { return UInt64(n) }
        if let d = v as? Double, d.isFinite, d >= 0 { return UInt64(d) }
        if let num = v as? NSNumber { return num.uint64Value }
        return 0
    }

    private func u64Opt(_ v: Any?) -> UInt64? {
        guard let v, !(v is NSNull) else { return nil }
        if let n = v as? UInt64 { return n }
        if let n = v as? Int64, n >= 0 { return UInt64(n) }
        if let n = v as? Int, n >= 0 { return UInt64(n) }
        if let d = v as? Double, d.isFinite, d >= 0 { return UInt64(d) }
        if let num = v as? NSNumber { return num.uint64Value }
        return nil
    }

    private func dbl(_ v: Any?) -> Double? {
        guard let v, !(v is NSNull) else { return nil }
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    private func parse(_ raw: [String: Any]?, name: String, overlay: [String: Any]? = nil) -> Agent? {
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        let tsRaw = raw["last_turn_at"] as? String
        let ts: Date? = tsRaw.flatMap {
            iso.date(from: $0) ?? isoNoFrac.date(from: $0)
        }
        let startRaw = raw["active_session_started_at"] as? String
        let started: Date? = startRaw.flatMap {
            iso.date(from: $0) ?? isoNoFrac.date(from: $0)
        }

        let actives = (raw["active_sessions"] as? [[String: Any]] ?? []).compactMap { obj -> ActiveSession? in
            guard let id = obj["id"] as? String else { return nil }
            let lastRaw = obj["last_turn_at"] as? String
            let startedRaw = obj["started_at"] as? String
            let last: Date? = lastRaw.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
            let st: Date? = startedRaw.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
            return ActiveSession(
                id: id,
                tokens: u64(obj["tokens"]),
                cost: dbl(obj["cost"]) ?? 0,
                project: (obj["project"] as? String) ?? "—",
                model: obj["model"] as? String,
                lastTurn: last,
                started: st,
                ctxPct: dbl(obj["context_pct"])
            )
        }

        let parseDate: (String?) -> Date? = { s in
            guard let s else { return nil }
            return iso.date(from: s) ?? isoNoFrac.date(from: s)
        }

        let fiveHourOverlay = overlay?["five_hour"] as? [String: Any]
        let sevenDayOverlay = overlay?["seven_day"] as? [String: Any]

        // Engine occasionally drops `last_context_pct` (and sometimes `last_cwd`)
        // even when an `active_sessions` entry has fresh data. Fall back to the
        // most-recently-updated session so the menubar % keeps tracking instead
        // of going blank between turns.
        let mostRecentActive = actives.max(by: {
            ($0.lastTurn ?? .distantPast) < ($1.lastTurn ?? .distantPast)
        })
        let resolvedCtxPct = dbl(raw["last_context_pct"]) ?? mostRecentActive?.ctxPct
        let resolvedCwd = (raw["last_cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? mostRecentActive?.project

        return Agent(
            name: name,
            session5h: u64(raw["session_5h_tokens"]),
            session5hPercent: dbl(raw["session_5h_percent"])
                ?? dbl(fiveHourOverlay?["utilization"])
                ?? dbl(fiveHourOverlay?["used_percentage"]),
            week7d: u64(raw["week_7d_tokens"]),
            week7dPercent: dbl(raw["week_7d_percent"])
                ?? dbl(sevenDayOverlay?["utilization"])
                ?? dbl(sevenDayOverlay?["used_percentage"]),
            activeSession: u64(raw["active_session_tokens"]),
            activeSessionCost: dbl(raw["active_session_cost"]) ?? 0,
            model: raw["last_model"] as? String,
            cwd: resolvedCwd,
            ctxPct: resolvedCtxPct,
            ctxWindow: u64Opt(raw["last_context_window"]),
            lastTurn: ts,
            sessionStarted: started,
            activeSessions: actives,
            session5hResetsAt: parseDate(raw["session_5h_resets_at"] as? String)
                ?? parseDate(fiveHourOverlay?["resets_at"] as? String),
            week7dResetsAt: parseDate(raw["week_7d_resets_at"] as? String)
                ?? parseDate(sevenDayOverlay?["resets_at"] as? String)
        )
    }

    /// Formats a reset date according to the user's display preference.
    /// `.relative` → "1h 47m"; `.absolute` → "14:32" (or "May 17, 14:32" if
    /// reset is more than 24h out so the user knows it's not today).
    static func resetsText(_ date: Date?) -> String {
        switch DisplayPrefs.resetStyle {
        case .relative: return resetsIn(date)
        case .absolute: return resetsAt(date)
        }
    }

    static func resetsAt(_ date: Date?) -> String {
        guard let date else { return "—" }
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return L10n.text("ready", "hazır") }
        let f = DateFormatter()
        if remaining < 86400 {
            f.dateFormat = "HH:mm"
        } else {
            f.dateStyle = .medium
            f.timeStyle = .short
        }
        return f.string(from: date)
    }

    /// Linear extrapolation of when the active session will fill its context
    /// window at current burn rate. Returns nil if we lack data, the session
    /// is too short for a confident estimate, or token rate is non-positive.
    /// Confidence gates: need ≥ 2 min elapsed and ≥ 5% pct change worth of
    /// tokens since session start.
    static func burnRate(_ a: Agent) -> (etaSeconds: TimeInterval, etaDate: Date)? {
        guard let pct = a.ctxPct, pct > 0, pct < 100,
              let start = a.sessionStarted,
              let window = a.ctxWindow, window > 0 else { return nil }
        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 120 else { return nil }
        let used = Double(a.activeSession)
        guard used > 0 else { return nil }
        let rate = used / elapsed
        guard rate > 0 else { return nil }
        let remaining = Double(window) - used
        guard remaining > 0 else { return nil }
        let eta = remaining / rate
        guard eta.isFinite, eta > 60 else { return nil }
        return (eta, now.addingTimeInterval(eta))
    }

    /// Formats a burn-rate ETA as "in 1h 47m". Shorter than `resetsIn` —
    /// suppresses leading "<1m" / day-units for the hero where space matters.
    static func burnRateText(_ eta: TimeInterval) -> String {
        let tr = L10n.lang == .tr
        let hU = tr ? "sa" : "h"
        let mU = tr ? "dk" : "m"
        if eta < 60 { return "<1\(mU)" }
        if eta < 3600 { return "\(Int(eta / 60))\(mU)" }
        let h = Int(eta / 3600)
        let m = (Int(eta) % 3600) / 60
        return m == 0 ? "\(h)\(hU)" : "\(h)\(hU) \(m)\(mU)"
    }

    static func resetsIn(_ date: Date?) -> String {
        guard let date else { return "—" }
        let remaining = date.timeIntervalSinceNow
        let tr = L10n.lang == .tr
        let dU = tr ? "g" : "d"
        let hU = tr ? "sa" : "h"
        let mU = tr ? "dk" : "m"
        if remaining <= 0 { return L10n.text("ready", "hazır") }
        if remaining < 60 { return "<1\(mU)" }
        if remaining < 3600 { return "\(Int(remaining/60))\(mU)" }
        if remaining < 86400 {
            let h = Int(remaining / 3600)
            let m = (Int(remaining) % 3600) / 60
            return m == 0 ? "\(h)\(hU)" : "\(h)\(hU) \(m)\(mU)"
        }
        let d = Int(remaining / 86400)
        let h = (Int(remaining) % 86400) / 3600
        return h == 0 ? "\(d)\(dU)" : "\(d)\(dU) \(h)\(hU)"
    }

    static func formatDuration(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "—" }
        let s = max(0.0, end.timeIntervalSince(start))
        if s < 60 { return "\(Int(s))s" }
        let m = Int(s / 60)
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let mm = m % 60
        if h < 24 {
            return mm == 0 ? "\(h)h" : "\(h)h \(mm)m"
        }
        let d = h / 24
        let hh = h % 24
        return hh == 0 ? "\(d)d" : "\(d)d \(hh)h"
    }

    static func formatTokens(_ value: UInt64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000.0) }
        return "\(value)"
    }

    /// USD with comma grouping + 2 decimals; `<$0.01` for tiny non-zero values.
    /// Shared by the Cost tab and the popover so money reads consistently.
    static func formatUSD(_ value: Double) -> String {
        if value <= 0 { return "$0.00" }
        if value < 0.01 { return "<$0.01" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        return "$" + (f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    static func formatUsageValue(percent: Double?, tokens: UInt64) -> String {
        if let percent {
            return String(format: "%.0f%%", percent)
        }
        return formatTokens(tokens)
    }

    static func formatRemainingValue(percentUsed: Double?, tokens: UInt64) -> String {
        guard let percentUsed else { return formatTokens(tokens) }
        let remaining = max(0, min(100, 100 - percentUsed))
        let suffix = L10n.text(" left", " kalan")
        return String(format: "%.0f%%%@", remaining, suffix)
    }

    static func relative(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        return L10n.relative(elapsed)
    }

    /// Traffic-light color for a context % value.
    static func ctxColor(_ pct: Double?) -> NSColor {
        guard let pct else { return .labelColor }
        switch pct {
        case ..<60: return NSColor.systemGreen
        case ..<85: return NSColor.systemOrange
        default:    return NSColor.systemRed
        }
    }
}
