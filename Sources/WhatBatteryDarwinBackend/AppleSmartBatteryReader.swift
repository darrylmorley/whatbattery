import Foundation
import IOKit
import WhatBatteryCore

/// Reads the IOKit `AppleSmartBattery` service into the Core model. Desktop Macs
/// have no AppleSmartBattery service, or report `BatteryInstalled = false`.
///
/// Focused copy of WhatCable's reader: only the battery-relevant keys, none of
/// the cable / port-controller parsing.
public enum AppleSmartBatteryReader {
    public struct Result {
        public let isDesktopMac: Bool
        public let battery: AppleSmartBattery?
    }

    public static func read() -> Result {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return Result(isDesktopMac: true, battery: nil)
        }
        defer { IOObjectRelease(iter) }

        let service = IOIteratorNext(iter)
        guard service != 0 else {
            return Result(isDesktopMac: true, battery: nil)
        }
        defer { IOObjectRelease(service) }

        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch can abort the process from inside
        // IOCFUnserializeBinary when the kernel returns a malformed blob during
        // teardown. The per-key call has no such failure path. (WhatCable #181.)
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        guard boolVal(read("BatteryInstalled")) else {
            return Result(isDesktopMac: true, battery: nil)
        }

        let battery = AppleSmartBattery(
            batteryInstalled: true,
            deviceName: (read("DeviceName") as? String) ?? "",
            serial: (read("Serial") as? String) ?? "",
            designCapacity: intVal(read("DesignCapacity")),
            nominalChargeCapacity: intVal(read("NominalChargeCapacity")),
            rawMaxCapacity: intVal(read("AppleRawMaxCapacity")),
            rawCurrentCapacity: intVal(read("AppleRawCurrentCapacity")),
            currentCapacity: intVal(read("CurrentCapacity")),
            maxCapacity: intVal(read("MaxCapacity")),
            designCycleCount: intVal(read("DesignCycleCount9C")),
            cycleCount: intVal(read("CycleCount")),
            voltage: intVal(read("Voltage")),
            amperage: signedIntVal(read("Amperage")),
            instantAmperage: signedIntVal(read("InstantAmperage")),
            temperature: intVal(read("Temperature")),
            virtualTemperature: intVal(read("VirtualTemperature")),
            isCharging: boolVal(read("IsCharging")),
            fullyCharged: boolVal(read("FullyCharged")),
            externalConnected: boolVal(read("ExternalConnected")),
            atCriticalLevel: boolVal(read("AtCriticalLevel")),
            timeToFullMinutes: intVal(read("AvgTimeToFull")),
            timeToEmptyMinutes: intVal(read("AvgTimeToEmpty")),
            chargerData: parseChargerData(read("ChargerData")),
            adapter: parseAdapterDetails(read("AdapterDetails"))
        )
        return Result(isDesktopMac: false, battery: battery)
    }

    // MARK: - Sub-parsers

    private static func parseChargerData(_ value: Any?) -> ChargerData? {
        guard let d = value as? [String: Any] else { return nil }
        return ChargerData(
            chargingVoltageMV: intVal(d["ChargingVoltage"]),
            chargingCurrentMA: intVal(d["ChargingCurrent"]),
            notChargingReason: intVal(d["NotChargingReason"])
        )
    }

    private static func parseAdapterDetails(_ value: Any?) -> AdapterInfo? {
        guard let d = value as? [String: Any] else { return nil }
        return AdapterInfo(
            watts: (d["Watts"] as? NSNumber)?.intValue,
            voltageMV: (d["AdapterVoltage"] as? NSNumber)?.intValue,
            currentMA: (d["Current"] as? NSNumber)?.intValue,
            description: nonEmptyString(d["Description"]),
            manufacturer: nonEmptyString(d["Manufacturer"]),
            name: nonEmptyString(d["Name"]),
            model: nonEmptyString(d["Model"]),
            isWireless: (d["IsWireless"] as? NSNumber)?.boolValue
        )
    }

    // MARK: - Helpers

    private static func nonEmptyString(_ value: Any?) -> String? {
        let raw: String?
        if let s = value as? String {
            raw = s
        } else if let n = value as? NSNumber {
            raw = n.stringValue
        } else {
            raw = nil
        }
        guard let s = raw else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Unsigned-style read (most keys). Negative values from a signed gauge are
    /// not expected here.
    private static func intVal(_ value: Any?) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        return 0
    }

    /// Amperage can be reported as a signed value packed into an unsigned 16-bit
    /// field on some gauges. `NSNumber.intValue` already handles the common
    /// signed case; this is a named alias to document intent at the call site.
    private static func signedIntVal(_ value: Any?) -> Int {
        intVal(value)
    }

    private static func boolVal(_ value: Any?) -> Bool {
        if let n = value as? NSNumber { return n.boolValue }
        if let b = value as? Bool { return b }
        return false
    }
}
