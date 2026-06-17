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

    // Live electrical
    public let voltageMillivolts: Int
    public let amperageMilliamps: Int      // signed
    public let powerWatts: Double          // + charging, - discharging, 0 idle/full
    public let temperatureCelsius: Double

    // Adapter
    public let adapter: AdapterInfo?

    // Identity
    public let deviceModel: String
    public let batterySerial: String?
    public let manufactureDate: Date?

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
        voltageMillivolts: Int,
        amperageMilliamps: Int,
        powerWatts: Double,
        temperatureCelsius: Double,
        adapter: AdapterInfo?,
        deviceModel: String,
        batterySerial: String?,
        manufactureDate: Date?
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
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
        self.adapter = adapter
        self.deviceModel = deviceModel
        self.batterySerial = batterySerial
        self.manufactureDate = manufactureDate
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
            voltageMillivolts: battery.voltage,
            amperageMilliamps: battery.amperage,
            powerWatts: powerWatts(for: battery, state: state, smcDischargeWatts: smcDischargeWatts),
            temperatureCelsius: BatteryHealth.celsius(fromCentiCelsius: battery.temperature),
            adapter: battery.adapter,
            deviceModel: deviceModel,
            batterySerial: battery.serial.isEmpty ? nil : battery.serial,
            manufactureDate: nil   // best-effort; not yet parsed (see SPEC, "Manufacture date")
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
