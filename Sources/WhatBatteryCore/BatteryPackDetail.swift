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

    /// The gauge's raw `ManufactureDate`, passed through undecoded. It is not a
    /// date in any standard encoding; `BatteryManufactureMonth.decode` is the
    /// only thing that should interpret it, and it needs the gauge name too.
    public let manufactureRaw: Int?

    public init(
        cellVoltagesMV: [Int] = [],
        cellQmax: [Int] = [],
        cellResistance: [Int] = [],
        dailyMinSoc: Int? = nil,
        dailyMaxSoc: Int? = nil,
        cycleCountAtLastQmax: Int? = nil,
        lifetime: BatteryLifetime? = nil,
        manufactureRaw: Int? = nil
    ) {
        self.cellVoltagesMV = cellVoltagesMV
        self.cellQmax = cellQmax
        self.cellResistance = cellResistance
        self.dailyMinSoc = dailyMinSoc
        self.dailyMaxSoc = dailyMaxSoc
        self.cycleCountAtLastQmax = cycleCountAtLastQmax
        self.lifetime = lifetime
        self.manufactureRaw = manufactureRaw
    }

    /// Nothing worth showing: every field came back empty.
    public var isEmpty: Bool {
        cellVoltagesMV.isEmpty && cellQmax.isEmpty && cellResistance.isEmpty
            && dailyMinSoc == nil && dailyMaxSoc == nil && cycleCountAtLastQmax == nil
            && lifetime == nil && manufactureRaw == nil
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
    ///
    /// `currentTemperatureCentiC` is the battery node's own `Temperature`, whose
    /// scale we know. It is passed in because the lifetime temperatures do not
    /// declare theirs, and a reading of known scale is the only independent
    /// check available: see `BatteryLifetime.temperatureRange`.
    public static func from(
        batteryData: [String: Any]?,
        currentTemperatureCentiC: Int? = nil
    ) -> BatteryPackDetail? {
        guard let data = batteryData else { return nil }
        let detail = BatteryPackDetail(
            cellVoltagesMV: intArray(data["CellVoltage"]),
            cellQmax: intArray(data["Qmax"]),
            cellResistance: intArray(data["WeightedRa"]),
            dailyMinSoc: percentValue(data["DailyMinSoc"]),
            dailyMaxSoc: percentValue(data["DailyMaxSoc"]),
            cycleCountAtLastQmax: positiveInt(data["CycleCountLastQmax"]),
            lifetime: BatteryLifetime.from(
                lifetimeData: data["LifetimeData"] as? [String: Any],
                currentTemperatureC: currentTemperatureCentiC.map { Double($0) / 100 }
            ),
            manufactureRaw: positiveInt(data["ManufactureDate"])
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

    public static func from(
        lifetimeData: [String: Any]?,
        currentTemperatureC: Double? = nil
    ) -> BatteryLifetime? {
        guard let data = lifetimeData else { return nil }
        let range = temperatureRange(
            minRaw: int(data["MinimumTemperature"]),
            maxRaw: int(data["MaximumTemperature"]),
            currentC: currentTemperatureC
        )
        let lifetime = BatteryLifetime(
            minimumTemperatureC: range.map { Int($0.min.rounded()) },
            maximumTemperatureC: range.map { Int($0.max.rounded()) },
            averageTemperatureC: averageTemperature(data["AverageTemperature"], range: range),
            maximumChargeCurrentMA: int(data["MaximumChargeCurrent"]),
            maximumDischargeCurrentMA: signedCurrent(data["MaximumDischargeCurrent"]),
            minimumPackVoltageMV: int(data["MinimumPackVoltage"]),
            maximumPackVoltageMV: int(data["MaximumPackVoltage"]),
            totalOperatingTimeHours: int(data["TotalOperatingTime"])
        )
        return lifetime.isEmpty ? nil : lifetime
    }

    /// The lifetime min/max in whole degrees, or nil when the scale cannot be
    /// settled.
    ///
    /// The gauge does not say which scale it is using, and it is not the same on
    /// every machine: 114 of the 746 corpus machines carrying `LifetimeData`
    /// report deci-degrees and 632 report whole ones. Printing them raw is what
    /// told a MacBook Air M1 owner his battery had reached 454°C.
    ///
    /// There is no field to ask. `LifetimeData` has no unit or version key, and
    /// while the fuel gauge is a strong predictor (every `bq20z451` in the corpus
    /// is deci, nearly every `bq40z651` is whole) it is not authoritative: one
    /// `bq40z651` machine reports deci, so an allowlist would ship a wrong number
    /// to somebody. The scale tracks pack and firmware revisions rather than a
    /// name we can enumerate, exactly like `ChargingVoltage` before it.
    ///
    /// So it is settled from the data, with two independent signals:
    ///
    /// 1. **Magnitude.** A lifetime maximum above 80°C is not a temperature, it
    ///    is a tenth of one. This classifies all 746 corpus machines correctly on
    ///    its own. The threshold sits in a dead zone: no pack in service reaches
    ///    80°C, and no pack in service has a lifetime *maximum* as low as 8°C.
    /// 2. **The pack's own thermometer.** `Temperature` is centi-degrees, a scale
    ///    we know, and a lifetime range has to contain the current reading. This
    ///    catches the `bq40z651` exception on its own, and across the corpus it
    ///    never once contradicted the magnitude rule.
    ///
    /// When the two disagree, nothing is shown. A temperature that might be off
    /// by a factor of ten is worse than a blank row.
    ///
    /// The minimum is deliberately not consulted: several M1s report lifetime
    /// minima like -123, which is a believable -12.3°C under deci and nonsense
    /// under whole, so it cannot discriminate. The pair is scaled together off
    /// the maximum.
    static func temperatureRange(
        minRaw: Int?,
        maxRaw: Int?,
        currentC: Double?
    ) -> (min: Double, max: Double)? {
        guard let minRaw, let maxRaw, minRaw <= maxRaw else { return nil }
        // An uninitialised blob reads as zero in either scale, so there is
        // nothing to choose between and nothing worth showing. Any other equal
        // pair is fine: a pack whose range has not widened yet is legitimate.
        guard !(minRaw == 0 && maxRaw == 0) else { return nil }

        let whole = (min: Double(minRaw), max: Double(maxRaw))
        let deci = (min: Double(minRaw) / 10, max: Double(maxRaw) / 10)
        let byMagnitude = maxRaw > deciDegreeThreshold ? deci : whole

        // Without a reading to check against, magnitude stands alone. It
        // classifies every machine in the corpus correctly, and refusing to show
        // anything just because the thermometer is missing would punish the
        // machines least able to spare the data.
        guard let currentC else {
            return isPlausible(byMagnitude) ? byMagnitude : nil
        }

        // With one, prefer the scale that actually contains it. The current
        // reading is recorded continuously, so it lies inside the lifetime range
        // by construction; a degree of slack absorbs rounding.
        let fits = [whole, deci].filter {
            isPlausible($0) && $0.min - 1 <= currentC && currentC <= $0.max + 1
        }
        switch fits.count {
        case 1:
            // Containment settles the ambiguity the magnitude rule cannot, but it
            // is not licensed to overrule it. A range of 20 to 90 with the pack
            // reading 85°C fits the whole-degree reading and nothing else, so the
            // old code returned "20°C to 90°C" with confidence, while magnitude
            // says a lifetime maximum of 90 can only be tenths. Two signals
            // pointing opposite ways is not a resolved scale. No corpus machine
            // reaches this branch: across all 746 the two never once disagreed.
            guard fits[0] == byMagnitude else { return nil }
            return fits[0]
        default:
            // Either nothing can be reconciled with the pack's own thermometer,
            // or both readings can, and neither case is a resolved scale.
            //
            // No machine in the corpus reaches the ambiguous branch: a range
            // wide enough to contain the current reading under both scales, like
            // -80 to 450, has already failed the plausibility net under the
            // whole-degree reading. It is defensive, not observed. An earlier
            // revision resolved it by magnitude on the strength of a
            // measurement that had omitted the plausibility gate and so counted
            // 24 machines here; with the gate the true count is zero, and the
            // reason for preferring a guess over a blank evaporated with it.
            //
            // So when both fit, show nothing: two candidates a factor of ten
            // apart that both look reasonable is precisely the situation this
            // whole function exists to stop us printing through.
            return nil
        }
    }

    /// A range no battery could have lived through is not a scale we have
    /// resolved, whichever way we read it.
    private static func isPlausible(_ range: (min: Double, max: Double)) -> Bool {
        range.min >= -40 && range.max <= 100
    }

    /// Above this a lifetime maximum can only be deci-degrees. See
    /// `temperatureRange`.
    private static let deciDegreeThreshold = 80

    /// The average carries its own scale, which is not always the pair's: try
    /// both readings and keep the one that falls inside the resolved range.
    ///
    /// If *both* fit, the scale is genuinely ambiguous (min 0, max 50, raw 20
    /// could be 20°C or 2°C) and we report nothing. This is the original
    /// heuristic; what the deci-degree fix changed is that it is now measured against a
    /// range in known units, rather than against whatever the pair happened to
    /// be reported in.
    private static func averageTemperature(_ value: Any?, range: (min: Double, max: Double)?) -> Double? {
        guard let raw = (value as? NSNumber)?.doubleValue, let range else { return nil }
        let fitting = [raw, raw / 10].filter { $0 >= range.min && $0 <= range.max }
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
