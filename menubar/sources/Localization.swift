import AppKit
import Foundation

enum AppLanguage: String, CaseIterable {
    case auto
    case en
    case tr

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .en: return "EN"
        case .tr: return "TR"
        }
    }
}

final class LanguageStore {
    static let key = "language"

    static var selected: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "auto") ?? .auto }
    }

    static var resolved: AppLanguage {
        switch selected {
        case .auto:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("tr") ? .tr : .en
        case .en, .tr:
            return selected
        }
    }

    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }
}

enum L10n {
    static var lang: AppLanguage { LanguageStore.resolved }

    static func text(_ en: String, _ tr: String) -> String {
        lang == .tr ? tr : en
    }

    static func displayElementLabel(_ element: DisplayElement) -> String {
        switch element {
        case .agent: return text("Agent icon", "Ajan ikonu")
        case .project: return text("Project (cwd)", "Proje (cwd)")
        case .pct: return text("Context %", "Bağlam %")
        }
    }

    static func relative(_ elapsed: TimeInterval) -> String {
        if elapsed < 60 { return lang == .tr ? "\(Int(elapsed)) sn önce" : "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return lang == .tr ? "\(Int(elapsed/60)) dk önce" : "\(Int(elapsed/60))m ago" }
        if elapsed < 86400 { return lang == .tr ? "\(Int(elapsed/3600)) sa önce" : "\(Int(elapsed/3600))h ago" }
        return lang == .tr ? "\(Int(elapsed/86400)) g önce" : "\(Int(elapsed/86400))d ago"
    }
}

