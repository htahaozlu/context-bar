import Foundation

/// Cross-machine usage aggregation (boss: "I also work from another Mac").
/// Local-first, no server, no telemetry: the user points context-bar at a folder
/// THEY already sync (iCloud Drive, Dropbox, …). Each Mac writes a compact
/// per-machine usage file there; every Mac reads them all and merges into a
/// combined view. Off by default — nothing is written until a folder is set.
///
/// The app is not sandboxed (it already reads ~/.claude), so a plain stored
/// path works — no security-scoped bookmark needed.

extension DisplayPrefs {
    private static let kSyncFolder = "displayPrefs.syncFolder"
    /// Folder the user already syncs across Macs. Empty = feature off.
    static var syncFolder: String {
        get { UserDefaults.standard.string(forKey: kSyncFolder) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kSyncFolder) }
    }
}

/// One machine's compact usage snapshot (what gets written to / read from the
/// synced folder). Aggregates only — no transcripts, no raw paths.
struct MachineUsage {
    let machine: String
    let updatedAt: Date?
    let isSelf: Bool
    // Per-agent 30-day rollups, keyed by agent name ("Claude"/"Codex").
    let totalTokens30d: [String: UInt64]
    let totalCost30d: [String: Double]
    let subagentTokens30d: [String: UInt64]

    var grandTokens: UInt64 { totalTokens30d.values.reduce(0, +) }
    var grandCost: Double { totalCost30d.values.reduce(0, +) }
}

enum MachineSync {
    /// Stable, human-readable machine name (the Mac's sharing name).
    static var machineName: String {
        let n = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        // Filesystem-safe slug for the filename.
        return n
    }

    private static let suffix = ".contextbar.json"
    private static var enabled: Bool { !DisplayPrefs.syncFolder.isEmpty }

    private static func fileSafe(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }).trimmingCharacters(in: .whitespaces)
    }

    /// Write THIS machine's compact usage to the synced folder. Called on refresh.
    /// No-op when the feature is off. Atomic write (tmp + rename).
    static func exportLocal() {
        guard enabled else { return }
        let folder = DisplayPrefs.syncFolder
        let path = ContextSnapshot.resolveSnapshotPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        func u(_ a: [String: Any]?, _ k: String) -> UInt64 {
            guard let v = a?[k] else { return 0 }
            if let n = v as? UInt64 { return n }
            if let n = v as? Int, n >= 0 { return UInt64(n) }
            if let d = v as? Double, d >= 0 { return UInt64(d) }
            return 0
        }
        func d(_ a: [String: Any]?, _ k: String) -> Double { (a?[k] as? Double) ?? 0 }

        var agents: [String: Any] = [:]
        for (key, name) in [("claude", "Claude"), ("codex", "Codex")] {
            let a = root[key] as? [String: Any]
            guard a != nil, u(a, "total_tokens_30d") > 0 || d(a, "total_cost_30d") > 0 else { continue }
            agents[name] = [
                "total_tokens_30d": u(a, "total_tokens_30d"),
                "total_cost_30d": d(a, "total_cost_30d"),
                "subagent_tokens_30d": u(a, "subagent_tokens_30d"),
            ]
        }

        let payload: [String: Any] = [
            "schema": 1,
            "machine": machineName,
            "updated_at": iso8601(Date()),
            "agents": agents,
        ]
        guard let out = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
        let dst = (folder as NSString).appendingPathComponent(fileSafe(machineName) + suffix)
        let tmp = dst + ".tmp"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        if (try? out.write(to: URL(fileURLWithPath: tmp))) != nil {
            try? FileManager.default.removeItem(atPath: dst)
            try? FileManager.default.moveItem(atPath: tmp, toPath: dst)
        }
    }

    /// Read every machine's file from the synced folder (incl. this one).
    static func readAll() -> [MachineUsage] {
        guard enabled else { return [] }
        let folder = DisplayPrefs.syncFolder
        let self_ = machineName
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        var out: [MachineUsage] = []
        for n in names where n.hasSuffix(suffix) {
            let p = (folder as NSString).appendingPathComponent(n)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let machine = (j["machine"] as? String) ?? n.replacingOccurrences(of: suffix, with: "")
            let agents = (j["agents"] as? [String: Any]) ?? [:]
            var tok: [String: UInt64] = [:], cost: [String: Double] = [:], sub: [String: UInt64] = [:]
            for (name, raw) in agents {
                let a = raw as? [String: Any]
                tok[name] = (a?["total_tokens_30d"] as? Double).map { UInt64($0) } ?? (a?["total_tokens_30d"] as? UInt64) ?? UInt64((a?["total_tokens_30d"] as? Int) ?? 0)
                cost[name] = (a?["total_cost_30d"] as? Double) ?? 0
                sub[name] = (a?["subagent_tokens_30d"] as? Double).map { UInt64($0) } ?? (a?["subagent_tokens_30d"] as? UInt64) ?? UInt64((a?["subagent_tokens_30d"] as? Int) ?? 0)
            }
            out.append(MachineUsage(
                machine: machine,
                updatedAt: parseISO(j["updated_at"] as? String),
                isSelf: machine == self_,
                totalTokens30d: tok, totalCost30d: cost, subagentTokens30d: sub
            ))
        }
        out.sort { $0.grandCost > $1.grandCost }
        return out
    }

    /// Combined 30-day cost across all machines (the headline cross-machine number).
    static func combinedCost30d() -> Double { readAll().reduce(0) { $0 + $1.grandCost } }

    // MARK: - small date helpers
    private static func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
    private static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
