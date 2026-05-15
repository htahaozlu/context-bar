import AppKit
import Foundation

enum DisplayElement: String, CaseIterable {
    case agent, project, pct
    var label: String {
        L10n.displayElementLabel(self)
    }
}

struct DisplayItem {
    let element: DisplayElement
    var enabled: Bool
}

final class DisplayStore {
    static let key = "displayItems"
    static var items: [DisplayItem] {
        if let arr = UserDefaults.standard.array(forKey: key) as? [[String: Any]] {
            var parsed: [DisplayItem] = []
            var seen = Set<DisplayElement>()
            for dict in arr {
                if let id = dict["id"] as? String, let elem = DisplayElement(rawValue: id), !seen.contains(elem) {
                    parsed.append(DisplayItem(element: elem, enabled: (dict["enabled"] as? Bool) ?? true))
                    seen.insert(elem)
                }
            }
            for elem in DisplayElement.allCases where !seen.contains(elem) {
                parsed.append(DisplayItem(element: elem, enabled: true))
            }
            return parsed
        }
        return DisplayElement.allCases.map { DisplayItem(element: $0, enabled: true) }
    }
    static func save(_ items: [DisplayItem]) {
        let arr: [[String: Any]] = items.map { ["id": $0.element.rawValue, "enabled": $0.enabled] }
        UserDefaults.standard.set(arr, forKey: key)
    }
}
