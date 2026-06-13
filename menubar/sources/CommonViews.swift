import AppKit
import Foundation

// MARK: - ProgressBarView

final class ProgressBarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true; updateA11y() } }
    var tint: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var gradientEnd: NSColor? { didSet { needsDisplay = true } }
    var trackColor: NSColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.18)
    var corner: CGFloat = 3
    var glow: Bool = false { didSet { needsDisplay = true } }
    /// Threshold tick marks rendered as 1pt vertical lines, in `[0, 1]`.
    /// Empty = no marks. Color follows ctx-color thresholds per mark.
    var tickMarks: [Double] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.progressIndicator)
        updateA11y()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateA11y() {
        let clamped = max(0, min(1, value))
        setAccessibilityValue(NSNumber(value: Int(clamped * 100)))
        setAccessibilityLabel("Progress")
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner)
        trackColor.setFill()
        track.fill()
        let clamped = max(0, min(1, value))
        guard clamped > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let fillRect = NSRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: corner, yRadius: corner)
        ctx.saveGState()
        fillPath.addClip()
        if let end = gradientEnd {
            let cg = CGGradient(colorsSpace: nil,
                                colors: [tint.cgColor, end.cgColor] as CFArray,
                                locations: [0, 1])!
            ctx.drawLinearGradient(cg,
                                   start: CGPoint(x: fillRect.minX, y: 0),
                                   end: CGPoint(x: fillRect.maxX, y: 0),
                                   options: [])
        } else {
            tint.setFill()
            fillPath.fill()
        }
        ctx.restoreGState()
        if !tickMarks.isEmpty {
            ctx.saveGState()
            for raw in tickMarks {
                let t = max(0, min(1, raw))
                let x = bounds.width * CGFloat(t)
                let pctValue = t * 100
                let color: NSColor
                if pctValue >= 90 { color = .systemRed }
                else if pctValue >= 70 { color = .systemOrange }
                else { color = NSColor.tertiaryLabelColor }
                ctx.setFillColor(color.withAlphaComponent(0.85).cgColor)
                ctx.fill(CGRect(x: x - 0.5, y: 0, width: 1, height: bounds.height))
            }
            ctx.restoreGState()
        }
        if glow && !MotionPrefs.reduceTransparency {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6, color: tint.withAlphaComponent(0.55).cgColor)
            tint.withAlphaComponent(0.0).setFill()
            fillPath.fill()
            ctx.restoreGState()
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - SparklineView (gradient area + line + endpoint dot)

/// 30-day sparkline rendered as a smooth gradient-filled area beneath a
/// stroked line, with an emphasized endpoint dot. Replaces the prior
/// bar-style sparkline for a more premium "live ticker" feel.
final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var tint: NSColor = ThemeStore.current.accent { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 56) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("Token usage sparkline")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count >= 2, let maxV = values.max(), maxV > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let n = values.count
        let w = bounds.width
        let h = bounds.height
        let padTop: CGFloat = 6
        let padBottom: CGFloat = 2
        let usableH = h - padTop - padBottom

        func pointAt(_ i: Int) -> CGPoint {
            let x = (n == 1) ? w / 2 : CGFloat(i) * (w / CGFloat(n - 1))
            let norm = CGFloat(values[i] / maxV)
            let y = padBottom + (1 - norm) * usableH
            return CGPoint(x: x, y: y)
        }

        // Line path
        let line = CGMutablePath()
        line.move(to: pointAt(0))
        for i in 1..<n { line.addLine(to: pointAt(i)) }

        // Area path (closed below)
        let area = CGMutablePath()
        area.move(to: CGPoint(x: 0, y: padBottom))
        for i in 0..<n { area.addLine(to: pointAt(i)) }
        area.addLine(to: CGPoint(x: w, y: padBottom))
        area.closeSubpath()

        // Gradient fill
        ctx.saveGState()
        ctx.addPath(area)
        ctx.clip()
        let cg = CGGradient(colorsSpace: nil,
                            colors: [tint.withAlphaComponent(0.22).cgColor,
                                     tint.withAlphaComponent(0.0).cgColor] as CFArray,
                            locations: [0, 1])!
        ctx.drawLinearGradient(cg,
                               start: CGPoint(x: 0, y: padBottom),
                               end: CGPoint(x: 0, y: h),
                               options: [])
        ctx.restoreGState()

        // Stroke line
        ctx.saveGState()
        ctx.setStrokeColor(tint.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(line)
        ctx.strokePath()
        ctx.restoreGState()

        // Endpoint dot
        let last = pointAt(n - 1)
        let dotR: CGFloat = 2.5
        let ringR: CGFloat = 4.5
        ctx.saveGState()
        ctx.setFillColor(tint.withAlphaComponent(0.20).cgColor)
        ctx.fillEllipse(in: CGRect(x: last.x - ringR, y: last.y - ringR, width: ringR * 2, height: ringR * 2))
        ctx.setFillColor(tint.cgColor)
        ctx.fillEllipse(in: CGRect(x: last.x - dotR, y: last.y - dotR, width: dotR * 2, height: dotR * 2))
        ctx.restoreGState()
    }
}

// MARK: - StatTileView (premium — number first, kerned caption below)

final class StatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Radius.card
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        Surface.refreshCardColors(self)

        let val = NSTextField(labelWithString: value)
        val.font = mono
            ? Typography.displayMono(25, weight: .semibold)
            : Typography.display(25, weight: .semibold)
        val.textColor = valueColor
        val.attributedStringValue = NSAttributedString(string: value, attributes: [
            .font: val.font!,
            .foregroundColor: valueColor,
            .kern: -0.3,
        ])
        val.translatesAutoresizingMaskIntoConstraints = false
        val.lineBreakMode = .byTruncatingTail
        val.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cap = NSTextField(labelWithAttributedString: Typography.captionAttributed(caption))
        cap.translatesAutoresizingMaskIntoConstraints = false
        cap.lineBreakMode = .byTruncatingTail

        addSubview(val); addSubview(cap)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            val.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.s),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            cap.topAnchor.constraint(equalTo: val.bottomAnchor, constant: Spacing.xxs),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            cap.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.s),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(caption)
        setAccessibilityValue(value)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

// MARK: - DualStatTileView (primary value + sub caption + UPPERCASE label)

final class DualStatTileView: NSView {
    init(caption: String, value: String, valueColor: NSColor = .labelColor,
         sub: String, mono: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Radius.card
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        Surface.refreshCardColors(self)

        let val = NSTextField(labelWithString: value)
        let valFont = mono
            ? Typography.displayMono(25, weight: .semibold)
            : Typography.display(25, weight: .semibold)
        val.attributedStringValue = NSAttributedString(string: value, attributes: [
            .font: valFont,
            .foregroundColor: valueColor,
            .kern: -0.3,
        ])
        val.translatesAutoresizingMaskIntoConstraints = false
        val.lineBreakMode = .byTruncatingTail

        let cap = NSTextField(labelWithAttributedString: Typography.captionAttributed(caption))
        cap.translatesAutoresizingMaskIntoConstraints = false

        let subLbl = NSTextField(labelWithString: sub)
        subLbl.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subLbl.textColor = .secondaryLabelColor
        subLbl.lineBreakMode = .byTruncatingTail
        subLbl.translatesAutoresizingMaskIntoConstraints = false

        addSubview(val); addSubview(cap); addSubview(subLbl)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            val.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.s),
            val.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            val.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            cap.topAnchor.constraint(equalTo: val.bottomAnchor, constant: Spacing.xxs),
            cap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            cap.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            subLbl.topAnchor.constraint(equalTo: cap.bottomAnchor, constant: Spacing.xxs),
            subLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            subLbl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.s),
            subLbl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.s),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(caption)
        setAccessibilityValue("\(value), \(sub)")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

// MARK: - ClayChipButton

/// Small pill button in the signature accent — accent text + 0.5px accent-soft
/// border over an accent-softer wash (the design's `.cb-chip`). Used for the
/// empty-state "How it works" affordance.
final class ClayChipButton: NSView {
    private let onClick: () -> Void

    init(title: String, symbol: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Radius.chip
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5

        let img = NSImageView()
        img.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        img.contentTintColor = Palette.accent
        img.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        lbl.textColor = Palette.accent
        lbl.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [img, lbl])
        row.orientation = .horizontal
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        refreshColors()
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refreshColors() {
        layer?.backgroundColor = Palette.accentSofter.cgColor
        layer?.borderColor = Palette.accentSoft.cgColor
    }
    override func updateLayer() { refreshColors() }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: - LoadingStripeView

/// Animated diagonal-stripe placeholder used while the engine is producing
/// the first context.json. Static gradient when reduce-motion is on.
final class LoadingStripeView: NSView {
    var tint: NSColor = ThemeStore.current.accent { didSet { needsDisplay = true } }
    private var phase: CGFloat = 0
    private var displayLink: CVDisplayLink?
    /// Last CACurrentMediaTime() at which we hopped to main from the CV
    /// callback. Accessed only on the CV display thread, so no lock.
    private var lastFrameHop: CFTimeInterval = 0

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 4) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityLabel("Loading")
        startAnimating()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { stopAnimating() }

    private func startAnimating() {
        guard !MotionPrefs.reduceMotion else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<LoadingStripeView>.fromOpaque(userInfo).takeUnretainedValue()
            // Throttle to ~30fps. CV display link fires at the panel's refresh
            // rate (often 60–120 Hz). Hopping to main every frame saturates
            // the run loop and shows up on Instruments as needless overhead
            // while the loading state is on screen.
            let now = CACurrentMediaTime()
            if now - view.lastFrameHop < 0.033 { return kCVReturnSuccess }
            view.lastFrameHop = now
            DispatchQueue.main.async {
                view.phase = (view.phase + 1.6).truncatingRemainder(dividingBy: 24)
                view.needsDisplay = true
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopAnimating() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.18).setFill()
        track.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        track.addClip()
        let stripeWidth: CGFloat = 12
        let gap: CGFloat = 12
        let step = stripeWidth + gap
        var x: CGFloat = -bounds.height - step + phase
        tint.withAlphaComponent(0.55).setFill()
        while x < bounds.width + bounds.height {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: 0))
            p.line(to: NSPoint(x: x + stripeWidth, y: 0))
            p.line(to: NSPoint(x: x + stripeWidth + bounds.height, y: bounds.height))
            p.line(to: NSPoint(x: x + bounds.height, y: bounds.height))
            p.close()
            p.fill()
            x += step
        }
        ctx.restoreGState()
    }
}

// MARK: - IncidentBadgeView

/// Inline incident strip used in the hero card meta row when upstream
/// status pages report an active incident. Click opens the status URL.
final class IncidentBadgeView: NSView {
    var state: IncidentState = .none {
        didSet {
            rebuild()
            isHidden = state.severity == .none
        }
    }
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(dot)
        addSubview(label)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        let color: NSColor
        switch state.severity {
        case .critical: color = .systemRed
        case .major: color = .systemOrange
        case .minor: color = .systemYellow
        case .none: color = .clear
        }
        dot.layer?.backgroundColor = color.cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        label.stringValue = state.title
        toolTip = state.url?.absoluteString
    }

    override func mouseDown(with event: NSEvent) {
        if let url = state.url { NSWorkspace.shared.open(url) }
    }
}

/// Native Usage panel — rebuilt per refresh from context.json. One card per agent
/// with stat tiles, window progress bars, active-session strip, and a 30-day
/// sparkline. Replaces the previous webview approach so the panel feels at
/// home on macOS (no scrollbars, no font drift, no white flash).

// MARK: - Shared design primitives (cb-seg-ctrl / popup / switch / glyph / divider / dot)
//
// Faithful AppKit ports of the redesign's reusable controls (docs/macOS UI
// Theme). Used across the popover, Stats, Cost and Settings so every "filter
// button", toggle, glyph well and hairline reads identically.

/// Resolve a dynamic `NSColor` to a concrete `CGColor` for `view`'s current
/// appearance. (A `cgColor` is otherwise frozen at assignment time and won't
/// follow a light/dark switch — re-resolve from `viewDidChangeEffectiveAppearance`.)
fileprivate func cg(_ color: NSColor, _ view: NSView) -> CGColor {
    var out = color.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance { out = color.cgColor }
    return out
}

/// The redesign's segmented "filter button" (`cb-seg-ctrl`): a rounded track
/// with 2pt padding; the selected segment floats on a `card-solid` chip.
final class PillSegmentedControl: NSView {
    private(set) var selectedIndex: Int
    private let onChange: (Int) -> Void
    private var segments: [Segment] = []

    final class Segment: NSView {
        let label = NSTextField(labelWithString: "")
        let onTap: () -> Void
        init(title: String, symbol: String?, onTap: @escaping () -> Void) {
            self.onTap = onTap
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.cornerCurve = .continuous
            translatesAutoresizingMaskIntoConstraints = false
            label.stringValue = title
            label.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            let content: NSView
            if let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
                let iv = NSImageView(image: img)
                iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                iv.translatesAutoresizingMaskIntoConstraints = false
                let row = NSStackView(views: [iv, label])
                row.orientation = .horizontal; row.spacing = 5; row.alignment = .centerY
                row.translatesAutoresizingMaskIntoConstraints = false
                content = row
            } else {
                content = label
            }
            addSubview(content)
            NSLayoutConstraint.activate([
                content.centerYAnchor.constraint(equalTo: centerYAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
                content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
                heightAnchor.constraint(equalToConstant: 22),
            ])
            setAccessibilityRole(.button)
            setAccessibilityLabel(title)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func mouseDown(with event: NSEvent) { onTap() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    }

    init(options: [String], symbols: [String?]? = nil, selectedIndex: Int = 0,
         onChange: @escaping (Int) -> Void) {
        self.selectedIndex = selectedIndex
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Radius.chip
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (i, opt) in options.enumerated() {
            let sym = (symbols != nil && i < symbols!.count) ? symbols![i] : nil
            let seg = Segment(title: opt, symbol: sym) { [weak self] in self?.select(i, notify: true) }
            segments.append(seg)
            stack.addArrangedSubview(seg)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        refreshColors()
        applySelectionStyles()
        setAccessibilityRole(.radioGroup)
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ index: Int, notify: Bool) {
        guard index >= 0, index < segments.count else { return }
        selectedIndex = index
        applySelectionStyles()
        if notify { onChange(index) }
    }

    private func applySelectionStyles() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for (i, seg) in segments.enumerated() {
            let on = i == selectedIndex
            seg.label.textColor = on ? Palette.primaryText : Palette.secondaryText
            if on {
                if isDark {
                    seg.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
                    seg.layer?.shadowOpacity = 0
                } else {
                    seg.layer?.backgroundColor = cg(Palette.cardSolid, self)
                    seg.layer?.shadowColor = NSColor.black.cgColor
                    seg.layer?.shadowOpacity = 0.16
                    seg.layer?.shadowRadius = 1.5
                    seg.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
                    seg.layer?.masksToBounds = false
                }
            } else {
                seg.layer?.backgroundColor = NSColor.clear.cgColor
                seg.layer?.shadowOpacity = 0
            }
        }
    }

    private func refreshColors() {
        layer?.backgroundColor = cg(Palette.track, self)
        layer?.borderColor = cg(Palette.hairline, self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors(); applySelectionStyles()
    }
}

/// The redesign's rounded popup ("Popup"): a `card-solid` pill with a value
/// label and an up/down chevron, opening an `NSMenu` of options.
final class PopupButton: NSView {
    private(set) var selectedIndex: Int
    private(set) var options: [String]
    private let onChange: (Int) -> Void
    private let valueLabel = NSTextField(labelWithString: "")

    init(options: [String], selectedIndex: Int = 0, onChange: @escaping (Int) -> Void) {
        self.options = options
        self.selectedIndex = min(max(0, selectedIndex), max(0, options.count - 1))
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = Palette.primaryText
        valueLabel.stringValue = options.isEmpty ? "" : options[self.selectedIndex]
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.up.chevron.down",
                                                 accessibilityDescription: nil) ?? NSImage())
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = Palette.tertiaryText
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [valueLabel, chevron])
        row.orientation = .horizontal; row.spacing = 8; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        refreshColors()
        setAccessibilityRole(.popUpButton)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Replace the option list (e.g. when the underlying model set changes).
    func setOptions(_ opts: [String], selectedIndex: Int) {
        options = opts
        self.selectedIndex = min(max(0, selectedIndex), max(0, opts.count - 1))
        valueLabel.stringValue = opts.isEmpty ? "" : opts[self.selectedIndex]
    }
    /// Override the displayed value text without changing the option list.
    func setValue(_ string: String) { valueLabel.stringValue = string }

    private func refreshColors() {
        layer?.backgroundColor = cg(Palette.cardSolid, self)
        layer?.borderColor = cg(Palette.hairlineStrong, self)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for (i, opt) in options.enumerated() {
            let item = NSMenuItem(title: opt, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == selectedIndex) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }
    @objc private func pick(_ sender: NSMenuItem) {
        selectedIndex = sender.tag
        if sender.tag < options.count { valueLabel.stringValue = options[sender.tag] }
        onChange(sender.tag)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// The redesign's pill toggle ("Switch"): 34×20 track, accent when on, white knob.
final class PillSwitch: NSView {
    private(set) var isOn: Bool
    private let onToggle: (Bool) -> Void
    private let knob = NSView()
    private var knobLeading: NSLayoutConstraint!

    init(isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.onToggle = onToggle
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
        knob.wantsLayer = true
        knob.layer?.cornerRadius = 8
        knob.layer?.backgroundColor = NSColor.white.cgColor
        knob.layer?.shadowColor = NSColor.black.cgColor
        knob.layer?.shadowOpacity = 0.3
        knob.layer?.shadowRadius = 1
        knob.layer?.shadowOffset = CGSize(width: 0, height: -1)
        knob.layer?.masksToBounds = false
        knob.translatesAutoresizingMaskIntoConstraints = false
        addSubview(knob)
        knobLeading = knob.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isOn ? 16 : 2)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 20),
            knob.widthAnchor.constraint(equalToConstant: 16),
            knob.heightAnchor.constraint(equalToConstant: 16),
            knob.centerYAnchor.constraint(equalTo: centerYAnchor),
            knobLeading,
        ])
        refreshTrack()
        setAccessibilityRole(.checkBox)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setOn(_ on: Bool, animated: Bool = false) {
        isOn = on
        knobLeading.constant = on ? 16 : 2
        refreshTrack()
        setAccessibilityValue(on)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                layoutSubtreeIfNeeded()
            }
        }
    }
    private func refreshTrack() {
        layer?.backgroundColor = isOn ? cg(Palette.accent, self) : cg(Palette.track, self)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshTrack() }
    override func mouseDown(with event: NSEvent) { setOn(!isOn, animated: true); onToggle(isOn) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// The redesign's glyph well (`cb-glyph`): a rounded square holding a centered
/// SF Symbol (accent) or a brand image, over an accent-soft / neutral wash.
final class GlyphWell: NSView {
    private var bg: NSColor = Palette.accentSoft

    init(symbol: String, size: CGFloat = 28, iconSize: CGFloat = 16,
         tint: NSColor = Palette.accent, background: NSColor = Palette.accentSoft) {
        super.init(frame: .zero)
        commonInit(size: size, background: background)
        let iv = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        iv.contentTintColor = tint
        place(iv, iconSize: iconSize)
    }
    init(image: NSImage, size: CGFloat = 28, iconSize: CGFloat = 16,
         background: NSColor = Palette.accentSoft) {
        super.init(frame: .zero)
        commonInit(size: size, background: background)
        let iv = NSImageView(image: image)
        iv.imageScaling = .scaleProportionallyUpOrDown
        place(iv, iconSize: iconSize)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func commonInit(size: CGFloat, background: NSColor) {
        bg = background
        wantsLayer = true
        layer?.cornerRadius = Radius.chip
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        refreshBg()
    }
    private func place(_ iv: NSImageView, iconSize: CGFloat) {
        iv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: iconSize),
            iv.heightAnchor.constraint(equalToConstant: iconSize),
        ])
    }
    private func refreshBg() { layer?.backgroundColor = cg(bg, self) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshBg() }
}

/// The redesign's hairline (`cb-div`) — a 1px separator following `Palette.hairline`.
final class DividerView: NSView {
    init(vertical: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        if vertical {
            widthAnchor.constraint(equalToConstant: 1).isActive = true
            setContentHuggingPriority(.required, for: .horizontal)
        } else {
            heightAnchor.constraint(equalToConstant: 1).isActive = true
            setContentHuggingPriority(.required, for: .vertical)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func refresh() { layer?.backgroundColor = cg(Palette.hairline, self) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    override func updateLayer() { refresh() }
}

/// The redesign's status dot (`cb-dot`): `.live` adds the soft accent halo ring,
/// `.idle` is a muted grey, `.accent` is a plain accent dot.
final class StatusDotView: NSView {
    enum DotState { case live, idle, accent }
    private var state: DotState
    private let diameter: CGFloat

    init(state: DotState = .live, diameter: CGFloat = 8) {
        self.state = state
        self.diameter = diameter
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let total = diameter + 6   // room for the 3pt live halo
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: total),
            heightAnchor.constraint(equalToConstant: total),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setState(_ s: DotState) { state = s; needsDisplay = true }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let r = diameter / 2
        let color: NSColor = (state == .idle) ? Palette.tertiaryText : Palette.accent
        if state == .live {
            ctx.setFillColor(Palette.accentSofter.cgColor)
            let halo = r + 3
            ctx.fillEllipse(in: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2))
        }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }
}
