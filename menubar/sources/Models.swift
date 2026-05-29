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
    let cost: Double
    let project: String
    let model: String?
    let lastTurn: Date?
    let started: Date?
    let ctxPct: Double?
}

struct Agent {
    let name: String
    let session5h: UInt64
    let session5hPercent: Double?
    let week7d: UInt64
    let week7dPercent: Double?
    let activeSession: UInt64
    let activeSessionCost: Double
    let model: String?
    let cwd: String?
    let ctxPct: Double?
    let ctxWindow: UInt64?
    let lastTurn: Date?
    let sessionStarted: Date?
    let activeSessions: [ActiveSession]
    let session5hResetsAt: Date?
    let week7dResetsAt: Date?

    /// Returns project basename (last path segment) or "—".
    var project: String {
        guard let cwd, !cwd.isEmpty else { return "—" }
        return (cwd as NSString).lastPathComponent
    }
}
