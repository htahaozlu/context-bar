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
    /// Transient popover that hosts a tapped session's `/context`-style detail.
    /// Held so a second click (or a rebuild) can dismiss the previous one before
    /// showing the next, instead of stacking popovers.
    private var sessionDetailPopover: NSPopover?

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
        // The OTHER first-party agent (Claude vs Codex). Both must be visible at
        // once (product requirement), but only when it actually has data — an
        // empty/idle second agent must not add a blank card. `agentHasData`
        // gates render-worthiness; ordering follows `all` so the result is stable.
        let secondary = all.first { $0.name != primary?.name && agentHasData($0) }
        let activeOthers = others.filter { isActivelyUsed($0, now: now) }
        // Parallel-session visibility is time-dependent but NOT reflected in the
        // raw session timestamps the key already hashes, so fold the visible
        // count in explicitly. Without this, a session aging past the 30-min
        // cutoff leaves the key byte-identical → the early-bail fires → the
        // parallel card is never removed and the popover never shrinks.
        let parallelVisible = primary.map { parallelSessions(for: $0, now: now).count } ?? 0
        let key = snapshotKey(
            active: active, primary: primary, secondary: secondary, all: all,
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
            // usage limits → [other agent hero + its limits] → other tools.
            addCard(buildHero(agent: agent, isActive: isLive(agent, now: now)))
            if hasParallelSessions(agent: agent, now: now) {
                addCard(buildParallelSessions(agent: agent, now: now))
            }
            if hasSecondaryData(agent) {
                addCard(buildUsageLimits(agent))
            }
            // Second first-party agent (the OTHER of Claude/Codex). Both are
            // shown at once: a captioned hero for the agent, then its own
            // usage-limits card. `secondary` is already nil-gated on having
            // data, so an idle agent adds nothing. Liveness is evaluated PER
            // AGENT (`isLive`) — not against the single global `active` — so a
            // second agent that is itself mid-session shows its live context %
            // and live dot rather than reading as idle just because the other
            // agent fired more recently.
            if let other = secondary {
                let live = isLive(other, now: now)
                let caption = live
                    ? L10n.text("\(other.name) — also active", "\(other.name) — ayrıca aktif")
                    : L10n.text("\(other.name) — recent", "\(other.name) — yakın zamanda")
                addCard(buildSectionCaption(caption))
                addCard(buildHero(agent: other, isActive: live))
                if hasParallelSessions(agent: other, now: now) {
                    addCard(buildParallelSessions(agent: other, now: now))
                }
                if hasSecondaryData(other) {
                    addCard(buildUsageLimits(other))
                }
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
        // Full-bleed hairline immediately before the footer (popover.jsx:
        // `<div className="cb-div" style={{ margin: '14px -16px 12px' }} />`).
        // `addFullBleedDivider` pins it edge-to-edge, ignoring the per-card
        // horizontal inset so it reads as a true separator strip.
        addFullBleedDivider()
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

    /// Adds a hairline that spans the popover's full content width (edge to
    /// edge), bypassing `addCard`'s per-card horizontal inset. Matches the
    /// `margin: 0 -16px` full-bleed divider drawn before the footer in
    /// popover.jsx.
    private func addFullBleedDivider() {
        let div = DividerView()
        contentStack.addArrangedSubview(div)
        NSLayoutConstraint.activate([
            div.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            div.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
        ])
    }

    /// A first-party agent is "worth showing" when it has any live context, any
    /// rolling-limit pressure, or a recent turn — i.e. there is something for
    /// the user to read. Mirrors `hasSecondaryData` but also counts a live
    /// context % so an agent mid-session (limits not yet populated) still shows.
    private func agentHasData(_ a: Agent) -> Bool {
        if a.ctxPct != nil { return true }
        if a.activeSession > 0 { return true }
        if a.session5h > 0 || a.session5hPercent != nil { return true }
        if a.week7d > 0 || a.week7dPercent != nil { return true }
        if a.lastTurn != nil { return true }
        return false
    }

    /// Stand-alone section caption used between the two agent blocks. Unlike the
    /// in-card `sectionCaption`, this is laid out directly in the popover stack
    /// as its own row (with the standard card inset) so it titles the agent
    /// block that follows.
    private func buildSectionCaption(_ text: String) -> NSView {
        sectionCaption(Typography.captionAttributed(text))
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
        stack.alignment = .centerX
        stack.spacing = Spacing.m

        // 26pt circular spinner — the redesign's calm "we're reading" beat.
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let title = NSTextField(
            labelWithString: L10n.text("Gathering session data…", "Oturum verileri toplanıyor…"))
        title.font = Typography.body(12.5)
        title.textColor = .secondaryLabelColor
        title.alignment = .center

        // Three skeleton rows with the design's opacity cascade (0.5/0.38/0.26).
        let skeleton = NSStackView()
        skeleton.orientation = .vertical
        skeleton.spacing = Spacing.xs
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        for alpha in [0.5, 0.38, 0.26] {
            let row = NSView()
            row.wantsLayer = true
            row.layer?.cornerRadius = Radius.chip
            row.layer?.cornerCurve = .continuous
            row.layer?.backgroundColor = Palette.track.withAlphaComponent(CGFloat(alpha)).cgColor
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 30).isActive = true
            skeleton.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: skeleton.widthAnchor).isActive = true
        }

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(skeleton)
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 26),
            spinner.heightAnchor.constraint(equalToConstant: 26),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            skeleton.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    private func buildEmptyState() -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.alignment = .centerX
        stack.spacing = Spacing.s

        // Stack glyph in a 48pt accent-softer well — the design's "nothing here
        // yet" mark (replaces the old loose sparkles symbol).
        let well = NSView()
        well.translatesAutoresizingMaskIntoConstraints = false
        well.wantsLayer = true
        well.layer?.cornerRadius = Radius.card
        well.layer?.cornerCurve = .continuous
        well.layer?.backgroundColor = Palette.accentSofter.cgColor

        let cfg = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iv.contentTintColor = Palette.accent
        iv.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(iv)
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 48),
            well.heightAnchor.constraint(equalToConstant: 48),
            iv.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: well.centerYAnchor),
        ])

        let title = NSTextField(
            labelWithString: L10n.text("No agent data yet", "Henüz ajan verisi yok"))
        title.font = Typography.title(14)
        title.textColor = .labelColor
        title.alignment = .center

        let sub = NSTextField(
            wrappingLabelWithString: L10n.text(
                "Start a Claude Code or Codex session and ContextBar will read it from your local transcripts.",
                "Bir Claude Code veya Codex oturumu başlatın; ContextBar bunu yerel transcript'lerinizden okur."
            ))
        sub.font = Typography.body(11)
        sub.textColor = .secondaryLabelColor
        sub.alignment = .center
        sub.maximumNumberOfLines = 0
        sub.preferredMaxLayoutWidth = Self.contentWidth - 2 * hPad

        let howBtn = ClayChipButton(
            title: L10n.text("How it works", "Nasıl çalışır"),
            symbol: "info.circle"
        ) { [weak self] in self?.handleHowItWorks() }

        stack.addArrangedSubview(well)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(sub)
        stack.setCustomSpacing(Spacing.m, after: sub)
        stack.addArrangedSubview(howBtn)
        sub.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return container
    }

    @objc private func handleHowItWorks() {
        if let url = URL(string: "https://github.com/htahaozlu/context-bar#readme") {
            NSWorkspace.shared.open(url)
        }
    }

    private func buildHero(agent a: Agent, isActive: Bool) -> NSView {
        let (container, stack) = sectionContainer(hero: true)
        stack.spacing = Spacing.s

        // ── Header row: ● + project (left)  ·  brand glyph well (right) ──
        // The status dot is now a real `StatusDotView` (cb-dot): a `.live` dot
        // shows the soft accent halo ring while the agent is active; `.idle`
        // greys it out. Replaces the prior inline "●" glyph.
        let dot = StatusDotView(state: isActive ? .live : .idle, diameter: 8)
        let title = NSMutableAttributedString()
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

        // Brand glyph in a soft accent well (28pt) — the shared `GlyphWell`
        // (cb-glyph). Prefers the real provider logo; falls back to a neutral
        // sparkle symbol when the brand asset is unavailable.
        let well: GlyphWell
        if let url = agentIconURL(name: a.name), let img = NSImage(contentsOf: url) {
            well = GlyphWell(image: img, size: 28, iconSize: 16, background: Palette.accentSofter)
        } else {
            well = GlyphWell(symbol: "sparkle", size: 28, iconSize: 16, background: Palette.accentSofter)
        }
        well.toolTip = AgentVisual.forName(a.name).accessibilityLabel
        let headSpacer = NSView()
        headSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let headerRow = NSStackView(views: [dot, projectLbl, headSpacer, well])
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

        // Make the hero open the detail for this agent's most-relevant active
        // session. Resolve the real ActiveSession when one exists; otherwise
        // synthesize a minimal one from the agent's live ctx/model/project so
        // the click still surfaces what we know. Wrapping the hero card in a
        // zero-inset ClickableRowView keeps the hero visual identical while
        // adding the click target + pointing-hand cursor (same affordance as
        // the parallel rows). If there's nothing to show, return the hero as-is.
        guard let session = heroSession(for: a) else { return container }
        let agentName = a.name
        var wrapper: ClickableRowView!
        wrapper = ClickableRowView(content: container) { [weak self, weak wrapper] in
            guard let self, let wrapper else { return }
            self.showSessionDetail(session: session, agentName: agentName, anchor: wrapper)
        }
        wrapper.toolTip = L10n.text("Open context detail", "Bağlam ayrıntısını aç")
        return wrapper
    }

    /// Resolves the ActiveSession to show when the hero is clicked: prefer the
    /// agent's most-recent live `activeSessions` entry, else synthesize a
    /// minimal one from the agent's rolled-up live fields so the detail can
    /// still show context %/window, total tokens, sub-agent burn and cost.
    private func heroSession(for a: Agent) -> ActiveSession? {
        if let best = a.activeSessions.max(by: {
            ($0.lastTurn ?? .distantPast) < ($1.lastTurn ?? .distantPast)
        }) {
            return best
        }
        // Nothing in the per-session list — synthesize from agent rollups. Only
        // worth doing if there is *something* to show.
        guard a.ctxPct != nil || a.activeSession > 0 || a.activeSessionCost > 0 else { return nil }
        return ActiveSession(
            id: "\(a.name)-hero",
            tokens: a.activeSession,
            subagentTokens: a.activeSessionSubagent,
            cost: a.activeSessionCost,
            project: a.project,
            model: a.model,
            lastTurn: a.lastTurn,
            started: a.sessionStarted,
            ctxPct: a.ctxPct,
            ctxWindow: a.ctxWindow
        )
    }

    /// Opens (or replaces) the transient session-detail popover anchored to the
    /// clicked row / hero card. `.transient` so it dismisses on outside clicks
    /// without swallowing the next interaction.
    private func showSessionDetail(session: ActiveSession, agentName: String, anchor: NSView) {
        sessionDetailPopover?.performClose(nil)
        let detail = SessionDetailView(session: session, agentName: agentName)
        let vc = NSViewController()
        vc.view = detail
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = vc
        // The "context loaded each turn" section fills in asynchronously after a
        // background transcript parse — the popover is sized once here, so let the
        // detail view ask us to re-measure when those rows (or their removal)
        // change its intrinsic height. Guard against the popover having been
        // dismissed/replaced in the meantime.
        detail.onContentResize = { [weak detail, weak pop] in
            guard let detail, let pop, pop.isShown else { return }
            detail.layoutSubtreeIfNeeded()
            pop.contentSize = NSSize(
                width: SessionDetailView.preferredWidth,
                height: max(detail.fittingSize.height, 1))
        }
        // Size from the detail's fitting height so the popover is exactly as
        // tall as its content (width is fixed by SessionDetailView).
        detail.layoutSubtreeIfNeeded()
        pop.contentSize = NSSize(
            width: SessionDetailView.preferredWidth,
            height: max(detail.fittingSize.height, 1))
        sessionDetailPopover = pop
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
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

        // popover.jsx drops the agent·model·time meta line here — the hero meta
        // row already carries that. The limits card is just the rolling rows,
        // each separated by a `cb-div` hairline (matching the spec's stacked
        // LimitRow / cb-div / LimitRow / cb-div / Session total layout).
        var rows: [NSView] = []
        let showsRemaining = a.name.caseInsensitiveCompare("Codex") == .orderedSame
        if a.session5hPercent != nil || a.session5h > 0 {
            rows.append(
                makeLimitRow(
                    label: L10n.text("5-hour rolling", "5 saatlik"),
                    percent: a.session5hPercent,
                    fallbackValue: ContextSnapshot.formatTokens(a.session5h),
                    resetsAt: a.session5hResetsAt,
                    showsRemaining: showsRemaining
                ))
        }
        if a.week7dPercent != nil || a.week7d > 0 {
            rows.append(
                makeLimitRow(
                    label: L10n.text("7-day rolling", "7 günlük"),
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
                    valueColor: Palette.primaryText
                ))
        }
        // Interleave a hairline between each row (not after the last) so the
        // card reads as discrete rolling windows.
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let div = DividerView()
                stack.addArrangedSubview(div)
                div.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
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

        let allOthers = parallelSessions(for: a, now: now)
        let cap = 5
        let shown = Array(allOthers.prefix(cap))
        let overflow = max(0, allOthers.count - cap)

        // Caption with a right-aligned "N active" count (popover.jsx PopCap
        // `right={SESSIONS.length + ' active'}`).
        let header = captionRow(
            L10n.text("Parallel sessions", "Paralel oturumlar"),
            right: L10n.text("\(allOthers.count) active", "\(allOthers.count) aktif"))
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for (i, sess) in shown.enumerated() {
            if i > 0 {
                let div = DividerView()
                stack.addArrangedSubview(div)
                div.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            // Wrap the row so clicking it opens that session's context detail,
            // anchored to the row, with a pointing-hand cursor on hover. The
            // anchor is resolved lazily through `weak row` so the closure can
            // reference the wrapper it's installed on without a cycle.
            let inner = makeParallelSessionRow(sess)
            let agentName = a.name
            var row: ClickableRowView!
            row = ClickableRowView(content: inner) { [weak self, weak row] in
                guard let self, let row else { return }
                self.showSessionDetail(session: sess, agentName: agentName, anchor: row)
            }
            row.toolTip = L10n.text("Open context detail", "Bağlam ayrıntısını aç")
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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

    /// An agent is "live" when its own last turn landed inside the active
    /// window (matches `ContextSnapshot.active`'s gate, but evaluated per agent
    /// so a second live agent isn't forced to read as idle just because the
    /// other one fired more recently).
    private func isLive(_ a: Agent, now: Date = Date()) -> Bool {
        guard let t = a.lastTurn else { return false }
        return now.timeIntervalSince(t) <= Self.activeToolWindow
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

    /// Single horizontal row inside the parallel-sessions card, matching
    /// popover.jsx: [idle dot][project + model column ~116pt][flex thin
    /// bar][pct (right, 34pt)][time (right, 40pt)]. The project/model stay a
    /// two-line column inside the fixed-width slot; everything else is one line.
    private func makeParallelSessionRow(_ sess: ActiveSession) -> NSView {
        let dot = StatusDotView(state: .idle, diameter: 6)

        let proj = NSTextField(labelWithString: sess.project)
        proj.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        proj.textColor = Palette.primaryText
        proj.lineBreakMode = .byTruncatingTail
        proj.cell?.usesSingleLineMode = true

        let modelLbl = NSTextField(labelWithString: sess.model ?? "")
        modelLbl.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        modelLbl.textColor = Palette.tertiaryText
        modelLbl.lineBreakMode = .byTruncatingTail
        modelLbl.cell?.usesSingleLineMode = true

        let idCol = NSStackView(views: [proj, modelLbl])
        idCol.orientation = .vertical
        idCol.alignment = .leading
        idCol.spacing = 1
        idCol.translatesAutoresizingMaskIntoConstraints = false
        // Fixed 116pt slot (popover.jsx `flex: '0 0 116px'`).
        idCol.widthAnchor.constraint(equalToConstant: 116).isActive = true

        let bar = ProgressBarView()
        bar.value = sess.ctxPct.map { max(0, min(1, $0 / 100.0)) } ?? 0
        bar.tint = Palette.accent
        bar.gradientEnd = Palette.urgencyAmber
        bar.corner = 2
        if DisplayPrefs.tickMarks { bar.tickMarks = [0.70, 0.90] }
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.setAccessibilityLabel(L10n.text("Context usage", "Bağlam kullanımı"))

        let pctStr = sess.ctxPct.map { String(format: "%.0f%%", $0) } ?? "—"
        let pctLbl = NSTextField(labelWithString: pctStr)
        pctLbl.font = Typography.bodyMono(11.5, weight: .semibold)
        pctLbl.textColor = Palette.secondaryText
        pctLbl.alignment = .right
        pctLbl.setContentHuggingPriority(.required, for: .horizontal)
        pctLbl.widthAnchor.constraint(equalToConstant: 34).isActive = true

        let timeStr = sess.lastTurn.map { ContextSnapshot.relative($0) } ?? ""
        let timeLbl = NSTextField(labelWithString: timeStr)
        timeLbl.font = Typography.bodyMono(10.5, weight: .regular)
        timeLbl.textColor = Palette.tertiaryText
        timeLbl.alignment = .right
        timeLbl.setContentHuggingPriority(.required, for: .horizontal)
        timeLbl.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let row = NSStackView(views: [dot, idCol, bar, pctLbl, timeLbl])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = Spacing.xs
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// Fingerprint of the data the popover actually renders. Two consecutive
    /// refreshes producing the same key skip the rebuild entirely so the
    /// popover doesn't tear down + re-add its cards on every 10s tick.
    private func snapshotKey(
        active: Agent?, primary: Agent?, secondary: Agent?, all: [Agent],
        others: [ToolSummary], parallelVisible: Int
    ) -> String {
        var parts: [String] = []
        parts.append(active?.name ?? "-")
        // Time-derived visible count — folds the 30-min parallel-session cutoff
        // into the key so an aging-out card isn't stranded by the early-bail.
        parts.append("PV:\(parallelVisible)")
        // Per-agent liveness is `now`-derived (lastTurn vs the active window),
        // so it can flip while the raw timestamps the key hashes stay identical.
        // Fold both flags in so an agent aging from live→idle (dot + context %
        // change) isn't frozen by the early-bail.
        parts.append("LV:\(primary.map { isLive($0) } ?? false ? 1 : 0)")
        parts.append("LV2:\(secondary.map { isLive($0) } ?? false ? 1 : 0)")
        // The second agent now renders a full hero + parallel + limits card, so
        // ITS render-affecting fields must be in the key too — otherwise its
        // context %, window, model or session list could change while the key
        // stayed byte-identical and the early-bail would freeze the stale card.
        if let s = secondary {
            let parallel2 = parallelSessions(for: s).count
            parts.append("PV2:\(parallel2)")
            parts.append("SEC:\(s.name)|\(s.project)|\(s.model ?? "-")")
            parts.append(s.ctxPct.map { String(format: "%.1f", $0) } ?? "-")
            parts.append(s.ctxWindow.map(String.init) ?? "-")
            parts.append(String(s.activeSession))
            parts.append(s.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")
            for ss in s.activeSessions {
                parts.append(
                    "S2:\(ss.id)|\(ss.project)|\(ss.model ?? "-")|\(ss.ctxPct.map { String(format: "%.1f", $0) } ?? "-")|\(ss.tokens)|\(ss.lastTurn.map { String(Int($0.timeIntervalSince1970)) } ?? "-")"
                )
            }
        } else {
            parts.append("SEC:-")
        }
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

    /// Caption header with a left title and an optional right-aligned caption,
    /// matching popover.jsx's `PopCap` (space-between, both `.caption`). Used
    /// for the "Parallel sessions … N active" header.
    private func captionRow(_ title: String, right: String?) -> NSView {
        let left = sectionCaption(Typography.captionAttributed(title))
        let row: NSStackView
        if let right {
            let rightLbl = NSTextField(
                labelWithAttributedString: Typography.captionAttributed(right))
            rightLbl.alignment = .right
            rightLbl.lineBreakMode = .byTruncatingTail
            rightLbl.maximumNumberOfLines = 1
            rightLbl.cell?.usesSingleLineMode = true
            rightLbl.setContentHuggingPriority(.required, for: .horizontal)
            rightLbl.setContentCompressionResistancePriority(.required, for: .horizontal)
            let spacer = NSView()
            spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            row = NSStackView(views: [left, spacer, rightLbl])
        } else {
            row = NSStackView(views: [left])
        }
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = Spacing.xs
        return row
    }

    private func buildOthers(tools: [ToolSummary]) -> NSView {
        let (container, stack) = sectionContainer()
        stack.spacing = 4

        let header = sectionCaption(
            Typography.captionAttributed(L10n.text("Other tools", "Diğer araçlar"))
        )
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for (i, tool) in tools.enumerated() {
            if i > 0 {
                let div = DividerView()
                stack.addArrangedSubview(div)
                div.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
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

        // Design footer is a space-between row: the action icons sit on the
        // left, Quit (power) alone on the right.
        let leftStack = NSStackView(views: [shareBtn, settingsBtn, refreshBtn])
        leftStack.orientation = .horizontal
        leftStack.spacing = 4
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        quitBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(leftStack)
        container.addSubview(quitBtn)

        let edgeGuard: CGFloat = Spacing.m
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: edgeGuard),
            leftStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            quitBtn.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -edgeGuard),
            quitBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
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
