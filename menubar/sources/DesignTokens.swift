import AppKit
import Foundation

// MARK: - Design Tokens
//
// Single source of truth for spacing, corner radii, typography, and motion
// across every menubar surface (popover, usage, stats, appearance, about).
// All ad-hoc paddings and font sizes should reference these values so the
// app feels consistent end to end.

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let chip: CGFloat = 8
    static let card: CGFloat = 12
    static let hero: CGFloat = 16
    static let popover: CGFloat = 20
}

enum Typography {
    /// Signature numeral font — bundled JetBrains Mono (registered at launch by
    /// `Fonts.registerBundled()`). Every number in the UI flows through here so
    /// the tabular figures match the redesign exactly. Falls back to the system
    /// monospaced-digit font if the bundle/registration is unavailable.
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let face: String
        switch weight {
        case .bold, .heavy, .black: face = "JetBrainsMono-Bold"
        case .semibold:             face = "JetBrainsMono-SemiBold"
        case .medium:               face = "JetBrainsMono-Medium"
        default:                    face = "JetBrainsMono-Regular"
        }
        if let f = NSFont(name: face, size: size) { return f }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// Hero/display number — 40pt semibold by the redesign style tile.
    static func display(_ size: CGFloat = 40, weight: NSFont.Weight = .semibold) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    static func displayMono(_ size: CGFloat = 40, weight: NSFont.Weight = .semibold) -> NSFont {
        mono(size, weight: weight)
    }
    /// Secondary metric number — 25pt semibold (cost hero, stat tiles).
    static func metric(_ size: CGFloat = 25, weight: NSFont.Weight = .semibold) -> NSFont {
        mono(size, weight: weight)
    }
    static func title(_ size: CGFloat = 15) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }
    static func body(_ size: CGFloat = 12) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }
    static func bodyMono(_ size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSFont {
        mono(size, weight: weight)
    }
    static func caption() -> NSFont {
        NSFont.systemFont(ofSize: 10, weight: .semibold)
    }

    /// Builds an UPPERCASE kerned attributed string used for section captions
    /// ("CONTEXT", "30-DAY TOKENS", etc.). Consistent across all panes.
    static func captionAttributed(_ text: String, color: NSColor = Palette.tertiaryText) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: caption(),
            .foregroundColor: color,
            .kern: 0.8,
        ])
    }

    /// Display number — supports tabular figures and slight tracking for the
    /// premium hero "42%" look. Number labels that animate / update on refresh
    /// should always use this so the width doesn't jitter as digits change.
    static func displayNumberAttributed(_ text: String, size: CGFloat = 28,
                                        weight: NSFont.Weight = .semibold,
                                        color: NSColor = Palette.primaryText) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: mono(size, weight: weight),
            .foregroundColor: color,
            .kern: -0.4,
        ])
    }
}

// Signature accent direction. The redesign keeps ONE chromatic note over a
// neutral gray scale; the user picks which hue that note is. Clay is the
// recommended default; Indigo and Teal are the alternate directions from the
// style tile. The accent drives hero numbers, bars, the heatmap ramp and any
// over-threshold highlight — nothing else is colored.
enum AccentDirection: String, CaseIterable {
    case clay, indigo, teal

    var displayName: String {
        switch self {
        case .clay: return "Clay"
        case .indigo: return "Indigo"
        case .teal: return "Teal"
        }
    }
    /// Accent on light backgrounds.
    var lightHex: UInt32 {
        switch self {
        case .clay: return 0xC2553A
        case .indigo: return 0x4F6BED
        case .teal: return 0x1F8A5B
        }
    }
    /// Accent on dark backgrounds (lifted for contrast).
    var darkHex: UInt32 {
        switch self {
        case .clay: return 0xE68A66
        case .indigo: return 0x8AA0FF
        case .teal: return 0x3FCB8E
        }
    }
    /// The live direction — backed by the theme selection so the existing
    /// theme grid in Settings doubles as the accent picker.
    static var current: AccentDirection {
        AccentDirection(rawValue: ThemeStore.current.id) ?? .clay
    }
}

// Signature design language: ONE accent (clay / indigo / teal) over a neutral
// gray scale. Numbers are always mono + tabular. Neutral surfaces, amber/red
// reserved for the urgency ramp.
enum Palette {
    // ---- text tiers ----
    static let primaryText = dynamicColor(name: "ContextBarPrimaryText") { isDark in
        isDark ? srgb(0xF5F5F5) : srgb(0x141414)
    }
    static let secondaryText = dynamicColor(name: "ContextBarSecondaryText") { isDark in
        isDark ? NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 0.58)
               : NSColor(srgbRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.56)
    }
    static let tertiaryText = dynamicColor(name: "ContextBarTertiaryText") { isDark in
        isDark ? NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 0.40)
               : NSColor(srgbRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.40)
    }

    // ---- signature accent (clay / indigo / teal direction) ----
    /// Live accent for the selected direction. Drives hero numbers, bars, the
    /// heatmap ramp and over-threshold highlights — the only chromatic note.
    static var accent: NSColor { accentColor(AccentDirection.current) }
    /// 16% (light) / 22% (dark) accent — chips, glyph wells, hot-bar wash.
    static var accentSoft: NSColor { accentTint(AccentDirection.current, light: 0.16, dark: 0.22, suffix: "Soft") }
    /// 8% (light) / 11% (dark) accent — insight-card fills, faint tints.
    static var accentSofter: NSColor { accentTint(AccentDirection.current, light: 0.08, dark: 0.11, suffix: "Softer") }

    /// Accent for an explicit direction — used by the accent picker cards so a
    /// swatch can preview a direction that is not the currently-selected one.
    static func accentColor(_ dir: AccentDirection) -> NSColor {
        NSColor(name: NSColor.Name("ContextBarAccent.\(dir.rawValue)")) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return srgb(isDark ? dir.darkHex : dir.lightHex)
        }
    }
    private static func accentTint(_ dir: AccentDirection, light: CGFloat, dark: CGFloat, suffix: String) -> NSColor {
        NSColor(name: NSColor.Name("ContextBarAccent\(suffix).\(dir.rawValue)")) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return srgb(isDark ? dir.darkHex : dir.lightHex).withAlphaComponent(isDark ? dark : light)
        }
    }

    // ---- surfaces ----
    /// Window / pane backdrop (Stats/Cost/Settings).
    static let window = dynamicColor(name: "ContextBarWindow") { isDark in
        isDark ? srgb(0x1C1B19) : srgb(0xECEAE6)
    }
    /// Translucent card fill — floats over vibrancy. Falls back to solid when
    /// reduce-transparency is on (handled in Surface).
    static let cardFill = dynamicColor(name: "ContextBarCardFill") { isDark in
        isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.055) : NSColor(calibratedWhite: 1.0, alpha: 0.72)
    }
    /// Opaque card — the hero and any solid surface.
    static let cardSolid = dynamicColor(name: "ContextBarCardSolid") { isDark in
        isDark ? srgb(0x2B2A28) : srgb(0xFFFFFF)
    }

    // ---- hairlines / tracks ----
    static let hairline = dynamicColor(name: "ContextBarHairline") { isDark in
        isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.10) : NSColor(calibratedWhite: 0.0, alpha: 0.09)
    }
    static let hairlineStrong = dynamicColor(name: "ContextBarHairlineStrong") { isDark in
        isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.16) : NSColor(calibratedWhite: 0.0, alpha: 0.14)
    }
    static let track = dynamicColor(name: "ContextBarTrack") { isDark in
        isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.11) : NSColor(calibratedWhite: 0.0, alpha: 0.08)
    }

    // ---- semantic ----
    static let positive = dynamicColor(name: "ContextBarPositive") { isDark in
        isDark ? srgb(0x3FCB7E) : srgb(0x1E8A4C)
    }
    /// Urgency ramp — used ONLY by the menubar gauge / limit pressure, never as
    /// general chrome. Calm work stays on the accent; amber = attention, red =
    /// at the limit.
    static let urgencyAmber = dynamicColor(name: "ContextBarUrgencyAmber") { isDark in
        isDark ? srgb(0xF2B33D) : srgb(0xD98A0B)
    }
    static let urgencyRed = dynamicColor(name: "ContextBarUrgencyRed") { isDark in
        isDark ? srgb(0xFF6B5E) : srgb(0xE0452F)
    }

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1)
    }

    private static func dynamicColor(name: String, provider: @escaping (Bool) -> NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return provider(isDark)
        }
    }
}

enum MotionPrefs {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

// MARK: - Accent helpers

extension Theme {
    /// Semantic accent — the project / agent signature color of the theme.
    /// Used for sparkline strokes, heatmap ramps, hero gradients.
    var accent: NSColor { projectColor }

    /// Soft fill version of the accent — for hero gradients, chips, hover
    /// states. Alpha 0.18 by default.
    var accentSoft: NSColor { accent.withAlphaComponent(0.18) }

    /// Glow version — used for the "high pct" warning glow under the meter
    /// and as the second stop in gradient strokes.
    var accentGlow: NSColor { pctMid.withAlphaComponent(0.35) }
}

// MARK: - Surface recipes

enum Surface {
    /// THE card recipe. One definition for every pane.
    /// - fill: controlBackgroundColor at 0.55 light / 0.35 dark
    /// - border: separatorColor at 0.45 alpha, 0.5pt
    /// - corner: Radius.card, continuous
    static func applyCard(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = Radius.card
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 0.5
        refreshCardColors(view)
    }

    static func refreshCardColors(_ view: NSView) {
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Translucent card that floats over the popover/window material. When
        // reduce-transparency is on, fall back to the opaque card so contrast
        // survives.
        let fill: NSColor
        if MotionPrefs.reduceTransparency {
            fill = isDark ? NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 1)  // #2B2A28
                          : NSColor(calibratedWhite: 1.0, alpha: 1)
        } else {
            fill = isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.055)
                          : NSColor(calibratedWhite: 1.0, alpha: 0.72)
        }
        let border = isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.10)
                            : NSColor(calibratedWhite: 0.0, alpha: 0.09)
        view.layer?.backgroundColor = fill.cgColor
        view.layer?.borderColor = border.cgColor
    }

    /// Hero card recipe — larger radius, subtle elevation shadow,
    /// continuous corners. Caller sets the gradient layer separately.
    static func applyHero(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = Radius.hero
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 0.5
        refreshHeroChrome(view)
    }

    static func refreshHeroChrome(_ view: NSView) {
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let border = isDark ? NSColor(calibratedWhite: 1.0, alpha: 0.10)
                            : NSColor(calibratedWhite: 0.0, alpha: 0.09)
        view.layer?.borderColor = border.cgColor
        // Subtle elevation shadow
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOffset = CGSize(width: 0, height: -4)
        view.layer?.shadowRadius = 9 // ~ blur 18 / 2
        view.layer?.shadowOpacity = MotionPrefs.reduceTransparency ? 0 : (isDark ? 0.36 : 0.10)
        view.layer?.masksToBounds = false
    }
}
