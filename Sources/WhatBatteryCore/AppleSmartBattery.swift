import Foundation

/// Battery-relevant subset of the IOKit `AppleSmartBattery` service.
///
/// This is a focused copy of WhatCable's larger model: the cable / port-
/// controller fields (PortControllerInfo, FederatedIdentity, full power
/// telemetry) are dropped because WhatBattery does not need them. Laptops only;
/// desktops have no AppleSmartBattery service.
///
/// Capacity units are not consistent across Apple Silicon and Intel, which is
/// the classic battery-health trap:
/// - On Apple Silicon, `currentCapacity` / `maxCapacity` are *percentages*
///   (maxCapacity is usually pinned at 100). The real mAh figures live in
///   `rawCurrentCapacity` (AppleRawCurrentCapacity), `rawMaxCapacity`
///   (AppleRawMaxCapacity), and `nominalChargeCapacity` (NominalChargeCapacity).
/// - Health must be computed from the mAh fields, never from `maxCapacity`.
public struct AppleSmartBattery: Equatable, Sendable {
    // Identity
    public let batteryInstalled: Bool
    public let deviceName: String
    public let serial: String

    // Capacity (see unit note above)
    public let designCapacity: Int          // mAh
    public let nominalChargeCapacity: Int   // mAh, full-charge on Apple Silicon
    public let rawMaxCapacity: Int          // mAh, AppleRawMaxCapacity
    public let rawCurrentCapacity: Int      // mAh, AppleRawCurrentCapacity
    public let currentCapacity: Int         // percent on Apple Silicon
    public let maxCapacity: Int             // percent on Apple Silicon (usually 100)

    // Cycles
    public let designCycleCount: Int
    public let cycleCount: Int

    // Live electrical
    public let voltage: Int                 // mV
    public let amperage: Int                // mA, signed
    public let instantAmperage: Int         // mA, signed
    public let temperature: Int             // centi-degrees Celsius (divide by 100)
    public let virtualTemperature: Int      // centi-degrees Celsius

    // State
    public let isCharging: Bool
    public let fullyCharged: Bool
    public let externalConnected: Bool
    public let atCriticalLevel: Bool

    // Time estimates (minutes; 65535 / 0 means "not computed")
    public let timeToFullMinutes: Int
    public let timeToEmptyMinutes: Int
    // iOS reports a single unified estimate in `TimeRemaining` (time to full while
    // charging, time to empty while discharging) instead of the Mac's separate
    // AvgTimeToFull / AvgTimeToEmpty. The builder uses it as a fallback.
    public let timeRemainingMinutes: Int

    // Sub-structures
    public let chargerData: ChargerData?
    public let adapter: AdapterInfo?

    public init(
        batteryInstalled: Bool = false,
        deviceName: String = "",
        serial: String = "",
        designCapacity: Int = 0,
        nominalChargeCapacity: Int = 0,
        rawMaxCapacity: Int = 0,
        rawCurrentCapacity: Int = 0,
        currentCapacity: Int = 0,
        maxCapacity: Int = 0,
        designCycleCount: Int = 0,
        cycleCount: Int = 0,
        voltage: Int = 0,
        amperage: Int = 0,
        instantAmperage: Int = 0,
        temperature: Int = 0,
        virtualTemperature: Int = 0,
        isCharging: Bool = false,
        fullyCharged: Bool = false,
        externalConnected: Bool = false,
        atCriticalLevel: Bool = false,
        timeToFullMinutes: Int = 0,
        timeToEmptyMinutes: Int = 0,
        timeRemainingMinutes: Int = 0,
        chargerData: ChargerData? = nil,
        adapter: AdapterInfo? = nil
    ) {
        self.batteryInstalled = batteryInstalled
        self.deviceName = deviceName
        self.serial = serial
        self.designCapacity = designCapacity
        self.nominalChargeCapacity = nominalChargeCapacity
        self.rawMaxCapacity = rawMaxCapacity
        self.rawCurrentCapacity = rawCurrentCapacity
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.designCycleCount = designCycleCount
        self.cycleCount = cycleCount
        self.voltage = voltage
        self.amperage = amperage
        self.instantAmperage = instantAmperage
        self.temperature = temperature
        self.virtualTemperature = virtualTemperature
        self.isCharging = isCharging
        self.fullyCharged = fullyCharged
        self.externalConnected = externalConnected
        self.atCriticalLevel = atCriticalLevel
        self.timeToFullMinutes = timeToFullMinutes
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeRemainingMinutes = timeRemainingMinutes
        self.chargerData = chargerData
        self.adapter = adapter
    }

    /// The best available full-charge capacity in mAh. Prefers
    /// `nominalChargeCapacity`, falling back to `rawMaxCapacity`.
    public var fullChargeCapacitymAh: Int {
        nominalChargeCapacity > 0 ? nominalChargeCapacity : rawMaxCapacity
    }

    /// Whether this looks like a real, sane battery reading worth showing.
    ///
    /// We read iPhone/iPad batteries through a private, undocumented Apple
    /// interface whose keys can change between iOS versions. Rather than gate on a
    /// version allow-list (which we cannot enumerate and which would block iOS
    /// versions that work fine), we validate the fields: a real battery always has
    /// a positive design and full-charge capacity, and a health that lands in a
    /// plausible band. Garbage from a changed/missing key fails this and is shown
    /// as "not readable" instead of as bogus numbers. This mirrors how
    /// coconutBattery degrades by field rather than by version.
    public var isPlausible: Bool {
        guard designCapacity > 0, fullChargeCapacitymAh > 0 else { return false }
        let health = Double(fullChargeCapacitymAh) / Double(designCapacity) * 100
        // The floor is a data-error sentinel, not a health threshold: a deeply
        // worn but real battery (even single-digit %) must still pass, so we only
        // reject a near-zero ratio that signals a misread key. The ceiling rejects
        // a full-charge well above design (also a misread, not a battery).
        return health > 1 && health <= 150
    }
}

/// The charger's negotiated voltage / current, from AppleSmartBattery's
/// `ChargerData` key. Used to compute charge power when plugged in.
public struct ChargerData: Equatable, Sendable {
    public let chargingVoltageMV: Int
    public let chargingCurrentMA: Int
    public let notChargingReason: Int

    public init(chargingVoltageMV: Int = 0, chargingCurrentMA: Int = 0, notChargingReason: Int = 0) {
        self.chargingVoltageMV = chargingVoltageMV
        self.chargingCurrentMA = chargingCurrentMA
        self.notChargingReason = notChargingReason
    }
}

/// The connected power adapter, from AppleSmartBattery's `AdapterDetails` key.
/// Codable because it is carried inside `BatterySnapshot`.
public struct AdapterInfo: Equatable, Sendable, Codable {
    public let watts: Int?
    public let voltageMV: Int?
    public let currentMA: Int?
    public let description: String?
    public let manufacturer: String?
    public let name: String?
    public let model: String?
    public let isWireless: Bool?

    public init(
        watts: Int? = nil,
        voltageMV: Int? = nil,
        currentMA: Int? = nil,
        description: String? = nil,
        manufacturer: String? = nil,
        name: String? = nil,
        model: String? = nil,
        isWireless: Bool? = nil
    ) {
        self.watts = watts
        self.voltageMV = voltageMV
        self.currentMA = currentMA
        self.description = description
        self.manufacturer = manufacturer
        self.name = name
        self.model = model
        self.isWireless = isWireless
    }

    /// A short human label, e.g. "96W USB-C Power Adapter" or "70W pd charger".
    public var label: String? {
        var parts: [String] = []
        if let watts { parts.append("\(watts)W") }
        if let name, !name.isEmpty {
            parts.append(name)
        } else if let description, !description.isEmpty {
            parts.append(description)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
