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
    static func display(_ size: CGFloat = 28, weight: NSFont.Weight = .semibold) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    static func displayMono(_ size: CGFloat = 28, weight: NSFont.Weight = .semibold) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
    static func title(_ size: CGFloat = 15) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }
    static func body(_ size: CGFloat = 12) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }
    static func bodyMono(_ size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
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
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: -0.4,
        ])
    }
}

// Signature design language: ONE warm clay accent over a neutral gray scale.
// Numbers are always mono + tabular. Values mirror the redesign tokens exactly
// (clay #C2553A/#E68A66, neutral surfaces, amber/red reserved for urgency).
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

    // ---- signature accent (clay / terracotta) ----
    static let accent = dynamicColor(name: "ContextBarAccent") { isDark in
        isDark ? srgb(0xE68A66) : srgb(0xC2553A)
    }
    /// 16% (light) / 22% (dark) accent — chips, glyph wells, hot-bar wash.
    static let accentSoft = dynamicColor(name: "ContextBarAccentSoft") { isDark in
        isDark ? srgb(0xE68A66).withAlphaComponent(0.22) : srgb(0xC2553A).withAlphaComponent(0.16)
    }
    /// 8% (light) / 11% (dark) accent — insight-card fills, faint tints.
    static let accentSofter = dynamicColor(name: "ContextBarAccentSofter") { isDark in
        isDark ? srgb(0xE68A66).withAlphaComponent(0.11) : srgb(0xC2553A).withAlphaComponent(0.08)
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
