import Foundation

/// A threshold alert worth notifying the user about. Pure data: the platform
/// notification layer (in the Plugins target) turns these into user notifications.
public enum BatteryAlert: Equatable, Sendable {
    /// Charge reached or passed the high threshold (the carried Int is the live %).
    case chargeHigh(Int)
    /// Charge fell to or below the low threshold (the carried Int is the live %).
    case chargeLow(Int)
    /// Battery temperature reached or passed the high threshold (Celsius).
    case temperatureHigh(Double)
    /// Battery health dropped below the milestone threshold (the carried Int is
    /// the milestone %, not the live value, so the message reads cleanly).
    case healthBelow(Int)

    /// Distinguishes alert types for crossing/debounce bookkeeping. One active
    /// flag per kind, so a hovering value fires once, not on every refresh.
    public enum Kind: Hashable, Sendable {
        case chargeHigh
        case chargeLow
        case temperatureHigh
        case healthBelow
    }

    public var kind: Kind {
        switch self {
        case .chargeHigh: return .chargeHigh
        case .chargeLow: return .chargeLow
        case .temperatureHigh: return .temperatureHigh
        case .healthBelow: return .healthBelow
        }
    }

    public var title: String {
        switch self {
        case .chargeHigh: return "Battery charged"
        case .chargeLow: return "Battery low"
        case .temperatureHigh: return "Battery running warm"
        case .healthBelow: return "Battery health milestone"
        }
    }

    public var body: String {
        switch self {
        case .chargeHigh(let pct):
            return "Charge has reached \(pct)%. You can unplug to ease wear."
        case .chargeLow(let pct):
            return "Charge has dropped to \(pct)%. Consider plugging in."
        case .temperatureHigh(let c):
            return String(format: "Battery temperature is %.0f°C.", c)
        case .healthBelow(let milestone):
            return "Battery health has fallen below \(milestone)%."
        }
    }
}
