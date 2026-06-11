import AppKit
import Foundation

final class MenubarCardView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Surface.applyCard(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

/// Hero card — the single SOLID surface in the popover. Everything else floats
/// as translucent cards on the OS popover material; the hero anchors the panel
/// with an opaque fill and a 2.5pt accent stripe across its top edge (the lone
/// chromatic note). Border + elevation shadow come from `Surface.applyHero`.
final class MenubarHeroCardView: NSView {
    /// Clipped body layer: holds the opaque fill and the accent stripe so both
    /// honour the rounded top corners. The view's own layer keeps the shadow
    /// (which needs `masksToBounds = false`), so the two concerns stay split.
    private let body = CALayer()
    private let stripe = CALayer()
    private let stripeHeight: CGFloat = 2.5

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Surface.applyHero(self)
        body.cornerRadius = Radius.hero
        body.cornerCurve = .continuous
        body.masksToBounds = true
        body.addSublayer(stripe)
        layer?.insertSublayer(body, at: 0)
        applyFill()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        body.frame = bounds
        // Layer space is bottom-left origin (view is not flipped) → the stripe
        // sits at the top edge.
        stripe.frame = CGRect(x: 0, y: bounds.height - stripeHeight,
                              width: bounds.width, height: stripeHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshHeroChrome(self)
        applyFill()
    }

    private func applyFill() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let solid = isDark ? NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 1)  // #2B2A28
                           : NSColor(calibratedWhite: 1.0, alpha: 1)
        body.backgroundColor = solid.cgColor
        // Resolve the dynamic accent against this view's appearance.
        var accentCG = Palette.accent.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            accentCG = Palette.accent.cgColor
        }
        stripe.backgroundColor = accentCG
    }
}

/// Compact stat tile used inside the 3-column grid. Caption sits above a
/// large monospaced value, with an optional faded sub-line for context like
/// "resets in 2h".
final class CompactStatView: NSView {
    init(caption: String, value: String, valueColor: NSColor, sub: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Surface.applyCard(self)

        let cap = NSTextField(labelWithAttributedString: Typography.captionAttributed(caption))
        cap.translatesAutoresizingMaskIntoConstraints = false

        let val = NSTextField(labelWithString: value)
        val.font = Typography.displayMono(17, weight: .semibold)
        val.textColor = valueColor
        val.lineBreakMode = .byTruncatingTail
        val.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cap); addSubview(val)
        let padH: CGFloat = Spacing.s
        let padV: CGFloat = Spacing.s
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
        Surface.refreshCardColors(self)
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
        setAccessibilityRole(.image)
        setAccessibilityLabel("Agent activity")
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
        setAccessibilityValue(isActive ? "Active" : "Idle")
        guard let layer = self.layer else { return }
        layer.removeAnimation(forKey: "pulse")
        guard isActive, !MotionPrefs.reduceMotion else { return }
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
    /// Square overlay that hosts the icon while spinning so rotation pivots on
    /// the symbol centre instead of the 30×28 button bounds (which would slide
    /// the icon off-axis and rotate the hover background too).
    private let iconLayer = CALayer()
    private var iconImage: NSImage?

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
            self.iconImage = img
            self.image = img
        }
        self.contentTintColor = .secondaryLabelColor
        self.setAccessibilityLabel(tooltip)
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 30),
            self.heightAnchor.constraint(equalToConstant: 28),
        ])
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.isHidden = true
        iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(iconLayer)
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

    /// "Working" indicator on the refresh button. Replaces the prior
    /// mechanical full-rotation spin with a calm breathe — opacity dips and
    /// the symbol scales down ~12% then back. Reads as "active" without the
    /// helicopter look. Skipped under reduce-motion (just dim the icon).
    func setSpinning(_ on: Bool) {
        if on {
            guard let img = iconImage else { return }
            let side: CGFloat = 16
            let tinted = tintedIcon(img, color: contentTintColor ?? .secondaryLabelColor)
            iconLayer.contents = tinted
            iconLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            iconLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            iconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            iconLayer.isHidden = false
            self.image = nil
            if MotionPrefs.reduceMotion {
                iconLayer.opacity = 0.55
                return
            }
            let opacityAnim = CABasicAnimation(keyPath: "opacity")
            opacityAnim.fromValue = 1.0
            opacityAnim.toValue = 0.35
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 1.0
            scaleAnim.toValue = 0.88
            let group = CAAnimationGroup()
            group.animations = [opacityAnim, scaleAnim]
            group.duration = 0.85
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            iconLayer.add(group, forKey: "breathe")
        } else {
            iconLayer.removeAnimation(forKey: "breathe")
            iconLayer.opacity = 1.0
            iconLayer.isHidden = true
            self.image = iconImage
        }
    }

    override func layout() {
        super.layout()
        iconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func tintedIcon(_ image: NSImage, color: NSColor) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        rep?.size = size
        guard let rep, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
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
        if tool.tokens7d > 0 { parts.append(ContextSnapshot.formatTokens(tool.tokens7d)) }
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
/// every show so the panel reflects the most recent context.json.
