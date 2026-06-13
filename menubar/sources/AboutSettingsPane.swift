import AppKit
import Foundation

/// About pane — app identity hero, updates, repository context, data sources,
/// and files/shortcuts. Split back out of Privacy so the update controls live
/// on their own tab.
final class AboutSettingsViewController: PreferencePaneViewController {
    private let changelogURL = URL(string: "https://github.com/htahaozlu/context-bar/blob/main/CHANGELOG.md")!

    /// Center + cap at 580pt to match the Settings and Privacy tabs.
    override var preferredContentWidth: CGFloat? { 580 }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        addHero(AboutHeroView())

        let actions = NSStackView(views: [
            makeActionButton(title: L10n.text("Check for Updates", "Güncellemeleri kontrol et"),
                             action: #selector(checkForUpdates)),
            makeActionButton(title: L10n.text("View Changelog", "Değişiklik kaydını aç"),
                             action: #selector(openChangelog)),
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        addSection(
            title: L10n.text("Updates", "Güncellemeler"),
            subtitle: L10n.text("Distributed from GitHub Releases.",
                                "GitHub Releases üzerinden dağıtılır."),
            symbol: "arrow.down.circle",
            body: actions)

        let context = NSStackView(views: [
            makeInfoRow(title: L10n.text("Artifacts folder", "Artifact klasörü"), value: "\(NSHomeDirectory())/.context-bar"),
            makeInfoRow(title: L10n.text("Repository brief", "Repo brifi"), value: ".context-bar/AGENT.md"),
            makeInfoRow(title: L10n.text("Claude compatibility", "Claude uyumluluğu"), value: "CLAUDE.md"),
        ])
        context.orientation = .vertical; context.spacing = 10; context.alignment = .leading
        addSection(
            title: L10n.text("Repository context", "Repo bağlamı"),
            subtitle: L10n.text("Local brief + sidecars for agents.",
                                "Ajanlar için yerel brief + yan dosyalar."),
            symbol: "folder",
            info: L10n.text(
                "Stable local brief and machine-readable sidecars so agents re-enter a project with less drift.",
                "Ajanlar projeye daha az kayma ile geri dönebilsin diye sabit yerel brief ve makinece okunabilir yan dosyalar."),
            body: context)

        let sources = NSStackView(views: [
            makeInfoRow(title: "Git", value: L10n.text("branch, commits, worktree", "branch, commit, worktree")),
            makeInfoRow(title: "Claude Code", value: "~/.claude/projects/**/*.jsonl"),
            makeInfoRow(title: "Codex CLI", value: "~/.codex/sessions/**/*.jsonl"),
            makeInfoRow(title: "Output", value: "~/.context-bar/context.json"),
        ])
        sources.orientation = .vertical; sources.spacing = 10; sources.alignment = .leading
        addSection(
            title: L10n.text("Data sources", "Veri kaynakları"),
            subtitle: L10n.text("Built locally from transcripts. No server.",
                                "Transkriptlerden yerelde oluşur. Sunucu yok."),
            symbol: "tray.full",
            info: L10n.text(
                "Usage is built locally from existing transcript files. No remote service required.",
                "Kullanım özeti mevcut transcript dosyalarından yerelde oluşturulur. Uzak servis gerekmez."),
            body: sources)

        let locations = NSStackView(views: [
            makeInfoRow(title: L10n.text("Version", "Sürüm"), value: AppMetadata.current.detailedVersionLabel),
            makeInfoRow(title: L10n.text("App bundle", "Uygulama paketi"), value: "dist/ContextBar.app"),
            makeInfoRow(title: L10n.text("Disk image", "DMG"), value: "dist/ContextBar.dmg"),
            makeInfoRow(title: L10n.text("Open window", "Pencereyi aç"), value: "⌘D"),
            makeInfoRow(title: L10n.text("Refresh", "Yenile"), value: "⌘R"),
        ])
        locations.orientation = .vertical; locations.spacing = 10; locations.alignment = .leading
        addSection(
            title: L10n.text("Files and shortcuts", "Dosyalar ve kısayollar"),
            subtitle: L10n.text("Where things live + keyboard shortcuts.",
                                "Dosyaların yeri + klavye kısayolları."),
            symbol: "keyboard",
            info: L10n.text(
                "Build artifacts live in the repository. Runtime data stays under your home directory.",
                "Build artefact'ları repo içinde kalır. Çalışma verileri home dizini altında tutulur."),
            body: locations)
    }

    private func makeActionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates(presenter: view.window)
    }

    @objc private func openChangelog() {
        NSWorkspace.shared.open(changelogURL)
    }
}
