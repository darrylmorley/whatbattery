import Foundation

/// Maps a parsed `AppleSmartBattery` property dictionary into the Core model.
///
/// The Mac reader (`AppleSmartBatteryReader`) reads IORegistry keys one at a time
/// to dodge a kernel teardown crash, so it does its own mapping. An iPhone/iPad
/// read arrives instead as a full JSON dictionary over the lockdown diagnostics
/// relay, with the *same* `AppleSmartBattery` keys. This mapper turns that
/// dictionary into the model, so the iDevice path reuses all the existing health
/// math and snapshot building. Pure (Foundation only), so it is unit-testable
/// with a fixture dictionary.
public enum AppleSmartBatteryMapper {
    /// Build the model from an `AppleSmartBattery` properties dictionary. Returns
    /// nil if the dictionary clearly is not a battery node (no capacity at all).
    public static func from(dictionary d: [String: Any]) -> AppleSmartBattery? {
        let design = intVal(d["DesignCapacity"])
        let rawMax = intVal(d["AppleRawMaxCapacity"])
        let nominal = intVal(d["NominalChargeCapacity"])
        // A real battery node always reports a design capacity. Bail otherwise so
        // a stray dictionary does not become a bogus zero-capacity battery.
        guard design > 0 || rawMax > 0 || nominal > 0 else { return nil }

        return AppleSmartBattery(
            batteryInstalled: true,
            deviceName: stringVal(d["DeviceName"]) ?? "",
            serial: stringVal(d["Serial"]) ?? "",
            designCapacity: design,
            nominalChargeCapacity: nominal,
            rawMaxCapacity: rawMax,
            rawCurrentCapacity: intVal(d["AppleRawCurrentCapacity"]),
            currentCapacity: intVal(d["CurrentCapacity"]),
            maxCapacity: intVal(d["MaxCapacity"]),
            designCycleCount: intVal(d["DesignCycleCount9C"]),
            cycleCount: intVal(d["CycleCount"]),
            voltage: intVal(d["Voltage"]) > 0 ? intVal(d["Voltage"]) : intVal(d["AppleRawBatteryVoltage"]),
            amperage: intVal(d["Amperage"]),
            instantAmperage: intVal(d["InstantAmperage"]),
            temperature: intVal(d["Temperature"]),
            virtualTemperature: intVal(d["VirtualTemperature"]),
            isCharging: boolVal(d["IsCharging"]),
            fullyCharged: boolVal(d["FullyCharged"]),
            externalConnected: boolVal(d["ExternalConnected"]) || boolVal(d["AppleRawExternalConnected"]),
            atCriticalLevel: boolVal(d["AtCriticalLevel"]),
            timeToFullMinutes: intVal(d["AvgTimeToFull"]),
            timeToEmptyMinutes: intVal(d["AvgTimeToEmpty"]),
            timeRemainingMinutes: intVal(d["TimeRemaining"]),
            chargerData: parseChargerData(d["ChargerData"]),
            adapter: parseAdapterDetails(d["AdapterDetails"])
        )
    }

    // MARK: - Sub-parsers

    private static func parseChargerData(_ value: Any?) -> ChargerData? {
        guard let c = value as? [String: Any] else { return nil }
        return ChargerData(
            chargingVoltageMV: intVal(c["ChargingVoltage"]),
            chargingCurrentMA: intVal(c["ChargingCurrent"]),
            notChargingReason: intVal(c["NotChargingReason"])
        )
    }

    private static func parseAdapterDetails(_ value: Any?) -> AdapterInfo? {
        guard let a = value as? [String: Any] else { return nil }
        return AdapterInfo(
            watts: optionalIntVal(a["Watts"]),
            voltageMV: optionalIntVal(a["AdapterVoltage"]),
            currentMA: optionalIntVal(a["Current"]),
            description: stringVal(a["Description"]),
            manufacturer: stringVal(a["Manufacturer"]),
            name: stringVal(a["Name"]),
            model: stringVal(a["Model"]),
            isWireless: (a["IsWireless"] as? NSNumber)?.boolValue
        )
    }

    // MARK: - Helpers

    private static func intVal(_ value: Any?) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        return 0
    }

    private static func optionalIntVal(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        return nil
    }

    private static func boolVal(_ value: Any?) -> Bool {
        if let n = value as? NSNumber { return n.boolValue }
        if let b = value as? Bool { return b }
        return false
    }

    private static func stringVal(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
