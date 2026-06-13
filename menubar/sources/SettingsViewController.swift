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

    /// Center + cap the Settings column at 580pt (matches
    /// `docs/macOS UI Theme/settings.jsx` — `width: 580`, `justifyContent:
    /// center`). The data tabs (Stats/Cost) keep the full 820pt canvas via
    /// the `nil` default on `PreferencePaneViewController`.
    override var preferredContentWidth: CGFloat? { 580 }

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
        // groups into our content stack. The `addGroup` / `addSection` calls
        // inside each child write into the child's own `contentStack`
        // (a private property of PreferencePaneViewController), so we
        // transplant the populated rows into ours.
        //
        // GENERAL has NO parent super-heading: per settings.jsx its three
        // groups (Appearance · Alerts · Behavior) sit directly in the
        // centered 580pt column with their own caption headers. Privacy and
        // About stay reachable as captioned sections further down the same
        // continuous scroll.
        adoptGroups(of: general)
        embed(child: privacy, heading: L10n.text("Privacy", "Gizlilik"),
               symbol: "hand.raised",
               subtitle: L10n.text("AI advisor, sharing, and multi-machine sync.",
                                   "Yapay zekâ danışmanı, paylaşım ve çoklu makine senkronu."))
        embed(child: about,   heading: L10n.text("About", "Hakkında"),
               symbol: "info.circle",
               subtitle: L10n.text("Version, updates, files & shortcuts.",
                                   "Sürüm, güncellemeler, dosyalar ve kısayollar."))

        // Single centered reassurance line at the very bottom of the scroll
        // (settings.jsx footer). Rendered once here so the adopted General
        // groups and the embedded Privacy/About panes don't each repeat it.
        addSettingsFooter()
    }

    /// The lone footer line from settings.jsx, centered under every group.
    private func addSettingsFooter() {
        let label = NSTextField(labelWithString: L10n.text(
            "ContextBar 2.0 · all data stays on this Mac · no account, no server",
            "ContextBar 2.0 · tüm veriler bu Mac'te kalır · hesap yok, sunucu yok"))
        label.font = NSFont.systemFont(ofSize: 10.5)
        label.textColor = Palette.tertiaryText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// Moves a child pane's already-built group cards straight into our
    /// content stack with no wrapping super-heading — used for GENERAL so the
    /// Appearance/Alerts/Behavior groups read as the top level of the pane.
    private func adoptGroups(of child: PreferencePaneViewController) {
        if !child.isViewLoaded { child.loadView() }
        if child.view.window == nil { child.viewDidLoad() }
        child.view.layoutSubtreeIfNeeded()
        while let arranged = child.contentStack.arrangedSubviews.first {
            child.contentStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
            contentStack.addArrangedSubview(arranged)
            arranged.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
    }

    /// Forces a child pane to lay out, then transplants its `view` (a
    /// `FlippedView` containing the populated scroll + content stack)
    /// into our content stack under a captioned header. The child keeps
    /// owning the views; we just reparent the top-level container.
    private func embed(child: PreferencePaneViewController,
                       heading: String, symbol: String, subtitle: String) {
        // `loadViewIfNeeded` is macOS 14+, so manually call the two lifecycle
        // hooks we need without the API.
        if !child.isViewLoaded { child.loadView() }
        if child.view.window == nil { child.viewDidLoad() }
        child.view.layoutSubtreeIfNeeded()

        // Re-home the CHILD CONTENT STACK, not the child's scroll view. The
        // redesign wants one continuous Settings scroller; nested scroll views
        // leave the outer pane with no intrinsic height and render as the blank
        // shell seen in capture.
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

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = child.contentStack.spacing
        body.translatesAutoresizingMaskIntoConstraints = false
        while let arranged = child.contentStack.arrangedSubviews.first {
            child.contentStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
            body.addArrangedSubview(arranged)
            arranged.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }

        wrap.addArrangedSubview(header)
        wrap.addArrangedSubview(sub)
        wrap.addArrangedSubview(body)
        wrap.setCustomSpacing(10, after: sub)

        contentStack.addArrangedSubview(wrap)
        wrap.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: wrap.widthAnchor).isActive = true
    }
}
