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

        // Read once, convert once, and keep the "absent" case distinct from a
        // real zero: the pack-detail cross-check needs to know the difference,
        // while the model's own field is non-optional and takes 0 for missing as
        // it always has.
        //
        // `Temperature` is tenths of a Kelvin here, not centi-Celsius: macOS
        // publishes the raw SmartBattery value. Converting at the edge
        // means `AppleSmartBattery.temperature` means the same thing whichever
        // reader filled it, which is what the rest of the app assumes.
        // `VirtualTemperature` is the same measurement compensated by the gauge,
        // and the driver publishes it in centi-Celsius on every platform, so it
        // is a usable stand-in when the main reading is missing or nonsense. On
        // this hardware the two agree to a fraction of a degree. Without it, an
        // unusable reading became a confident 0°C downstream, which then reached
        // the display, the history statistics and the report.
        let virtualCentiC = optionalIntVal(read("VirtualTemperature"))
            .flatMap { BatteryHealth.isPlausibleCentiCelsius($0) ? $0 : nil }
        let temperatureCentiC = optionalIntVal(read("Temperature"))
            .flatMap { BatteryHealth.centiCelsius(fromDeciKelvin: $0) }
            ?? virtualCentiC

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
            temperature: temperatureCentiC ?? 0,
            // The validated value, not a second raw read: the gauge's 65535
            // sentinel would otherwise clear the `> 0` display gate and show the
            // pack at 655.4°C.
            virtualTemperature: virtualCentiC ?? 0,
            isCharging: boolVal(read("IsCharging")),
            fullyCharged: boolVal(read("FullyCharged")),
            externalConnected: boolVal(read("ExternalConnected")),
            atCriticalLevel: boolVal(read("AtCriticalLevel")),
            timeToFullMinutes: intVal(read("AvgTimeToFull")),
            timeToEmptyMinutes: intVal(read("AvgTimeToEmpty")),
            chargerData: parseChargerData(read("ChargerData")),
            adapter: parseAdapterDetails(read("AdapterDetails")),
            packDetail: BatteryPackDetail.from(
                batteryData: read("BatteryData") as? [String: Any],
                // The node's own thermometer, in a scale we know, so the pack's
                // undeclared lifetime temperatures can be checked against it.
                // Absent stays absent: 0 would read as 0°C and veto every real
                // range, which is the opposite of degrading gracefully.
                currentTemperatureCentiC: temperatureCentiC
            )
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
    /// Nil when the key is absent or not a number, so a caller that cares about
    /// the difference between "missing" and "zero" can tell them apart.
    private static func optionalIntVal(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        return nil
    }

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
