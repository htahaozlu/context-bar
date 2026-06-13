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

    // MARK: - iCloud Drive (zero-config, no account)
    //
    // The easiest no-account path: the user's iCloud Drive already syncs across
    // every Mac signed into the same Apple ID. We write our per-machine files
    // into a `ContextBar` folder inside iCloud Drive — so a second Mac just
    // flips the same switch and combined usage appears, with no folder picking,
    // no server, and no ContextBar account. The app is not sandboxed, so we use
    // the CloudDocs path directly and need no iCloud entitlement.

    /// `~/Library/Mobile Documents/com~apple~CloudDocs` — the iCloud Drive root.
    static var iCloudDriveRoot: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }

    /// True when iCloud Drive is set up on this Mac: the user is actually signed
    /// into iCloud (ubiquity token present) AND the CloudDocs dir exists. Both
    /// matter — the dir can linger after sign-out, and the token can exist while
    /// iCloud Drive itself is disabled.
    static var iCloudAvailable: Bool {
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: iCloudDriveRoot, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// The `ContextBar` folder inside iCloud Drive used when iCloud sync is on.
    static var iCloudSyncFolder: String {
        (iCloudDriveRoot as NSString).appendingPathComponent("ContextBar")
    }

    /// True when the active sync folder is the iCloud Drive folder.
    static var isICloudMode: Bool {
        !DisplayPrefs.syncFolder.isEmpty && DisplayPrefs.syncFolder == iCloudSyncFolder
    }

    /// Turn on zero-config iCloud sync: create the folder and write this Mac's
    /// snapshot immediately so the other Macs see it on their next read.
    static func enableICloudSync() {
        try? FileManager.default.createDirectory(
            atPath: iCloudSyncFolder, withIntermediateDirectories: true)
        DisplayPrefs.syncFolder = iCloudSyncFolder
        exportLocal()
    }

    /// Turn off folder/iCloud sync (stops writing; leaves existing files).
    static func disableSync() {
        DisplayPrefs.syncFolder = ""
    }

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
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        } catch {
            // iCloud may not be ready yet (signing in, Drive disabled, quota).
            // Bail safely rather than crash; next refresh retries.
            NSLog("[MachineSync] exportLocal: cannot create sync folder %@ — %@", folder, error.localizedDescription)
            return
        }
        if (try? out.write(to: URL(fileURLWithPath: tmp))) != nil {
            try? FileManager.default.removeItem(atPath: dst)
            try? FileManager.default.moveItem(atPath: tmp, toPath: dst)
        }
    }

    /// Read every machine's file from the synced folder (incl. this one).
    ///
    /// iCloud keeps a peer Mac's file as a non-materialized placeholder until
    /// something asks for it — on disk that's `.<name>.icloud` (leading dot +
    /// `.icloud` suffix), and `contentsOfDirectory(atPath:)` won't see the real
    /// name at all. So before reading we coerce iCloud to download every
    /// candidate: real `*.contextbar.json` files AND any `.*.icloud`
    /// placeholders (whose real URL we reconstruct). Downloads are async, so a
    /// freshly-added peer may still be missing this pass; it materializes within
    /// a tick or two and shows up on the next refresh. We parse whatever read
    /// successfully and skip the rest gracefully.
    static func readAll() -> [MachineUsage] {
        guard enabled else { return [] }
        let folder = DisplayPrefs.syncFolder
        let self_ = machineName
        let folderURL = URL(fileURLWithPath: folder, isDirectory: true)
        let fm = FileManager.default

        // Enumerate by URL so we can trigger downloads. Collect the real
        // `*.contextbar.json` URLs to parse this pass.
        var realURLs: [URL] = []
        if let entries = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) {
            // Visible (already-materialized) real files.
            for url in entries where url.lastPathComponent.hasSuffix(suffix) {
                // Nudge iCloud to keep it current; harmless for local files.
                try? fm.startDownloadingUbiquitousItem(at: url)
                realURLs.append(url)
            }
        }
        // Placeholders are hidden (leading dot), so enumerate WITHOUT skipping
        // hidden files to catch `.<name>.contextbar.json.icloud`. Trigger their
        // download (materializes for the next pass) and also add the derived
        // real URL in case the file is already readable this pass.
        if let allEntries = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: []) {
            for url in allEntries {
                let name = url.lastPathComponent
                guard name.hasPrefix("."), name.hasSuffix(".icloud") else { continue }
                // `.MacBook.contextbar.json.icloud` -> `MacBook.contextbar.json`
                let realName = String(name.dropFirst().dropLast(".icloud".count))
                guard realName.hasSuffix(suffix) else { continue }
                let realURL = folderURL.appendingPathComponent(realName)
                // Kick the download using the real URL (iCloud API expects it).
                try? fm.startDownloadingUbiquitousItem(at: realURL)
                if !realURLs.contains(realURL) { realURLs.append(realURL) }
            }
        }

        var out: [MachineUsage] = []
        for p in realURLs.map({ $0.path }) {
            let n = (p as NSString).lastPathComponent
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
