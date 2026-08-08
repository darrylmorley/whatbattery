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
    public let temperatureCelsius: Double

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
        temperatureCelsius: Double,
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
        try container.encode(temperatureCelsius, forKey: .temperatureCelsius)
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
            temperatureCelsius: try container.decode(Double.self, forKey: .temperatureCelsius),
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
            temperatureCelsius: BatteryHealth.celsius(fromCentiCelsius: battery.temperature),
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
        if battery.fullyCharged { return .full }
        if battery.isCharging { return .charging }
        if battery.externalConnected { return .acNoCharge }
        return .discharging
    }

    /// Signed power: positive charging, negative discharging, zero when full or
    /// holding on AC. Charging power prefers the charger's negotiated V*A;
    /// discharge power prefers the SMC's live battery rail (PPBR) because the
    /// fuel gauge's own figure sits stale on Apple Silicon.
    static func powerWatts(for battery: AppleSmartBattery, state: ChargingState, smcDischargeWatts: Double?) -> Double {
        let gaugeMagnitude = abs(Double(battery.voltage) / 1000 * Double(battery.amperage) / 1000)
        switch state {
        case .charging:
            if let charger = battery.chargerData, charger.chargingVoltageMV > 0, charger.chargingCurrentMA > 0 {
                return Double(charger.chargingVoltageMV) / 1000 * Double(charger.chargingCurrentMA) / 1000
            }
            return gaugeMagnitude
        case .discharging:
            return -(smcDischargeWatts ?? gaugeMagnitude)
        case .full, .acNoCharge:
            return 0
        }
    }
}
