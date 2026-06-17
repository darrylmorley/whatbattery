import Foundation

/// Display helpers shared by the CLI and (later) the SwiftUI app. Kept in Core
/// because the CLI legitimately needs to format too; the SwiftUI app may still
/// format inline where it wants finer control.
public enum BatteryFormatter {
    public enum TemperatureUnit { case celsius, fahrenheit }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return "\(Int(value.rounded()))%"
    }

    /// Battery health as a one-decimal percentage (e.g. "99.5%"), capped at 100.
    /// Health needs the decimal: rounding to a whole number lets 99.5% read as a
    /// misleading "100%" when the full-charge capacity is clearly below design.
    public static func healthPercent(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return String(format: "%.1f%%", min(value, 100))
    }

    public static func milliampHours(_ mAh: Int) -> String {
        "\(grouped(mAh)) mAh"
    }

    public static func health(_ snapshot: BatterySnapshot) -> String {
        let pct = healthPercent(snapshot.healthPercent)
        guard snapshot.fullChargeCapacitymAh > 0, snapshot.designCapacitymAh > 0 else { return pct }
        return "\(pct) (\(grouped(snapshot.fullChargeCapacitymAh)) / \(grouped(snapshot.designCapacitymAh)) mAh)"
    }

    public static func power(_ watts: Double) -> String {
        let sign = watts > 0 ? "+" : (watts < 0 ? "-" : "")
        return String(format: "%@%.1f W", sign, abs(watts))
    }

    public static func voltage(_ millivolts: Int) -> String {
        String(format: "%.2f V", Double(millivolts) / 1000)
    }

    public static func temperature(_ celsius: Double, unit: TemperatureUnit = .celsius) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.1f C", celsius)
        case .fahrenheit:
            return String(format: "%.1f F", celsius * 9 / 5 + 32)
        }
    }

    public static func duration(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins) min" }
        return "\(hours)h \(mins)m"
    }

    /// The charge state as one line. `includeTimeEstimate` keeps the inline "X to
    /// full / remaining" suffix (the CLI wants it); the GUI passes false and
    /// shows the estimate as its own row via `timeEstimate(_:)`.
    public static func chargeLine(_ snapshot: BatterySnapshot, includeTimeEstimate: Bool = true) -> String {
        var line = "\(snapshot.currentChargePercent)%"
        switch snapshot.chargingState {
        case .charging:
            line += ", charging"
            if includeTimeEstimate, let eta = duration(minutes: snapshot.timeToFullMinutes) { line += ", \(eta) to full" }
        case .discharging:
            line += ", on battery"
            if includeTimeEstimate, let eta = duration(minutes: snapshot.timeToEmptyMinutes) { line += ", \(eta) remaining" }
        case .full:
            line += ", fully charged"
        case .acNoCharge:
            line += ", on AC (not charging)"
        }
        return line
    }

    /// A labelled time estimate for the current state: time to full while
    /// charging, time remaining while discharging. Nil when there is no estimate
    /// (full, on AC holding, or the gauge hasn't settled on a number yet).
    public static func timeEstimate(_ snapshot: BatterySnapshot) -> (label: String, value: String)? {
        switch snapshot.chargingState {
        case .charging:
            guard let value = duration(minutes: snapshot.timeToFullMinutes) else { return nil }
            return ("Time to full", value)
        case .discharging:
            guard let value = duration(minutes: snapshot.timeToEmptyMinutes) else { return nil }
            return ("Time remaining", value)
        case .full, .acNoCharge:
            return nil
        }
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
