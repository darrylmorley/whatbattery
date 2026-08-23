import Foundation

/// What the battery is doing right now.
public enum ChargingState: String, Codable, Sendable {
    case charging
    case discharging
    case full
    case acNoCharge   // on AC, holding (e.g. optimized charging paused, or at 100)
}

/// The complete, app-facing battery snapshot. Codable so the menu bar app, the
/// widget (via the App Group), `--json`, and the history store all share one
/// shape. Built by `BatterySnapshotBuilder` from a raw `AppleSmartBattery`.
public struct BatterySnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date

    // Health
    public let designCapacitymAh: Int
    public let fullChargeCapacitymAh: Int
    public let healthPercent: Double?
    public let cycleCount: Int
    public let designCycleCount: Int

    // Charge state
    public let currentChargePercent: Int
    public let currentChargemAh: Int
    public let chargingState: ChargingState
    public let timeToFullMinutes: Int?
    public let timeToEmptyMinutes: Int?
    /// The gauge's own critical-charge flag, not a threshold we picked.
    public let atCriticalLevel: Bool

    // Live electrical
    public let voltageMillivolts: Int
    public let amperageMilliamps: Int      // signed, the gauge's averaged figure
    /// The gauge's unaveraged current, signed. Moves with the load; the averaged
    /// figure above is what a reading should normally quote.
    public let instantAmperageMilliamps: Int
    public let powerWatts: Double          // + charging, - discharging, 0 idle/full
    /// nil when the pack reported no usable temperature. Never 0.0 for absent:
    /// see `BatteryHealth.celsiusOrNil(fromCentiCelsius:)`.
    public let temperatureCelsius: Double?

    // Adapter
    public let adapter: AdapterInfo?

    // Identity
    public let deviceModel: String
    public let batterySerial: String?
    /// When the pack was made, to the month, or nil when the gauge's encoding is
    /// one we cannot read. See `BatteryManufactureMonth`.
    public let manufactureMonth: BatteryManufactureMonth?

    public init(
        timestamp: Date,
        designCapacitymAh: Int,
        fullChargeCapacitymAh: Int,
        healthPercent: Double?,
        cycleCount: Int,
        designCycleCount: Int,
        currentChargePercent: Int,
        currentChargemAh: Int,
        chargingState: ChargingState,
        timeToFullMinutes: Int?,
        timeToEmptyMinutes: Int?,
        atCriticalLevel: Bool = false,
        voltageMillivolts: Int,
        amperageMilliamps: Int,
        instantAmperageMilliamps: Int = 0,
        powerWatts: Double,
        temperatureCelsius: Double?,
        adapter: AdapterInfo?,
        deviceModel: String,
        batterySerial: String?,
        manufactureMonth: BatteryManufactureMonth? = nil
    ) {
        self.timestamp = timestamp
        self.designCapacitymAh = designCapacitymAh
        self.fullChargeCapacitymAh = fullChargeCapacitymAh
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.currentChargePercent = currentChargePercent
        self.currentChargemAh = currentChargemAh
        self.chargingState = chargingState
        self.timeToFullMinutes = timeToFullMinutes
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.atCriticalLevel = atCriticalLevel
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.instantAmperageMilliamps = instantAmperageMilliamps
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
        self.adapter = adapter
        self.deviceModel = deviceModel
        self.batterySerial = batterySerial
        self.manufactureMonth = manufactureMonth
    }
}

// MARK: - Coding

public extension CodingUserInfoKey {
    /// Set on a `JSONEncoder` to leave the Pro-only figures out of the encoded
    /// snapshot: the raw mAh capacities and the pack's manufacture month. The
    /// window hides both behind a licence, so every other surface fed by an
    /// encoder has to be able to do the same.
    static let omitProDetail = CodingUserInfoKey(rawValue: "app.whatbattery.omitProDetail")!
}

public extension BatterySnapshot {
    private enum CodingKeys: String, CodingKey {
        case timestamp
        case designCapacitymAh, fullChargeCapacitymAh, healthPercent, cycleCount, designCycleCount
        case currentChargePercent, currentChargemAh, chargingState
        case timeToFullMinutes, timeToEmptyMinutes, atCriticalLevel
        case voltageMillivolts, amperageMilliamps, instantAmperageMilliamps
        case powerWatts, temperatureCelsius
        case adapter, deviceModel, batterySerial, manufactureMonth
    }

    /// Hand-written so the Pro figures can be dropped for an unlicensed reader.
    ///
    /// `currentChargemAh` goes with the capacities: on its own it looks
    /// harmless, but divided by the charge percent it hands back the full-charge
    /// capacity the other two were withheld to protect. `manufactureMonth` is
    /// here because the window treats it as Pro, and `--json` handing it out
    /// free would put the two surfaces straight back into the disagreement this
    /// work exists to end.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let includeProDetail = encoder.userInfo[.omitProDetail] as? Bool != true
        try container.encode(timestamp, forKey: .timestamp)
        if includeProDetail {
            try container.encode(designCapacitymAh, forKey: .designCapacitymAh)
            try container.encode(fullChargeCapacitymAh, forKey: .fullChargeCapacitymAh)
            try container.encode(currentChargemAh, forKey: .currentChargemAh)
        }
        try container.encode(healthPercent, forKey: .healthPercent)
        try container.encode(cycleCount, forKey: .cycleCount)
        try container.encode(designCycleCount, forKey: .designCycleCount)
        try container.encode(currentChargePercent, forKey: .currentChargePercent)
        try container.encode(chargingState, forKey: .chargingState)
        try container.encode(timeToFullMinutes, forKey: .timeToFullMinutes)
        try container.encode(timeToEmptyMinutes, forKey: .timeToEmptyMinutes)
        try container.encode(atCriticalLevel, forKey: .atCriticalLevel)
        try container.encode(voltageMillivolts, forKey: .voltageMillivolts)
        try container.encode(amperageMilliamps, forKey: .amperageMilliamps)
        try container.encode(instantAmperageMilliamps, forKey: .instantAmperageMilliamps)
        try container.encode(powerWatts, forKey: .powerWatts)
        try container.encodeIfPresent(temperatureCelsius, forKey: .temperatureCelsius)
        try container.encode(adapter, forKey: .adapter)
        try container.encode(deviceModel, forKey: .deviceModel)
        try container.encode(batterySerial, forKey: .batterySerial)
        if includeProDetail {
            try container.encode(manufactureMonth, forKey: .manufactureMonth)
        }
    }

    /// Every field the encoder can legitimately omit decodes as absent rather
    /// than as a failure: the capacities because a redacted payload must still
    /// round-trip, the newer fields because the widget can be reading a file the
    /// previous app version wrote.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            designCapacitymAh: try container.decodeIfPresent(Int.self, forKey: .designCapacitymAh) ?? 0,
            fullChargeCapacitymAh: try container.decodeIfPresent(Int.self, forKey: .fullChargeCapacitymAh) ?? 0,
            healthPercent: try container.decodeIfPresent(Double.self, forKey: .healthPercent),
            cycleCount: try container.decode(Int.self, forKey: .cycleCount),
            designCycleCount: try container.decode(Int.self, forKey: .designCycleCount),
            currentChargePercent: try container.decode(Int.self, forKey: .currentChargePercent),
            currentChargemAh: try container.decodeIfPresent(Int.self, forKey: .currentChargemAh) ?? 0,
            chargingState: try container.decode(ChargingState.self, forKey: .chargingState),
            timeToFullMinutes: try container.decodeIfPresent(Int.self, forKey: .timeToFullMinutes),
            timeToEmptyMinutes: try container.decodeIfPresent(Int.self, forKey: .timeToEmptyMinutes),
            atCriticalLevel: try container.decodeIfPresent(Bool.self, forKey: .atCriticalLevel) ?? false,
            voltageMillivolts: try container.decode(Int.self, forKey: .voltageMillivolts),
            amperageMilliamps: try container.decode(Int.self, forKey: .amperageMilliamps),
            instantAmperageMilliamps: try container.decodeIfPresent(Int.self, forKey: .instantAmperageMilliamps) ?? 0,
            powerWatts: try container.decode(Double.self, forKey: .powerWatts),
            temperatureCelsius: try container.decodeIfPresent(Double.self, forKey: .temperatureCelsius),
            adapter: try container.decodeIfPresent(AdapterInfo.self, forKey: .adapter),
            deviceModel: try container.decode(String.self, forKey: .deviceModel),
            batterySerial: try container.decodeIfPresent(String.self, forKey: .batterySerial),
            manufactureMonth: try container.decodeIfPresent(BatteryManufactureMonth.self, forKey: .manufactureMonth)
        )
    }
}

/// Turns a raw `AppleSmartBattery` reading into a `BatterySnapshot`.
///
/// Pure: it takes the live discharge watts (from the SMC, read by the Darwin
/// backend) as an argument rather than reaching for the SMC itself, so Core
/// stays free of platform code and the builder stays unit-testable.
public enum BatterySnapshotBuilder {
    public static func build(
        battery: AppleSmartBattery,
        deviceModel: String,
        smcDischargeWatts: Double?,
        now: Date
    ) -> BatterySnapshot {
        let fullmAh = battery.fullChargeCapacitymAh

        let state = chargingState(for: battery)

        let chargePercent = BatteryHealth.chargePercent(
            currentCapacityPercent: battery.currentCapacity,
            maxCapacityPercent: battery.maxCapacity,
            currentmAh: battery.rawCurrentCapacity,
            fullChargemAh: fullmAh
        )

        return BatterySnapshot(
            timestamp: now,
            designCapacitymAh: battery.designCapacity,
            fullChargeCapacitymAh: fullmAh,
            healthPercent: BatteryHealth.healthPercent(fullChargemAh: fullmAh, designmAh: battery.designCapacity),
            cycleCount: battery.cycleCount,
            designCycleCount: battery.designCycleCount,
            currentChargePercent: chargePercent,
            currentChargemAh: battery.rawCurrentCapacity,
            chargingState: state,
            // iDevices report only the unified `TimeRemaining`, so fall back to it
            // when the Mac-style AvgTimeToFull / AvgTimeToEmpty is absent.
            timeToFullMinutes: state == .charging
                ? (BatteryHealth.minutesOrNil(battery.timeToFullMinutes) ?? BatteryHealth.minutesOrNil(battery.timeRemainingMinutes))
                : nil,
            timeToEmptyMinutes: state == .discharging
                ? (BatteryHealth.minutesOrNil(battery.timeToEmptyMinutes) ?? BatteryHealth.minutesOrNil(battery.timeRemainingMinutes))
                : nil,
            atCriticalLevel: battery.atCriticalLevel,
            voltageMillivolts: battery.voltage,
            amperageMilliamps: battery.amperage,
            instantAmperageMilliamps: battery.instantAmperage,
            powerWatts: powerWatts(for: battery, state: state, smcDischargeWatts: smcDischargeWatts),
            temperatureCelsius: BatteryHealth.celsiusOrNil(fromCentiCelsius: battery.temperature),
            adapter: battery.adapter,
            deviceModel: deviceModel,
            batterySerial: battery.serial.isEmpty ? nil : battery.serial,
            manufactureMonth: BatteryManufactureMonth.decode(
                raw: battery.packDetail?.manufactureRaw,
                gaugeName: battery.deviceName,
                now: now
            )
        )
    }

    static func chargingState(for battery: AppleSmartBattery) -> ChargingState {
        // FullyCharged describes the battery, not the cable: it stays set
        // for a while after unplugging a full pack, so the cable check must
        // come first or an unplugged Mac at 100% reads as still on power.
        if !battery.externalConnected { return .discharging }
        if battery.fullyCharged { return .full }
        if battery.isCharging { return .charging }
        return .acNoCharge
    }

    /// Signed power: positive charging, negative discharging, zero when full or
    /// holding on AC. Both directions are computed from the pack's own voltage
    /// and current; discharge prefers the SMC's live battery rail (PPBR) because
    /// the fuel gauge's own power figure sits stale on Apple Silicon.
    ///
    /// Charging used to multiply `ChargerData.ChargingVoltage` by
    /// `ChargingCurrent`, which understated charge power by the cell count:
    /// **`ChargingVoltage` is a per-cell figure on Apple Silicon**, around 4.05 V
    /// on a pack sitting at 12.0 V. A 65 W charge read as 23 W before this.
    ///
    /// The field cannot be rescued by multiplying by the cell count, because its
    /// scale is not universal. Across the 816 probe-corpus machines carrying
    /// `ChargerData`, pack voltage divided by `ChargingVoltage` is:
    ///
    /// - Apple Silicon, 3 cells (738 machines): median 2.96, so per-cell.
    /// - Intel, 3 cells (69 machines): median 0.97, so pack-level.
    ///
    /// `Voltage` and `Amperage` are pack-level on both, so they are what we use.
    ///
    /// Sanity anchor, on the 224 Apple Silicon Macs in the corpus that were
    /// charging with an adapter wattage on the label (the `Watts` inside the
    /// live `AdapterDetails` dict, not the `AppleRawAdapterDetails` log, which
    /// is a different number): this figure is a median 49% of the rating and
    /// tops out at 87%, never above. The old formula sat at a median 20% and
    /// came out above the adapter's rating outright on 10 of the 187 machines
    /// carrying `ChargerData`, peaking at 421%, so it was not even reliably low.
    static func powerWatts(for battery: AppleSmartBattery, state: ChargingState, smcDischargeWatts: Double?) -> Double {
        let gaugeMagnitude = abs(Double(battery.voltage) / 1000 * Double(battery.amperage) / 1000)
        switch state {
        case .charging:
            // The gauge's state and its current can disagree for a moment: the
            // corpus holds machines reporting IsCharging with the current still
            // flowing out. `abs()` would turn that into confident charge power
            // and, worse, into a lifetime peak that never washes out. A reading
            // that contradicts itself is not a measurement.
            guard battery.amperage > 0, isPlausibleCurrent(battery.amperage) else { return 0 }
            return gaugeMagnitude
        case .discharging:
            // The SMC rail is measured independently of the gauge, so it wins
            // when it is there.
            if let smcDischargeWatts { return -smcDischargeWatts }
            // Same guard as charging, mirrored. The contradiction happens in
            // this direction too: 3 of 179 discharging machines in the corpus
            // report a positive current. Without the sign check, one of them
            // computes a confident -42.9 W the moment the SMC read is
            // unavailable (a refused AppleSMC open, a missing PPBR key, a value
            // outside the reader's sanity band), and that lands in
            // `LifetimeSummary.maxDischargeW`, which only ever takes a maximum.
            guard battery.amperage < 0, isPlausibleCurrent(battery.amperage) else { return 0 }
            return -gaugeMagnitude
        case .full, .acNoCharge:
            return 0
        }
    }

    /// A ceiling on the pack current we will turn into watts.
    ///
    /// Not observed in the wild: across the 1105 corpus machines reporting
    /// `Amperage`, every value is either already signed or inside a sane range,
    /// and none sits in the 16-bit or 64-bit unsigned wrap ranges that other
    /// fields on this node do use (`BatteryPower` and `MaximumDischargeCurrent`
    /// both arrive wrapped). The guard is here because the failure is silent and
    /// permanent rather than because it has happened: a wrapped -2000 mA read as
    /// 63536 would price a 12 V pack at 762 W, and that single sample would
    /// become the lifetime and session peak with nothing to wash it out.
    ///
    /// The biggest real figures in the corpus are a 7716 mA charge and a 5089 mA
    /// draw, so 25 A clears reality by 3.2x: comfortably above any pack while
    /// still an order of magnitude below what a wrap produces.
    static func isPlausibleCurrent(_ milliamps: Int) -> Bool {
        // .magnitude, not abs(): abs(Int.min) traps, and a value that malformed
        // is exactly what this guard exists to reject rather than crash on.
        milliamps.magnitude <= 25_000
    }
}
