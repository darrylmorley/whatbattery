import Foundation

/// The battery's service condition, mirroring exactly what macOS System
/// Information / Settings shows (the "Condition" line). Parsed from
/// `system_profiler SPPowerDataType` rather than the IOPowerSources
/// `BatteryHealth` key, which proved unreliable (it can report "Check Battery"
/// on a healthy battery). The parsing lives here, pure and testable.
public enum BatteryCondition: String, Sendable, Equatable {
    /// Healthy ("Normal").
    case normal
    /// Worn but working; "Service Recommended" / "Replace Soon".
    case serviceRecommended
    /// A fault macOS flags for replacement ("Replace Now" / "Service Battery" /
    /// "Permanent Failure").
    case serviceBattery
    /// Not reported (no battery, or no Condition line in the output).
    case unknown

    /// Pull the "Condition:" value out of `system_profiler SPPowerDataType` text
    /// and map it. Returns `.unknown` when there is no Condition line.
    public static func from(systemProfilerOutput output: String) -> BatteryCondition {
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("Condition:") else { continue }
            let value = line.dropFirst("Condition:".count).trimmingCharacters(in: .whitespaces)
            return from(conditionLabel: value)
        }
        return .unknown
    }

    /// Map a macOS condition label to a condition. Covers the current and older
    /// macOS wordings.
    public static func from(conditionLabel value: String) -> BatteryCondition {
        switch value {
        case "Normal":
            return .normal
        case "Service Recommended", "Replace Soon":
            return .serviceRecommended
        case "Replace Now", "Service Battery", "Check Battery", "Permanent Failure":
            return .serviceBattery
        default:
            return .unknown
        }
    }

    /// User-facing label, matching macOS wording.
    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .serviceRecommended: return "Service Recommended"
        case .serviceBattery: return "Service Battery"
        case .unknown: return "Unknown"
        }
    }

    /// Whether this condition is something the user should act on (drives the UI
    /// colour: normal is fine, the rest are warnings).
    public var isWarning: Bool {
        switch self {
        case .normal, .unknown: return false
        case .serviceRecommended, .serviceBattery: return true
        }
    }
}
