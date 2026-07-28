import Foundation

/// What number, if any, sits next to the menu bar glyph. SPEC wanted this as a
/// user setting (its suggested default was off for a clean bar); the shipped
/// default stays "charge" because every existing install has shown the charge
/// percentage since 1.0, and a routine update silently emptying the menu bar
/// would read as a regression.
enum MenuBarBadge: String, CaseIterable, Identifiable {
    case charge
    case health
    case none

    static let key = "menuBarBadge"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charge: return "Charge %"
        case .health: return "Health %"
        case .none: return "None"
        }
    }

    /// The stored choice, defaulting to the pre-setting behaviour.
    static var current: MenuBarBadge {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let badge = MenuBarBadge(rawValue: raw) else { return .charge }
        return badge
    }
}
