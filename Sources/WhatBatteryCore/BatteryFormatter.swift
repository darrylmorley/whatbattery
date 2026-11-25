import Foundation

/// Display helpers shared by the CLI and (later) the SwiftUI app. Kept in Core
/// because the CLI legitimately needs to format too; the SwiftUI app may still
/// format inline where it wants finer control.
public enum BatteryFormatter {
    public enum TemperatureUnit {
        case celsius, fahrenheit

        /// A Celsius reading in this unit, for plotting.
        public func value(fromCelsius celsius: Double) -> Double {
            switch self {
            case .celsius: return celsius
            case .fahrenheit: return celsius * 9 / 5 + 32
            }
        }

        public var symbol: String {
            switch self {
            case .celsius: return "°C"
            case .fahrenheit: return "°F"
            }
        }
    }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return "\(Int(value.rounded()))%"
    }

    /// Battery health as a one-decimal percentage (e.g. "99.5%"), capped at 100.
    /// Health needs the decimal: rounding to a whole number lets 99.5% read as a
    /// misleading "100%" when the full-charge capacity is clearly below design.
    public static func healthPercent(_ value: Double?, locale: Locale = .current) -> String {
        guard let value else { return "unknown" }
        return String(format: "%.1f%%", locale: locale, min(value, 100))
    }

    public static func milliampHours(_ mAh: Int, locale: Locale = .current) -> String {
        "\(grouped(mAh, locale: locale)) mAh"
    }

    /// Health as a percentage, with the raw capacities in brackets.
    ///
    /// `includeCapacities: false` drops the bracketed mAh, which is what an
    /// unlicensed reader gets: the app has always hidden those figures behind a
    /// licence, and this is the only reason the CLI could ever print them when
    /// the window would not.
    public static func health(_ snapshot: BatterySnapshot, includeCapacities: Bool = true, locale: Locale = .current) -> String {
        let pct = healthPercent(snapshot.healthPercent, locale: locale)
        guard includeCapacities, snapshot.fullChargeCapacitymAh > 0, snapshot.designCapacitymAh > 0 else { return pct }
        return "\(pct) (\(grouped(snapshot.fullChargeCapacitymAh, locale: locale)) / \(grouped(snapshot.designCapacitymAh, locale: locale)) mAh)"
    }

    public static func power(_ watts: Double, locale: Locale = .current) -> String {
        let sign = watts > 0 ? "+" : (watts < 0 ? "-" : "")
        return String(format: "%@%.1f W", locale: locale, sign, abs(watts))
    }

    /// A measured power rounded to a whole watt, "55 W". Same spacing as
    /// `power`, so a session's figures and the live reading read alike.
    public static func wholeWatts(_ watts: Double, locale: Locale = .current) -> String {
        // + 0 turns a rounded -0.0 into 0.0, so -0.4 prints "0 W", not "-0 W".
        String(format: "%.0f W", locale: locale, watts.rounded() + 0)
    }

    /// A charger's display name. The firmware's generic description for a USB
    /// Power Delivery adapter is a lowercase "pd charger", which means nothing
    /// to most people, so it reads as plain "charger". Display only: the raw
    /// label stays the stored key (charging session ids, the adapter-wattage
    /// parse), so this must never be fed back into either.
    public static func chargerName(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        // A case-insensitive search on the string itself, not a character
        // count taken from a lowercased copy, so the cut lands exactly.
        guard let match = trimmed.range(of: "pd charger", options: [.caseInsensitive, .backwards, .anchored]) else {
            return trimmed.isEmpty ? "Charger" : trimmed
        }
        // Whole word only: "Upd charger" is somebody's name, not the generic one.
        if match.lowerBound > trimmed.startIndex, !trimmed[trimmed.index(before: match.lowerBound)].isWhitespace {
            return trimmed
        }
        let prefix = trimmed[..<match.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? "Charger" : "\(prefix) charger"
    }

    /// A low-to-high span, "10.6 to 32.8°C". `unit` carries its own leading
    /// space where the unit takes one (" V"), since degrees do not.
    public static func range(_ low: Double, _ high: Double, unit: String, decimals: Int, locale: Locale = .current) -> String {
        let format = "%.\(decimals)f"
        let lo = String(format: format, locale: locale, low)
        let hi = String(format: format, locale: locale, high)
        return "\(lo) to \(hi)\(unit)"
    }

    /// A calendar day for tables, "24 Nov 2026". Exports keep ISO dates; this
    /// is for people reading the window.
    public static func day(_ date: Date, locale: Locale = .current, calendar: Calendar = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style.day().month(.abbreviated).year())
    }

    /// A calendar month for tables, "Jul 2026".
    public static func month(year: Int, month: Int, locale: Locale = .current, calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 15)) else {
            return String(format: "%04d-%02d", year, month)
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style.month(.abbreviated).year())
    }

    /// The full "Power" line: the live wattage, ", no reading" when a zero is a
    /// rejected reading rather than a measurement, and the adapter in brackets.
    ///
    /// A zero when full or on AC is left bare ("0.0 W  (100W pd charger)"):
    /// the charge line shown beside it on every surface already says "fully
    /// charged" or "on AC (not charging)". Shared by the window, the popover,
    /// the CLI, the report and the iDevice view, which all used to build this
    /// line separately.
    /// `includeAdapter: false` leaves the charger off, for layouts that give the
    /// adapter a slot of its own rather than trailing it on the reading.
    public static func powerLine(
        _ snapshot: BatterySnapshot,
        adapterSeparator: String = "  ",
        includeAdapter: Bool = true,
        locale: Locale = .current
    ) -> String {
        var text = power(snapshot.powerWatts, locale: locale)
        // Exactly zero while charging or discharging is the builder's
        // sign/magnitude guard rejecting a self-contradicting reading (a genuine
        // measurement demands a nonzero current), so say that rather than show a
        // confident 0.0 W beside a live charger label. A zero when full or on AC
        // stays bare: every caller also shows `chargeLine`, which already names
        // that state, and repeating it here printed it twice.
        switch snapshot.chargingState {
        case .charging, .discharging:
            if snapshot.powerWatts == 0 { text += ", no reading" }
        case .full, .acNoCharge:
            break
        }
        if includeAdapter, let adapter = snapshot.adapter?.label {
            text += "\(adapterSeparator)(\(chargerName(adapter)))"
        }
        return text
    }

    /// The desktop DC-in line, e.g. "47.3 W (12.00 V, 3.94 A)". Shared by the
    /// CLI's no-battery fallback and the GUI's desktop power view so the two
    /// never drift. Raw doubles rather than the SMC struct because Core cannot
    /// see the Darwin backend.
    public static func dcInPower(watts: Double, volts: Double, amps: Double, locale: Locale = .current) -> String {
        String(format: "%.1f W (%.2f V, %.2f A)", locale: locale, watts, volts, amps)
    }

    public static func voltage(_ millivolts: Int, locale: Locale = .current) -> String {
        String(format: "%.2f V", locale: locale, Double(millivolts) / 1000)
    }

    /// The current the gauge reports, signed the same way as power: positive into
    /// the battery, negative out of it.
    ///
    /// The gauge keeps two figures, an averaged one and an unaveraged one. The
    /// averaged figure is the reading; the unaveraged one is only worth showing
    /// when the load has moved enough that the two would visibly disagree, which
    /// is exactly the moment someone comparing us against another tool sees two
    /// different numbers and wonders which is wrong.
    ///
    /// This will not always multiply out against the power reading beside it, and
    /// that is why every surface labels it as the battery's own current: on Apple
    /// Silicon the discharge watts come from the SMC's live rail while this comes
    /// from the gauge, so a load that has just moved shows up in one before the
    /// other.
    public static func current(_ snapshot: BatterySnapshot, locale: Locale = .current) -> String {
        var text = amps(snapshot.amperageMilliamps, locale: locale)
        let instant = snapshot.instantAmperageMilliamps
        if instant != 0, abs(instant - snapshot.amperageMilliamps) >= instantAmperageGapMA {
            text += ", \(amps(instant, locale: locale)) now"
        }
        return text
    }

    /// Below this the averaged and unaveraged currents are the same reading with
    /// rounding noise between them, and showing both would be clutter.
    private static let instantAmperageGapMA = 100

    private static func amps(_ milliamps: Int, locale: Locale) -> String {
        let sign = milliamps > 0 ? "+" : (milliamps < 0 ? "-" : "")
        return String(format: "%@%.2f A", locale: locale, sign, abs(Double(milliamps)) / 1000)
    }

    /// A pack that reported no usable temperature says so, rather than being
    /// printed as a believable 0.0°C.
    public static func temperature(_ celsius: Double?, unit: TemperatureUnit = .celsius, locale: Locale = .current) -> String {
        guard let celsius else { return "Unknown" }
        return temperature(celsius, unit: unit, locale: locale)
    }

    public static func temperature(_ celsius: Double, unit: TemperatureUnit = .celsius, locale: Locale = .current) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.1f°C", locale: locale, celsius)
        case .fahrenheit:
            return String(format: "%.1f°F", locale: locale, celsius * 9 / 5 + 32)
        }
    }

    /// A low-to-high temperature span in the user's unit, "10.6 to 32.8°C".
    public static func temperatureRange(_ lowCelsius: Double, _ highCelsius: Double, unit: TemperatureUnit = .celsius, decimals: Int = 1, locale: Locale = .current) -> String {
        switch unit {
        case .celsius:
            return range(lowCelsius, highCelsius, unit: "°C", decimals: decimals, locale: locale)
        case .fahrenheit:
            return range(lowCelsius * 9 / 5 + 32, highCelsius * 9 / 5 + 32, unit: "°F", decimals: decimals, locale: locale)
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
            // The battery's own critical flag, not our low-charge threshold: the
            // gauge decides this from voltage under load, so it can fire at a
            // percentage that still looks comfortable.
            if snapshot.atCriticalLevel { line += ", critically low" }
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

    // Locale-driven grouping: 8,694 in en, 8.694 in nl, 8 694 in fr. The
    // hard-coded "," this replaces was the report from a comma-decimal
    // locale user.
    private static func grouped(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
