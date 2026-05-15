import AppKit
import Foundation

final class ProgressBarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var tint: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var trackColor: NSColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.18)
    var corner: CGFloat = 3

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner)
        trackColor.setFill()
        track.fill()
        let clamped = max(0, min(1, value))
        guard clamped > 0 else { return }
        let fillRect = NSRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: corner, yRadius: corner)
        tint.setFill()
        fill.fill()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Compact 30-day sparkline drawn with rounded mini bars. Highlights the most
/// recent day to give an at-a-glance sense of recent burn vs trend.
final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var tint: NSColor = .controlAccentColor

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 56) }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty, let maxV = values.max(), maxV > 0 else { return }
        let n = values.count
        let gap: CGFloat = 2
        let totalGap = gap * CGFloat(n - 1)
        let barW = max(2, (bounds.width - totalGap) / CGFloat(n))
        for (i, v) in values.enumerated() {
            let h = max(2, CGFloat(v / maxV) * (bounds.height - 4))
            let x = CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: bounds.height - h, width: barW, height: h)
            let color = (i == n - 1) ? tint : tint.withAlphaComponent(0.45)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

/// Custom NSView used inside an NSMenuItem to render a per-window limit row
/// with a horizontal progress bar showing window-elapsed fraction.
final class LimitRowView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let pctField   = NSTextField(labelWithString: "")
    private let resetField = NSTextField(labelWithString: "")
    private let bar        = ProgressBarView()

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 38) }

    init(label: String, percent: Double?, reset: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 38))

        let pctText = percent.map { String(format: "%.0f%%", $0) } ?? "—"
        let barValue = (percent ?? 0) / 100.0
        let barColor: NSColor = {
            guard let p = percent else { return .controlAccentColor }
            if p >= 90 { return .systemRed }
            if p >= 70 { return .systemOrange }
            return .systemGreen
        }()

        labelField.stringValue = label
        labelField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        labelField.textColor = .secondaryLabelColor
        labelField.translatesAutoresizingMaskIntoConstraints = false

        pctField.stringValue = pctText
        pctField.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        pctField.textColor = barColor
        pctField.translatesAutoresizingMaskIntoConstraints = false

        resetField.stringValue = "↻ \(reset)"
        resetField.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
        resetField.textColor = .tertiaryLabelColor
        resetField.alignment = .right
        resetField.translatesAutoresizingMaskIntoConstraints = false

        bar.value = barValue
        bar.tint = barColor
        bar.corner = 2
        bar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelField); addSubview(pctField); addSubview(resetField); addSubview(bar)
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            labelField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            labelField.widthAnchor.constraint(equalToConstant: 36),

            pctField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 6),
            pctField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),

            resetField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            resetField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),

            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bar.topAnchor.constraint(equalTo: labelField.bottomAnchor, constant: 5),
            bar.heightAnchor.constraint(equalToConstant: 4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Stat tile — a small native card with a caption + big value. Used in the
/// Usage tab to surface tokens / sessions / context % at a glance.
final class StatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.borderWidth = 1

        let cap = NSTextField(labelWithString: caption.uppercased())
        cap.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        cap.textColor = .tertiaryLabelColor
        cap.translatesAutoresizingMaskIntoConstraints = false

        let val = NSTextField(labelWithString: value)
        val.font = mono
            ? NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
            : NSFont.systemFont(ofSize: 20, weight: .semibold)
        val.textColor = valueColor
        val.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cap)
        addSubview(val)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cap.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            val.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: 4),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            val.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Stat tile with caption + primary value + faded sub-value. Lets each tile
/// surface a number (eg "3.4M") alongside its context (eg "resets in 2h").
final class DualStatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor,
         sub: String, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 0

        let cap = NSTextField(labelWithString: caption)
        cap.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        cap.textColor = .secondaryLabelColor
        cap.translatesAutoresizingMaskIntoConstraints = false

        let val = NSTextField(labelWithString: value)
        val.font = mono
            ? NSFont.monospacedSystemFont(ofSize: 22, weight: .medium)
            : NSFont.systemFont(ofSize: 22, weight: .semibold)
        val.textColor = valueColor
        val.translatesAutoresizingMaskIntoConstraints = false

        let subLbl = NSTextField(labelWithString: sub)
        subLbl.font = NSFont.systemFont(ofSize: 10)
        subLbl.textColor = .secondaryLabelColor
        subLbl.lineBreakMode = .byTruncatingTail
        subLbl.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cap); addSubview(val); addSubview(subLbl)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cap.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            val.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: 4),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            subLbl.topAnchor.constraint(equalTo: val.bottomAnchor, constant: 4),
            subLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            subLbl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            subLbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Native Usage panel — rebuilt per refresh from hud.json. One card per agent
/// with stat tiles, window progress bars, active-session strip, and a 30-day
/// sparkline. Replaces the previous webview approach so the panel feels at
/// home on macOS (no scrollbars, no font drift, no white flash).
