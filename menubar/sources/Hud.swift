import AppKit
import Foundation

final class Hud {
    let path: String
    let usageCachePath: String
    init() {
        let env = ProcessInfo.processInfo.environment
        self.path = env["CONTEXTHUD_HUD_PATH"] ?? "\(NSHomeDirectory())/.context-hud/hud.json"
        self.usageCachePath = env["CONTEXTHUD_USAGE_CACHE_PATH"] ?? "\(NSHomeDirectory())/.context-hud/usage_api_cache.json"
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
                tokens7d: (obj["tokens_7d"] as? UInt64) ?? UInt64(obj["tokens_7d"] as? Int ?? 0),
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
                tokens: (obj["tokens"] as? UInt64) ?? UInt64(obj["tokens"] as? Int ?? 0),
                project: (obj["project"] as? String) ?? "—",
                model: obj["model"] as? String,
                lastTurn: last,
                started: st,
                ctxPct: obj["context_pct"] as? Double
            )
        }

        let parseDate: (String?) -> Date? = { s in
            guard let s else { return nil }
            return iso.date(from: s) ?? isoNoFrac.date(from: s)
        }

        let fiveHourOverlay = overlay?["five_hour"] as? [String: Any]
        let sevenDayOverlay = overlay?["seven_day"] as? [String: Any]

        return Agent(
            name: name,
            session5h: (raw["session_5h_tokens"] as? UInt64) ?? UInt64(raw["session_5h_tokens"] as? Int ?? 0),
            session5hPercent: (raw["session_5h_percent"] as? Double)
                ?? (fiveHourOverlay?["utilization"] as? Double)
                ?? (fiveHourOverlay?["used_percentage"] as? Double),
            week7d: (raw["week_7d_tokens"] as? UInt64) ?? UInt64(raw["week_7d_tokens"] as? Int ?? 0),
            week7dPercent: (raw["week_7d_percent"] as? Double)
                ?? (sevenDayOverlay?["utilization"] as? Double)
                ?? (sevenDayOverlay?["used_percentage"] as? Double),
            activeSession: (raw["active_session_tokens"] as? UInt64) ?? UInt64(raw["active_session_tokens"] as? Int ?? 0),
            model: raw["last_model"] as? String,
            cwd: raw["last_cwd"] as? String,
            ctxPct: raw["last_context_pct"] as? Double,
            ctxWindow: (raw["last_context_window"] as? UInt64) ?? (raw["last_context_window"] as? Int).map(UInt64.init),
            lastTurn: ts,
            sessionStarted: started,
            activeSessions: actives,
            session5hResetsAt: parseDate(raw["session_5h_resets_at"] as? String)
                ?? parseDate(fiveHourOverlay?["resets_at"] as? String),
            week7dResetsAt: parseDate(raw["week_7d_resets_at"] as? String)
                ?? parseDate(sevenDayOverlay?["resets_at"] as? String)
        )
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

    static func formatUsageValue(percent: Double?, tokens: UInt64) -> String {
        if let percent {
            return String(format: "%.0f%%", percent)
        }
        return formatTokens(tokens)
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

// MARK: - Detail window

/// Horizontal progress bar drawn natively. Fills `value` (0...1) with the
/// supplied tint over a subtle track. Used for window-elapsed limits and
