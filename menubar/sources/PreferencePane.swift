import AppKit
import Foundation

final class PreferenceSectionCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Surface.applyCard(self)

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.m),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.l),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.l),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.m),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Surface.refreshCardColors(self)
    }
}

class PreferencePaneViewController: NSViewController {
    let scrollView = NSScrollView()
    let contentStack = NSStackView()

    /// Override to cap + center the content column at a fixed width (the redesign
    /// centers Settings at 580pt). `nil` = full-width (Stats/Cost use the whole
    /// 820pt canvas for their two-column grids).
    var preferredContentWidth: CGFloat? { nil }

    override func loadView() {
        view = FlippedView()
        view.wantsLayer = true
        // Transparent so the window's NSVisualEffectView frost shows through.
        view.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
        ])
        if let maxWidth = preferredContentWidth {
            NSLayoutConstraint.activate([
                contentStack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
                contentStack.widthAnchor.constraint(equalToConstant: maxWidth),
                contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor, constant: 24),
                contentStack.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -24),
            ])
        } else {
            NSLayoutConstraint.activate([
                contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
                contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            ])
        }
    }

    /// A bare two-column row (no section header / card wrapper), added full-width
    /// to the content column. `leftRatio` sets the left:right width ratio (1.5 →
    /// 1.5fr : 1fr). Pass already-styled cards as `left` / `right`.
    func addGridRow(left: NSView, right: NSView, leftRatio: CGFloat = 1.0,
                    spacing: CGFloat = Spacing.m) {
        left.translatesAutoresizingMaskIntoConstraints = false
        right.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fill
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            left.widthAnchor.constraint(equalTo: right.widthAnchor, multiplier: leftRatio),
        ])
    }

    func addHero(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// A section: uppercase header (optional SF Symbol anchor + optional ⓘ
    /// info popover) over a short one-line subtitle and a card body. Keep
    /// `subtitle` to ~one line; move the long "why" into `info` so the pane
    /// stays scannable instead of a wall of prose.
    func addSection(title: String, subtitle: String? = nil,
                    symbol: String? = nil, info: String? = nil, body: NSView) {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 4
        section.translatesAutoresizingMaskIntoConstraints = false

        let header = makeSectionHeader(title: title, symbol: symbol, info: info)
        section.addArrangedSubview(header)

        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11)
            subtitleLabel.textColor = .tertiaryLabelColor
            subtitleLabel.maximumNumberOfLines = 0
            section.addArrangedSubview(subtitleLabel)
            section.setCustomSpacing(8, after: subtitleLabel)
        } else {
            section.setCustomSpacing(6, after: header)
        }

        let card = PreferenceSectionCard(content: body)
        section.addArrangedSubview(card)
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// Sonoma System Settings-style header: small uppercase label, optionally
    /// led by a monochrome SF Symbol and trailed by an ⓘ button that reveals
    /// the long explanation on demand (so it doesn't crowd the page).
    private func makeSectionHeader(title: String, symbol: String?, info: String?) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false

        if let symbol,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            let iv = NSImageView(image: image)
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            iv.contentTintColor = .secondaryLabelColor
            iv.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(iv)
        }

        let titleLabel = NSTextField(labelWithAttributedString:
            Typography.captionAttributed(title, color: .secondaryLabelColor))
        row.addArrangedSubview(titleLabel)

        if let info, !info.isEmpty {
            row.addArrangedSubview(InfoButton(info: info))
        }
        return row
    }

    func makeInfoRow(title: String, value: String) -> NSView {
        ResponsiveInfoRowView(title: title, value: value)
    }
}

/// A small ⓘ glyph that reveals a section's long explanation in a transient
/// popover on click (and as a tooltip on hover). Lets headers carry a short
/// subtitle while the full "why" stays one tap away — no wall of text.
final class InfoButton: NSButton {
    private let infoText: String
    private var popover: NSPopover?

    init(info: String) {
        self.infoText = info
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .inline
        imagePosition = .imageOnly
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        image = NSImage(systemSymbolName: "info.circle", accessibilityDescription:
            L10n.text("More info", "Daha fazla bilgi"))?.withSymbolConfiguration(cfg)
        contentTintColor = .tertiaryLabelColor
        target = self
        action = #selector(toggle)
        toolTip = info
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityLabel(L10n.text("More info", "Daha fazla bilgi"))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        if let popover, popover.isShown { popover.close(); return }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.contentViewController = InfoPopoverViewController(text: infoText)
        p.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        popover = p
    }
}

/// Popover body for an `InfoButton` — a single wrapping paragraph, sized to a
/// comfortable reading width.
final class InfoPopoverViewController: NSViewController {
    private let text: String
    init(text: String) { self.text = text; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let width: CGFloat = 320
        let root = NSView()
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = width - 2 * Spacing.m
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: width),
            label.topAnchor.constraint(equalTo: root.topAnchor, constant: Spacing.m),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Spacing.m),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Spacing.m),
            label.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Spacing.m),
        ])
        view = root
    }
}

