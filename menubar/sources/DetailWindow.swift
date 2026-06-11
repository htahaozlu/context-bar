import AppKit
import Foundation

/// Detail window — three tabs that match the design brief (`docs/macOS UI
/// Theme`): **Stats · Cost · Settings**. The previous implementation had
/// six tabs (Usage, Stats, Value, General, Privacy, About); the redesign
/// collapses them into three by:
///   * Dropping the standalone "Usage" tab — the same data the popover
///     hero shows is already on the popover, and the Stats tab covers
///     the historical view.
///   * Renaming "Value" → "Cost" (matches the design mockup).
///   * Folding General + Privacy + About into a single "Settings" tab
///     that scrolls three group cards (General · Privacy · About).
final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC = NSTabViewController()
    let statsVC = StatsViewController()
    let costVC = CostViewController()
    private let settingsVC = SettingsViewController()

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

        // Settings — General (Appearance · Alerts · Behavior), Privacy
        // (AI Advisor · Sharing · Across your Macs), and About live in
        // one scrollable pane.
        let settingsItem = NSTabViewItem(viewController: settingsVC)
        settingsItem.label = L10n.text("Settings", "Ayarlar")
        settingsItem.image = NSImage(systemSymbolName: "gearshape",
                                      accessibilityDescription: settingsItem.label)

        [statsItem, costItem, settingsItem].forEach(tabVC.addTabViewItem)

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

        // "Connect a key" / "Connect to a server" CTAs on the Stats + Cost
        // panes jump to the Settings tab (index 2: Stats·Cost·Settings)
        // where the AI key + sync server URL live.
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
