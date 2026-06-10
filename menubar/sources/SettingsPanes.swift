import AppKit
import Foundation

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
    func addWideRow(title: String, desc: String? = nil, content: NSView) {
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
            "ContextBar · all data stays on this Mac · no account, no server",
            "ContextBar · tüm veriler bu Mac'te kalır · hesap yok, sunucu yok"))
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
    private let displayChips = HorizontalDisplayController()
    private let preview = TitlePreviewView()
    private var cardViews: [(ThemeCardView, Theme)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshPreview()
    }

    private func buildUI() {
        buildAppearanceGroup()
        buildAlertsGroup()
        buildBehaviorGroup()
        addPrivacyFooter()
    }

    /// APPEARANCE — theme grid, language, separator, title fields, live preview.
    /// (Formerly the standalone Appearance tab, merged into General.)
    private func buildAppearanceGroup() {
        let appearance = addGroup(symbol: "paintbrush", title: L10n.text("Appearance", "Görünüm"))

        // ── Theme — full-width card grid (keeps the rich named-palette picker).
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
            title: L10n.text("Theme", "Tema"),
            desc: L10n.text(
                "Pick the menubar palette that matches your desktop.",
                "Masaüstüne en uygun menubar paletini seçin."),
            content: themeGrid)
        cardViews.forEach { $0.0.heightAnchor.constraint(equalToConstant: 82).isActive = true }

        // ── Language — segmented (Auto · EN · TR).
        let langControl = NSSegmentedControl(
            labels: AppLanguage.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:)))
        langControl.selectedSegment = AppLanguage.allCases.firstIndex(of: LanguageStore.selected) ?? 0
        langControl.setAccessibilityLabel(L10n.text("Language", "Dil"))
        appearance.addRow(
            title: L10n.text("Language", "Dil"),
            desc: L10n.text(
                "Follow the system language or pin to English / Turkish.",
                "Sistem dilini izleyin ya da İngilizce / Türkçe sabitleyin."),
            control: langControl)

        // ── Separator — segmented glyph picker between title fields.
        let sepControl = NSSegmentedControl(
            labels: SeparatorStore.options.map { $0.label },
            trackingMode: .selectOne,
            target: self,
            action: #selector(separatorChanged(_:)))
        sepControl.selectedSegment = SeparatorStore.currentIndex
        sepControl.setAccessibilityLabel(L10n.text("Separator", "Ayraç"))
        appearance.addRow(
            title: L10n.text("Separator", "Ayraç"),
            desc: L10n.text(
                "Character between the agent icon, project, and context values.",
                "Ajan ikonu, proje ve bağlam değerleri arasındaki karakter."),
            control: sepControl)

        // ── Title content — toggle/reorder chips (full width).
        displayChips.onChange = { [weak self] in
            self?.refreshPreview()
            self?.onThemeChange?(ThemeStore.current.id)
        }
        appearance.addWideRow(
            title: L10n.text("Title content", "Başlık içeriği"),
            desc: L10n.text(
                "Toggle a field's checkbox to show it. Drag the ⠿ handle to reorder.",
                "Bir alanı göstermek için onay kutusunu işaretleyin. Sıralamak için ⠿ tutamacından sürükleyin."),
            content: displayChips.container)

        // ── Live preview — menubar title sample (full width).
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        appearance.addWideRow(
            title: L10n.text("Preview", "Önizleme"),
            desc: L10n.text(
                "Live sample of the menubar title. Changes apply instantly.",
                "Menubar başlığının canlı örneği. Değişiklikler anında uygulanır."),
            content: preview)
    }

    /// ALERTS — context-bar marks, background sessions, provider status, monthly
    /// budget. Everything that can raise an attention signal in the menubar.
    /// (Merges the former Notifications/Alerts and the alert-shaped Display rows.)
    private func buildAlertsGroup() {
        let alerts = addGroup(symbol: "bell", title: L10n.text("Alerts", "Uyarılar"))

        alerts.addRow(
            title: L10n.text("Bar marks", "Çubuk işaretleri"),
            desc: L10n.text(
                "Thin ticks at 70% and 90% on every context bar. Off by default.",
                "Her bağlam çubuğunda %70 ve %90'a ince çizgiler. Varsayılan kapalı."),
            control: makeSwitch(on: DisplayPrefs.tickMarks, action: #selector(ticksChanged(_:)),
                                a11y: L10n.text("Warning marks on bars", "Çubuklarda uyarı işaretleri")))

        alerts.addRow(
            title: L10n.text("Background sessions", "Arka plan oturumları"),
            desc: L10n.text(
                "Surface a background session above 80% while the foreground is calm.",
                "Aktif oturum sakinken %80'i geçen arka plan oturumunu göster."),
            control: makeSwitch(on: DisplayPrefs.criticalBackground, action: #selector(criticalChanged(_:)),
                                a11y: L10n.text("Surface critical background sessions", "Kritik arka plan oturumlarını göster")))

        alerts.addRow(
            title: L10n.text("Provider status", "Sağlayıcı durumu"),
            desc: L10n.text(
                "Surface Anthropic / OpenAI incidents in the menubar and popover.",
                "Anthropic / OpenAI olaylarını menubar ve popover'da göster."),
            control: makeSwitch(on: DisplayPrefs.incidents, action: #selector(incidentsChanged(_:)),
                                a11y: L10n.text("Show upstream incident overlay", "Üst kaynak olay göstergesi")))

        alerts.addRow(
            title: L10n.text("Monthly budget", "Aylık bütçe"),
            desc: L10n.text(
                "Tint the title as the run-rate nears this cap, or the 5h limit fills. 0 = off.",
                "Harcama hızı bu üst sınıra ya da 5sa limitine yaklaşınca başlığı renklendir. 0 = kapalı."),
            control: makeBudgetField())
    }

    /// BEHAVIOR — how rolling-window resets read, and celebration.
    private func buildBehaviorGroup() {
        let behavior = addGroup(symbol: "slider.horizontal.3", title: L10n.text("Behavior", "Davranış"))

        let resetCtrl = NSSegmentedControl(
            labels: [L10n.text("Relative", "Göreli"), L10n.text("Absolute", "Mutlak")],
            trackingMode: .selectOne, target: self, action: #selector(resetStyleChanged(_:)))
        resetCtrl.selectedSegment = DisplayPrefs.resetStyle == .relative ? 0 : 1
        resetCtrl.setAccessibilityLabel(L10n.text("Reset time", "Sıfırlama zamanı"))
        behavior.addRow(
            title: L10n.text("Reset time", "Sıfırlama zamanı"),
            desc: L10n.text(
                "Show resets as a duration (\"in 1h 47m\") or a clock time (\"14:32\").",
                "Sıfırlamaları süre (\"1sa 47dk\") veya saat (\"14:32\") olarak göster."),
            control: resetCtrl)

        behavior.addRow(
            title: L10n.text("Delight", "İnce dokunuş"),
            desc: L10n.text(
                "A particle burst when a quota window resets. Respects reduce-motion.",
                "Kota penceresi sıfırlanınca kısa animasyon. Hareketi azalt ayarına uyar."),
            control: makeSwitch(on: DisplayPrefs.confetti, action: #selector(confettiChanged(_:)),
                                a11y: L10n.text("Celebrate quota window resets", "Pencere sıfırlamada kutlama")))
    }

    private func updateCardSelection() {
        let current = ThemeStore.current.id
        for (card, theme) in cardViews { card.isSelected = theme.id == current }
    }

    private func makeSwitch(on: Bool, action: Selector, a11y: String) -> NSSwitch {
        makeSettingsSwitch(on: on, target: self, action: action, a11y: a11y)
    }

    private func makeBudgetField() -> NSView {
        let field = NSTextField()
        field.placeholderString = L10n.text("USD / month", "USD / ay")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let v = DisplayPrefs.monthlyBudgetUSD
        field.stringValue = v > 0 ? String(format: "%.0f", v) : ""
        field.target = self
        field.action = #selector(budgetChanged(_:))
        field.setAccessibilityLabel(L10n.text("Monthly budget USD", "Aylık bütçe USD"))
        let row = NSStackView(views: [NSTextField(labelWithString: "$"), field])
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .firstBaseline
        return row
    }

    @objc private func budgetChanged(_ sender: NSTextField) {
        let cleaned = sender.stringValue.filter { $0.isNumber || $0 == "." }
        DisplayPrefs.monthlyBudgetUSD = Double(cleaned) ?? 0
        onChange?()
    }

    @objc private func resetStyleChanged(_ sender: NSSegmentedControl) {
        DisplayPrefs.resetStyle = sender.selectedSegment == 0 ? .relative : .absolute
        onChange?()
    }
    @objc private func ticksChanged(_ sender: NSSwitch) {
        DisplayPrefs.tickMarks = sender.state == .on
        onChange?()
    }
    @objc private func criticalChanged(_ sender: NSSwitch) {
        DisplayPrefs.criticalBackground = sender.state == .on
        onChange?()
    }
    @objc private func incidentsChanged(_ sender: NSSwitch) {
        DisplayPrefs.incidents = sender.state == .on
        if sender.state == .on { IncidentPoller.shared.start() } else { IncidentPoller.shared.stop() }
        onChange?()
    }
    @objc private func confettiChanged(_ sender: NSSwitch) {
        DisplayPrefs.confetti = sender.state == .on
        onChange?()
    }

    private func refreshPreview() {
        preview.update(
            items: displayChips.currentItems,
            agent: "Claude",
            project: L10n.text("my-project", "projem"),
            pct: 27
        )
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        let language = AppLanguage.allCases[sender.selectedSegment]
        LanguageStore.set(language)
        onThemeChange?(ThemeStore.current.id)
    }

    @objc private func separatorChanged(_ sender: NSSegmentedControl) {
        let value = SeparatorStore.options[sender.selectedSegment].value
        SeparatorStore.set(value)
        refreshPreview()
        onThemeChange?(ThemeStore.current.id)
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
    private let syncFolderLabel = NSTextField(labelWithString: "")

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        // ── AI ADVISOR — the actionable opt-in users come here for.
        let advisor = addGroup(symbol: "sparkles", title: L10n.text("AI Advisor", "AI Danışman"))
        advisor.addWideRow(
            title: L10n.text("Bring your own key", "Kendi anahtarını getir"),
            desc: L10n.text(
                "Optional. Connect your own OpenAI or Gemini API key for usage-efficiency tips. Only an aggregate summary — no transcripts, no project names — is sent, and only when you press Analyze in the Value tab. Off by default.",
                "İsteğe bağlı. Kullanım verimliliği önerileri için kendi OpenAI veya Gemini API anahtarını bağla. Yalnızca özet — transcript yok, proje adı yok — gönderilir, o da yalnızca Değer sekmesinde Analiz'e bastığında. Varsayılan kapalı."),
            content: makeAIAdvisorField())

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

        // ── SYNC — combine usage across your Macs via a folder you already sync.
        let sync = addGroup(symbol: "macbook.and.iphone", title: L10n.text("Across your Macs", "Mac'lerin arasında"))
        sync.addWideRow(
            title: L10n.text("Combined usage", "Birleşik kullanım"),
            desc: L10n.text(
                "Point this at a folder you already sync (iCloud Drive, Dropbox…). Each Mac writes a compact usage summary there; the Value tab then shows combined usage. Aggregates only — no transcripts, no project names. No server.",
                "Zaten senkronladığın bir klasörü seç (iCloud Drive, Dropbox…). Her Mac oraya özet kullanım yazar; Değer sekmesi makineler arası birleşik kullanımı gösterir. Yalnızca özet — transcript yok, proje adı yok. Sunucu yok."),
            content: makeSyncFolderField())

        addPrivacyFooter()
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
        DisplayPrefs.syncFolder.isEmpty
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
    }

    @objc private func aiKeyCommitted(_ f: NSSecureTextField) {
        let p = DisplayPrefs.aiProvider
        guard p != .off else { return }
        let v = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        AIKeychain.save(v, for: p)
        f.stringValue = ""
        f.placeholderString = L10n.text("Key saved ✓", "Anahtar kayıtlı ✓")
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
