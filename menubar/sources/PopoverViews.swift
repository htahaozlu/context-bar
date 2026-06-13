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

/// Single-row entry used for the "Other tools" list inside the popover,
/// matching popover.jsx: [glyph well][name (flex)][tokens][freq (right,
/// 50pt)][model (right, 52pt)]. The glyph well shows the brand logo when an
/// asset exists, else a neutral symbol over the quiet wash.
final class OtherToolRowView: NSView {
    init(tool: ToolSummary) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // Leading glyph well (cb-glyph): brand image else a generic tool glyph,
        // on the neutral `track` wash to match the spec's `bg="var(--quiet-2)"`.
        let glyph: GlyphWell
        if let url = agentIconURL(name: tool.name), let img = NSImage(contentsOf: url) {
            glyph = GlyphWell(image: img, size: 22, iconSize: 13, background: Palette.track)
        } else {
            glyph = GlyphWell(
                symbol: "terminal", size: 22, iconSize: 13,
                tint: Palette.secondaryText, background: Palette.track)
        }
        glyph.toolTip = tool.name

        let nameLbl = NSTextField(labelWithString: tool.name)
        nameLbl.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        nameLbl.textColor = Palette.primaryText
        nameLbl.lineBreakMode = .byTruncatingTail
        nameLbl.cell?.usesSingleLineMode = true
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        nameLbl.toolTip = tool.name
        nameLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Token total — mono, secondary (popover.jsx `t.tok`).
        let tok = NSTextField(
            labelWithString: tool.tokens7d > 0 ? ContextSnapshot.formatTokens(tool.tokens7d) : "")
        tok.font = Typography.bodyMono(11, weight: .regular)
        tok.textColor = Palette.secondaryText
        tok.alignment = .right
        tok.setContentHuggingPriority(.required, for: .horizontal)
        tok.translatesAutoresizingMaskIntoConstraints = false

        // Frequency column (`t.freq`, width 50).
        let freqStr = tool.sessions7d > 0 ? "\(tool.sessions7d)×/\(L10n.text("wk", "hf"))" : ""
        let freq = NSTextField(labelWithString: freqStr)
        freq.font = Typography.bodyMono(10.5, weight: .regular)
        freq.textColor = Palette.tertiaryText
        freq.alignment = .right
        freq.lineBreakMode = .byTruncatingTail
        freq.translatesAutoresizingMaskIntoConstraints = false

        // Model column (`t.model`, width 52).
        let model = NSTextField(labelWithString: tool.lastModel ?? "")
        model.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        model.textColor = Palette.tertiaryText
        model.alignment = .right
        model.lineBreakMode = .byTruncatingTail
        model.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [glyph, nameLbl, tok, freq, model])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = Spacing.xs
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            freq.widthAnchor.constraint(equalToConstant: 50),
            model.widthAnchor.constraint(equalToConstant: 52),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A transparent row wrapper that turns its content into a click target with a
/// pointing-hand cursor. Used to make parallel-session rows (and the hero card)
/// open the session-detail popover. The closure fires on `mouseUp` inside the
/// bounds so a press-then-drag-away cancels like a normal button.
final class ClickableRowView: NSView {
    private let onClick: () -> Void

    init(content: NSView, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if bounds.contains(p) { onClick() }
    }
}

/// Session "context detail" surface — a richer, honest analog of Claude Code's
/// `/context`. Hosted in a transient `NSPopover` anchored to the clicked row /
/// hero card. Builds its own top-down layout from an `ActiveSession` plus the
/// owning agent's name. The centrepiece is the context-window FILL bar (used vs
/// free of `ctxWindow`); below it sit the token composition (total · sub-agent
/// share · est. cost), session timing, and a one-line honest note that the
/// exact `/context` category split lives only inside Claude Code.
final class SessionDetailView: NSView {
    static let preferredWidth: CGFloat = 320

    /// Fired after the async "context loaded each turn" estimate populates and
    /// the view's intrinsic height changes, so the hosting popover can re-measure
    /// `fittingSize` and grow its `contentSize` (it's sized once at show time and
    /// would otherwise clip rows added later). Set by the controller; called on
    /// the main thread.
    var onContentResize: (() -> Void)?

    /// The whole "context loaded each turn" section (divider + caption + rows),
    /// wrapped so it can be collapsed as a unit when the estimate turns out
    /// empty (no Claude loader attachments at all). nil for sessions with no
    /// Claude transcript (Codex / synthetic).
    private weak var loadersSection: NSStackView?
    /// The "calculating…" placeholder shown inside the loaders stack until the
    /// estimate resolves. Removed when real rows arrive (the inner stack is
    /// passed directly to `populateLoaders`, so it isn't stored here).
    private weak var loadersPlaceholder: NSView?

    init(session: ActiveSession, agentName: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let pad: CGFloat = Spacing.m
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            widthAnchor.constraint(equalToConstant: Self.preferredWidth),
        ])

        // ── Header: brand glyph · agent + model (pretty) · project ──
        let glyph: GlyphWell
        if let url = agentIconURL(name: agentName), let img = NSImage(contentsOf: url) {
            glyph = GlyphWell(image: img, size: 26, iconSize: 15, background: Palette.accentSofter)
        } else {
            glyph = GlyphWell(symbol: "sparkle", size: 26, iconSize: 15, background: Palette.accentSofter)
        }
        glyph.toolTip = AgentVisual.forName(agentName).accessibilityLabel

        var titleParts: [String] = [agentName]
        if let m = session.model { titleParts.append(Self.prettyModel(m)) }
        let titleLbl = NSTextField(labelWithString: titleParts.joined(separator: " · "))
        titleLbl.font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        titleLbl.textColor = Palette.primaryText
        titleLbl.lineBreakMode = .byTruncatingTail
        titleLbl.cell?.usesSingleLineMode = true
        titleLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let projLbl = NSTextField(labelWithString: session.project)
        projLbl.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        projLbl.textColor = Palette.secondaryText
        projLbl.lineBreakMode = .byTruncatingTail
        projLbl.cell?.usesSingleLineMode = true
        projLbl.toolTip = session.project
        projLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleCol = NSStackView(views: [titleLbl, projLbl])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 1
        let header = NSStackView(views: [glyph, titleCol])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = Spacing.xs
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // ── Centrepiece: context-window fill (used vs free) ──
        // Closest faithful analog to `/context`'s used / free split that the
        // available data supports. Shown only when we actually have a live
        // ctxPct (an idle/historical session has no current fill to report).
        if let pct = session.ctxPct {
            stack.addArrangedSubview(DividerView().widthPinned(to: stack))
            let cap = NSTextField(
                labelWithAttributedString:
                    Typography.captionAttributed(L10n.text("Context window", "Bağlam penceresi")))
            stack.addArrangedSubview(cap)

            // Headline line: "32.5% · 325k / 1.0M tokens · 675k free"
            let clamped = max(0, min(100, pct))
            var parts: [String] = [String(format: "%.1f%%", clamped)]
            if let w = session.ctxWindow, w > 0 {
                let used = UInt64((Double(w) * clamped / 100.0).rounded())
                let free = w > used ? w - used : 0
                parts.append(
                    "\(ContextSnapshot.formatTokens(used)) / \(ContextSnapshot.formatTokens(w)) "
                        + L10n.text("tokens", "token"))
                parts.append(
                    "\(ContextSnapshot.formatTokens(free)) " + L10n.text("free", "boş"))
            }
            let fillLbl = NSTextField(labelWithString: parts.joined(separator: "  ·  "))
            fillLbl.font = Typography.bodyMono(11.5, weight: .medium)
            fillLbl.textColor = Palette.secondaryText
            fillLbl.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(fillLbl)

            // Thick fill bar with the urgency tint (accent → amber ≥75 → red ≥90).
            let bar = ProgressBarView()
            bar.value = clamped / 100.0
            bar.tint = Self.urgencyTint(clamped)
            bar.gradientEnd = clamped >= 75 ? Self.urgencyTint(min(100, clamped + 12)) : nil
            bar.corner = 4
            bar.glow = clamped >= 75
            if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.setAccessibilityLabel(L10n.text("Context usage", "Bağlam kullanımı"))
            stack.addArrangedSubview(bar)
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 10).isActive = true
        }

        // ── Token composition the data supports ──
        // total session tokens, sub-agent burn (+ its share %), estimated cost.
        stack.addArrangedSubview(DividerView().widthPinned(to: stack))
        let compCap = NSTextField(
            labelWithAttributedString:
                Typography.captionAttributed(L10n.text("Tokens this session", "Bu oturumdaki token")))
        stack.addArrangedSubview(compCap)

        stack.addArrangedSubview(
            Self.kvRow(
                label: L10n.text("Total", "Toplam"),
                value: ContextSnapshot.formatTokens(session.tokens),
                valueColor: Palette.primaryText
            ).widthPinned(to: stack))

        if session.subagentTokens > 0 {
            let share = session.tokens > 0
                ? Double(session.subagentTokens) / Double(session.tokens) * 100.0 : 0
            let shareStr = share > 0 ? String(format: "  (%.0f%%)", share) : ""
            stack.addArrangedSubview(
                Self.kvRow(
                    label: L10n.text("Sub-agents", "Alt-ajanlar"),
                    value: ContextSnapshot.formatTokens(session.subagentTokens) + shareStr,
                    valueColor: Palette.secondaryText
                ).widthPinned(to: stack))
        }

        if session.cost > 0 {
            stack.addArrangedSubview(
                Self.kvRow(
                    label: L10n.text("Est. cost", "Tah. maliyet"),
                    value: ContextSnapshot.formatUSD(session.cost),
                    valueColor: Palette.accent
                ).widthPinned(to: stack))
        }

        // ── That day's usage for this project ──
        // The session is one slice of a day's work on a project; surface the
        // whole day's rollup for the same project (engine `by_day_project`) so
        // clicking a session also answers "how much on <project> that day?".
        let day = session.lastTurn ?? session.started ?? Date()
        if let usage = Self.dayProjectUsage(agentName: agentName, project: session.project, on: day) {
            stack.addArrangedSubview(DividerView().widthPinned(to: stack))
            stack.addArrangedSubview(NSTextField(
                labelWithAttributedString: Typography.captionAttributed(
                    Self.isToday(day)
                        ? L10n.text("Today · this project", "Bugün · bu proje")
                        : L10n.text("That day · this project", "O gün · bu proje"))))
            stack.addArrangedSubview(
                Self.kvRow(label: L10n.text("Tokens", "Token"),
                           value: ContextSnapshot.formatTokens(usage.tokens),
                           valueColor: Palette.primaryText).widthPinned(to: stack))
            if usage.sessions > 0 {
                stack.addArrangedSubview(
                    Self.kvRow(label: L10n.text("Sessions", "Oturum"),
                               value: "\(usage.sessions)",
                               valueColor: Palette.secondaryText).widthPinned(to: stack))
            }
            if usage.cost > 0 {
                stack.addArrangedSubview(
                    Self.kvRow(label: L10n.text("Cost", "Maliyet"),
                               value: ContextSnapshot.formatUSD(usage.cost),
                               valueColor: Palette.accent).widthPinned(to: stack))
            }
        }

        // ── Timing: started → last turn (duration) · relative "active Xm ago" ──
        if session.started != nil || session.lastTurn != nil {
            stack.addArrangedSubview(DividerView().widthPinned(to: stack))
            let timeCap = NSTextField(
                labelWithAttributedString:
                    Typography.captionAttributed(L10n.text("Timing", "Zamanlama")))
            stack.addArrangedSubview(timeCap)

            let duration = ContextSnapshot.formatDuration(session.started, session.lastTurn)
            if duration != "—" {
                stack.addArrangedSubview(
                    Self.kvRow(
                        label: L10n.text("Duration", "Süre"),
                        value: duration,
                        valueColor: Palette.secondaryText
                    ).widthPinned(to: stack))
            }
            if let last = session.lastTurn {
                stack.addArrangedSubview(
                    Self.kvRow(
                        label: L10n.text("Last turn", "Son tur"),
                        value: ContextSnapshot.relative(last),
                        valueColor: Palette.secondaryText
                    ).widthPinned(to: stack))
            }
        }

        // ── Context loaded each turn (≈ estimate) ── (CLAUDE sessions only) ──
        // The feasible, truthful slice of `/context`: the persistent loaders that
        // are re-injected into the window every turn (CLAUDE.md memory, MCP
        // instructions, the skills/agents listing, deferred tools). Sizes are
        // estimated from the session's transcript on a background queue and
        // filled in below; system prompt + built-in tool schemas live only in
        // the CC binary and are intentionally NOT reconstructed here.
        if Self.canEstimateLoaders(session: session, agentName: agentName) {
            // Whole section wrapped in one stack so an empty estimate can collapse
            // divider + caption + rows together (no orphaned header).
            let section = NSStackView()
            section.orientation = .vertical
            section.alignment = .leading
            section.spacing = Spacing.xs
            section.translatesAutoresizingMaskIntoConstraints = false

            section.addArrangedSubview(DividerView().widthPinned(to: section))
            let loadersCap = NSTextField(
                labelWithAttributedString:
                    Typography.captionAttributed(
                        L10n.text("Context loaded each turn · ≈ est",
                                  "Her turda yüklenen bağlam · ≈ tahmini")))
            section.addArrangedSubview(loadersCap)

            let lstack = NSStackView()
            lstack.orientation = .vertical
            lstack.alignment = .leading
            lstack.spacing = Spacing.xs
            lstack.translatesAutoresizingMaskIntoConstraints = false
            section.addArrangedSubview(lstack)
            lstack.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            self.loadersSection = section

            let placeholder = NSTextField(
                labelWithString: L10n.text("calculating…", "hesaplanıyor…"))
            placeholder.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            placeholder.textColor = Palette.tertiaryText
            lstack.addArrangedSubview(placeholder)
            self.loadersPlaceholder = placeholder

            Self.estimateLoaders(sessionID: session.id) { [weak self] est in
                self?.populateLoaders(est, stack: lstack)
            }
        }

        // ── Honest note — the exact /context split lives only in Claude Code ──
        stack.addArrangedSubview(DividerView().widthPinned(to: stack))
        let note = NSTextField(
            wrappingLabelWithString: L10n.text(
                "The full /context split (system prompt · built-in tools) is computed inside Claude Code and isn't saved to disk — these loader sizes are estimated from your transcript.",
                "Tam /context dökümü (sistem istemi · yerleşik araçlar) Claude Code içinde hesaplanır, diske yazılmaz — bu yükleyici boyutları transkriptinden tahmin edilir."
            ))
        note.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        note.textColor = Palette.tertiaryText
        note.maximumNumberOfLines = 0
        note.preferredMaxLayoutWidth = Self.preferredWidth - 2 * pad
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Label (left, secondary) + mono value (right) row, full-width.
    private static func kvRow(label: String, value: String, valueColor: NSColor) -> NSView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        lbl.textColor = Palette.secondaryText
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let val = NSTextField(labelWithString: value)
        val.font = Typography.bodyMono(11.5, weight: .semibold)
        val.textColor = valueColor
        val.alignment = .right
        val.lineBreakMode = .byTruncatingTail
        val.setContentHuggingPriority(.required, for: .horizontal)
        val.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [lbl, spacer, val])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = Spacing.xs
        return row
    }

    // MARK: - That day's per-project usage

    private struct DayProjectUsage { let tokens: UInt64; let sessions: Int; let cost: Double }

    /// Sums the engine's `by_day_project` rollup for one agent · project · day
    /// (read straight from the snapshot JSON, same source as the sparkline).
    /// Returns nil when the day/project has no row so the section is omitted.
    private static func dayProjectUsage(
        agentName: String, project: String, on day: Date
    ) -> DayProjectUsage? {
        let path = ContextSnapshot.resolveSnapshotPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agent = root[agentName.lowercased()] as? [String: Any],
              let rows = agent["by_day_project"] as? [[String: Any]] else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: day)
        var tokens: UInt64 = 0, sessions = 0, cost = 0.0, found = false
        for r in rows where (r["date"] as? String) == key && (r["project"] as? String) == project {
            found = true
            tokens += jsonU64(r["tokens"])
            sessions += Int(jsonU64(r["sessions"]))
            cost += jsonDouble(r["cost"])
        }
        return found ? DayProjectUsage(tokens: tokens, sessions: sessions, cost: cost) : nil
    }

    private static func isToday(_ d: Date) -> Bool { Calendar.current.isDateInToday(d) }

    private static func jsonU64(_ v: Any?) -> UInt64 {
        if let n = v as? UInt64 { return n }
        if let n = v as? Int, n >= 0 { return UInt64(n) }
        if let d = v as? Double, d.isFinite, d >= 0 { return UInt64(d) }
        if let num = v as? NSNumber { return num.uint64Value }
        return 0
    }

    private static func jsonDouble(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let num = v as? NSNumber { return num.doubleValue }
        return 0
    }

    // MARK: - Context-loaded-each-turn estimate (CLAUDE sessions)

    /// Per-category estimated CHAR totals for the persistent loaders that Claude
    /// Code re-injects into the context every turn. Tokens are derived as
    /// `ceil(chars / 4)` at render time so the math stays in one place. All four
    /// are honest approximations of `/context`'s loader lines — never the full
    /// window split.
    private struct LoaderEstimate {
        var memoryChars = 0          // nested_memory (summed)
        var mcpChars = 0            // mcp_instructions_delta addedBlocks (summed)
        var skillsChars = 0        // skill_listing — LARGEST content seen
        var deferredChars = 0      // deferred_tools_delta addedLines — largest snapshot
        var deferredCount = 0      // deferred_tools_delta addedNames count (net of removed)
        var isEmpty: Bool {
            memoryChars == 0 && mcpChars == 0 && skillsChars == 0 && deferredChars == 0
        }
    }

    /// Only Claude sessions backed by a real transcript can be estimated. Codex
    /// sessions (id maps to ~/.codex, no attachments) and the synthesized
    /// "<agent>-hero" placeholder session (no file on disk) are skipped — the
    /// caller then renders only the existing exact content.
    private static func canEstimateLoaders(session: ActiveSession, agentName: String) -> Bool {
        if agentName.caseInsensitiveCompare("Codex") == .orderedSame { return false }
        if session.id.hasSuffix("-hero") { return false }
        if session.id.isEmpty { return false }
        return true
    }

    /// Locates `~/.claude/projects/*/<id>.jsonl` (the session id is the filename
    /// stem), reads + parses it on a background queue, and calls `completion` on
    /// the MAIN thread with the accumulated estimate. If no transcript is found
    /// or it has no loader attachments, `completion` still fires (with an empty
    /// estimate) so the placeholder can be cleared.
    private static func estimateLoaders(
        sessionID: String, completion: @escaping (LoaderEstimate) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var est = LoaderEstimate()
            if let url = transcriptURL(for: sessionID) {
                est = parseTranscript(at: url)
            }
            DispatchQueue.main.async { completion(est) }
        }
    }

    /// First `<id>.jsonl` directly under any `~/.claude/projects/<proj>/` dir.
    /// Claude main sessions live exactly one level under a project dir, so a
    /// shallow scan over the project subdirs is enough (and cheap). Returns nil
    /// for Codex / unknown ids.
    private static func transcriptURL(for sessionID: String) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let target = "\(sessionID).jsonl"
        guard let projDirs = try? fm.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return nil }
        for dir in projDirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let candidate = dir.appendingPathComponent(target)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Reads the JSONL transcript line-by-line, cheap-filtering out any line that
    /// doesn't mention `attachment` before paying for a JSON decode, and sums the
    /// four loader categories' char totals. Tolerant of malformed lines and the
    /// two observed `nested_memory.content` shapes (a `{path,type,content}` dict
    /// — the on-disk form — or a bare string).
    private static func parseTranscript(at url: URL) -> LoaderEstimate {
        var est = LoaderEstimate()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return est }
        raw.enumerateLines { line, _ in
            guard line.contains("\"attachment\"") else { return }
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "attachment",
                  let att = obj["attachment"] as? [String: Any],
                  let kind = att["type"] as? String
            else { return }

            switch kind {
            case "nested_memory":
                // On disk `content` is a `{path,type,content}` dict; fall back to
                // a bare string for forward/backward tolerance.
                if let dict = att["content"] as? [String: Any],
                   let text = dict["content"] as? String {
                    est.memoryChars += text.count
                } else if let text = att["content"] as? String {
                    est.memoryChars += text.count
                }
            case "mcp_instructions_delta":
                if let blocks = att["addedBlocks"] as? [String] {
                    est.mcpChars += blocks.reduce(0) { $0 + $1.count }
                }
            case "skill_listing":
                // The listing is re-sent in full as it grows — take the LARGEST
                // snapshot, not a sum of deltas.
                if let content = att["content"] as? String {
                    est.skillsChars = max(est.skillsChars, content.count)
                }
            case "deferred_tools_delta":
                // The deferred-tool list accretes across deltas (added − removed
                // is the live set). Sum the added names/lines and net out removals
                // from the count so the figure tracks what's actually loaded.
                if let names = att["addedNames"] as? [String] {
                    est.deferredCount += names.count
                }
                if let removed = att["removedNames"] as? [String] {
                    est.deferredCount = max(0, est.deferredCount - removed.count)
                }
                if let lines = att["addedLines"] as? [String] {
                    // +1 per line approximates the newline joining the listing.
                    est.deferredChars += lines.reduce(0) { $0 + $1.count + 1 }
                }
            default:
                break
            }
        }
        return est
    }

    /// Main-thread render of the resolved estimate into the pre-built loaders
    /// stack: one row per non-zero category + a summed total, then asks the
    /// hosting popover to re-measure (it was sized before these rows existed).
    /// An all-empty estimate (no Claude attachments at all) hides the section
    /// entirely rather than showing a row of zeros.
    private func populateLoaders(_ est: LoaderEstimate, stack: NSStackView) {
        loadersPlaceholder?.removeFromSuperview()
        loadersPlaceholder = nil

        if est.isEmpty {
            // No Claude loader attachments at all — collapse the entire section
            // (divider + caption + rows) so there's no orphaned header.
            loadersSection?.isHidden = true
            onContentResize?()
            return
        }

        func tokens(_ chars: Int) -> UInt64 { UInt64((Double(max(0, chars)) / 4.0).rounded(.up)) }

        var total: UInt64 = 0
        if est.memoryChars > 0 {
            let t = tokens(est.memoryChars); total += t
            stack.addArrangedSubview(
                Self.loaderRow(
                    label: L10n.text("CLAUDE.md memory", "CLAUDE.md hafıza"),
                    tokens: t, color: Palette.secondaryText
                ).widthPinned(to: stack))
        }
        if est.mcpChars > 0 {
            let t = tokens(est.mcpChars); total += t
            stack.addArrangedSubview(
                Self.loaderRow(
                    label: L10n.text("MCP instructions", "MCP yönergeleri"),
                    tokens: t, color: Palette.secondaryText
                ).widthPinned(to: stack))
        }
        if est.skillsChars > 0 {
            let t = tokens(est.skillsChars); total += t
            stack.addArrangedSubview(
                Self.loaderRow(
                    label: L10n.text("Skills / agents", "Beceriler / ajanlar"),
                    tokens: t, color: Palette.secondaryText
                ).widthPinned(to: stack))
        }
        if est.deferredChars > 0 {
            let t = tokens(est.deferredChars); total += t
            let label = L10n.text(
                "Deferred tools (\(est.deferredCount))", "Ertelenmiş araçlar (\(est.deferredCount))")
            stack.addArrangedSubview(
                Self.loaderRow(label: label, tokens: t, color: Palette.secondaryText)
                    .widthPinned(to: stack))
        }

        // Summed total (accent, mono) — the bottom line of "what the loaders add".
        stack.addArrangedSubview(DividerView().widthPinned(to: stack))
        stack.addArrangedSubview(
            Self.loaderRow(
                label: L10n.text("Total loaders", "Toplam yükleyici"),
                tokens: total, color: Palette.primaryText, emphasised: true
            ).widthPinned(to: stack))

        onContentResize?()
    }

    /// One loader row: left label (secondary) + right mono "≈ Nk" token estimate.
    /// `emphasised` bumps the label to medium/primary for the total line.
    private static func loaderRow(
        label: String, tokens: UInt64, color: NSColor, emphasised: Bool = false
    ) -> NSView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 11.5, weight: emphasised ? .medium : .regular)
        lbl.textColor = emphasised ? Palette.primaryText : Palette.secondaryText
        lbl.lineBreakMode = .byTruncatingTail
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let val = NSTextField(labelWithString: "≈ " + approxTokenString(tokens))
        val.font = Typography.bodyMono(11.5, weight: .semibold)
        val.textColor = color
        val.alignment = .right
        val.lineBreakMode = .byTruncatingTail
        val.setContentHuggingPriority(.required, for: .horizontal)
        val.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [lbl, spacer, val])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = Spacing.xs
        return row
    }

    /// Compact token string for the estimate ("3.6k", "12k", "940"). Mirrors
    /// `ContextSnapshot.formatTokens`'s scale but without the agent-facing exact
    /// path; kept local so the loaders math owns its own rounding.
    private static func approxTokenString(_ value: UInt64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 10_000 { return String(format: "%.0fk", Double(value) / 1_000.0) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000.0) }
        return "\(value)"
    }

    /// Urgency tint matching the menubar gauge: calm accent, amber ≥75, red ≥90.
    private static func urgencyTint(_ pct: Double) -> NSColor {
        if pct >= 90 { return Palette.urgencyRed }
        if pct >= 75 { return Palette.urgencyAmber }
        return Palette.accent
    }

    /// Self-contained model-id prettifier (mirrors the panes' `prettyModelName`,
    /// which is private to their controllers). Maps `claude-opus-4-8[1m]` →
    /// "Opus 4.8 (1M)", `gpt-5-...` → "GPT-5", etc.; unknown ids pass through.
    static func prettyModel(_ id: String) -> String {
        let m = id.lowercased()
        let suffix = m.contains("[1m]") || m.contains("-1m") ? " (1M)" : ""
        let base: String
        switch true {
        case m.contains("opus-4-9"): base = "Opus 4.9"
        case m.contains("opus-4-8"): base = "Opus 4.8"
        case m.contains("opus-4-7"): base = "Opus 4.7"
        case m.contains("opus-4-6"): base = "Opus 4.6"
        case m.contains("opus-4-5"): base = "Opus 4.5"
        case m.contains("opus-4"): base = "Opus 4"
        case m.contains("sonnet-4-7"): base = "Sonnet 4.7"
        case m.contains("sonnet-4-6"): base = "Sonnet 4.6"
        case m.contains("sonnet-4-5"): base = "Sonnet 4.5"
        case m.contains("sonnet-4"): base = "Sonnet 4"
        case m.contains("haiku-4-5"): base = "Haiku 4.5"
        case m.contains("haiku-4"): base = "Haiku 4"
        case m.contains("gpt-5-5"), m.contains("gpt-5.5"): base = "GPT-5.5"
        case m.contains("gpt-5"): base = "GPT-5"
        case m.contains("gpt-4"): base = "GPT-4"
        case m.contains("mythos"): base = "Claude Mythos"
        default: return id
        }
        return base + suffix
    }
}

/// Pins a view's width to a stack's width and returns it, for fluent use inside
/// `addArrangedSubview(...)` chains in `SessionDetailView`.
private extension NSView {
    func widthPinned(to stack: NSStackView) -> NSView {
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return self
    }
}

/// Popover content view controller. Card-based layout — each section is a
/// rounded card laid out in a single vertical stack with NSStackView's
/// .width alignment so every card spans the full content width (minus
/// stack edge insets) regardless of its intrinsic content. Rebuilt on
/// every show so the panel reflects the most recent context.json.
