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

    /// Converts AppleSmartBattery's centi-Celsius temperature to degrees Celsius.
    public static func celsius(fromCentiCelsius raw: Int) -> Double {
        Double(raw) / 100
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
