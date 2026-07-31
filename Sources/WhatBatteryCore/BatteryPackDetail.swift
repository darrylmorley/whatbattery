import Foundation

/// The per-cell and lifetime figures the fuel gauge keeps in the
/// `AppleSmartBattery` node's `BatteryData` dictionary. We have always read that
/// node and thrown all of this away.
///
/// The per-cell values are the interesting part: a pack that is failing usually
/// shows it as one cell drifting away from its neighbours long before the
/// headline health figure moves. Nothing else on the Mac surfaces them.
public struct BatteryPackDetail: Equatable, Sendable {
    /// Live per-cell voltage in millivolts, in pack order.
    public let cellVoltagesMV: [Int]
    /// The gauge's learned maximum charge per cell, in mAh.
    public let cellQmax: [Int]
    /// Per-cell internal resistance, in the gauge's own scale. Unitless here on
    /// purpose: the absolute number means little, the spread between cells does.
    public let cellResistance: [Int]

    /// Lowest and highest charge the battery has sat at today, in percent.
    public let dailyMinSoc: Int?
    public let dailyMaxSoc: Int?

    /// The cycle count when the gauge last relearned its capacity estimate.
    /// Worth surfacing: a recent relearn is the usual explanation for health
    /// appearing to step down overnight.
    public let cycleCountAtLastQmax: Int?

    public let lifetime: BatteryLifetime?

    public init(
        cellVoltagesMV: [Int] = [],
        cellQmax: [Int] = [],
        cellResistance: [Int] = [],
        dailyMinSoc: Int? = nil,
        dailyMaxSoc: Int? = nil,
        cycleCountAtLastQmax: Int? = nil,
        lifetime: BatteryLifetime? = nil
    ) {
        self.cellVoltagesMV = cellVoltagesMV
        self.cellQmax = cellQmax
        self.cellResistance = cellResistance
        self.dailyMinSoc = dailyMinSoc
        self.dailyMaxSoc = dailyMaxSoc
        self.cycleCountAtLastQmax = cycleCountAtLastQmax
        self.lifetime = lifetime
    }

    /// Nothing worth showing: every field came back empty.
    public var isEmpty: Bool {
        cellVoltagesMV.isEmpty && cellQmax.isEmpty && cellResistance.isEmpty
            && dailyMinSoc == nil && dailyMaxSoc == nil && cycleCountAtLastQmax == nil
            && lifetime == nil
    }

    /// Millivolts between the highest and lowest cell. The number that matters:
    /// a healthy pack sits within a few mV, and a cell going bad opens the gap.
    public var cellVoltageSpreadMV: Int? {
        guard let low = cellVoltagesMV.min(), let high = cellVoltagesMV.max(), cellVoltagesMV.count > 1 else {
            return nil
        }
        return high - low
    }

    /// mAh between the strongest and weakest cell's learned capacity.
    public var cellQmaxSpreadmAh: Int? {
        guard let low = cellQmax.min(), let high = cellQmax.max(), cellQmax.count > 1 else { return nil }
        return high - low
    }

    /// Build from the raw `BatteryData` dictionary. Pure, so the same parsing
    /// serves the Mac's IOKit read and an iPhone's relay read.
    public static func from(batteryData: [String: Any]?) -> BatteryPackDetail? {
        guard let data = batteryData else { return nil }
        let detail = BatteryPackDetail(
            cellVoltagesMV: intArray(data["CellVoltage"]),
            cellQmax: intArray(data["Qmax"]),
            cellResistance: intArray(data["WeightedRa"]),
            dailyMinSoc: percentValue(data["DailyMinSoc"]),
            dailyMaxSoc: percentValue(data["DailyMaxSoc"]),
            cycleCountAtLastQmax: positiveInt(data["CycleCountLastQmax"]),
            lifetime: BatteryLifetime.from(lifetimeData: data["LifetimeData"] as? [String: Any])
        )
        return detail.isEmpty ? nil : detail
    }

    // MARK: - Conversion

    /// A CFArray of numbers. The reader had no array handling before this: every
    /// other key it touches is a scalar or a flat dictionary.
    ///
    /// All or nothing on purpose. The cell arrays are read positionally (cell 2's
    /// voltage next to cell 2's capacity), so silently dropping one bad element
    /// would shift every later cell against its neighbours and label the data
    /// wrongly. A value outside a plausible range counts as bad: it would also
    /// let the spread arithmetic overflow.
    static func intArray(_ value: Any?) -> [Int] {
        guard let raw = value as? [Any] else { return [] }
        var values: [Int] = []
        values.reserveCapacity(raw.count)
        for element in raw {
            guard let number = (element as? NSNumber)?.intValue,
                  (0..<1_000_000).contains(number) else { return [] }
            values.append(number)
        }
        return values
    }

    static func positiveInt(_ value: Any?) -> Int? {
        guard let n = (value as? NSNumber)?.intValue, n > 0 else { return nil }
        return n
    }

    static func percentValue(_ value: Any?) -> Int? {
        guard let n = (value as? NSNumber)?.intValue, (0...100).contains(n) else { return nil }
        return n
    }
}

/// Extremes the gauge has recorded across the pack's whole life. Read-only
/// history that predates WhatBattery being installed, which is the appeal: it
/// covers the time before we were watching.
public struct BatteryLifetime: Equatable, Sendable {
    public let minimumTemperatureC: Int?
    public let maximumTemperatureC: Int?
    /// The gauge reports this on a different scale from the min/max pair, so it
    /// is resolved at parse time against them rather than assumed.
    public let averageTemperatureC: Double?

    public let maximumChargeCurrentMA: Int?
    public let maximumDischargeCurrentMA: Int?
    public let minimumPackVoltageMV: Int?
    public let maximumPackVoltageMV: Int?

    /// Hours the pack has been powered on.
    public let totalOperatingTimeHours: Int?

    public init(
        minimumTemperatureC: Int? = nil,
        maximumTemperatureC: Int? = nil,
        averageTemperatureC: Double? = nil,
        maximumChargeCurrentMA: Int? = nil,
        maximumDischargeCurrentMA: Int? = nil,
        minimumPackVoltageMV: Int? = nil,
        maximumPackVoltageMV: Int? = nil,
        totalOperatingTimeHours: Int? = nil
    ) {
        self.minimumTemperatureC = minimumTemperatureC
        self.maximumTemperatureC = maximumTemperatureC
        self.averageTemperatureC = averageTemperatureC
        self.maximumChargeCurrentMA = maximumChargeCurrentMA
        self.maximumDischargeCurrentMA = maximumDischargeCurrentMA
        self.minimumPackVoltageMV = minimumPackVoltageMV
        self.maximumPackVoltageMV = maximumPackVoltageMV
        self.totalOperatingTimeHours = totalOperatingTimeHours
    }

    public var isEmpty: Bool {
        minimumTemperatureC == nil && maximumTemperatureC == nil && averageTemperatureC == nil
            && maximumChargeCurrentMA == nil && maximumDischargeCurrentMA == nil
            && minimumPackVoltageMV == nil && maximumPackVoltageMV == nil
            && totalOperatingTimeHours == nil
    }

    public static func from(lifetimeData: [String: Any]?) -> BatteryLifetime? {
        guard let data = lifetimeData else { return nil }
        let minTemp = int(data["MinimumTemperature"])
        let maxTemp = int(data["MaximumTemperature"])
        let lifetime = BatteryLifetime(
            minimumTemperatureC: minTemp,
            maximumTemperatureC: maxTemp,
            averageTemperatureC: averageTemperature(data["AverageTemperature"], min: minTemp, max: maxTemp),
            maximumChargeCurrentMA: int(data["MaximumChargeCurrent"]),
            maximumDischargeCurrentMA: signedCurrent(data["MaximumDischargeCurrent"]),
            minimumPackVoltageMV: int(data["MinimumPackVoltage"]),
            maximumPackVoltageMV: int(data["MaximumPackVoltage"]),
            totalOperatingTimeHours: int(data["TotalOperatingTime"])
        )
        return lifetime.isEmpty ? nil : lifetime
    }

    /// The min and max come back as whole degrees while the average appears to
    /// be scaled by ten (a real pack reported 11, 41 and 211). Rather than hard
    /// code that, try both readings and keep the one that falls between the
    /// observed extremes.
    ///
    /// If *both* fit, the scale is genuinely ambiguous (min 0, max 50, raw 20
    /// could be 20°C or 2°C) and we report nothing: a temperature that might be
    /// off by a factor of ten is worse than a blank row.
    private static func averageTemperature(_ value: Any?, min: Int?, max: Int?) -> Double? {
        guard let raw = (value as? NSNumber)?.doubleValue else { return nil }
        guard let low = min.map(Double.init), let high = max.map(Double.init), low <= high else { return nil }
        let fitting = [raw, raw / 10].filter { $0 >= low && $0 <= high }
        return fitting.count == 1 ? fitting[0] : nil
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// Discharge is stored as a negative number, and arrives wrapped into an
    /// unsigned field (a real pack reported 18446744073709546764, which is
    /// -4852 read as signed, i.e. a 4.85 A peak draw). Take the magnitude, and
    /// drop anything still implausible after that rather than print nonsense.
    private static func signedCurrent(_ value: Any?) -> Int? {
        guard let n = (value as? NSNumber)?.intValue else { return nil }
        let magnitude = abs(n)
        guard magnitude > 0, magnitude < 100_000 else { return nil }
        return magnitude
    }
}
