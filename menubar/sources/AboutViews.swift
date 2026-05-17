import AppKit
import Foundation

final class AboutHeroView: NSView {
    init(metadata: AppMetadata = .current) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let logoView = NSImageView()
        logoView.image = appLogoImage()
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.imageAlignment = .alignCenter
        logoView.translatesAutoresizingMaskIntoConstraints = false

        let appName = NSTextField(labelWithString: "ContextBar")
        appName.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        appName.textColor = .labelColor
        appName.alignment = .center

        let version = NSTextField(labelWithString: "Version \(metadata.version) (\(metadata.build))")
        version.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let note = NSTextField(wrappingLabelWithString: L10n.text(
            "Native repository context and coding-agent usage visibility for macOS.",
            "macOS için yerel depo bağlamı ve kodlama ajanı kullanım görünürlüğü."
        ))
        note.font = NSFont.systemFont(ofSize: 12)
        note.textColor = .tertiaryLabelColor
        note.maximumNumberOfLines = 0
        note.alignment = .center

        let stack = NSStackView(views: [logoView, appName, version, note])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: logoView)
        stack.setCustomSpacing(2, after: appName)
        stack.setCustomSpacing(10, after: version)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            logoView.heightAnchor.constraint(equalToConstant: 120),
            logoView.widthAnchor.constraint(equalToConstant: 360),
            note.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class ResponsiveInfoRowView: NSView {
    init(title: String, value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(wrappingLabelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.maximumNumberOfLines = 2
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

