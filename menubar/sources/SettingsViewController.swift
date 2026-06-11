import AppKit
import Foundation

/// Unified Settings pane. Replaces the previous three-tab split
/// (General · Privacy · About) with a single scrollable pane per the
/// `docs/macOS UI Theme` redesign — three top-level group cards:
///   1. **General** — Appearance · Alerts · Behavior (delegated to
///      `GeneralSettingsViewController.buildUI`)
///   2. **Privacy** — AI Advisor · Sharing · Across your Macs (delegated
///      to `PrivacySettingsViewController.buildUI`)
///   3. **About** — version, updates, repository context, files & shortcuts
///      (inlined from the old `AboutSettingsViewController`).
///
/// Each child pane is built as a standalone view and inserted into a
/// shared content stack so the user scrolls through all settings in one
/// continuous flow, the way System Settings now does for related prefs.
final class SettingsViewController: PreferencePaneViewController {
    var onThemeChange: ((String) -> Void)?
    var onChange: (() -> Void)?

    private let general = GeneralSettingsViewController()
    private let privacy = PrivacySettingsViewController()
    private let about = AboutSettingsViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        // Forward child events so the detail window can refresh data
        // tabs when a setting changes (theme switch, budget edit, …).
        general.onThemeChange = { [weak self] id in self?.onThemeChange?(id) }
        general.onChange = { [weak self] in self?.onChange?() }
        privacy.onChange = { [weak self] in self?.onChange?() }

        // Build each child pane into its own view and adopt the resulting
        // view into our content stack. The `addSection` / `addHero` calls
        // inside each child write into the child's own `contentStack`
        // (a private property of PreferencePaneViewController), so we
        // transplant the populated scroll view into ours.
        embed(child: general, heading: L10n.text("General", "Genel"),
               symbol: "gearshape",
               subtitle: L10n.text("How the menubar looks, alerts, and rolling windows read.",
                                   "Menubar'ın görünümü, uyarıları ve pencere davranışı."))
        embed(child: privacy, heading: L10n.text("Privacy", "Gizlilik"),
               symbol: "hand.raised",
               subtitle: L10n.text("AI advisor, sharing, and multi-machine sync.",
                                   "Yapay zekâ danışmanı, paylaşım ve çoklu makine senkronu."))
        embed(child: about,   heading: L10n.text("About", "Hakkında"),
               symbol: "info.circle",
               subtitle: L10n.text("Version, updates, files & shortcuts.",
                                   "Sürüm, güncellemeler, dosyalar ve kısayollar."))
    }

    /// Forces a child pane to lay out, then transplants its `view` (a
    /// `FlippedView` containing the populated scroll + content stack)
    /// into our content stack under a captioned header. The child keeps
    /// owning the views; we just reparent the top-level container.
    private func embed(child: PreferencePaneViewController,
                       heading: String, symbol: String, subtitle: String) {
        // `loadViewIfNeeded` is macOS 14+, so manually call the two
        // lifecycle hooks we need without the API.
        if !child.isViewLoaded { child.loadView() }
        if child.view.window == nil { child.viewDidLoad() }
        child.view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        child.view.layoutSubtreeIfNeeded()
        // Wrap the child's scroll view in a captioned container so the
        // user can scan General / Privacy / About at a glance instead of
        // having to remember which tab they came from.
        let wrap = NSStackView()
        wrap.orientation = .vertical
        wrap.alignment = .leading
        wrap.spacing = 6
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let glyph = NSImageView()
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: heading)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        glyph.contentTintColor = .secondaryLabelColor
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(heading, color: .secondaryLabelColor))
        let header = NSStackView(views: [glyph, title])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 7
        glyph.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor).isActive = true

        let sub = NSTextField(wrappingLabelWithString: subtitle)
        sub.font = NSFont.systemFont(ofSize: 11)
        sub.textColor = .tertiaryLabelColor
        sub.maximumNumberOfLines = 0

        // The child's `view` is itself a FlippedView with an NSScrollView
        // pinned to its edges. Detach the scroll view from the child so
        // it can be reparented under our wrap, otherwise AppKit treats
        // the child view as a single window content and refuses to
        // embed it twice.
        guard let scroll = child.view.subviews.compactMap({ $0 as? NSScrollView }).first else {
            return
        }
        scroll.removeFromSuperview()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // Detach the child from any further viewDidLoad / viewWillAppear
        // work — it has already built its content above. We just hold
        // the scroll view hostage inside our pane.
        child.view.removeFromSuperview()

        wrap.addArrangedSubview(header)
        wrap.addArrangedSubview(sub)
        wrap.addArrangedSubview(scroll)
        wrap.setCustomSpacing(10, after: sub)

        contentStack.addArrangedSubview(wrap)
        wrap.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: wrap.widthAnchor).isActive = true
    }
}
