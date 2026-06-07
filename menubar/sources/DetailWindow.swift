import AppKit
import Foundation

final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC = NSTabViewController()
    let usageVC = UsageViewController()
    let statsVC = StatsViewController()
    let costVC = CostViewController()
    private let generalVC = GeneralSettingsViewController()
    private let privacyVC = PrivacySettingsViewController()
    private let aboutVC = AboutSettingsViewController()

    init(onThemeChange: @escaping (String) -> Void) {
        super.init(window: nil)

        tabVC.tabStyle = .toolbar

        let usageItem = NSTabViewItem(viewController: usageVC)
        usageItem.label = L10n.text("Usage", "Kullanım")
        usageItem.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: usageItem.label)

        let statsItem = NSTabViewItem(viewController: statsVC)
        statsItem.label = L10n.text("Stats", "İstatistik")
        statsItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: statsItem.label)

        // "Value" (was "Cost") — the figure is hypothetical API value, not a
        // bill. The hero on this tab makes that explicit.
        let costItem = NSTabViewItem(viewController: costVC)
        costItem.label = L10n.text("Value", "Değer")
        costItem.image = NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: costItem.label)

        // Settings panes: General (incl. Appearance) · Privacy · About. About
        // is its own tab again so the update controls stand on their own.
        let generalItem = NSTabViewItem(viewController: generalVC)
        generalItem.label = L10n.text("General", "Genel")
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: generalItem.label)

        let privacyItem = NSTabViewItem(viewController: privacyVC)
        privacyItem.label = L10n.text("Privacy", "Gizlilik")
        privacyItem.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: privacyItem.label)

        let aboutItem = NSTabViewItem(viewController: aboutVC)
        aboutItem.label = L10n.text("About", "Hakkında")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: aboutItem.label)

        [usageItem, statsItem, costItem, generalItem, privacyItem, aboutItem].forEach(tabVC.addTabViewItem)

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
        // wallpaper softly bleeds through behind the tab content.
        if let contentView = window.contentView {
            let effect = NSVisualEffectView(frame: contentView.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            contentView.addSubview(effect, positioned: .below, relativeTo: nil)
        }

        // "Connect a key" (Value + Stats AI advisor) jumps to the Privacy pane
        // (index 4: Usage·Stats·Value·General·Privacy) where the AI key lives.
        costVC.onShowPrivacy = { [weak self] in self?.selectTab(index: 4) }
        statsVC.onShowPrivacy = { [weak self] in self?.selectTab(index: 4) }

        // A theme/language/setting change must immediately re-render the data
        // tabs too — so the Value hero picks up the new accent (contrast-corrected
        // per theme), the budget bar reflects a new budget, and labels re-localize
        // without reopening the window.
        let apply: (String) -> Void = { [weak self] id in
            onThemeChange(id)
            self?.usageVC.reload()
            self?.statsVC.reload()
            self?.costVC.reload()
        }
        generalVC.onThemeChange = apply
        generalVC.onChange = { apply(ThemeStore.current.id) }
        privacyVC.onChange = { apply(ThemeStore.current.id) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        load()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func load() {
        usageVC.reload()
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

