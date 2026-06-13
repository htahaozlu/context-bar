import AppKit
import Foundation

struct ToolSummary {
    let name: String
    let sessions7d: Int
    let tokens7d: UInt64
    let lastUsed: String?
    let lastModel: String?
}

struct AgentVisual {
    let assetName: String?
    let accessibilityLabel: String

    static func forName(_ name: String) -> Self {
        switch name.lowercased() {
        case "claude":
            return .init(assetName: "claude", accessibilityLabel: "Claude")
        case "codex":
            return .init(assetName: "codex", accessibilityLabel: "Codex")
        case "gemini":
            return .init(assetName: "gemini", accessibilityLabel: "Gemini")
        case "copilot cli", "copilot":
            return .init(assetName: "copilot", accessibilityLabel: "Copilot CLI")
        case "deepseek":
            return .init(assetName: "deepseek", accessibilityLabel: "DeepSeek")
        case "qwen":
            return .init(assetName: "qwen", accessibilityLabel: "Qwen")
        case "minimax":
            return .init(assetName: "minimax", accessibilityLabel: "MiniMax")
        default:
            return .init(assetName: nil, accessibilityLabel: name)
        }
    }
}

func agentIconURL(name: String) -> URL? {
    guard let assetName = AgentVisual.forName(name).assetName else { return nil }
    if let bundled = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "brands") {
        return bundled
    }
    let repoAsset = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("menubar/assets/brands/\(assetName).png")
    return FileManager.default.fileExists(atPath: repoAsset.path) ? repoAsset : nil
}

func agentInlineString(
    name: String,
    font: NSFont,
    fallbackColor: NSColor,
    iconScale: CGFloat = 1.0
) -> NSAttributedString {
    let visual = AgentVisual.forName(name)
    if let url = agentIconURL(name: name), let image = NSImage(contentsOf: url) {
        let attachment = NSTextAttachment()
        let icon = (image.copy() as? NSImage) ?? image
        // Size the icon to match cap-height so it occupies the same vertical
        // band as capital letters — no nudge needed because the bottom of the
        // icon sits on the baseline like the text glyphs do.
        let side = max(10, round(font.capHeight * iconScale))
        icon.size = NSSize(width: side, height: side)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: icon)
        attachment.bounds = NSRect(x: 0, y: 0, width: side, height: side)
        return NSAttributedString(attachment: attachment)
    }
    return NSAttributedString(
        string: visual.accessibilityLabel,
        attributes: [
            .font: font,
            .foregroundColor: fallbackColor,
        ]
    )
}

func agentInlineLabel(name: String, font: NSFont, color: NSColor, iconScale: CGFloat = 1.0) -> NSTextField {
    let label = NSTextField(
        labelWithAttributedString: agentInlineString(
            name: name,
            font: font,
            fallbackColor: color,
            iconScale: iconScale
        )
    )
    label.textColor = color
    label.toolTip = AgentVisual.forName(name).accessibilityLabel
    return label
}

struct ActiveSession {
    let id: String
    let tokens: UInt64
    let subagentTokens: UInt64   // portion of `tokens` from sub-agent (Task) turns
    let cost: Double
    let project: String
    let model: String?
    let lastTurn: Date?
    let started: Date?
    let ctxPct: Double?
    let ctxWindow: UInt64?
}

/// Menubar budget-pressure tier (C1), worst-of monthly $ run-rate and 5h %.
enum BudgetTier: Int { case ok = 0, warn = 1, critical = 2 }

/// Resolves a human-facing project name for a working directory, preferring the
/// git repository name (origin remote, else toplevel dir) over the leaf folder —
/// so the menubar shows the real repo (e.g. "context-bar") instead of whichever
/// sub-directory an agent happened to start in (e.g. "backend"). Mirrors the
/// engine's `project_name_from_cwd`. Pure filesystem, cached per cwd.
enum GitRepoName {
    private static var cache: [String: String] = [:]

    static func forCwd(_ cwd: String) -> String {
        if let hit = cache[cwd] { return hit }
        let name = resolve(cwd) ?? basename(cwd)
        cache[cwd] = name
        return name
    }

    private static func basename(_ c: String) -> String {
        let leaf = (c as NSString).lastPathComponent
        return leaf.isEmpty ? c : leaf
    }

    private static func resolve(_ cwd: String) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        let fm = FileManager.default
        var dir = (cwd as NSString).standardizingPath
        while !dir.isEmpty {
            let dotgit = (dir as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: dotgit) {
                if let cfg = configPath(dotgit),
                   let text = try? String(contentsOfFile: cfg, encoding: .utf8),
                   let name = originRepoName(text) {
                    return name
                }
                let leaf = (dir as NSString).lastPathComponent
                return leaf.isEmpty ? nil : leaf
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return nil
    }

    private static func configPath(_ dotgit: String) -> String? {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: dotgit, isDirectory: &isDir)
        if isDir.boolValue {
            return (dotgit as NSString).appendingPathComponent("config")
        }
        // `.git` file → "gitdir: <path>" (linked worktrees / submodules).
        guard let text = try? String(contentsOfFile: dotgit, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        var gitdir = String(line.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
        if !gitdir.hasPrefix("/") {
            gitdir = ((dotgit as NSString).deletingLastPathComponent as NSString).appendingPathComponent(gitdir)
        }
        let common = (gitdir as NSString).appendingPathComponent("commondir")
        if let c = try? String(contentsOfFile: common, encoding: .utf8) {
            let ct = c.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = ct.hasPrefix("/") ? ct : (gitdir as NSString).appendingPathComponent(ct)
            return ((base as NSString).standardizingPath as NSString).appendingPathComponent("config")
        }
        return (gitdir as NSString).appendingPathComponent("config")
    }

    private static func originRepoName(_ config: String) -> String? {
        var inOrigin = false
        for raw in config.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") {
                inOrigin = (t == "[remote \"origin\"]")
                continue
            }
            if inOrigin, t.hasPrefix("url") {
                let rest = t.dropFirst(3).drop(while: { $0 == " " || $0 == "\t" })
                if rest.first == "=" {
                    return repoNameFromURL(String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }

    private static func repoNameFromURL(_ url: String) -> String? {
        var u = url.trimmingCharacters(in: .whitespaces)
        while u.hasSuffix("/") { u.removeLast() }
        guard let seg = u.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) else { return nil }
        let name = seg.hasSuffix(".git") ? String(seg.dropLast(4)) : seg
        return name.isEmpty ? nil : name
    }
}

struct Agent {
    let name: String
    let session5h: UInt64
    let session5hPercent: Double?
    let week7d: UInt64
    let week7dPercent: Double?
    let activeSession: UInt64
    let activeSessionSubagent: UInt64   // portion of activeSession from sub-agents
    let activeSessionCost: Double
    /// Estimated API-equivalent cost over the last 30 days — the monthly
    /// run-rate the budget (C1) compares against.
    let totalCost30d: Double
    let model: String?
    let cwd: String?
    let ctxPct: Double?
    let ctxWindow: UInt64?
    let lastTurn: Date?
    let sessionStarted: Date?
    let activeSessions: [ActiveSession]
    let session5hResetsAt: Date?
    let week7dResetsAt: Date?

    /// Git repository name for the cwd (origin remote, else toplevel dir),
    /// falling back to the directory basename, or "—". See [GitRepoName].
    var project: String {
        guard let cwd, !cwd.isEmpty else { return "—" }
        return GitRepoName.forCwd(cwd)
    }
}
