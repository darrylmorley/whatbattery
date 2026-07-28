import Foundation

/// Chooses the menu bar SF Symbol for the current battery state. Pure so the
/// mapping is testable; the app layer turns the name into an `NSImage`.
///
/// The one thing a menu bar battery glyph should convey is "am I charging and
/// am I low", so the symbol is state-driven: a bolt whenever the Mac is on
/// power (SF Symbols only ships the bolt at the 100percent fill, so the bolt
/// itself is the signal, not the fill), a quartile fill while discharging, and
/// a power plug on a Mac with no battery at all.
public enum MenuBarGlyph {
    /// Symbol for a Mac battery snapshot; nil means no battery (a desktop).
    public static func symbolName(for snapshot: BatterySnapshot?) -> String {
        guard let snapshot else { return "powerplug" }
        // Any externally powered state gets the bolt: that is Apple's own menu
        // bar convention (bolt = on power), and it is the only bolt variant SF
        // Symbols provides.
        if snapshot.chargingState != .discharging {
            return "battery.100percent.bolt"
        }
        return dischargeSymbol(percent: snapshot.currentChargePercent)
    }

    /// Quartile fill for a discharging battery, rounded to the nearest of the
    /// five fills SF Symbols provides.
    static func dischargeSymbol(percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// The accessibility description for the status item, so VoiceOver conveys
    /// the same state the glyph does.
    public static func accessibilityDescription(for snapshot: BatterySnapshot?) -> String {
        guard let snapshot else { return "WhatBattery" }
        let charge = "\(snapshot.currentChargePercent) percent"
        switch snapshot.chargingState {
        case .charging: return "WhatBattery: \(charge), charging"
        case .full: return "WhatBattery: \(charge), fully charged"
        case .acNoCharge: return "WhatBattery: \(charge), on power"
        case .discharging: return "WhatBattery: \(charge)"
        }
    }
}
