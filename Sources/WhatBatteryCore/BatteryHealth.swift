import Foundation

/// Pure battery math. No IOKit, no side effects, fully unit-testable.
public enum BatteryHealth {
    /// Battery health as a percentage: full-charge capacity over design
    /// capacity. Returns nil when either input is non-positive (so callers show
    /// "unknown" rather than a fake 0% or a divide-by-zero).
    public static func healthPercent(fullChargemAh: Int, designmAh: Int) -> Double? {
        guard fullChargemAh > 0, designmAh > 0 else { return nil }
        return Double(fullChargemAh) / Double(designmAh) * 100
    }

    /// Current charge as a 0...100 percentage.
    ///
    /// On Apple Silicon `currentCapacity` is already a percentage, so when it
    /// looks like one (and `maxCapacity` is the usual 100) we trust it. Otherwise
    /// we compute it from the mAh figures. Falls back to the reported percentage
    /// when no usable mAh capacity is present.
    public static func chargePercent(
        currentCapacityPercent: Int,
        maxCapacityPercent: Int,
        currentmAh: Int,
        fullChargemAh: Int
    ) -> Int {
        if maxCapacityPercent == 100, (1...100).contains(currentCapacityPercent) {
            return currentCapacityPercent
        }
        if fullChargemAh > 0, currentmAh > 0 {
            let pct = Double(currentmAh) / Double(fullChargemAh) * 100
            return Int(pct.rounded()).clamped(to: 0...100)
        }
        return currentCapacityPercent.clamped(to: 0...100)
    }

    /// Converts a centi-Celsius temperature to degrees Celsius.
    ///
    /// This is the right conversion for `VirtualTemperature`, which the driver
    /// always publishes in centi-Celsius. It is **not** the right conversion for
    /// `Temperature` on a Mac: see `centiCelsius(fromDeciKelvin:)`.
    public static func celsius(fromCentiCelsius raw: Int) -> Double {
        Double(raw) / 100
    }

    /// The same conversion, but honouring the "no reading" sentinel.
    ///
    /// `AppleSmartBattery.temperature` is non-optional and has always taken 0 to
    /// mean absent (`virtualTemperature > 0` gates its own display the same way).
    /// Passing that 0 through `celsius(fromCentiCelsius:)` produces 0.0°C, which
    /// is worse than the bug DAR-326 fixed: 454°C announces itself as broken,
    /// 0.0°C reads as a cold room. It reached the display, `--json`, the widget,
    /// the temperature alert and the lifetime minimum, where it would have stood
    /// as a fabricated all-time low forever.
    public static func celsiusOrNil(fromCentiCelsius raw: Int) -> Double? {
        raw == 0 ? nil : Double(raw) / 100
    }

    /// Converts AppleSmartBattery's `Temperature` to centi-Celsius, the unit the
    /// rest of the app carries it in.
    ///
    /// On macOS this key is **tenths of a Kelvin**, not centi-Celsius, straight
    /// from Apple's driver (`AppleSmartBatteryManager/AppleSmartBattery.cpp` in
    /// `apple-oss-distributions/PowerManagement`):
    ///
    ///     case kBTemperatureCmd:
    ///         // OSX historically uses SmartBattery format directly. On other
    ///         // platforms we publish in centi C.
    ///     #if !TARGET_OS_OSX
    ///         val = (uint32_t)((val64 * 100) >> 16);
    ///     #endif
    ///
    /// The conversion is skipped on macOS, so the raw SmartBattery value is
    /// published, and SmartBattery temperature is defined in 0.1 K.
    ///
    /// Confirmed against the corpus using `VirtualTemperature` as an independent
    /// check, since the driver always converts that one: across the 746 machines
    /// carrying both, reading this as deci-Kelvin agrees with it to a median of
    /// 0.06°C, while reading it as centi-Celsius is out by 2.28°C. The old
    /// reading also squeezed every machine in the corpus into 29.31°C to 31.94°C,
    /// which is not a temperature distribution; this one spans 20.0°C to 46.3°C
    /// (DAR-329).
    ///
    /// Returns nil rather than a number when the result could not be a battery,
    /// so a caller can tell "no reading" from "0°C".
    public static func centiCelsius(fromDeciKelvin raw: Int) -> Int? {
        guard raw > 0 else { return nil }
        // (raw / 10 - 273.15) * 100, kept in integers. Reported arithmetic
        // because this takes whatever IOKit hands over: a malformed or widened
        // value would otherwise trap on the multiply before the band below ever
        // ran.
        let (scaled, scaleOverflowed) = raw.multipliedReportingOverflow(by: 10)
        guard !scaleOverflowed else { return nil }
        let (centiCelsius, shiftOverflowed) = scaled.subtractingReportingOverflow(27_315)
        guard !shiftOverflowed, isPlausibleCentiCelsius(centiCelsius) else { return nil }
        return centiCelsius
    }

    /// A temperature a battery could actually be at, in centi-Celsius. The
    /// bounds are deliberately generous: a laptop left in a cold car and one on
    /// a hot dashboard both have to pass.
    public static func isPlausibleCentiCelsius(_ centiCelsius: Int) -> Bool {
        (-4_000...10_000).contains(centiCelsius)
    }

    /// Treats AppleSmartBattery time estimates as optional: 0 or the 65535
    /// sentinel both mean "not computed yet".
    public static func minutesOrNil(_ value: Int) -> Int? {
        (value <= 0 || value >= 65535) ? nil : value
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
