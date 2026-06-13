import AppKit
import Foundation

// MARK: - Appearance (light / dark / system) mode store
//
// The redesign's "Theme" control is a System/Light/Dark appearance switch
// (distinct from the accent picker, which stays the ThemeCardView grid). No
// persisted store existed for this — only a capture-only env override in
// AppDelegate — so we add one here. It writes the user's choice to
// UserDefaults and applies `NSApp.appearance` live. The capture env override
// still wins at launch (it sets `NSApp.appearance` directly).
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return L10n.text("System", "Sistem")
        case .light: return L10n.text("Light", "Açık")
        case .dark: return L10n.text("Dark", "Koyu")
        }
    }
}

enum AppearanceStore {
    private static let key = "appearanceMode"
    private static let kLivePreview = "appearance.livePreview"

    static var current: AppearanceMode {
        get { AppearanceMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "system") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Whether the live menu-bar title sample shows while editing Settings.
    /// Defaults ON. (Kept here rather than DisplayPrefs since this is purely a
    /// Settings-pane affordance.)
    static var livePreview: Bool {
        get {
            if UserDefaults.standard.object(forKey: kLivePreview) == nil { return true }
            return UserDefaults.standard.bool(forKey: kLivePreview)
        }
        set { UserDefaults.standard.set(newValue, forKey: kLivePreview) }
    }

    /// Maps the stored mode to a concrete `NSAppearance` (nil = follow system)
    /// and applies it to the running app.
    static func apply() {
        switch current {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Alerts (warning-threshold) store
//
// The redesign's "Context bar marks" control is a % picker (Off / 60 / 70 /
// 75 / 80 / 90) rather than a plain on/off. We persist the chosen threshold
// here and keep the existing `DisplayPrefs.tickMarks` boolean in sync (Off →
// false, any % → true) so the bar-rendering path is unchanged.
enum AlertsStore {
    private static let kThreshold = "alerts.barMarkThreshold"

    /// % values offered by the popup. `0` = Off.
    static let thresholds: [Int] = [0, 60, 70, 75, 80, 90]

    /// Persisted warning threshold. 0 = off. Defaults to 0 (off) to match the
    /// previous out-of-box `tickMarks == false`.
    static var threshold: Int {
        get {
            if UserDefaults.standard.object(forKey: kThreshold) == nil {
                return DisplayPrefs.tickMarks ? 75 : 0
            }
            return UserDefaults.standard.integer(forKey: kThreshold)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kThreshold)
            DisplayPrefs.tickMarks = newValue > 0
        }
    }

    static var optionLabels: [String] {
        thresholds.map { $0 == 0 ? L10n.text("Off", "Kapalı") : "\($0)%" }
    }
    static var selectedIndex: Int {
        thresholds.firstIndex(of: threshold) ?? 0
    }
}

// MARK: - Budget cap presets
//
// The redesign's "Budget alerts" control is a cap-preset popup (Off / $50 /
// $100 / $150 / $300 mo) mapped onto the existing `DisplayPrefs.monthlyBudgetUSD`
// pref. The detailed field + live pace preview is preserved as a wide row.
enum BudgetPresets {
    /// USD/month caps. `0` = Off.
    static let caps: [Double] = [0, 50, 100, 150, 300]

    static var optionLabels: [String] {
        caps.map { $0 == 0 ? L10n.text("Off", "Kapalı") : String(format: "$%.0f/mo", $0) }
    }
    /// Index of the preset matching the current budget, or 0 (Off) when the
    /// budget is a custom value not in the preset list.
    static var selectedIndex: Int {
        caps.firstIndex(of: DisplayPrefs.monthlyBudgetUSD) ?? 0
    }
}

// MARK: - Grouped settings card
//
// The redesign collapses each settings pane into a few native grouped sections.
// A section is an UPPERCASE caption with a small leading SF-symbol glyph above a
// single rounded card (the standard `Surface.applyCard` recipe). Rows inside the
// card are separated by 0.5pt hairlines; each row carries a label (plus an
// optional dim sub-description) on the left and a control on the right. This
// mirrors System Settings' grouped lists while keeping our warm clay palette.

/// One label/(description)/control row inside a `SettingsGroupCard`. Draws its
/// own 0.5pt top hairline unless it is the first row in the card.
private final class SettingsRowView: NSView {
    private let separator = NSView()

    /// - Parameters:
    ///   - title: primary label (medium weight, primary text).
    ///   - desc: optional dim sub-description shown beneath the label.
    ///   - control: trailing control (switch / popup / segmented / field).
    ///   - leadingHairline: draw the top hairline (false for the first row).
    init(title: String, desc: String?, control: NSView, leadingHairline: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.isHidden = !leadingHairline
        addSubview(separator)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = Palette.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail

        // Left column — title, optionally stacked over a dim description.
        let labelStack = NSStackView(views: [titleLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 1
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        if let desc, !desc.isEmpty {
            let descLabel = NSTextField(wrappingLabelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 10.5)
            descLabel.textColor = Palette.tertiaryText
            descLabel.maximumNumberOfLines = 0
            labelStack.addArrangedSubview(descLabel)
        }

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(labelStack)
        addSubview(control)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            labelStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            labelStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            labelStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            control.leadingAnchor.constraint(greaterThanOrEqualTo: labelStack.trailingAnchor, constant: Spacing.m),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            control.centerYAnchor.constraint(equalTo: labelStack.centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])

        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refreshColors() {
        separator.layer?.backgroundColor = Palette.hairline.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

/// Full-width row body with a leading hairline — used by `addWideRow` for a
/// control (theme grid, preview, chip strip) that needs the card's full width
/// beneath its label.
private final class SettingsWideRowView: NSView {
    private let separator = NSView()

    init(content: NSView, leadingHairline: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.isHidden = !leadingHairline
        addSubview(separator)

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refreshColors() {
        separator.layer?.backgroundColor = Palette.hairline.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

/// A single rounded card that stacks `SettingsRowView`s with hairline dividers.
/// Use `addRow` for the standard label+control row, or `addWideRow` for a
/// control (theme grid, preview, chip strip) that needs the full width beneath
/// its label.
private final class SettingsGroupCard: NSView {
    private let stack = NSStackView()
    private var rowCount = 0

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Surface.applyCard(self)
        layer?.masksToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func addRow(title: String, desc: String? = nil, control: NSView) {
        let row = SettingsRowView(title: title, desc: desc, control: control,
                                  leadingHairline: rowCount > 0)
        appendRow(row)
    }

    /// A row whose control occupies the full card width below the label —
    /// for the theme grid, the menubar preview, and the title-field chips.
    /// Returns the created row so callers can show/hide it (e.g. the live
    /// preview sample toggles with its switch).
    @discardableResult
    func addWideRow(title: String, desc: String? = nil, content: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = Palette.primaryText

        let column = NSStackView(views: [titleLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        var lastLabel: NSView = titleLabel
        if let desc, !desc.isEmpty {
            let descLabel = NSTextField(wrappingLabelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 10.5)
            descLabel.textColor = Palette.tertiaryText
            descLabel.maximumNumberOfLines = 0
            column.addArrangedSubview(descLabel)
            lastLabel = descLabel
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(content)
        // Wider gap between the label block and the full-width control below it.
        column.setCustomSpacing(10, after: lastLabel)

        let wrapper = SettingsWideRowView(content: column, leadingHairline: rowCount > 0)
        appendRow(wrapper)
        content.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return wrapper
    }

    private func appendRow(_ row: NSView) {
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        rowCount += 1
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

extension PreferencePaneViewController {
    /// Adds an UPPERCASE caption (with a small leading SF-symbol glyph) above a
    /// `SettingsGroupCard`, then arranges it into the content stack. Returns the
    /// card so the caller can append rows.
    fileprivate func addGroup(symbol: String, title: String) -> SettingsGroupCard {
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 8
        group.translatesAutoresizingMaskIntoConstraints = false

        let glyph = NSImageView()
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        glyph.contentTintColor = Palette.secondaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(title, color: Palette.secondaryText))

        let header = NSStackView(views: [glyph, caption])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 7
        // Keep the glyph optically aligned with the kerned caption baseline.
        glyph.firstBaselineAnchor.constraint(equalTo: caption.firstBaselineAnchor).isActive = true
        group.addArrangedSubview(header)

        let card = SettingsGroupCard()
        group.addArrangedSubview(card)

        contentStack.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        card.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return card
    }

    /// Centered tertiary "stays on this Mac" reassurance line under the groups.
    fileprivate func addPrivacyFooter() {
        let label = NSTextField(labelWithString: L10n.text(
            "ContextBar · local-first · no account required · sync stays in your iCloud or your own server",
            "ContextBar · yerel öncelikli · hesap gerekmez · senkron kendi iCloud'unuzda ya da kendi sunucunuzda kalır"))
        label.font = NSFont.systemFont(ofSize: 10.5)
        label.textColor = Palette.tertiaryText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }
}

// MARK: - Settings controls (switch)

/// Trailing on/off control matching the redesign — an NSSwitch tinted with the
/// app accent so toggles read as one consistent affordance.
private func makeSettingsSwitch(on: Bool, target: AnyObject, action: Selector,
                                a11y: String) -> NSSwitch {
    let toggle = NSSwitch()
    toggle.state = on ? .on : .off
    toggle.target = target
    toggle.action = action
    toggle.setAccessibilityLabel(a11y)
    return toggle
}

// MARK: - General pane (Appearance · Alerts · Behavior)

/// General settings — merges the former Menubar, Display, Notifications, and
/// Appearance tabs into one pane. The settings window holds General · Privacy ·
/// About (the 3 data views live on their own tabs). The redesign reorganizes
/// this pane into three grouped cards: APPEARANCE (how the menubar looks),
/// ALERTS (what surfaces an attention signal), and BEHAVIOR (how values read).
final class GeneralSettingsViewController: PreferencePaneViewController {
    var onThemeChange: ((String) -> Void)?
    var onChange: (() -> Void)?
    private var displayChips = HorizontalDisplayController()
    /// Stable container the chips controller's view lives inside, so the "N
    /// shown" popup can toggle a field, rebuild the controller from the
    /// persisted store, and swap the chips view in without losing its place in
    /// the card.
    private let chipsHolder = FlippedView()
    private let preview = TitlePreviewView()
    private var cardViews: [(ThemeCardView, Theme)] = []
    private var titleFieldsPopup: PopupButton?
    private var previewSwitch: PillSwitch?
    private var previewRow: NSView?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Enforce the persisted appearance mode when the UI is built. (Launch
        // is owned by AppDelegate, which is frozen; this is the earliest hook
        // we own.) Skip when a capture-only override is pinned via env so
        // marketing/regression screenshots keep their forced appearance.
        if ProcessInfo.processInfo.environment["CONTEXTBAR_FORCE_APPEARANCE"] == nil {
            AppearanceStore.apply()
        }
        buildUI()
        refreshPreview()
    }

    private func buildUI() {
        buildAppearanceGroup()
        buildAlertsGroup()
        buildBehaviorGroup()
        // Footer is rendered once by the parent SettingsViewController at the
        // very bottom of the combined scroll (settings.jsx renders it once).
    }

    /// APPEARANCE — theme mode, accent grid, language, separator, title fields,
    /// live preview. (Formerly the standalone Appearance tab, merged into
    /// General.) Mirrors settings.jsx's "Appearance" group, row for row.
    private func buildAppearanceGroup() {
        let appearance = addGroup(symbol: "paintbrush", title: L10n.text("Appearance", "Görünüm"))

        // ── Theme → System / Light / Dark pill segmented control (settings.jsx
        //    `SegCtrl options={['System','Light','Dark']}`). Drives the live
        //    NSApp.appearance via AppearanceStore.
        let modeCtrl = PillSegmentedControl(
            options: AppearanceMode.allCases.map(\.label),
            selectedIndex: AppearanceMode.allCases.firstIndex(of: AppearanceStore.current) ?? 0
        ) { [weak self] idx in
            AppearanceStore.current = AppearanceMode.allCases[idx]
            AppearanceStore.apply()
            self?.refreshPreview()
            self?.onThemeChange?(ThemeStore.current.id)
        }
        modeCtrl.setAccessibilityLabel(L10n.text("Theme", "Tema"))
        appearance.addRow(
            title: L10n.text("Theme", "Tema"),
            desc: L10n.text(
                "Follow the system appearance, or pin Light / Dark.",
                "Sistem görünümünü izleyin ya da Açık / Koyu sabitleyin."),
            control: modeCtrl)

        // ── Accent — KEEP the rich named-palette picker (ThemeCardView grid).
        //    Distinct from Theme mode above: this is the single chromatic note
        //    (Clay / Indigo / Teal). Full-width row below the mode switch.
        cardViews = Theme.all.map { theme in
            let card = ThemeCardView(theme: theme)
            card.isSelected = theme.id == ThemeStore.current.id
            card.translatesAutoresizingMaskIntoConstraints = false
            card.onSelect = { [weak self] in
                ThemeStore.set(theme.id)
                self?.updateCardSelection()
                self?.onThemeChange?(theme.id)
            }
            return (card, theme)
        }
        let rows = stride(from: 0, to: cardViews.count, by: 3).map { start -> NSStackView in
            let end = min(start + 3, cardViews.count)
            let row = NSStackView(views: cardViews[start..<end].map { $0.0 as NSView })
            row.orientation = .horizontal
            row.spacing = 12
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            return row
        }
        let themeGrid = NSStackView(views: rows)
        themeGrid.orientation = .vertical
        themeGrid.spacing = 12
        appearance.addWideRow(
            title: L10n.text("Accent", "Vurgu"),
            desc: L10n.text(
                "The single accent hue used across the menubar and panes.",
                "Menubar ve panellerde kullanılan tek vurgu rengi."),
            content: themeGrid)
        cardViews.forEach { $0.0.heightAnchor.constraint(equalToConstant: 82).isActive = true }

        // ── Language → rounded popup (Auto · English · Türkçe). settings.jsx
        //    `<Popup value="English" />`.
        let langOptions = AppLanguage.allCases.map { lang -> String in
            switch lang {
            case .auto: return L10n.text("Auto", "Otomatik")
            case .en: return "English"
            case .tr: return "Türkçe"
            }
        }
        let langPopup = PopupButton(
            options: langOptions,
            selectedIndex: AppLanguage.allCases.firstIndex(of: LanguageStore.selected) ?? 0
        ) { [weak self] idx in
            LanguageStore.set(AppLanguage.allCases[idx])
            self?.onThemeChange?(ThemeStore.current.id)
        }
        langPopup.setAccessibilityLabel(L10n.text("Language", "Dil"))
        appearance.addRow(
            title: L10n.text("Language", "Dil"),
            desc: L10n.text(
                "Follow the system language or pin to English / Turkish.",
                "Sistem dilini izleyin ya da İngilizce / Türkçe sabitleyin."),
            control: langPopup)

        // ── Menu-bar separator → rounded popup of glyph options. settings.jsx
        //    `<Popup value="·  dot" />`, desc "Character between title fields".
        let sepOptions = SeparatorStore.options.map { opt -> String in
            opt.value.isEmpty ? L10n.text("None", "Yok") : opt.label
        }
        let sepPopup = PopupButton(
            options: sepOptions,
            selectedIndex: SeparatorStore.currentIndex
        ) { [weak self] idx in
            SeparatorStore.set(SeparatorStore.options[idx].value)
            self?.refreshPreview()
            self?.onThemeChange?(ThemeStore.current.id)
        }
        sepPopup.setAccessibilityLabel(L10n.text("Menu-bar separator", "Menü çubuğu ayracı"))
        appearance.addRow(
            title: L10n.text("Menu-bar separator", "Menü çubuğu ayracı"),
            desc: L10n.text(
                "Character between title fields.",
                "Başlık alanları arasındaki karakter."),
            control: sepPopup)

        // ── Title fields → "N shown" popup (settings.jsx `<Popup value="3
        //    shown" />`, desc "Project · Model · Context %"). The popup toggles
        //    a field's visibility; the rich drag-reorder chips stay below it as
        //    a full-width row so the reorder feature is preserved.
        titleFieldsPopup = makeTitleFieldsPopup()
        appearance.addRow(
            title: L10n.text("Title fields", "Başlık alanları"),
            desc: L10n.text("Project · Model · Context %", "Proje · Model · Bağlam %"),
            control: titleFieldsPopup!)
        refreshTitleFieldsPopup()

        wireChips()
        appearance.addWideRow(
            title: L10n.text("Reorder fields", "Alanları sırala"),
            desc: L10n.text(
                "Toggle a field's checkbox to show it. Drag the ⠿ handle to reorder.",
                "Bir alanı göstermek için onay kutusunu işaretleyin. Sıralamak için ⠿ tutamacından sürükleyin."),
            content: chipsHolder)

        // ── Live preview → pill switch (settings.jsx `<Switch on />`, desc
        //    "Show this menu-bar title sample while editing"). The sample
        //    itself stays visible below as a full-width row.
        previewSwitch = PillSwitch(isOn: AppearanceStore.livePreview) { [weak self] on in
            AppearanceStore.livePreview = on
            self?.applyPreviewVisibility()
        }
        previewSwitch?.setAccessibilityLabel(L10n.text("Live preview", "Canlı önizleme"))
        appearance.addRow(
            title: L10n.text("Live preview", "Canlı önizleme"),
            desc: L10n.text(
                "Show this menu-bar title sample while editing.",
                "Düzenlerken bu menü çubuğu başlık örneğini göster."),
            control: previewSwitch!)

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        previewRow = appearance.addWideRow(
            title: L10n.text("Preview", "Önizleme"),
            desc: nil,
            content: preview)
        applyPreviewVisibility()
    }

    /// Builds the "N shown" popup for title-field visibility. Each menu item
    /// is a field with a leading ✓ when visible; picking one toggles it. The
    /// displayed value summarizes how many fields are shown. Checkmarks are
    /// rendered as a text prefix (not the popup's single-selection state) so
    /// the menu reads as a multi-toggle list.
    private func makeTitleFieldsPopup() -> PopupButton {
        let popup = PopupButton(options: [], selectedIndex: 0) { [weak self] idx in
            guard let self else { return }
            self.toggleTitleField(at: idx)
            self.refreshPreview()
            self.refreshTitleFieldsPopup()
            self.onThemeChange?(ThemeStore.current.id)
        }
        return popup
    }

    /// Refreshes the title-fields popup option list + summary value to mirror
    /// the persisted display items (kept in sync with the reorder chips).
    private func refreshTitleFieldsPopup() {
        guard let popup = titleFieldsPopup else { return }
        let items = DisplayStore.items
        let opts = items.map { item -> String in
            (item.enabled ? "✓ " : "   ") + item.element.label
        }
        let shown = items.filter { $0.enabled }.count
        popup.setOptions(opts, selectedIndex: 0)
        popup.setValue(L10n.text("\(shown) shown", "\(shown) gösteriliyor"))
    }

    private func applyPreviewVisibility() {
        let on = AppearanceStore.livePreview
        previewRow?.isHidden = !on
        if on { refreshPreview() }
    }

    /// Installs the chips controller's container into the stable holder and
    /// wires its change handler. Called once on build, and again from
    /// `reloadChips()` after the "N shown" popup toggles a field.
    private func wireChips() {
        displayChips.onChange = { [weak self] in
            self?.refreshPreview()
            self?.refreshTitleFieldsPopup()
            self?.onThemeChange?(ThemeStore.current.id)
        }
        let container = displayChips.container
        chipsHolder.translatesAutoresizingMaskIntoConstraints = false
        chipsHolder.subviews.forEach { $0.removeFromSuperview() }
        container.translatesAutoresizingMaskIntoConstraints = false
        chipsHolder.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: chipsHolder.topAnchor),
            container.leadingAnchor.constraint(equalTo: chipsHolder.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: chipsHolder.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: chipsHolder.bottomAnchor),
        ])
    }

    /// Rebuilds the chips controller from the persisted `DisplayStore` (the
    /// source of truth) and swaps its fresh container into the holder. Used
    /// after the popup toggles a field so the chip checkboxes stay in sync —
    /// the controller reads `DisplayStore.items` on init.
    private func reloadChips() {
        displayChips = HorizontalDisplayController()
        wireChips()
    }

    /// Toggles a title field's visibility from the "N shown" popup, persists
    /// it, and re-syncs the chips so both controls agree.
    private func toggleTitleField(at index: Int) {
        var items = DisplayStore.items
        guard index >= 0, index < items.count else { return }
        items[index].enabled.toggle()
        DisplayStore.save(items)
        reloadChips()
    }

    /// ALERTS — context-bar marks, background sessions, provider status, monthly
    /// budget. Everything that can raise an attention signal in the menubar.
    /// (Merges the former Notifications/Alerts and the alert-shaped Display rows.)
    private func buildAlertsGroup() {
        let alerts = addGroup(symbol: "bell", title: L10n.text("Alerts", "Uyarılar"))

        // ── Context bar marks → % threshold popup (settings.jsx
        //    `<Popup value="75%" />`, desc "Tick the bar at your warning
        //    threshold"). Off / 60 / 70 / 75 / 80 / 90. Keeps DisplayPrefs.
        //    tickMarks in sync via AlertsStore.
        let marksPopup = PopupButton(
            options: AlertsStore.optionLabels,
            selectedIndex: AlertsStore.selectedIndex
        ) { [weak self] idx in
            AlertsStore.threshold = AlertsStore.thresholds[idx]
            self?.onChange?()
        }
        marksPopup.setAccessibilityLabel(L10n.text("Context bar marks", "Bağlam çubuğu işaretleri"))
        alerts.addRow(
            title: L10n.text("Context bar marks", "Bağlam çubuğu işaretleri"),
            desc: L10n.text(
                "Tick the bar at your warning threshold.",
                "Çubuğu uyarı eşiğinizde işaretleyin."),
            control: marksPopup)

        // ── Background sessions → pill switch.
        alerts.addRow(
            title: L10n.text("Background sessions", "Arka plan oturumları"),
            desc: L10n.text(
                "Surface a background session above 80% while the foreground is calm.",
                "Aktif oturum sakinken %80'i geçen arka plan oturumunu göster."),
            control: makePillSwitch(on: DisplayPrefs.criticalBackground) { on in
                DisplayPrefs.criticalBackground = on
            })

        // ── Provider status → pill switch.
        alerts.addRow(
            title: L10n.text("Provider status", "Sağlayıcı durumu"),
            desc: L10n.text(
                "Surface Anthropic / OpenAI incidents.",
                "Anthropic / OpenAI olaylarını göster."),
            control: makePillSwitch(on: DisplayPrefs.incidents) { on in
                DisplayPrefs.incidents = on
                if on { IncidentPoller.shared.start() } else { IncidentPoller.shared.stop() }
            })

        // ── Budget alerts → cap-preset popup (settings.jsx `<Popup
        //    value="$150/mo" />`, desc "Warn as API-equivalent value passes a
        //    cap"). Off / $50 / $100 / $150 / $300. Mapped onto
        //    DisplayPrefs.monthlyBudgetUSD.
        let budgetPopup = PopupButton(
            options: BudgetPresets.optionLabels,
            selectedIndex: BudgetPresets.selectedIndex
        ) { [weak self] idx in
            DisplayPrefs.monthlyBudgetUSD = BudgetPresets.caps[idx]
            self?.syncBudgetField()
            self?.refreshBudgetPace()
            self?.onChange?()
        }
        budgetPopup.setAccessibilityLabel(L10n.text("Budget alerts", "Bütçe uyarıları"))
        budgetPopupRef = budgetPopup
        alerts.addRow(
            title: L10n.text("Budget alerts", "Bütçe uyarıları"),
            desc: L10n.text(
                "Warn as API-equivalent value passes a cap.",
                "API eşdeğeri değer bir sınırı aşınca uyar."),
            control: budgetPopup)

        // Custom budget + live pace preview — preserved as a wide row so a
        // user who wants a non-preset cap can still type one, and so the live
        // run-rate vs. cap (color tier) sits directly under the input.
        alerts.addWideRow(
            title: L10n.text("Custom budget", "Özel bütçe"),
            desc: L10n.text(
                "Type any monthly cap, or read the live pace below. 0 = off.",
                "Herhangi bir aylık sınır yazın ya da aşağıdaki canlı hızı okuyun. 0 = kapalı."),
            content: makeBudgetFieldAndPreview())
    }

    /// BEHAVIOR — how rolling-window resets read, and celebration.
    private func buildBehaviorGroup() {
        let behavior = addGroup(symbol: "slider.horizontal.3", title: L10n.text("Behavior", "Davranış"))

        // ── Limit reset style → Countdown / Clock pill segmented control
        //    (settings.jsx `SegCtrl options={['Countdown','Clock']}`). Maps
        //    0 → relative (countdown), 1 → absolute (clock).
        let resetCtrl = PillSegmentedControl(
            options: [L10n.text("Countdown", "Geri sayım"), L10n.text("Clock", "Saat")],
            selectedIndex: DisplayPrefs.resetStyle == .relative ? 0 : 1
        ) { [weak self] idx in
            DisplayPrefs.resetStyle = idx == 0 ? .relative : .absolute
            self?.onChange?()
        }
        resetCtrl.setAccessibilityLabel(L10n.text("Limit reset style", "Limit sıfırlama biçimi"))
        behavior.addRow(
            title: L10n.text("Limit reset style", "Limit sıfırlama biçimi"),
            desc: L10n.text(
                "How rolling-window resets are shown.",
                "Pencere sıfırlamalarının nasıl gösterileceği."),
            control: resetCtrl)

        // ── Delight → pill switch (settings.jsx `<Switch on />`).
        behavior.addRow(
            title: L10n.text("Delight", "İnce dokunuş"),
            desc: L10n.text(
                "Celebrate streaks and milestones.",
                "Serileri ve dönüm noktalarını kutla."),
            control: makePillSwitch(on: DisplayPrefs.confetti) { on in
                DisplayPrefs.confetti = on
            })
    }

    private func updateCardSelection() {
        let current = ThemeStore.current.id
        for (card, theme) in cardViews { card.isSelected = theme.id == current }
    }

    /// Builds a redesign `PillSwitch`, runs the persistence action, and forwards
    /// an `onChange` so the data tabs refresh.
    private func makePillSwitch(on: Bool, persist: @escaping (Bool) -> Void) -> PillSwitch {
        PillSwitch(isOn: on) { [weak self] value in
            persist(value)
            self?.onChange?()
        }
    }

    /// Field + a live pace preview that re-renders on every refresh. The
    /// preview is a monospaced "X / Y · tier" line, tinted to match the
    /// menubar color tier the user would see live.
    private func makeBudgetFieldAndPreview() -> NSView {
        let field = NSTextField()
        field.placeholderString = L10n.text("USD / month", "USD / ay")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let v = DisplayPrefs.monthlyBudgetUSD
        field.stringValue = v > 0 ? String(format: "%.0f", v) : ""
        field.target = self
        field.action = #selector(budgetChanged(_:))
        field.setAccessibilityLabel(L10n.text("Monthly budget USD", "Aylık bütçe USD"))
        budgetField = field

        let fieldRow = NSStackView(views: [NSTextField(labelWithString: "$"), field])
        fieldRow.orientation = .horizontal
        fieldRow.spacing = 4
        fieldRow.alignment = .firstBaseline

        // Pace preview — sits right under the field so the user sees
        // "$847 / $1500 · comfortable" the moment they commit a value.
        let pace = NSTextField(labelWithString: "")
        pace.font = Typography.bodyMono(11, weight: .regular)
        pace.textColor = .secondaryLabelColor
        pace.maximumNumberOfLines = 0
        pace.lineBreakMode = .byWordWrapping
        pace.translatesAutoresizingMaskIntoConstraints = false
        budgetPaceLabel = pace

        let column = NSStackView(views: [fieldRow, pace])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        refreshBudgetPace()
        return column
    }

    private weak var budgetPaceLabel: NSTextField?
    private weak var budgetField: NSTextField?
    private weak var budgetPopupRef: PopupButton?

    @objc private func budgetChanged(_ sender: NSTextField) {
        let cleaned = sender.stringValue.filter { $0.isNumber || $0 == "." }
        DisplayPrefs.monthlyBudgetUSD = Double(cleaned) ?? 0
        syncBudgetPopup()
        onChange?()
        refreshBudgetPace()
    }

    /// Reflects the current budget back into the custom field (used when the
    /// preset popup changes the value).
    private func syncBudgetField() {
        let v = DisplayPrefs.monthlyBudgetUSD
        budgetField?.stringValue = v > 0 ? String(format: "%.0f", v) : ""
    }

    /// Reflects the current budget into the preset popup — selecting the
    /// matching preset, or "Off"/value-as-shown for a custom amount.
    private func syncBudgetPopup() {
        guard let popup = budgetPopupRef else { return }
        let v = DisplayPrefs.monthlyBudgetUSD
        if let idx = BudgetPresets.caps.firstIndex(of: v) {
            popup.setOptions(BudgetPresets.optionLabels, selectedIndex: idx)
        } else if v > 0 {
            // Custom amount with no matching preset — show the raw cap.
            popup.setValue(String(format: "$%.0f/mo", v))
        } else {
            popup.setOptions(BudgetPresets.optionLabels, selectedIndex: 0)
        }
    }

    /// Computes run-rate vs cap and writes the preview line. Color
    /// matches the menubar tier the user would see live: green for
    /// comfortable, orange for close, red for over.
    private func refreshBudgetPace() {
        guard let label = budgetPaceLabel else { return }
        let budget = DisplayPrefs.monthlyBudgetUSD
        guard budget > 0 else {
            label.stringValue = L10n.text(
                "No budget set. Menubar tier will follow the 5h limit % only.",
                "Bütçe yok. Menubar rengi yalnızca 5sa limit %'sini izler.")
            label.textColor = .tertiaryLabelColor
            return
        }
        let (_, agents, _) = ContextSnapshot().load()
        let runRate = agents.reduce(0.0) { $0 + $1.totalCost30d }
        let ratio = runRate / budget
        let cap = "\(ContextSnapshot.formatUSD(runRate))  ·  \(ContextSnapshot.formatUSD(budget))"
        let tier: String
        let color: NSColor
        switch ratio {
        case 1...:
            tier = L10n.text("over budget", "bütçe aşıldı")
            color = .systemRed
        case 0.8...:
            tier = L10n.text("close to cap", "sınıra yakın")
            color = .systemOrange
        default:
            tier = L10n.text("comfortable", "rahat")
            color = .systemGreen
        }
        label.stringValue = "\(cap)  ·  \(tier)"
        label.textColor = color
    }

    private func refreshPreview() {
        preview.update(
            items: displayChips.currentItems,
            agent: "Claude",
            project: L10n.text("my-project", "projem"),
            pct: 27
        )
    }
}

// MARK: - Privacy pane

/// Privacy settings — the AI Advisor opt-in, output redaction, and cross-Mac
/// sync. Reorganized into grouped cards: AI ADVISOR (the actionable opt-in),
/// SHARING (what gets masked in exports), and SYNC (combine usage across Macs).
final class PrivacySettingsViewController: PreferencePaneViewController {
    var onChange: (() -> Void)?
    private let aiProviderPopup = NSPopUpButton()
    private let aiKeyField = NSSecureTextField()
    private let aiRunButton = NSButton()
    private let aiResultLabel = NSTextField(labelWithString: "")
    private let syncURLField = NSTextField()
    private let syncStatusPill = NSTextField(labelWithString: "")
    private let syncPillDot = NSView()
    private let syncDetailLabel = NSTextField(labelWithString: "")
    private let syncNowButton = NSButton()
    private let syncTestButton = NSButton()
    private let syncFolderLabel = NSTextField(labelWithString: "")
    private let iCloudStatusLabel = NSTextField(labelWithString: "")
    private weak var iCloudSyncButton: NSButton?
    private var syncObserverToken: UUID?
    private var syncHeartbeat: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshAIStatus()
        refreshSyncStatus()
        observeSyncState()
    }

    deinit {
        if let t = syncObserverToken { ServerSync.shared.unobserve(t) }
        syncHeartbeat?.invalidate()
    }

    private func buildUI() {
        // ── AI ADVISOR — the actionable opt-in users come here for.
        let advisor = addGroup(symbol: "sparkles", title: L10n.text("AI Advisor", "AI Danışman"))
        advisor.addWideRow(
            title: L10n.text("Bring your own key", "Kendi anahtarını getir"),
            desc: L10n.text(
                "Optional. Connect your own OpenAI or Gemini API key for usage-efficiency tips. Only an aggregate summary — no transcripts, no project names — is sent, and only when you press Run analysis. Off by default.",
                "İsteğe bağlı. Kullanım verimliliği önerileri için kendi OpenAI veya Gemini API anahtarını bağla. Yalnızca özet — transcript yok, proje adı yok — gönderilir, o da yalnızca Analizi çalıştır'a bastığında. Varsayılan kapalı."),
            content: makeAIAdvisorField())

        // Run + last result row. Stays in the same card so the user can
        // set a key, press Run, and read the result in one continuous
        // flow without leaving the pane.
        advisor.addWideRow(
            title: L10n.text("Last analysis", "Son analiz"),
            desc: nil,
            content: makeAIRunRow())

        // ── SHARING — what gets masked when you export or share.
        let sharing = addGroup(symbol: "eye.slash", title: L10n.text("Sharing", "Paylaşım"))
        sharing.addRow(
            title: L10n.text("Shared output", "Paylaşılan çıktı"),
            desc: L10n.text(
                "Replace $HOME with ~, collapse /Users/<name>/ paths, and mask emails in exports.",
                "Dışa aktarımda $HOME değerini ~ yapar, /Users/<ad>/ yollarını sadeleştirir ve e-postaları gizler."),
            control: makeSwitch(on: DisplayPrefs.redactPaths, action: #selector(redactChanged(_:)),
                                a11y: L10n.text("Mask project paths and emails", "Proje yollarını ve e-postaları gizle")))

        sharing.addRow(
            title: L10n.text("Share card", "Paylaşım kartı"),
            desc: L10n.text(
                "Replace real project names with generic labels (Project A, B) when sharing Today's HUD.",
                "Today's HUD paylaşılırken gerçek proje adlarını genel etiketlerle (Proje A, B) değiştirir."),
            control: makeSwitch(on: DisplayPrefs.maskShareProjects, action: #selector(maskShareChanged(_:)),
                                a11y: L10n.text("Mask project names on share card", "Paylaşım kartında proje adlarını gizle")))

        // ── SYNC — combine usage across your Macs.
        // Three paths, listed in order of recommendation:
        //   1. iCloud Drive (easiest) — zero-config, no account, no server.
        //      Same Apple ID → flip the switch on each Mac and you're done.
        //   2. Self-hosted server — a tiny Rust binary on a homelab box for
        //      users who'd rather not route through iCloud.
        //   3. Manual folder — any folder you already sync (Dropbox, …).
        let sync = addGroup(symbol: "macbook.and.iphone", title: L10n.text("Across your Macs", "Mac'lerin arasında"))

        sync.addWideRow(
            title: L10n.text("iCloud Drive", "iCloud Drive"),
            desc: L10n.text(
                "Easiest. No account, no server. Turn this on with the same Apple ID on each Mac and ContextBar syncs your usage through your own iCloud Drive automatically.",
                "En kolayı. Hesap yok, sunucu yok. Her Mac'te aynı Apple ID ile bunu açın; ContextBar kullanımınızı kendi iCloud Drive'ınız üzerinden otomatik senkronlar."),
            content: makeICloudSyncRow())

        sync.addWideRow(
            title: L10n.text("Self-hosted server", "Kendi sunucunuz"),
            desc: L10n.text(
                "For homelab setups. Run the bundled `context-bar-server` on any always-on Mac (a Pi, NAS, homelab box) and point every Mac at it. Each Mac pushes its rollup; the Value tab combines them. No third-party service.",
                "Ev sunucusu kurulumları için. Paketlenmiş `context-bar-server`'ı sürekli açık bir Mac'te (Pi, NAS, ev sunucusu) çalıştırıp her Mac'i ona yönlendirin. Her Mac özetini gönderir; Değer sekmesi birleştirir. Üçüncü taraf yok."),
            content: makeSyncServerField())

        sync.addWideRow(
            title: L10n.text("Status", "Durum"),
            desc: nil,
            content: makeSyncStatusRow())

        sync.addWideRow(
            title: L10n.text("Local sync folder (legacy)", "Yerel senkron klasörü (eski)"),
            desc: L10n.text(
                "Only needed if you don't want to run a server. Each Mac writes a compact usage file there; the Value tab then combines them.",
                "Yalnızca sunucu çalıştırmak istemiyorsanız gerekir. Her Mac oraya özet kullanım yazar; Değer sekmesi birleştirir."),
            content: makeSyncFolderField())

        // Footer is rendered once by the parent SettingsViewController at the
        // very bottom of the combined scroll.
    }

    // ── AI ADVISOR UI

    private func makeAIAdvisorField() -> NSView {
        aiProviderPopup.removeAllItems()
        AIProvider.allCases.forEach { aiProviderPopup.addItem(withTitle: $0.label) }
        aiProviderPopup.selectItem(at: AIProvider.allCases.firstIndex(of: DisplayPrefs.aiProvider) ?? 0)
        aiProviderPopup.target = self
        aiProviderPopup.action = #selector(aiProviderChanged(_:))
        aiProviderPopup.translatesAutoresizingMaskIntoConstraints = false
        aiProviderPopup.setAccessibilityLabel(L10n.text("AI provider", "AI sağlayıcı"))

        aiKeyField.placeholderString = keyPlaceholder(for: DisplayPrefs.aiProvider)
        aiKeyField.target = self
        aiKeyField.action = #selector(aiKeyCommitted(_:))
        aiKeyField.translatesAutoresizingMaskIntoConstraints = false
        aiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        aiKeyField.setAccessibilityLabel(L10n.text("API key", "API anahtarı"))

        let row = NSStackView(views: [aiProviderPopup, aiKeyField])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline
        row.distribution = .fill
        aiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    /// Run button + a multi-line result area. The result area shows either
    /// the last analysis (from `LocalStore`) or, while a run is in flight,
    /// a status line.
    private func makeAIRunRow() -> NSView {
        aiRunButton.title = L10n.text("Run analysis", "Analizi çalıştır")
        aiRunButton.bezelStyle = .rounded
        aiRunButton.target = self
        aiRunButton.action = #selector(aiRunTapped(_:))
        aiRunButton.translatesAutoresizingMaskIntoConstraints = false
        aiRunButton.setContentHuggingPriority(.required, for: .horizontal)

        aiResultLabel.font = Typography.bodyMono(11, weight: .regular)
        aiResultLabel.textColor = .secondaryLabelColor
        aiResultLabel.maximumNumberOfLines = 0
        aiResultLabel.lineBreakMode = .byWordWrapping
        aiResultLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [aiRunButton, aiResultLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8

        let row = NSStackView(views: [column])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        column.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return row
    }

    private func keyPlaceholder(for p: AIProvider) -> String {
        if p == .off { return L10n.text("Select a provider first", "Önce bir sağlayıcı seçin") }
        return AIKeychain.hasKey(for: p)
            ? L10n.text("Key saved — paste to replace", "Anahtar kayıtlı — değiştirmek için yapıştır")
            : L10n.text("Paste \(p.label) API key", "\(p.label) API anahtarını yapıştır")
    }

    @objc private func aiProviderChanged(_ s: NSPopUpButton) {
        let p = AIProvider.allCases[max(0, s.indexOfSelectedItem)]
        DisplayPrefs.aiProvider = p
        aiKeyField.stringValue = ""
        aiKeyField.placeholderString = keyPlaceholder(for: p)
        onChange?()
        refreshAIStatus()
    }

    @objc private func aiKeyCommitted(_ f: NSSecureTextField) {
        let p = DisplayPrefs.aiProvider
        guard p != .off else { return }
        let v = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        AIKeychain.save(v, for: p)
        f.stringValue = ""
        f.placeholderString = L10n.text("Key saved ✓", "Anahtar kayıtlı ✓")
        refreshAIStatus()
    }

    @objc private func aiRunTapped(_ sender: NSButton) {
        guard DisplayPrefs.aiProvider != .off, AIKeychain.hasKey(for: DisplayPrefs.aiProvider) else {
            aiResultLabel.textColor = .systemOrange
            aiResultLabel.stringValue = L10n.text(
                "Pick a provider and paste your key first.",
                "Önce sağlayıcı seçin ve anahtarınızı yapıştırın.")
            return
        }
        sender.isEnabled = false
        aiResultLabel.textColor = .secondaryLabelColor
        aiResultLabel.stringValue = L10n.text(
            "Analyzing your 30-day usage…",
            "Son 30 günlük kullanımınız analiz ediliyor…")
        AIAdvisor.analyze { [weak self] result in
            guard let self else { return }
            self.aiRunButton.isEnabled = true
            switch result {
            case .success(let text):
                self.aiResultLabel.textColor = .labelColor
                self.aiResultLabel.stringValue = text
                LocalStore.shared.saveAIRun(
                    provider: DisplayPrefs.aiProvider.rawValue,
                    summary: AIUsageSummary.build(),
                    tips: text)
            case .failure(let err):
                self.aiResultLabel.textColor = .systemOrange
                self.aiResultLabel.stringValue =
                    L10n.text("Couldn't analyze: ", "Analiz edilemedi: ") + "\(err)"
            }
        }
    }

    private func refreshAIStatus() {
        if let run = LocalStore.shared.lastAIRun() {
            aiResultLabel.textColor = .secondaryLabelColor
            let rel = ContextSnapshot.relative(run.ranAt)
            aiResultLabel.stringValue =
                L10n.text("Last run ", "Son çalıştırma ") + rel
                + "  ·  " + (run.provider ?? "—")
                + "\n\n" + run.tips
        } else {
            aiResultLabel.textColor = .secondaryLabelColor
            aiResultLabel.stringValue = L10n.text(
                "No analysis yet. Set a key above and press Run analysis.",
                "Henüz analiz yok. Yukarıdan anahtar girin ve Analizi çalıştır'a basın.")
        }
    }

    // ── SYNC (self-hosted server) UI

    private func makeSyncServerField() -> NSView {
        syncURLField.placeholderString = L10n.text("http://home.local:7878", "http://home.local:7878")
        syncURLField.stringValue = ServerSync.shared.serverURL ?? ""
        syncURLField.target = self
        syncURLField.action = #selector(syncURLCommitted(_:))
        syncURLField.translatesAutoresizingMaskIntoConstraints = false

        // The width is constrained by the card; let it fill the row.
        syncURLField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return syncURLField
    }

    private func makeSyncStatusRow() -> NSView {
        // Status pill: small dot + monospaced label
        syncPillDot.wantsLayer = true
        syncPillDot.layer?.cornerRadius = 4
        syncPillDot.translatesAutoresizingMaskIntoConstraints = false
        syncPillDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        syncPillDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        syncStatusPill.font = Typography.bodyMono(11, weight: .semibold)
        syncStatusPill.textColor = .labelColor
        syncStatusPill.translatesAutoresizingMaskIntoConstraints = false

        let pillRow = NSStackView(views: [syncPillDot, syncStatusPill])
        pillRow.orientation = .horizontal
        pillRow.spacing = 7
        pillRow.alignment = .centerY

        syncDetailLabel.font = NSFont.systemFont(ofSize: 10.5)
        syncDetailLabel.textColor = .tertiaryLabelColor
        syncDetailLabel.maximumNumberOfLines = 0
        syncDetailLabel.lineBreakMode = .byWordWrapping
        syncDetailLabel.translatesAutoresizingMaskIntoConstraints = false

        syncNowButton.title = L10n.text("Sync now", "Şimdi senkronla")
        syncNowButton.bezelStyle = .rounded
        syncNowButton.target = self
        syncNowButton.action = #selector(syncNowTapped(_:))
        syncTestButton.title = L10n.text("Test", "Test et")
        syncTestButton.bezelStyle = .rounded
        syncTestButton.target = self
        syncTestButton.action = #selector(syncTestTapped(_:))
        let btnRow = NSStackView(views: [syncNowButton, syncTestButton])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8

        let column = NSStackView(views: [pillRow, syncDetailLabel, btnRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        let wrap = NSStackView(views: [column])
        wrap.orientation = .horizontal
        wrap.alignment = .top
        column.widthAnchor.constraint(equalTo: wrap.widthAnchor).isActive = true
        return wrap
    }

    @objc private func syncURLCommitted(_ f: NSTextField) {
        let v = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ServerSync.shared.serverURL = v.isEmpty ? nil : v
        refreshSyncStatus()
    }

    @objc private func syncNowTapped(_ sender: NSButton) {
        sender.isEnabled = false
        ServerSync.shared.syncNow { [weak self] _ in
            sender.isEnabled = true
            self?.refreshSyncStatus()
        }
    }

    @objc private func syncTestTapped(_ sender: NSButton) {
        sender.isEnabled = false
        ServerSync.shared.testConnection { [weak self] result in
            sender.isEnabled = true
            switch result {
            case .success:
                self?.syncDetailLabel.stringValue = L10n.text(
                    "Connection OK. Server reachable.",
                    "Bağlantı başarılı. Sunucu erişilebilir.")
            case .failure(let err):
                self?.syncDetailLabel.stringValue =
                    L10n.text("Connection failed: ", "Bağlantı başarısız: ") + err.message
            }
        }
    }

    private func observeSyncState() {
        syncObserverToken = ServerSync.shared.observeState { [weak self] _ in
            self?.refreshSyncStatus()
        }
        // 10s heartbeat so "last push / pull" ages gracefully.
        syncHeartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshSyncStatus()
        }
    }

    private func refreshSyncStatus() {
        let s = ServerSync.shared.state
        let label: String
        let color: NSColor
        switch s {
        case .disabled:
            label = L10n.text("Not configured", "Ayarlı değil")
            color = .tertiaryLabelColor
        case .idle:
            let pushed = ServerSync.shared.status.lastPushedAt
            label = pushed.map {
                L10n.text("Synced", "Senkron") + " · " + ContextSnapshot.relative($0)
            } ?? L10n.text("Ready", "Hazır")
            color = .systemGreen
        case .syncing:
            label = L10n.text("Syncing…", "Senkron ediliyor…")
            color = .systemBlue
        case .error(let msg):
            label = L10n.text("Error", "Hata") + " · " + msg
            color = .systemRed
        }
        syncStatusPill.stringValue = label
        syncPillDot.layer?.backgroundColor = color.cgColor
        if let pushed = ServerSync.shared.status.lastPushedAt,
           let pulled = ServerSync.shared.status.lastPulledAt {
            syncDetailLabel.stringValue = L10n.text(
                "Last push \(ContextSnapshot.relative(pushed))  ·  Last pull \(ContextSnapshot.relative(pulled))",
                "Son push \(ContextSnapshot.relative(pushed))  ·  Son pull \(ContextSnapshot.relative(pulled))")
        } else {
            syncDetailLabel.stringValue = L10n.text(
                "Server not contacted yet.",
                "Sunucu henüz bağlanmadı.")
        }
    }

    private func makeICloudSyncRow() -> NSView {
        let on = MachineSync.isICloudMode
        let btn = NSButton(
            title: on ? L10n.text("Turn off", "Kapat")
                      : L10n.text("Use iCloud Drive", "iCloud Drive kullan"),
            target: self, action: #selector(toggleICloudSync))
        btn.bezelStyle = .rounded
        btn.isEnabled = MachineSync.iCloudAvailable
        iCloudSyncButton = btn
        iCloudStatusLabel.font = .systemFont(ofSize: 11)
        iCloudStatusLabel.textColor = .secondaryLabelColor
        iCloudStatusLabel.lineBreakMode = .byTruncatingMiddle
        iCloudStatusLabel.stringValue = iCloudStatusText()
        let row = NSStackView(views: [btn, iCloudStatusLabel])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline
        return row
    }

    private func iCloudStatusText() -> String {
        if !MachineSync.iCloudAvailable {
            return L10n.text("iCloud Drive isn't set up on this Mac", "Bu Mac'te iCloud Drive ayarlı değil")
        }
        return MachineSync.isICloudMode
            ? L10n.text("On · syncs automatically to your other Macs", "Açık · diğer Mac'lerinize otomatik senkronlanır")
            : L10n.text("Off", "Kapalı")
    }

    @objc private func toggleICloudSync() {
        if MachineSync.isICloudMode {
            MachineSync.disableSync()
        } else {
            MachineSync.enableICloudSync()
        }
        let on = MachineSync.isICloudMode
        iCloudSyncButton?.title = on
            ? L10n.text("Turn off", "Kapat")
            : L10n.text("Use iCloud Drive", "iCloud Drive kullan")
        iCloudStatusLabel.stringValue = iCloudStatusText()
        syncFolderLabel.stringValue = syncFolderDisplay()
        onChange?()
    }

    private func makeSyncFolderField() -> NSView {
        let btn = NSButton(title: L10n.text("Choose folder…", "Klasör seç…"), target: self, action: #selector(chooseSyncFolder))
        btn.bezelStyle = .rounded
        syncFolderLabel.font = .systemFont(ofSize: 11)
        syncFolderLabel.textColor = .secondaryLabelColor
        syncFolderLabel.lineBreakMode = .byTruncatingMiddle
        syncFolderLabel.stringValue = syncFolderDisplay()
        let clear = NSButton(title: L10n.text("Clear", "Temizle"), target: self, action: #selector(clearSyncFolder))
        clear.bezelStyle = .rounded
        let row = NSStackView(views: [btn, syncFolderLabel, clear])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline
        return row
    }

    private func syncFolderDisplay() -> String {
        if MachineSync.isICloudMode {
            return L10n.text("Using iCloud Drive", "iCloud Drive kullanılıyor")
        }
        return DisplayPrefs.syncFolder.isEmpty
            ? L10n.text("Not set", "Ayarlı değil")
            : (DisplayPrefs.syncFolder as NSString).abbreviatingWithTildeInPath
    }

    @objc private func chooseSyncFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = L10n.text("Use folder", "Klasörü kullan")
        if p.runModal() == .OK, let url = p.url {
            DisplayPrefs.syncFolder = url.path
            syncFolderLabel.stringValue = syncFolderDisplay()
            onChange?()
        }
    }

    @objc private func clearSyncFolder() {
        DisplayPrefs.syncFolder = ""
        syncFolderLabel.stringValue = syncFolderDisplay()
        onChange?()
    }

    private func makeSwitch(on: Bool, action: Selector, a11y: String) -> NSSwitch {
        makeSettingsSwitch(on: on, target: self, action: action, a11y: a11y)
    }

    @objc private func redactChanged(_ sender: NSSwitch) {
        DisplayPrefs.redactPaths = sender.state == .on
        onChange?()
    }

    @objc private func maskShareChanged(_ sender: NSSwitch) {
        DisplayPrefs.maskShareProjects = sender.state == .on
        onChange?()
    }
}

// MARK: - Modern menubar popover
//
// Replaces the legacy NSMenu dropdown. Renders a native popover with a
// vibrant material background, hero card for the active agent, a context
// window meter, a 3-tile stat grid (5h / 7d / session), an optional list of
// other AI tools, and a footer toolbar (theme / settings / refresh / quit).
// Designed for macOS 13+ — uses NSVisualEffectView (.menu), continuous
// corner curves, and SF Symbol toolbar icons.

/// Rounded card backdrop tuned for use over an NSVisualEffectView. Slightly
/// translucent fill plus a hairline border so it reads on both light and
/// dark menubar materials without competing with the vibrancy underneath.
