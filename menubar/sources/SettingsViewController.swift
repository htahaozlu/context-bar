import AppKit
import Foundation

/// Settings pane — hosts ONLY the General preferences (Appearance · Alerts ·
/// Behavior). Privacy and About are now their own top-level tabs on the detail
/// window, so this pane no longer embeds them.
///
/// The General groups are built by `GeneralSettingsViewController` and adopted
/// into this pane's own content stack so they sit, full-width, directly inside
/// the centered 580pt column (matching `docs/macOS UI Theme/settings.jsx` —
/// `width: 580`, `justifyContent: center`).
final class SettingsViewController: PreferencePaneViewController {
    var onThemeChange: ((String) -> Void)?
    var onChange: (() -> Void)?

    private let general = GeneralSettingsViewController()

    /// Center + cap the Settings column at 580pt. The data tabs (Stats/Cost)
    /// keep the full 820pt canvas via the `nil` default on
    /// `PreferencePaneViewController`.
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

        // Adopt GENERAL's already-built group cards straight into our content
        // stack — no wrapping super-heading. Its three groups (Appearance ·
        // Alerts · Behavior) read as the top level of the pane, each a
        // full-width card in the centered 580pt column.
        adoptGroups(of: general)

        // Single centered reassurance line at the very bottom of the scroll
        // (settings.jsx footer).
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
}
