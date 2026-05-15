import AppKit
import Foundation

// MARK: - Themes

/// Visual theme — each preset overrides the menubar/dropdown palette and the
/// glyphs used to mark the active agent and separators. Selected via the
/// "Theme" submenu and persisted in UserDefaults under `theme`.
struct Theme {
    let id: String
    let name: String
    let agentColor: NSColor
    let projectColor: NSColor
    let separatorColor: NSColor
    let pctLow: NSColor       // < 60%
    let pctMid: NSColor       // < 85%
    let pctHigh: NSColor      // >= 85%
    let activeDot: String
    let inactiveDot: String
    let separator: String

    func ctxColor(_ pct: Double?) -> NSColor {
        guard let pct else { return agentColor }
        switch pct {
        case ..<60: return pctLow
        case ..<85: return pctMid
        default:    return pctHigh
        }
    }

    static let all: [Theme] = [
        Theme(
            id: "default",
            name: "Default",
            agentColor: .labelColor,
            projectColor: .controlAccentColor,
            separatorColor: .tertiaryLabelColor,
            pctLow: .systemGreen,
            pctMid: .systemOrange,
            pctHigh: .systemRed,
            activeDot: "●", inactiveDot: "○", separator: "·"
        ),
        Theme(
            id: "mono",
            name: "Mono",
            agentColor: .labelColor,
            projectColor: .labelColor,
            separatorColor: .tertiaryLabelColor,
            pctLow: .labelColor,
            pctMid: .labelColor,
            pctHigh: .labelColor,
            activeDot: "▸", inactiveDot: "·", separator: "·"
        ),
        Theme(
            id: "neon",
            name: "Neon",
            agentColor: NSColor(srgbRed: 0.45, green: 1.00, blue: 0.85, alpha: 1.0),
            projectColor: NSColor(srgbRed: 1.00, green: 0.45, blue: 0.85, alpha: 1.0),
            separatorColor: NSColor(srgbRed: 0.55, green: 0.45, blue: 0.85, alpha: 0.6),
            pctLow: NSColor(srgbRed: 0.10, green: 1.00, blue: 0.55, alpha: 1.0),
            pctMid: NSColor(srgbRed: 1.00, green: 0.85, blue: 0.20, alpha: 1.0),
            pctHigh: NSColor(srgbRed: 1.00, green: 0.30, blue: 0.45, alpha: 1.0),
            activeDot: "◆", inactiveDot: "◇", separator: "·"
        ),
        Theme(
            id: "pastel",
            name: "Pastel",
            agentColor: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.85, alpha: 1.0),
            projectColor: NSColor(srgbRed: 0.85, green: 0.65, blue: 0.95, alpha: 1.0),
            separatorColor: NSColor(srgbRed: 0.70, green: 0.70, blue: 0.78, alpha: 0.7),
            pctLow: NSColor(srgbRed: 0.60, green: 0.85, blue: 0.70, alpha: 1.0),
            pctMid: NSColor(srgbRed: 0.95, green: 0.80, blue: 0.55, alpha: 1.0),
            pctHigh: NSColor(srgbRed: 0.95, green: 0.65, blue: 0.70, alpha: 1.0),
            activeDot: "✦", inactiveDot: "✧", separator: "—"
        ),
        Theme(
            id: "terminal",
            name: "Terminal",
            agentColor: NSColor.systemGreen,
            projectColor: NSColor.systemYellow,
            separatorColor: .secondaryLabelColor,
            pctLow: NSColor.systemGreen,
            pctMid: NSColor.systemYellow,
            pctHigh: NSColor.systemRed,
            activeDot: ">", inactiveDot: " ", separator: "|"
        ),
        Theme(
            id: "compact",
            name: "Compact",
            agentColor: .labelColor,
            projectColor: .secondaryLabelColor,
            separatorColor: .tertiaryLabelColor,
            pctLow: .systemTeal,
            pctMid: .systemOrange,
            pctHigh: .systemRed,
            activeDot: "·", inactiveDot: " ", separator: ""
        ),
    ]

    static func by(id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

final class ThemeStore {
    static let key = "theme"
    static var current: Theme {
        get { Theme.by(id: UserDefaults.standard.string(forKey: key) ?? "default") }
    }
    static func set(_ id: String) {
        UserDefaults.standard.set(id, forKey: key)
    }
}

final class SeparatorStore {
    static let key = "separator"
    static let options: [(label: String, value: String)] = [
        ("·", "·"), ("|", "|"), ("-", "-"), ("—", "—"), ("/", "/"), ("none", ""),
    ]
    static var current: String {
        UserDefaults.standard.string(forKey: key) ?? "·"
    }
    static var currentIndex: Int {
        options.firstIndex(where: { $0.value == current }) ?? 0
    }
    static func set(_ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
