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
            // Centi-Celsius already on iOS (the driver converts on every platform
            // but macOS), so no deci-Kelvin conversion here. It does still need
            // the plausibility gate the Mac reader gets for free on its way
            // through `centiCelsius(fromDeciKelvin:)`: this is a private,
            // undocumented relay whose keys drift between iOS versions, and an
            // out-of-band value would otherwise reach the display and, worse,
            // become the cross-check that resolves the lifetime scale.
            temperature: plausibleCentiCelsius(d["Temperature"]) ?? 0,
            virtualTemperature: plausibleCentiCelsius(d["VirtualTemperature"]) ?? 0,
            isCharging: boolVal(d["IsCharging"]),
            fullyCharged: boolVal(d["FullyCharged"]),
            externalConnected: boolVal(d["ExternalConnected"]) || boolVal(d["AppleRawExternalConnected"]),
            atCriticalLevel: boolVal(d["AtCriticalLevel"]),
            timeToFullMinutes: intVal(d["AvgTimeToFull"]),
            timeToEmptyMinutes: intVal(d["AvgTimeToEmpty"]),
            timeRemainingMinutes: intVal(d["TimeRemaining"]),
            chargerData: parseChargerData(d["ChargerData"]),
            adapter: parseAdapterDetails(d["AdapterDetails"]),
            // Same blob, same parser as the Mac's IOKit read: an iPhone's relay
            // dictionary carries BatteryData in the identical shape.
            //
            // The temperature is deliberately NOT converted from deci-Kelvin
            // the way the Mac reader converts it: iOS falls under
            // `!TARGET_OS_OSX` in Apple's driver, so the phone's own kernel has
            // already published centi-Celsius (DAR-329).
            //
            // Confirmed on a real iPhone 15 (iOS 26.6) over the relay: it
            // reported Temperature 2809 while charging, which is 28.1°C read as
            // centi-Celsius and an impossible 7.8°C read as deci-Kelvin. Its
            // lifetime extremes came back 86 to 452, deci-degrees, so an iDevice
            // needs the scale resolution as much as an M1 does. Pinned in
            // AppleSmartBatteryMapperTests.
            packDetail: BatteryPackDetail.from(
                batteryData: d["BatteryData"] as? [String: Any],
                // Optional, not intVal: a missing key must arrive as "unknown",
                // not as 0°C. A relay that renames or drops this key between iOS
                // versions would otherwise fail the cross-check against every
                // real range and suppress the row, on exactly the devices that
                // need it, since the iPhone measured here reports its lifetime
                // extremes in deci-degrees.
                currentTemperatureCentiC: plausibleCentiCelsius(d["Temperature"])
            )
        )
    }

    // MARK: - Sub-parsers

    /// A relay temperature in centi-Celsius, or nil when it is absent or outside
    /// the band a battery could actually be at.
    private static func plausibleCentiCelsius(_ value: Any?) -> Int? {
        optionalIntVal(value).flatMap { BatteryHealth.isPlausibleCentiCelsius($0) ? $0 : nil }
    }

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
