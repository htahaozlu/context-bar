import AppKit
import Foundation

final class MenubarPopoverViewController: NSViewController {
    static let contentWidth: CGFloat = 360
    private static let activeToolWindow: TimeInterval = 30 * 60
    private let hPad: CGFloat = Spacing.m
    private let vGap: CGFloat = Spacing.s
    private var didShowOnce = false
    /// SHA-ish fingerprint of the snapshot the last rebuild rendered. When the
    /// next refresh tick computes the same fingerprint we skip the teardown to
    /// stop the popover from flashing on every 10s tick.
    private var lastSnapshotKey: String?

    var onOpenSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onShare: ((NSView) -> Void)?
    /// Called at the end of every rebuild with the freshly measured content
    /// size. The host forces `NSPopover.contentSize` from it so the panel
    /// SHRINKS as well as grows — `preferredContentSize` alone only grows the
    /// popover; it keeps its tallest frame on shrink, leaving a blank band.
    var onSized: ((NSSize) -> Void)?

    private let visualEffect = NSVisualEffectView()
    private let contentStack = NSStackView()

    /// Held weakly so the button — which lives on a stack rebuilt every show —
    /// can be told to spin while a manual refresh is in flight without taking
    /// ownership of view lifetime.
    private weak var refreshBtn: FooterIconButton?
    /// Last manual-refresh click; debounces double-clicks so we don't queue
    /// duplicate engine runs when a user hammers the button.
    private var lastRefreshClickAt: Date?

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true

        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(visualEffect)

        contentStack.orientation = .vertical
        // `.width` alignment stretches every arranged subview to the stack's
        // inset content rectangle. The companion `setHuggingPriority(.required,
        // for: .horizontal)` lifts the stretch constraint to required so
        // cards whose inner content hugs strongly (short headers, narrow
        // rows) can't shrink the card away from the stack edge. Horizontal
        // padding lives in `edgeInsets`; `addCard` adds no per-card pins.
        contentStack.spacing = Spacing.s
        // `.notAnAttribute` tells NSStackView to install NO implicit
        // horizontal alignment constraint. Every horizontal pin then comes
        // exclusively from `addCard` — no priority race, no flush-left /
        // right-gap split. Vertical insets stay on the stack so it still
        // lays out top-to-bottom with the right top/bottom breathing room.
        contentStack.alignment = .notAnAttribute
        // Tight outer gutter. Wider values repeatedly read as dead space at
        // the top and right of the shipped menubar popover.
        contentStack.edgeInsets = NSEdgeInsets(
            top: Spacing.xxs, left: 0,
            bottom: Spacing.xxs, right: 0
        )
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: root.topAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])
        view = root
    }

    func rebuild() {
        // One instant for the whole pass — every 30-min-cutoff visibility check
        // (parallel sessions, other tools) must agree, or a card can flap in/out
        // mid-rebuild and the measured size won't match what's drawn.
        let now = Date()
        let snapshot = ContextSnapshot()
        let (active, all, others) = snapshot.load()
        let primary = active ?? all.first
        let activeOthers = others.filter { isActivelyUsed($0, now: now) }
        // Parallel-session visibility is time-dependent but NOT reflected in the
        // raw session timestamps the key already hashes, so fold the visible
        // count in explicitly. Without this, a session aging past the 30-min
        // cutoff leaves the key byte-identical → the early-bail fires → the
        // parallel card is never removed and the popover never shrinks.
        let parallelVisible = primary.map { parallelSessions(for: $0, now: now).count } ?? 0
        let key = snapshotKey(
            active: active, primary: primary, all: all,
            others: activeOthers, parallelVisible: parallelVisible)
        // Engine returned — stop the manual-refresh spinner whether or not the
        // snapshot key actually changed. If the footer gets rebuilt below the
        // call is a no-op against the new button.
        refreshBtn?.setSpinning(false)
        // Bail early when nothing the popover renders has changed — this is
        // the cheapest fix for the 10s tick flicker (no teardown, no relayout).
        if key == lastSnapshotKey, !contentStack.arrangedSubviews.isEmpty {
            return
        }
        lastSnapshotKey = key

        // Suppress implicit CAAnimations so the rebuild swap doesn't crossfade
        // sublayers — that was the source of the visible flash when the active
        // sessions array changed shape between ticks.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if let agent = primary {
            // Card order: hero (active session) → parallel sessions →
            // usage limits → other tools.
            addCard(buildHero(agent: agent, isActive: agent.name == active?.name))
            if hasParallelSessions(agent: agent, now: now) {
                addCard(buildParallelSessions(agent: agent, now: now))
            }
            if hasSecondaryData(agent) {
                addCard(buildUsageLimits(agent))
            }
        } else {
            // Before the engine has produced a context.json (first launch / cache
            // miss after purge) show the loading stripe instead of the
            // "no agent" empty state — the latter falsely implies the user has
            // nothing running.
            let snapshotExists = FileManager.default.fileExists(atPath: snapshot.path)
            if snapshotExists {
                addCard(buildEmptyState())
            } else {
                addCard(buildLoadingState())
            }
        }
        if !activeOthers.isEmpty {
            addCard(buildOthers(tools: activeOthers))
        }
        addCard(buildFooter())

        view.layoutSubtreeIfNeeded()
        CATransaction.commit()
        // DON'T use view.fittingSize: once the popover is shown it pins the root
        // view to fill the popover window, so view.fittingSize reports the
        // window-IMPOSED height (never shrinking) instead of the natural content
        // height. Sum the cards directly — each card hugs its content vertically
        // (addCard sets required hugging) so its own fittingSize is accurate and
        // immune to the window's imposed size.
        let subs = contentStack.arrangedSubviews
        var contentH = contentStack.edgeInsets.top + contentStack.edgeInsets.bottom
        contentH += contentStack.spacing * CGFloat(max(0, subs.count - 1))
        for v in subs { contentH += v.fittingSize.height }
        let target = NSSize(width: Self.contentWidth, height: max(contentH, 1))
        preferredContentSize = target
        // Drive the popover frame explicitly so it contracts on shrink, not just
        // expands on grow (see `onSized`). Host no-ops when the popover isn't
        // shown — the pre-show rebuild is sized by `show()` from preferredContentSize.
        onSized?(target)

        // First-show fade-in. Subsequent rebuilds skip this so the panel
        // doesn't flicker on data refresh.
        if !didShowOnce, !MotionPrefs.reduceMotion {
            didShowOnce = true
            let t = CATransition()
            t.type = .fade
            t.duration = 0.20
            contentStack.layer?.add(t, forKey: "fadeIn")
        }
    }

    /// Adds a section view to the popover stack. Width is enforced by the
    /// stack's `.width` alignment + `edgeInsets`; no per-card L/R constraints
    /// here (those used to fight NSStackView's implicit alignment constraint
    /// and made the hero card jitter between flush-left and over-stretched).
    private func addCard(_ v: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.required, for: .vertical)
        v.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.addArrangedSubview(v)
        // Single horizontal source of truth. Keep this intentionally tight:
        // wider card gutters have repeatedly read as dead space on the right
        // side of the popover once the app is packaged and shown from the
        // menubar chrome.
        let pad: CGFloat = Spacing.xs
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: pad),
            v.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -pad),
        ])
    }

    // MARK: - Sections

    /// Returns a (card, contentStack) pair. The content stack is constrained
    /// inside the card with consistent 14h/12v padding. Callers add content to
    /// the stack and the card auto-sizes its height while filling the popover
    /// width via the parent contentStack's `.width` alignment.
    private func sectionContainer(hero: Bool = false) -> (NSView, NSStackView) {
        let card: NSView = hero ? MenubarHeroCardView() : MenubarCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        let pad: CGFloat = hero ? Spacing.m : Spacing.s
        // Symmetric internal padding. The hero's extra top breathing is now
        // supplied by the popover's uniform outer gutter, so its own insets
        // can stay even on all sides.
        let topPad: CGFloat = pad
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: topPad),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -pad),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -pad),
        ])
        return (card, stack)
    }

    private func buildLoadingState() -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.alignment = .leading
        stack.spacing = Spacing.s

        let title = NSTextField(
            labelWithString: L10n.text("Gathering session data…", "Oturum verileri toplanıyor…"))
        title.font = Typography.title(14)
        title.textColor = .labelColor

        let sub = NSTextField(
            wrappingLabelWithString: L10n.text(
                "Scanning Claude and Codex transcripts. This usually takes a second.",
                "Claude ve Codex transcript'leri taranıyor. Genellikle bir saniye sürer."
            ))
        sub.font = Typography.body(11)
        sub.textColor = .secondaryLabelColor
        sub.maximumNumberOfLines = 0
        sub.preferredMaxLayoutWidth = Self.contentWidth - 2 * hPad

        let stripe = LoadingStripeView()
        stripe.tint = Palette.accent
        stripe.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(sub)
        stack.addArrangedSubview(stripe)
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stripe.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stripe.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return container
    }

    private func buildEmptyState() -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.alignment = .centerX
        stack.spacing = Spacing.s

        let cfg = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iv.contentTintColor = .tertiaryLabelColor
        iv.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(
            labelWithString: L10n.text("No agent data yet", "Henüz ajan verisi yok"))
        title.font = Typography.title(14)
        title.textColor = .labelColor
        title.alignment = .center

        let sub = NSTextField(
            wrappingLabelWithString: L10n.text(
                "Start a Claude or Codex session to see context and limits here.",
                "Bağlam ve limitleri görmek için Claude veya Codex oturumu başlatın."
            ))
        sub.font = Typography.body(11)
        sub.textColor = .secondaryLabelColor
        sub.alignment = .center
        sub.maximumNumberOfLines = 0
        sub.preferredMaxLayoutWidth = Self.contentWidth - 2 * hPad

        stack.addArrangedSubview(iv)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(sub)
        sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return container
    }

    private func buildHero(agent a: Agent, isActive: Bool) -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.spacing = Spacing.s

        // ── Header row: ● + project (left)  ·  brand glyph well (right) ──
        // Inline "●" keeps the dot baseline-locked to the project name without
        // cap-height math; it warms to the accent while the agent is live and
        // greys to tertiary text when idle.
        let dotColor: NSColor = isActive ? Palette.accent : Palette.tertiaryText
        let title = NSMutableAttributedString()
        title.append(
            NSAttributedString(
                string: "●  ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: dotColor,
                    .baselineOffset: 2,
                ]))
        title.append(
            NSAttributedString(
                string: a.project,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: Palette.primaryText,
                    .kern: -0.2,
                ]))
        let projectLbl = NSTextField(labelWithAttributedString: title)
        projectLbl.lineBreakMode = .byTruncatingTail
        projectLbl.maximumNumberOfLines = 1
        projectLbl.cell?.usesSingleLineMode = true
        projectLbl.toolTip = a.project
        projectLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Brand glyph in a soft accent well (28pt). Keeps the real provider
        // logo (not a generic glyph) inside the design's tinted chip; the
        // `accentSofter` token resolves to the same warm clay wash in both
        // appearances so we don't have to hand-roll srgb per mode.
        let well = NSView()
        well.translatesAutoresizingMaskIntoConstraints = false
        well.wantsLayer = true
        well.layer?.cornerRadius = Radius.chip
        well.layer?.cornerCurve = .continuous
        well.layer?.backgroundColor = Palette.accentSofter.cgColor
        let brandView = NSImageView()
        if let url = agentIconURL(name: a.name), let img = NSImage(contentsOf: url) {
            brandView.image = img
        }
        brandView.imageScaling = .scaleProportionallyUpOrDown
        brandView.translatesAutoresizingMaskIntoConstraints = false
        brandView.toolTip = AgentVisual.forName(a.name).accessibilityLabel
        well.addSubview(brandView)
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 28),
            well.heightAnchor.constraint(equalToConstant: 28),
            brandView.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            brandView.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            brandView.widthAnchor.constraint(equalToConstant: 16),
            brandView.heightAnchor.constraint(equalToConstant: 16),
        ])
        let headSpacer = NSView()
        headSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let headerRow = NSStackView(views: [projectLbl, headSpacer, well])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.distribution = .fill
        headerRow.spacing = Spacing.xs

        // ── Hero metric row: caption + big % (left)  ·  token detail (right) ──
        // Context % is a live-session signal — blank it when the session is
        // idle so an old fill level doesn't read as the current one.
        let pct = isActive ? a.ctxPct : nil
        let pctInt = pct.map { String(format: "%.0f", $0) } ?? "—"
        // Big number stays NEUTRAL (primaryText) — the bar carries the
        // urgency color; a coloured giant number was too loud in the redesign.
        let bigNum = NSMutableAttributedString(
            string: pctInt,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: Palette.primaryText,
                .kern: -1.0,
            ])
        if pct != nil {
            bigNum.append(
                NSAttributedString(
                    string: "%",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
                        .foregroundColor: Palette.secondaryText,
                    ]))
        }
        let bigLbl = NSTextField(labelWithAttributedString: bigNum)
        bigLbl.setContentHuggingPriority(.required, for: .horizontal)
        bigLbl.setContentCompressionResistancePriority(.required, for: .horizontal)
        let capLbl = NSTextField(
            labelWithAttributedString:
                Typography.captionAttributed(L10n.text("Context window", "Bağlam penceresi")))
        let leftCol = NSStackView(views: [capLbl, bigLbl])
        leftCol.orientation = .vertical
        leftCol.alignment = .leading
        leftCol.spacing = 2

        let used = a.activeSession
        // Used tokens over "/ <window> tokens". When the session is idle we
        // surface its last-active time instead of a stale token count so an
        // old fill level can't read as the current one.
        let usedText: String
        let usedColor: NSColor
        if isActive {
            usedText = ContextSnapshot.formatTokens(used)
            usedColor = Palette.primaryText
        } else {
            usedText = a.lastTurn.map { _ in L10n.text("idle", "boşta") }
                ?? L10n.text("idle", "boşta")
            usedColor = Palette.tertiaryText
        }
        let usedLbl = NSTextField(labelWithString: usedText)
        usedLbl.font = Typography.bodyMono(13, weight: .semibold)
        usedLbl.textColor = usedColor
        usedLbl.alignment = .right
        let winText: String
        if !isActive {
            // No live session — report when it was last active rather than a
            // fixed window the idle session is no longer filling.
            winText = a.lastTurn.map {
                L10n.text("last active \(ContextSnapshot.relative($0))",
                          "son aktif \(ContextSnapshot.relative($0))")
            } ?? L10n.text("no active session", "aktif oturum yok")
        } else if let w = a.ctxWindow {
            winText = "/ \(ContextSnapshot.formatTokens(w)) " + L10n.text("tokens", "token")
        } else if used > 0 {
            winText = L10n.text("session", "oturum")
        } else {
            winText = L10n.text("window unknown", "pencere bilinmiyor")
        }
        let winLbl = NSTextField(labelWithString: winText)
        winLbl.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        winLbl.textColor = Palette.tertiaryText
        winLbl.alignment = .right
        let rightCol = NSStackView(views: [usedLbl, winLbl])
        rightCol.orientation = .vertical
        rightCol.alignment = .trailing
        rightCol.spacing = 1
        rightCol.setContentHuggingPriority(.required, for: .horizontal)

        let metricSpacer = NSView()
        metricSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let metricRow = NSStackView(views: [leftCol, metricSpacer, rightCol])
        metricRow.orientation = .horizontal
        metricRow.alignment = .bottom
        metricRow.distribution = .fill
        metricRow.spacing = Spacing.s

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(metricRow)
        headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        metricRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // ── Context meter (thick 8pt). Glow when hot; accent fill throughout. ──
        let bar = ProgressBarView()
        bar.value = pct.map { max(0, min(1, $0 / 100.0)) } ?? 0
        bar.tint = Palette.accent
        bar.gradientEnd = Palette.urgencyAmber
        bar.corner = 3
        bar.glow = (pct ?? 0) >= 75
        if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setAccessibilityLabel(L10n.text("Context usage", "Bağlam kullanımı"))

        // ── Meta row: agent · model (left)  ·  last turn · running (right) ──
        var leftParts: [String] = [a.name]
        if let m = a.model { leftParts.append(m) }
        let metaLeft = NSTextField(labelWithString: leftParts.joined(separator: " · "))
        metaLeft.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        metaLeft.textColor = Palette.secondaryText
        metaLeft.lineBreakMode = .byTruncatingTail
        metaLeft.maximumNumberOfLines = 1
        metaLeft.cell?.usesSingleLineMode = true
        metaLeft.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var rightParts: [String] = []
        if let t = a.lastTurn { rightParts.append(ContextSnapshot.relative(t)) }
        // Only claim the session is "running" when it is genuinely live; an
        // idle agent shows just its last-active time, not a fake live duration.
        let duration = ContextSnapshot.formatDuration(a.sessionStarted, a.lastTurn)
        if isActive, duration != "—" {
            rightParts.append(L10n.text("\(duration) running", "\(duration) aktif"))
        }
        let metaRight = NSTextField(labelWithString: rightParts.joined(separator: " · "))
        metaRight.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        metaRight.textColor = Palette.tertiaryText
        metaRight.alignment = .right
        metaRight.setContentHuggingPriority(.required, for: .horizontal)
        let metaSpacer = NSView()
        metaSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let metaRow = NSStackView(views: [metaLeft, metaSpacer, metaRight])
        metaRow.orientation = .horizontal
        metaRow.alignment = .firstBaseline
        metaRow.distribution = .fill
        metaRow.spacing = Spacing.xs

        stack.addArrangedSubview(bar)
        stack.addArrangedSubview(metaRow)
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        metaRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Incident strip — visible only when IncidentPoller surfaces an
        // active upstream incident. Click opens the status page.
        let incident = IncidentBadgeView()
        incident.state = IncidentPoller.shared.current
        if !incident.isHidden {
            stack.addArrangedSubview(incident)
            incident.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        // Celebration trigger — once per window rollover.
        if DisplayPrefs.confetti,
            Celebration.consumeReset(
                a.session5hResetsAt, key: "\(a.name).\(Celebration.session5hKey())")
                || Celebration.consumeReset(
                    a.week7dResetsAt, key: "\(a.name).\(Celebration.week7dKey())")
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak container] in
                guard let container else { return }
                Celebration.burst(in: container)
            }
        }
        return container
    }

    @available(*, deprecated)
    private func buildContextMeter(agent a: Agent, pct: Double) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 6

        let label = NSTextField(labelWithString: L10n.text("Context", "Bağlam"))
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor

        let pctStr = String(format: "%.0f%%", pct)
        let pctLbl = NSTextField(labelWithString: pctStr)
        pctLbl.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        pctLbl.textColor = ContextSnapshot.ctxColor(pct)

        let used = a.activeSession
        let detailText =
            a.ctxWindow.map { w in
                "\(ContextSnapshot.formatTokens(used)) / \(ContextSnapshot.formatTokens(w))"
            } ?? ContextSnapshot.formatTokens(used)
        let detail = NSTextField(labelWithString: detailText)
        detail.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .tertiaryLabelColor
        detail.alignment = .right

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let headerRow = NSStackView(views: [label, spacer, pctLbl, detail])
        headerRow.orientation = .horizontal
        headerRow.alignment = .firstBaseline
        headerRow.distribution = .fill
        headerRow.spacing = 6

        let bar = ProgressBarView()
        bar.value = max(0, min(1, pct / 100.0))
        bar.tint = ContextSnapshot.ctxColor(pct)
        bar.corner = 2.5
        bar.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(bar)
        headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 5).isActive = true
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return container
    }

    private func hasSecondaryData(_ a: Agent) -> Bool {
        if a.session5h > 0 || a.session5hPercent != nil { return true }
        if a.week7d > 0 || a.week7dPercent != nil { return true }
        if a.activeSession > 0 { return true }
        return false
    }

    /// Single usage-limits card for the hero agent. Background agents surface
    /// through the parallel / other-tools cards so the popover keeps one clear
    /// primary hierarchy instead of stacking equally loud limit blocks.
    private func buildUsageLimits(_ a: Agent) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = Spacing.xs

        let caption = sectionCaption(
            Typography.captionAttributed(L10n.text("Usage limits", "Kullanım limitleri"))
        )
        stack.addArrangedSubview(caption)
        caption.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        var metaParts: [String] = []
        metaParts.append(a.name)
        if let m = a.model { metaParts.append(m) }
        if let t = a.lastTurn { metaParts.append(ContextSnapshot.relative(t)) }
        let meta = NSTextField(labelWithString: metaParts.joined(separator: " · "))
        meta.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        meta.textColor = Palette.secondaryText
        meta.lineBreakMode = .byTruncatingTail
        meta.maximumNumberOfLines = 1

        stack.addArrangedSubview(meta)
        meta.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        var rows: [NSView] = []
        let showsRemaining = a.name.caseInsensitiveCompare("Codex") == .orderedSame
        if a.session5hPercent != nil || a.session5h > 0 {
            rows.append(
                makeLimitRow(
                    label: L10n.text("5h limit", "5sa limit"),
                    percent: a.session5hPercent,
                    fallbackValue: ContextSnapshot.formatTokens(a.session5h),
                    resetsAt: a.session5hResetsAt,
                    showsRemaining: showsRemaining
                ))
        }
        if a.week7dPercent != nil || a.week7d > 0 {
            rows.append(
                makeLimitRow(
                    label: L10n.text("7d limit", "7g limit"),
                    percent: a.week7dPercent,
                    fallbackValue: ContextSnapshot.formatTokens(a.week7d),
                    resetsAt: a.week7dResetsAt,
                    showsRemaining: showsRemaining
                ))
        }
        if a.activeSession > 0 {
            rows.append(
                makeSimpleStatRow(
                    label: L10n.text("Session total", "Oturum toplam"),
                    value: ContextSnapshot.formatTokens(a.activeSession),
                    valueColor: .secondaryLabelColor
                ))
        }
        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    /// Limit row with inline progress bar: label + percent + reset on top line,
    /// full-width bar below. Bar color tracks the usage threshold.
    private func makeLimitRow(
        label: String, percent: Double?, fallbackValue: String, resetsAt: Date?,
        showsRemaining: Bool = false
    ) -> NSView {
        let color = usageColor(percent)
        let valueText: String = {
            guard let percent else { return fallbackValue }
            if showsRemaining {
                return ContextSnapshot.formatRemainingValue(percentUsed: percent, tokens: 0)
            }
            return String(format: "%.0f%%", percent)
        }()

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.textColor = .labelColor

        let val = NSTextField(labelWithString: valueText)
        val.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        val.textColor = color

        let resetLbl: NSTextField? = resetsAt.map { _ in
            let l = NSTextField(labelWithString: "↻ \(ContextSnapshot.resetsText(resetsAt))")
            l.font = NSFont.systemFont(ofSize: 10)
            l.textColor = .tertiaryLabelColor
            return l
        }

        let rightStack = NSStackView()
        rightStack.orientation = .horizontal
        rightStack.alignment = .firstBaseline
        rightStack.spacing = 8
        rightStack.addArrangedSubview(val)
        if let r = resetLbl { rightStack.addArrangedSubview(r) }

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let header = NSStackView(views: [lbl, spacer, rightStack])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.distribution = .fill
        header.spacing = 6

        let bar = ProgressBarView()
        bar.value = max(0, min(1, (percent ?? 0) / 100.0))
        bar.tint = color
        bar.corner = 2
        if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
        bar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, bar])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return stack
    }

    /// Simple key/value row without a bar — used for stats that aren't a
    /// proportion of a known budget (e.g. raw session token counter).
    private func makeSimpleStatRow(label: String, value: String, valueColor: NSColor) -> NSView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.textColor = .labelColor

        let val = NSTextField(labelWithString: value)
        val.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        val.textColor = valueColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [lbl, spacer, val])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// "Parallel Sessions" card — one row per concurrent Claude/Codex session
    /// other than the hero (foreground) one. Each row shows the project name +
    /// model on top, a thin context-percent bar underneath, the percent text +
    /// last-turn relative time on the right. Capped at 5 rows; a "+N more"
    /// footer appears if exceeded. Caller is responsible for only invoking
    /// this when `hasParallelSessions(agent:)` returns true.
    private func parallelSessions(for a: Agent, now: Date = Date()) -> [ActiveSession] {
        let recentCutoff = now.addingTimeInterval(-Self.activeToolWindow)
        let foregroundCwd = a.cwd
        return a.activeSessions.filter { sess in
            guard (sess.lastTurn ?? .distantPast) >= recentCutoff else {
                return false
            }
            if let fg = foregroundCwd, !fg.isEmpty {
                let proj = (fg as NSString).lastPathComponent
                return sess.project != proj
            }
            return sess.id != a.activeSessions.first?.id
        }
    }

    private func hasParallelSessions(agent a: Agent, now: Date = Date()) -> Bool {
        !parallelSessions(for: a, now: now).isEmpty
    }

    private func buildParallelSessions(agent a: Agent, now: Date = Date()) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = Spacing.xs

        let header = sectionCaption(
            Typography.captionAttributed(L10n.text("Parallel Sessions", "Paralel oturumlar"))
        )
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let allOthers = parallelSessions(for: a, now: now)
        let cap = 5
        let shown = Array(allOthers.prefix(cap))
        let overflow = max(0, allOthers.count - cap)

        for sess in shown {
            stack.addArrangedSubview(makeParallelSessionRow(sess))
            stack.arrangedSubviews.last?.widthAnchor.constraint(equalTo: stack.widthAnchor)
                .isActive = true
        }

        if overflow > 0 {
            let more = NSTextField(
                labelWithString: L10n.text("+ \(overflow) more", "+ \(overflow) daha"))
            more.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            more.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(more)
        }
        return container
    }

    private func isActivelyUsed(_ tool: ToolSummary, now: Date = Date()) -> Bool {
        guard let lastUsed = parseISODate(tool.lastUsed) else { return false }
        return now.timeIntervalSince(lastUsed) <= Self.activeToolWindow
    }

    private func parseISODate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso.date(from: raw) { return parsed }
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        return isoNoFrac.date(from: raw)
    }

    /// Single row inside the parallel-sessions card: project · model on top
    /// row, capsule progress bar + percent + last-turn time below.
    private func makeParallelSessionRow(_ sess: ActiveSession) -> NSView {
        let proj = NSTextField(labelWithString: sess.project)
        proj.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        proj.textColor = .labelColor
        proj.lineBreakMode = .byTruncatingMiddle
        proj.cell?.usesSingleLineMode = true
        proj.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var metaParts: [String] = []
        if let m = sess.model { metaParts.append(m) }
        if let t = sess.lastTurn { metaParts.append(ContextSnapshot.relative(t)) }
        let meta = NSTextField(labelWithString: metaParts.joined(separator: " · "))
        meta.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        meta.textColor = .tertiaryLabelColor
        meta.lineBreakMode = .byTruncatingTail
        meta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pctStr = sess.ctxPct.map { String(format: "%.0f%%", $0) } ?? "—"
        let pctLbl = NSTextField(labelWithString: pctStr)
        pctLbl.font = Typography.bodyMono(11, weight: .semibold)
        pctLbl.textColor = usageColor(sess.ctxPct)
        pctLbl.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let topRow = NSStackView(views: [proj, spacer, pctLbl])
        topRow.orientation = .horizontal
        topRow.alignment = .firstBaseline
        topRow.distribution = .fill
        topRow.spacing = Spacing.xs

        let bar = ProgressBarView()
        if let p = sess.ctxPct {
            bar.value = max(0, min(1, p / 100.0))
        } else {
            bar.value = 0
        }
        bar.tint = Palette.accent
        bar.gradientEnd = Palette.urgencyAmber
        bar.corner = 2
        if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
        bar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [topRow, bar, meta])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return stack
    }

    /// Fingerprint of the data the popover actually renders. Two consecutive
    /// refreshes producing the same key skip the rebuild entirely so the
    /// popover doesn't tear down + re-add its cards on every 10s tick.
    private func snapshotKey(
        active: Agent?, primary: Agent?, all: [Agent], others: [ToolSummary], parallelVisible: Int
    ) -> String {
        var parts: [String] = []
        parts.append(active?.name ?? "-")
        // Time-derived visible count — folds the 30-min parallel-session cutoff
        // into the key so an aging-out card isn't stranded by the early-bail.
        parts.append("PV:\(parallelVisible)")
        if let p = primary {
            parts.append(p.name)
            parts.append(p.project)
            parts.append(p.model ?? "-")
            parts.append(p.ctxPct.map { String(format: "%.1f", $0) } ?? "-")
            parts.append(p.ctxWindow.map(String.init) ?? "-")
            parts.append(String(p.activeSession))
            parts.append(String(p.session5h))
            parts.append(p.session5hPercent.map { String(format: "%.1f", $0) } ?? "-")
            parts.append(String(p.week7d))
            parts.append(p.week7dPercent.map { String(format: "%.1f", $0) } ?? "-")
            parts.append(p.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")
            parts.append(p.sessionStarted.map { String(Int($0.timeIntervalSince1970)) } ?? "-")
            for s in p.activeSessions {
                parts.append(
                    "S:\(s.id)|\(s.project)|\(s.model ?? "-")|\(s.ctxPct.map { String(format: "%.1f", $0) } ?? "-")|\(s.tokens)|\(s.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")"
                )
            }
        }
        for ag in all where ag.name != primary?.name {
            parts.append(
                "A:\(ag.name)|\(ag.session5h)|\(ag.session5hPercent.map { String(format: "%.1f", $0) } ?? "-")|\(ag.week7d)|\(ag.week7dPercent.map { String(format: "%.1f", $0) } ?? "-")|\(ag.activeSession)|\(ag.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")|\(ag.model ?? "-")"
            )
        }
        for t in others {
            parts.append("O:\(t.name)|\(t.tokens7d)|\(t.sessions7d)|\(t.lastModel ?? "-")")
        }
        parts.append("T:\(ThemeStore.current.id)")
        parts.append("L:\(L10n.lang.rawValue)")
        return parts.joined(separator: "\u{1F}")
    }

    /// Card section caption — left-aligned title with low horizontal hugging
    /// so it stretches to fill the card content width via `widthAnchor`,
    /// matching how agent-card headers anchor to the card's leading edge.
    /// Without this, captions built from short attributed strings (e.g.
    /// "Parallel Sessions") fall back to their intrinsic content width and
    /// drift right inside a `.width`-aligned stack.
    private func sectionCaption(_ text: NSAttributedString) -> NSTextField {
        let lbl = NSTextField(labelWithAttributedString: text)
        lbl.alignment = .left
        lbl.lineBreakMode = .byTruncatingTail
        lbl.maximumNumberOfLines = 1
        lbl.cell?.usesSingleLineMode = true
        lbl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return lbl
    }

    private func buildOthers(tools: [ToolSummary]) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 4

        let header = sectionCaption(
            Typography.captionAttributed(L10n.text("Other tools", "Diğer araçlar"))
        )
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for tool in tools {
            let r = OtherToolRowView(tool: tool)
            stack.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return container
    }

    private func buildFooter() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let shareBtn = FooterIconButton(
            symbol: "square.and.arrow.up",
            tooltip: L10n.text("Share Today's HUD", "Bugünün HUD'unu paylaş"),
            target: self,
            action: #selector(handleShare(_:))
        )
        let settingsBtn = FooterIconButton(
            symbol: "slider.horizontal.3",
            tooltip: L10n.text("Settings", "Ayarlar"),
            target: self,
            action: #selector(handleSettings)
        )
        let refreshBtn = FooterIconButton(
            symbol: "arrow.clockwise",
            tooltip: L10n.text("Refresh", "Yenile"),
            target: self,
            action: #selector(handleRefresh)
        )
        self.refreshBtn = refreshBtn
        let quitBtn = FooterIconButton(
            symbol: "power",
            tooltip: L10n.text("Quit", "Çık"),
            target: self,
            action: #selector(handleQuit)
        )

        let rightStack = NSStackView(views: [shareBtn, settingsBtn, refreshBtn, quitBtn])
        rightStack.orientation = .horizontal
        rightStack.spacing = 4
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(rightStack)

        let edgeGuard: CGFloat = Spacing.m
        NSLayoutConstraint.activate([
            rightStack.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: edgeGuard),
            rightStack.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -edgeGuard),
            rightStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 40),
        ])
        return container
    }

    private func usageColor(_ pct: Double?) -> NSColor {
        guard let pct else { return .labelColor }
        if pct >= 90 { return Palette.urgencyRed }
        if pct >= 70 { return Palette.urgencyAmber }
        return Palette.accent
    }

    // MARK: Actions

    @objc private func handleSettings() { onOpenSettings?() }
    @objc private func handleRefresh() {
        let now = Date()
        if let last = lastRefreshClickAt, now.timeIntervalSince(last) < 2.0 {
            return
        }
        lastRefreshClickAt = now
        refreshBtn?.setSpinning(true)
        onRefresh?()
    }
    @objc private func handleQuit() { onQuit?() }
    @objc private func handleShare(_ sender: NSView) { onShare?(sender) }
}
