import AppKit
import Foundation

final class MenubarCardView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.05)
            : NSColor.black.withAlphaComponent(0.04)).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
    }
}

/// Compact stat tile used inside the 3-column grid. Caption sits above a
/// large monospaced value, with an optional faded sub-line for context like
/// "resets in 2h".
final class CompactStatView: NSView {
    init(caption: String, value: String, valueColor: NSColor, sub: String? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false
        updateColors()

        let cap = NSTextField(labelWithString: caption.uppercased())
        cap.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        cap.textColor = .tertiaryLabelColor
        cap.translatesAutoresizingMaskIntoConstraints = false

        let val = NSTextField(labelWithString: value)
        val.font = NSFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
        val.textColor = valueColor
        val.lineBreakMode = .byTruncatingTail
        val.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cap); addSubview(val)
        let padH: CGFloat = 12
        let padV: CGFloat = 10
        var constraints: [NSLayoutConstraint] = [
            cap.topAnchor.constraint(equalTo: topAnchor, constant: padV),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padH),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padH),
            val.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: 4),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padH),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padH),
        ]
        if let sub {
            let sublbl = NSTextField(labelWithString: sub)
            sublbl.font = NSFont.systemFont(ofSize: 10)
            sublbl.textColor = .secondaryLabelColor
            sublbl.lineBreakMode = .byTruncatingTail
            sublbl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sublbl)
            constraints.append(contentsOf: [
                sublbl.topAnchor.constraint(equalTo: val.bottomAnchor, constant: 3),
                sublbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padH),
                sublbl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padH),
                sublbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padV),
                heightAnchor.constraint(equalToConstant: 80),
            ])
        } else {
            constraints.append(contentsOf: [
                val.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padV),
                heightAnchor.constraint(equalToConstant: 64),
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
    }
}

/// Pulsing activity indicator dot. Animates while the agent is considered
/// "live" (has fired a turn in the recent window).
final class ActivityDotView: NSView {
    var isActive: Bool = false { didSet { restartIfNeeded() } }
    override var intrinsicContentSize: NSSize { NSSize(width: 10, height: 10) }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 5
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let color: NSColor = isActive ? .systemGreen : .tertiaryLabelColor
        layer?.backgroundColor = color.cgColor
    }

    private func restartIfNeeded() {
        updateAppearance()
        guard let layer = self.layer else { return }
        layer.removeAnimation(forKey: "pulse")
        guard isActive else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.35
        anim.duration = 1.1
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "pulse")
    }
}

/// Borderless square toolbar button used in the popover footer. Renders an
/// SF Symbol over a hover-highlighted rounded background.
final class FooterIconButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(symbol: String, tooltip: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.toolTip = tooltip
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.title = ""
        self.imagePosition = .imageOnly
        self.wantsLayer = true
        self.layer?.cornerRadius = 7
        self.layer?.cornerCurve = .continuous
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(cfg) {
            self.image = img
        }
        self.contentTintColor = .secondaryLabelColor
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 30),
            self.heightAnchor.constraint(equalToConstant: 28),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
}

/// Single-row entry used for the "Other tools" list inside the popover.
/// Brand icon (left) + tool name + usage stats line (right column).
final class OtherToolRowView: NSView {
    init(tool: ToolSummary) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let nameLbl = agentInlineLabel(
            name: tool.name,
            font: NSFont.systemFont(ofSize: 12, weight: .medium),
            color: .labelColor,
            iconScale: 1.0
        )
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        nameLbl.toolTip = tool.name

        var parts: [String] = []
        if tool.tokens7d > 0 { parts.append(Hud.formatTokens(tool.tokens7d)) }
        if tool.sessions7d > 0 { parts.append("\(tool.sessions7d)×/\(L10n.text("wk", "hf"))") }
        if let m = tool.lastModel { parts.append(m) }
        let info = NSTextField(labelWithString: parts.joined(separator: " · "))
        info.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        info.textColor = .secondaryLabelColor
        info.alignment = .right
        info.lineBreakMode = .byTruncatingTail
        info.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameLbl); addSubview(info)
        NSLayoutConstraint.activate([
            nameLbl.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            info.trailingAnchor.constraint(equalTo: trailingAnchor),
            info.centerYAnchor.constraint(equalTo: centerYAnchor),
            info.leadingAnchor.constraint(greaterThanOrEqualTo: nameLbl.trailingAnchor, constant: 8),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Popover content view controller. Card-based layout — each section is a
/// rounded card laid out in a single vertical stack with NSStackView's
/// .width alignment so every card spans the full content width (minus
/// stack edge insets) regardless of its intrinsic content. Rebuilt on
/// every show so the panel reflects the most recent hud.json.
