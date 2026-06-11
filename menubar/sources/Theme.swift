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

    /// The signature accent directions. Each is the SAME neutral language with
    /// a different single accent (the only chromatic note). Replaces the former
    /// six free-form palettes — the menubar gauge owns urgency (amber/red), so a
    /// theme only ever picks the calm accent hue. The Settings theme grid renders
    /// these three as the accent picker.
    static func direction(_ dir: AccentDirection) -> Theme {
        Theme(
            id: dir.rawValue,
            name: dir.displayName,
            agentColor: Palette.primaryText,
            projectColor: Palette.accentColor(dir),
            separatorColor: Palette.tertiaryText,
            pctLow: Palette.accentColor(dir),   // calm work rides the accent
            pctMid: Palette.urgencyAmber,        // attention
            pctHigh: Palette.urgencyRed,         // at the limit
            activeDot: "●", inactiveDot: "○", separator: "·"
        )
    }

    static let all: [Theme] = AccentDirection.allCases.map(direction)

    static func by(id: String) -> Theme {
        // Unknown / legacy ids (default, mono, neon, pastel, terminal, compact)
        // migrate to the recommended Clay direction (all[0]).
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

final class ThemeStore {
    static let key = "theme"
    static var current: Theme {
        get { Theme.by(id: UserDefaults.standard.string(forKey: key) ?? AccentDirection.clay.rawValue) }
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
