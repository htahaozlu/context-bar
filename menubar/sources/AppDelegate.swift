import AppKit
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer!
    var detailWindow: DetailWindowController?
    let snapshot = ContextSnapshot()
    var lastActive: Agent?
    private var previewTheme: Theme?
    private let popover = NSPopover()
    private let popoverVC = MenubarPopoverViewController()
    private var fsStream: FSEventStreamRef?
    private var fsDebounce: DispatchWorkItem?
    private var fsRunning = false
    /// Paths currently fed to FSEventStreamCreate. FSEvents captures the
    /// path set at creation — when ~/.claude/projects or ~/.codex/sessions
    /// materializes after launch we need to tear down and recreate the
    /// stream against the new union, otherwise the new agent stays invisible
    /// until restart.
    private var fsWatchedPaths: Set<String> = []
    private var popoverVisible = false
    private var lastAllAgents: [Agent] = []
    private var engineRunning = false
    private var enginePending = false
    private var lastForceRefreshAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Capture-only: pin the app to light/dark so marketing & regression
        // screenshots can render either appearance without flipping the whole
        // system. No effect in normal use (variable unset → follows system).
        if let want = ProcessInfo.processInfo.environment["CONTEXTBAR_FORCE_APPEARANCE"]?.lowercased() {
            NSApp.appearance = NSAppearance(named: want == "light" ? .aqua : .darkAqua)
        }
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // No icon — title-only menubar entry to save horizontal space.

        setupPopover()
        refresh()
        syncContextToGroupContainer()
        // Kick the engine immediately on launch so a freshly-opened
        // menubar reflects any updates the user made while the app was
        // closed (e.g. Codex CLI bumped today, Claude Code ran
        // overnight, …). Without this the user sees the previous run's
        // JSON until the first 10s tick, which feels like a stale
        // snapshot — and is, if the engine itself never runs (missing
        // binary, see `runEngine` for the candidate list).
        regenerateThenRefresh()
        let args = CommandLine.arguments.dropFirst()
        if ProcessInfo.processInfo.environment["CONTEXTBAR_OPEN_WINDOW"] == "1"
            || args.contains("--settings") || args.contains("--open") {
            openDetail()
        }
        if let screenshotPath = ProcessInfo.processInfo.environment["CONTEXTBAR_SCREENSHOT_PATH"] {
            openDetail()
            // Optional WxH override so marketing captures can show a taller
            // window (e.g. the full Cost tab). Capture-only; no effect in use.
            if let raw = ProcessInfo.processInfo.environment["CONTEXTBAR_SCREENSHOT_SIZE"] {
                let parts = raw.lowercased().split(separator: "x")
                if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
                   let win = detailWindow?.window {
                    win.setContentSize(NSSize(width: w, height: h))
                    win.center()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.detailWindow?.capture(to: screenshotPath)
                NSApp.terminate(nil)
            }
        }
        if ProcessInfo.processInfo.environment["CONTEXTBAR_MENU_SCREENSHOT_PATH"] != nil {
            // External script (marketing-screenshot.sh) handles the actual capture.
            // This env var just prevents the timer so the app stays responsive.
        }
        if let sharePath = ProcessInfo.processInfo.environment["CONTEXTBAR_SHARE_RENDER_PATH"] {
            let masked = (ProcessInfo.processInfo.environment["CONTEXTBAR_SHARE_MASK"] ?? "1") == "1"
            let (_, all, others) = snapshot.load()
            let img = ShareCard.render(agents: all, others: others, maskProjects: masked)
            try? ShareCard.writePNG(img, to: URL(fileURLWithPath: sharePath))
            NSApp.terminate(nil)
            return
        }
        if let popoverPath = ProcessInfo.processInfo.environment["CONTEXTBAR_POPOVER_SCREENSHOT_PATH"] {
            // Auto-open the menubar popover, give it a moment to lay out, then
            // shell out to `screencapture -l` on the popover's window number so
            // marketing can rebuild docs/images/context-bar-menubar.png without
            // manual click-and-frame work.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.togglePopover(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    self?.capturePopover(to: popoverPath)
                    let env = ProcessInfo.processInfo.environment
                    // Shrink regression harness: overwrite the live context file
                    // with a smaller fixture and drive the production refresh
                    // path, then re-capture. Proves the popover CONTRACTS (not
                    // just grows) — the blank-band bug. Gated; no effect in prod.
                    if let shrinkJSON = env["CONTEXTBAR_POPOVER_SHRINK_JSON"],
                       let shrinkOut = env["CONTEXTBAR_POPOVER_SHRINK_OUT"],
                       let data = try? Data(contentsOf: URL(fileURLWithPath: shrinkJSON)) {
                        let target = ContextSnapshot.resolveSnapshotPath()
                        try? data.write(to: URL(fileURLWithPath: target))
                        self?.refresh()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            self?.capturePopover(to: shrinkOut)
                            NSApp.terminate(nil)
                        }
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        }

        timer = Timer.scheduledTimer(
            timeInterval: 10.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)

        startAgentDirWatcher()
        registerSystemObservers()
        IncidentPoller.shared.start()
    }

    /// Hardens the status item against display reconfigure / sleep — common
    /// failure mode in menubar apps where an external monitor unplug leaves
    /// the status button orphaned with no rendering surface. Also redraws
    /// the title when the incident poller reports a status change so the
    /// overlay can light up between refresh ticks.
    private func registerSystemObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenReconfigure),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncidentChange),
            name: IncidentPoller.didChange,
            object: nil
        )
    }

    @objc private func handleScreenReconfigure() {
        ensureStatusItemAlive()
        repaintTitle()
    }

    @objc private func handleWake() {
        ensureStatusItemAlive()
        regenerateThenRefresh()
        IncidentPoller.shared.pollNow()
    }

    @objc private func handleIncidentChange() {
        repaintTitle()
        if popover.isShown { popoverVC.rebuild() }
    }

    /// Recreates the status item when its button is missing or its window has
    /// been orphaned by a display reconfigure. Idempotent — safe to call from
    /// any observer.
    private func ensureStatusItemAlive() {
        let alive: Bool = {
            guard let btn = statusItem?.button else { return false }
            return btn.window != nil
        }()
        if alive { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Watches the agent transcript directories so the menubar reflects the
    /// active project the moment the user starts typing in a different repo.
    /// FSEvents is recursive and debounced so a burst of writes only triggers
    /// one regenerate.
    ///
    /// Newer Codex CLI versions (mid-2025+) also write to `archived_sessions/`
    /// and `session_index.jsonl` — watching only `~/.codex/sessions/`
    /// misses a refresh after a Codex update, leaving the menubar pinned to
    /// the pre-update snapshot. We watch every Codex path that the engine
    /// could plausibly read from.
    private func startAgentDirWatcher() {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.claude/projects",
            "\(home)/.codex/sessions",
            "\(home)/.codex/archived_sessions",
            "\(home)/.codex/session_index.jsonl",
        ]
        let paths = candidates.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
            delegate.fsEventFired()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        if FSEventStreamStart(stream) {
            fsStream = stream
            fsRunning = true
            fsWatchedPaths = Set(paths)
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Rescan agent transcript dirs and, if a new one materialized since
    /// startup (e.g. user just installed the Codex CLI), tear down and
    /// recreate the FSEventStream against the expanded path set. FSEvents
    /// captures paths at creation and offers no in-place add.
    private func rescanAgentDirsIfNeeded() {
        let home = NSHomeDirectory()
        let existing: Set<String> = [
            "\(home)/.claude/projects",
            "\(home)/.codex/sessions",
            "\(home)/.codex/archived_sessions",
            "\(home)/.codex/session_index.jsonl",
        ].filter { FileManager.default.fileExists(atPath: $0) }
            .reduce(into: Set<String>()) { $0.insert($1) }
        if existing == fsWatchedPaths { return }
        if let s = fsStream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            fsStream = nil
            fsRunning = false
            fsWatchedPaths = []
        }
        startAgentDirWatcher()
    }

    private func fsEventFired() {
        fsDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.regenerateThenRefresh()
        }
        fsDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @objc func tick() {
        // Always regenerate so menubar title reflects the most recently
        // active project/session — even when popover and detail window are
        // both closed. Engine is fast (sub-100ms in steady state) and this
        // closes a UX gap where switching projects in another Claude session
        // left the menubar showing the old project until the popover opened.
        rescanAgentDirsIfNeeded()
        regenerateThenRefresh()
    }

    /// Finder double-click / Dock click while running. Accessory apps with
    /// no Dock tile still receive this when the user launches the app from
    /// Finder, Spotlight, or `open -a ContextBar`. Used as a fallback when
    /// the menubar icon is hidden by overflow / Bartender / Hidden Bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showFromReopen()
        return true
    }

    /// First-launch hand-off: if the app was already running and the user
    /// double-clicked it in Finder, AppKit may send `application(_:open:)`
    /// instead of reopen. Treat both the same.
    func application(_ application: NSApplication, open urls: [URL]) {
        showFromReopen()
    }

    private func showFromReopen() {
        // The status item button sits inside the menubar strip which is
        // outside `visibleFrame` (visibleFrame excludes menubar+dock). Check
        // against `frame` so a normally-visible button doesn't read as hidden.
        let button = statusItem.button
        let buttonHidden: Bool = {
            guard let btn = button, let win = btn.window else { return true }
            let frame = win.convertToScreen(btn.convert(btn.bounds, to: nil))
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(frame.origin) })
                ?? NSScreen.main else { return frame.width < 4 }
            return frame.width < 4 || !screen.frame.intersects(frame)
        }()
        if buttonHidden {
            openDetail()
        } else {
            togglePopover(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func refreshNow() { regenerateThenRefresh() }

    /// User-initiated full refresh from the popover button. Blows away both
    /// the Rust snapshot cache and the Python upstream-usage cache so the
    /// engine re-parses every transcript and re-fetches the usage API. The
    /// 2s debounce protects against double-clicks queueing a second engine
    /// run on top of the first.
    @objc func forceRefresh() {
        let now = Date()
        if let last = lastForceRefreshAt, now.timeIntervalSince(last) < 2.0 {
            return
        }
        lastForceRefreshAt = now
        let home = NSHomeDirectory()
        let fm = FileManager.default
        for name in ["usage.cache.json", "usage_api_cache.json"] {
            try? fm.removeItem(atPath: "\(home)/.context-bar/\(name)")
        }
        regenerateThenRefresh()
    }

    func popoverWillShow(_ notification: Notification) { popoverVisible = true }
    func popoverDidClose(_ notification: Notification) { popoverVisible = false }

    /// Spawns the bundled engine to rewrite ~/.context-bar/context.json, then reloads
    /// the menu. Engine runs off the main thread so the menubar stays responsive;
    /// UI update is dispatched back to main. If the engine binary is missing
    /// (e.g. running the Swift app standalone in dev), we still refresh from the
    /// existing JSON so behavior degrades gracefully to the previous mode.
    func regenerateThenRefresh() {
        // Reentrancy guard: if an engine run is already in flight, just mark
        // pending so we coalesce overlapping ticks (FSEvents burst + 10s timer
        // + wake-from-sleep) into at most one follow-up run. Without this two
        // engine processes can stomp on context.json simultaneously.
        if engineRunning {
            enginePending = true
            return
        }
        engineRunning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runEngine()
            DispatchQueue.main.async {
                guard let self else { return }
                self.refresh()
                self.reloadWidgets()
                self.engineRunning = false
                if self.enginePending {
                    self.enginePending = false
                    self.regenerateThenRefresh()
                }
            }
        }
    }

    private func reloadWidgets() {
        syncContextToGroupContainer()
        #if canImport(WidgetKit)
        if #available(macOS 11.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    /// The widget extension is sandboxed so it cannot read `~/.context-bar/context.json`
    /// directly. Mirror the latest snapshot into the shared App Group container
    /// the widget *can* read via `containerURL(forSecurityApplicationGroupIdentifier:)`.
    /// Also writes a `hud.json` copy for one release so widgets built against
    /// the old filename keep working.
    private func syncContextToGroupContainer() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let srcNew = "\(home)/.context-bar/context.json"
        let srcLegacy = "\(home)/.context-bar/hud.json"
        let src = fm.fileExists(atPath: srcNew) ? srcNew : srcLegacy
        guard fm.fileExists(atPath: src) else { return }
        guard let container = fm.containerURL(
            forSecurityApplicationGroupIdentifier: "DQJT5BCZCM.com.htahaozlu.contextbar"
        ) else { return }
        let srcURL = URL(fileURLWithPath: src)
        for name in ["context.json", "hud.json"] {
            let dst = container.appendingPathComponent(name)
            do {
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.copyItem(at: srcURL, to: dst)
            } catch {
                // Group container may not exist until the widget is provisioned;
                // ignore — the widget will fall back to the legacy path.
            }
        }
    }

    /// Last path that successfully ran the engine. `runEngine()` records
    /// here on success; if a future run fails to find any candidate, we
    /// log it so a missing-engine condition is visible (vs. silently
    /// falling back to stale JSON).
    private static var lastEnginePath: String?

    private func runEngine() {
        let home = NSHomeDirectory()
        let bundleExe = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/context-bar-engine")
        // Probe a wider set of locations than the original three — the
        // DMG-installed app lives in /Applications, and a dev build
        // ($PATH or /usr/local/bin) is the common case. Without this
        // list, a dev run falls back to the stale `context.json` with
        // zero indication that the engine never ran.
        var candidates: [URL] = [
            bundleExe,                                                      // self-bundled (DMG / packaged)
            URL(fileURLWithPath: "/Applications/ContextBar.app/Contents/MacOS/context-bar-engine"),
            URL(fileURLWithPath: "/usr/local/bin/context-bar"),
            URL(fileURLWithPath: "/opt/homebrew/bin/context-bar"),
            URL(fileURLWithPath: "\(home)/.cargo/bin/context-bar"),
            URL(fileURLWithPath: "/usr/bin/context-bar"),
        ]
        // Walk $PATH for any `context-bar` (or `context-bar-engine`)
        // the user might have installed via brew, mise, asdf, etc.
        candidates.append(contentsOf: pathLookupCandidates())
        guard let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            NSLog("[context-bar] engine not found in %d locations; refresh will use stale JSON", candidates.count)
            Self.lastEnginePath = nil
            return
        }
        Self.lastEnginePath = exe.path
        let pyURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/usage_signal.py")
        let task = Process()
        task.executableURL = exe
        task.arguments = ["global"]
        var env = ProcessInfo.processInfo.environment
        if FileManager.default.fileExists(atPath: pyURL.path) {
            env["CONTEXTBAR_USAGE_SCRIPT"] = pyURL.path
        }
        task.environment = env
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Engine missing or failed — refresh() will fall back to existing JSON.
            NSLog("[context-bar] engine run failed: %@", "\(error)")
        }
    }

    /// Walks $PATH for executables named `context-bar` (or
    /// `context-bar-engine` for a self-bundled binary). The original
    /// hard-coded candidate list missed `mise` / `asdf` / `brew` shims
    /// and dev shells that put cargo binaries outside `~/.cargo/bin`.
    private func pathLookupCandidates() -> [URL] {
        let names = ["context-bar", "context-bar-engine"]
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = pathEnv.split(separator: ":").map(String.init)
        var out: [URL] = []
        for d in dirs {
            for n in names {
                let p = (d as NSString).appendingPathComponent(n)
                if FileManager.default.isExecutableFile(atPath: p) {
                    out.append(URL(fileURLWithPath: p))
                }
            }
        }
        return out
    }

    /// Wires the popover and rewires the status item button to toggle it. The
    /// status item no longer owns an NSMenu — both left and right clicks open
    /// the modern popover panel. Quick actions (settings/refresh/quit/theme)
    /// live in the popover footer.
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
        // NOTE: deliberately NOT setting hasFullSizeContent — letting NSPopover
        // inset the content itself clears the arrow at the top and keeps left/
        // right margins symmetric. hasFullSizeContent=true pushed content under
        // the arrow (top gap) and into the rounded corners (left edge clipped).
        // NSPopover grows to a larger preferredContentSize but won't shrink back
        // while shown — it keeps its tallest frame, leaving a blank band below
        // the footer when a card disappears on a refresh tick. Assigning
        // contentSize explicitly forces the window to contract too. No-op before
        // the popover is shown (the first show() sizes it from preferredContentSize).
        popoverVC.onSized = { [weak self] size in
            guard let self, self.popover.isShown else { return }
            self.popover.contentSize = size
        }

        popoverVC.onOpenSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.openDetail()
        }
        popoverVC.onRefresh = { [weak self] in
            self?.forceRefresh()
        }
        popoverVC.onQuit = { [weak self] in
            self?.quit()
        }
        popoverVC.onShare = { [weak self] anchor in
            self?.presentShareCard(from: anchor)
        }
        popoverVC.onPickTheme = { [weak self] id in
            ThemeStore.set(id)
            self?.previewTheme = nil
            self?.refresh()
            self?.popoverVC.rebuild()
            self?.detailWindow?.load()
        }
        popoverVC.onPreviewTheme = { [weak self] id in
            guard let self else { return }
            self.previewTheme = id.map { Theme.by(id: $0) }
            self.repaintTitle()
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        regenerateThenRefresh()
        popoverVC.rebuild()
        // Activate so popover window becomes key — without this an accessory
        // app's popover requires a first focus-click before buttons respond.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let win = popover.contentViewController?.view.window {
            win.makeKey()
        }
    }

    func refresh() {
        let (active, all, _) = snapshot.load()
        lastActive = active
        lastAllAgents = all
        repaintTitle()
        // Publish this Mac's compact usage to the shared sync folder (no-op
        // unless the user set one). Off the main concern path; cheap.
        MachineSync.exportLocal()
        // Mirror the latest snapshot into the local SQLite store and, if a
        // self-hosted server URL is set, push / pull. Both are throttled
        // internally so this is safe to call every 10s tick.
        LocalStore.shared.ingestLocalSnapshot()
        ServerSync.shared.pushIfDue()
        ServerSync.shared.pullIfDue()
        if popover.isShown {
            popoverVC.rebuild()
        }
    }

    /// Renders the current usage state to a square-portrait PNG and opens the
    /// native macOS share sheet anchored at `anchor`. Project names are
    /// redacted by default (DisplayPrefs.maskShareProjects) so users can post
    /// the card to social channels without leaking private repository names.
    func presentShareCard(from anchor: NSView) {
        let (_, all, others) = snapshot.load()
        guard !all.isEmpty else { return }
        let image = ShareCard.render(
            agents: all,
            others: others,
            maskProjects: DisplayPrefs.maskShareProjects
        )
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ContextBar-DailyHUD.png")
        do {
            try ShareCard.writePNG(image, to: outURL)
        } catch {
            NSSound.beep()
            return
        }
        let picker = NSSharingServicePicker(items: [outURL])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    /// Repaints the status bar title using the current preview theme if any,
    /// otherwise the persisted theme. Used both on refresh and during the
    /// theme picker's live hover preview.
    private func repaintTitle() {
        let theme = previewTheme ?? ThemeStore.current
        statusItem.button?.attributedTitle = composeTitle(active: lastActive, theme: theme)
    }

    /// Builds the compact menubar title using the active theme:
    ///     <gauge> <Agent> <sep> <project> <sep> <ctx%>
    ///
    /// The leading gauge-dot is the ONE unified status signal — its arc shows
    /// context fill and its color carries urgency (calm accent → amber →
    /// red). It replaces the three competing badges (incident prefix, budget
    /// suffix, critical-background suffix); whichever is most urgent now just
    /// drives the single dot's color.
    private func composeTitle(active: Agent?, theme: Theme = ThemeStore.current) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        guard let a = active else {
            // Idle — hollow ring, no number.
            let result = NSMutableAttributedString(
                attributedString: gaugeAttachment(pct: nil, color: theme.separatorColor, font: font))
            result.append(NSAttributedString(string: L10n.text(" no agent", " ajan yok"),
                                             attributes: [
                                                 .font: font,
                                                 .foregroundColor: NSColor.secondaryLabelColor,
                                             ]))
            return result
        }
        let gaugeColor = menubarUrgencyColor(active: a, theme: theme)
        let result = NSMutableAttributedString(
            attributedString: gaugeAttachment(pct: a.ctxPct, color: gaugeColor, font: font))
        result.append(styleTitle(
            agent: a.name,
            project: a.project,
            pct: a.ctxPct,
            theme: theme,
            font: font
        ))
        return result
    }

    /// Unified menubar urgency color. Calm work stays on the accent; the dot
    /// only warms when something genuinely needs attention (an upstream
    /// incident, budget/limit pressure, a hot background session, or context
    /// pinned at the wall). The worst active signal wins.
    private func menubarUrgencyColor(active a: Agent, theme: Theme) -> NSColor {
        var level = 0  // 0 calm · 1 attention · 2 at-the-limit
        func bump(_ x: Int) { if x > level { level = x } }

        if (a.ctxPct ?? 0) >= 95 { bump(2) }
        if DisplayPrefs.incidents {
            switch IncidentPoller.shared.current.severity {
            case .critical: bump(2)
            case .major, .minor: bump(1)
            case .none: break
            }
        }
        if let tier = ContextSnapshot.budgetTier(lastAllAgents), tier != .ok {
            bump(tier == .critical ? 2 : 1)
        }
        if DisplayPrefs.criticalBackground, let hot = hottestBackgroundPct(foreground: a) {
            bump(hot >= 90 ? 2 : 1)
        }
        switch level {
        case 2: return theme.pctHigh
        case 1: return theme.pctMid
        default: return theme.accent
        }
    }

    /// Hottest background session percent that out-paces a calm foreground —
    /// same gates as the old critical-background suffix, now feeding the gauge.
    private func hottestBackgroundPct(foreground fg: Agent) -> Double? {
        let fgPct = fg.ctxPct ?? 0
        guard fgPct < 70 else { return nil }
        var best: Double?
        for ag in lastAllAgents {
            for sess in ag.activeSessions {
                guard sess.project != fg.project else { continue }
                let pct = sess.ctxPct ?? 0
                guard pct >= 75, pct >= fgPct + 15 else { continue }
                if best == nil || pct > best! { best = pct }
            }
        }
        return best
    }

    /// Renders the leading radial gauge as an inline text attachment sized to
    /// the menubar cap-height. `pct == nil` draws just the hollow ring (idle).
    private func gaugeAttachment(pct: Double?, color: NSColor, font: NSFont) -> NSAttributedString {
        let side = max(11, round(font.capHeight * 1.18))
        // Resolve dynamic colors against the status button's appearance so the
        // bitmap bakes the right light/dark variant.
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        var arc = color
        var track = NSColor.tertiaryLabelColor
        appearance.performAsCurrentDrawingAppearance {
            arc = color.usingColorSpace(.sRGB) ?? color
            track = (NSColor.tertiaryLabelColor.usingColorSpace(.sRGB) ?? .tertiaryLabelColor)
                .withAlphaComponent(0.45)
        }
        let lw: CGFloat = 1.7
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let inset = lw / 2 + 0.5
            let radius = (side - 2 * inset) / 2
            let center = CGPoint(x: side / 2, y: side / 2)
            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            ring.lineWidth = lw
            track.setStroke()
            ring.stroke()
            if let p = pct, p > 0 {
                let sweep = 360.0 * min(100, p) / 100.0
                let arcPath = NSBezierPath()
                // Start at 12 o'clock, sweep clockwise.
                arcPath.appendArc(withCenter: center, radius: radius,
                                  startAngle: 90, endAngle: 90 - sweep, clockwise: true)
                arcPath.lineWidth = lw
                arcPath.lineCapStyle = .round
                arc.setStroke()
                arcPath.stroke()
            }
            return true
        }
        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: img)
        // Sit the ring on the baseline like the brand icon, nudged up a hair so
        // its center aligns with the text x-height band.
        attachment.bounds = NSRect(x: 0, y: -1, width: side, height: side)
        return NSAttributedString(attachment: attachment)
    }

    private func styleTitle(
        agent: String,
        project: String,
        pct: Double?,
        theme: Theme,
        font: NSFont,
        renderAgentAsIcon: Bool = true
    ) -> NSAttributedString {
        let agentAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.agentColor,
        ]
        let dim: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.separatorColor,
        ]
        let projectAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.projectColor,
        ]
        let ctxAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.ctxColor(pct),
        ]
        let pctStr = pct.map { String(format: "%.0f%%", $0) } ?? "—"
        let rawSep = SeparatorStore.current
        let sep = rawSep.isEmpty ? " " : " \(rawSep) "

        let visible = DisplayStore.items.filter { $0.enabled }
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: " ", attributes: agentAttrs))
        if visible.isEmpty {
            return s
        }
        for (i, item) in visible.enumerated() {
            if i > 0 {
                s.append(NSAttributedString(string: sep, attributes: dim))
            }
            switch item.element {
            case .agent:
                if renderAgentAsIcon {
                    s.append(agentInlineString(name: agent, font: font, fallbackColor: theme.agentColor))
                } else {
                    s.append(NSAttributedString(string: agent, attributes: agentAttrs))
                }
            case .project:
                s.append(NSAttributedString(string: project, attributes: projectAttrs))
            case .pct:
                s.append(NSAttributedString(string: pctStr, attributes: ctxAttrs))
            }
        }
        return s
    }

    @objc func openDetail() {
        if detailWindow == nil {
            detailWindow = DetailWindowController(onThemeChange: { [weak self] _ in
                self?.refresh()
                self?.detailWindow?.load()
            })
        }
        detailWindow?.show()
    }

    private func captureMenu(to path: String) {
        // NSMenu popup is a system-managed CGWindow, not an NSWindow.
        // Use CGWindowList to find the largest visible window owned by this process.
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { NSApp.terminate(nil); return }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var bestID: CGWindowID = kCGNullWindowID
        var bestArea: Double = 0

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == myPID,
                  let widInt = info[kCGWindowNumber as String] as? Int,
                  let boundsAny = info[kCGWindowBounds as String] as? [String: Any],
                  let w = boundsAny["Width"] as? Double,
                  let h = boundsAny["Height"] as? Double,
                  w > 150, h > 100
            else { continue }
            let area = w * h
            if area > bestArea { bestArea = area; bestID = CGWindowID(widInt) }
        }

        guard bestID != kCGNullWindowID else { NSApp.terminate(nil); return }

        let opts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        if let cgImage = CGWindowListCreateImage(
            .null, .optionIncludingWindow, bestID, opts
        ) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = NSSize(width: cgImage.width, height: cgImage.height)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        NSApp.terminate(nil)
    }

    /// Screencaptures the open popover's window to `path`. Locates the
    /// popover's CGWindow by finding the largest visible window owned by
    /// this process — the popover is system-managed and isn't reachable as
    /// an NSWindow, so we go through CGWindowList + the `screencapture` CLI.
    private func capturePopover(to path: String) {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var bestID: CGWindowID = kCGNullWindowID
        var bestArea: Double = 0
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == myPID,
                  let widInt = info[kCGWindowNumber as String] as? Int,
                  let boundsAny = info[kCGWindowBounds as String] as? [String: Any],
                  let w = boundsAny["Width"] as? Double,
                  let h = boundsAny["Height"] as? Double,
                  w > 200, h > 200
            else { continue }
            let area = w * h
            if area > bestArea { bestArea = area; bestID = CGWindowID(widInt) }
        }
        guard bestID != kCGNullWindowID else { return }
        // CGWindowListCreateImage works on windows owned by the current
        // process without requiring Screen Recording TCC, unlike the
        // `screencapture` CLI which inherits the parent's permissions and
        // silently fails in headless / freshly-signed launches.
        let opts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let cgImage = CGWindowListCreateImage(
            .null, .optionIncludingWindow, bestID, opts
        ) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: cgImage.width, height: cgImage.height)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let quitItem = NSMenuItem(
            title: L10n.text("Quit ContextBar", "ContextBar'dan Çık"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        // Edit menu. Without it, ⌘X/⌘C/⌘V/⌘A don't reach text fields in an
        // accessory app (no menu supplies the key equivalents), so the API-key
        // field couldn't be pasted into — only typed. Standard responder-chain
        // selectors (nil target → routed to the focused field editor).
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.text("Edit", "Düzen"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: L10n.text("Cut", "Kes"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.text("Copy", "Kopyala"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.text("Paste", "Yapıştır"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.text("Select All", "Tümünü Seç"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }
}
