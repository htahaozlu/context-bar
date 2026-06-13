import AppKit
import Foundation

/// NSTabViewController in `.toolbar`/`.preference` mode resizes the window to
/// each pane's *fitting* size on every tab switch — and the centered 580pt
/// Settings/About panes fit narrower than the full-width 820pt data tabs, so the
/// window width (and height) jumped on every switch. `preferredContentSize`
/// alone doesn't stop it (that path is ignored for the fitting-size resize), so
/// we force the window back to one fixed content size after each switch.
final class FixedSizeTabViewController: NSTabViewController {
    static let fixedContentSize = NSSize(width: 820, height: 680)

    override var preferredContentSize: NSSize {
        get { Self.fixedContentSize }
        set { /* ignore child-driven size */ }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        transitionOptions = [] // no animated resize, so the size fix is synchronous
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        enforceFixedSize()
    }

    /// Pin the window's content area to `fixedContentSize`, anchoring the top
    /// edge so the title bar doesn't appear to creep when AppKit changed height.
    private func enforceFixedSize() {
        guard let window = view.window else { return }
        let target = Self.fixedContentSize
        // Re-assert the content-size clamp: NSTabViewController relaxes the
        // window's content min/max around its per-pane resize, so restore both
        // bounds after each switch or a later layout pass could resize again.
        window.contentMinSize = target
        window.contentMaxSize = target
        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - target.width) > 0.5
            || abs(current.height - target.height) > 0.5 else { return }
        let top = window.frame.maxY
        var frame = window.frameRect(forContentRect: NSRect(origin: window.frame.origin, size: target))
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
    }
}

/// Detail window — four top-level tabs: **Stats · Cost · Settings · About**.
/// Stats and Cost are the data views; Settings hosts the General preferences
/// (Appearance · Alerts · Behavior) plus the AI Advisor key and the across-your-
/// Macs (iCloud) sync that used to live on a separate Privacy tab. About is its
/// own top-level tab. Each settings tab is a standalone
/// `PreferencePaneViewController` with its own scroll view and centered 580pt
/// column; the data tabs keep the full 820pt canvas.
final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC = FixedSizeTabViewController()
    let statsVC = StatsViewController()
    let costVC = CostViewController()
    private let settingsVC = SettingsViewController()
    private let aboutVC = AboutSettingsViewController()

    init(onThemeChange: @escaping (String) -> Void) {
        super.init(window: nil)

        tabVC.tabStyle = .toolbar

        let statsItem = NSTabViewItem(viewController: statsVC)
        statsItem.label = L10n.text("Stats", "İstatistik")
        statsItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis",
                                   accessibilityDescription: statsItem.label)

        // "Cost" (was "Value") — matches the design mockup; the hero on
        // this tab makes it explicit that the figure is hypothetical
        // API value, not a bill.
        let costItem = NSTabViewItem(viewController: costVC)
        costItem.label = L10n.text("Cost", "Maliyet")
        costItem.image = NSImage(systemSymbolName: "dollarsign.circle",
                                  accessibilityDescription: costItem.label)

        // Settings — General only (Appearance · Alerts · Behavior).
        let settingsItem = NSTabViewItem(viewController: settingsVC)
        settingsItem.label = L10n.text("Settings", "Ayarlar")
        settingsItem.image = NSImage(systemSymbolName: "gearshape",
                                      accessibilityDescription: settingsItem.label)

        // About — version, updates, repository context, files & shortcuts.
        // Now its own top-level tab.
        let aboutItem = NSTabViewItem(viewController: aboutVC)
        aboutItem.label = L10n.text("About", "Hakkında")
        aboutItem.image = NSImage(systemSymbolName: "info.circle",
                                   accessibilityDescription: aboutItem.label)

        [statsItem, costItem, settingsItem, aboutItem]
            .forEach(tabVC.addTabViewItem)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ContextBar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        // Fixed content size — clamp both ways so neither the user nor the tab
        // controller's per-pane fitting-size resize can change the window.
        window.contentMinSize = FixedSizeTabViewController.fixedContentSize
        window.contentMaxSize = FixedSizeTabViewController.fixedContentSize
        window.minSize = NSSize(width: 720, height: 560)
        window.center()
        window.contentViewController = tabVC
        self.window = window
        window.delegate = self

        // Premium frosted background — under-window blending so the desktop
        // wallpaper softly bleeds through behind the tab content. Matches
        // the redesigned Settings pane aesthetic: a warm-neutral tonal wash.
        if let contentView = window.contentView {
            let effect = NSVisualEffectView(frame: contentView.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            contentView.addSubview(effect, positioned: .below, relativeTo: nil)
        }

        // "Connect a key" CTAs on the Stats + Cost panes jump to the Settings
        // tab (index 2: Stats·Cost·Settings·About) where the AI Advisor key now
        // lives (folded in from the removed Privacy tab).
        let openSettings: () -> Void = { [weak self] in
            self?.selectTab(index: 2)
        }
        costVC.onShowPrivacy = openSettings
        statsVC.onShowPrivacy = openSettings

        // A theme / language / setting change must immediately re-render
        // the data tabs too — so the Cost hero picks up the new accent
        // (contrast-corrected per theme), the budget bar reflects a new
        // budget, and labels re-localize without reopening the window.
        let apply: (String) -> Void = { [weak self] id in
            onThemeChange(id)
            self?.statsVC.reload()
            self?.costVC.reload()
        }
        settingsVC.onThemeChange = apply
        settingsVC.onChange = { apply(ThemeStore.current.id) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        load()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func load() {
        statsVC.reload()
        costVC.reload()
    }

    func selectTab(index: Int) {
        guard index >= 0, index < tabVC.tabViewItems.count else { return }
        tabVC.selectedTabViewItemIndex = index
    }

    func capture(to path: String) {
        load()
        if let rawIndex = ProcessInfo.processInfo.environment["CONTEXTBAR_SELECT_TAB"],
           let index = Int(rawIndex) {
            selectTab(index: index)
        }
        guard let window, let targetView = window.contentView?.superview ?? window.contentView else { return }
        window.displayIfNeeded()
        targetView.layoutSubtreeIfNeeded()
        let bounds = targetView.bounds
        guard let rep = targetView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        targetView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
