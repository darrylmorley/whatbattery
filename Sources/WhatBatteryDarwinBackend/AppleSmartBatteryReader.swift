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

        // macOS 27 moved most of the gauge's figures (raw capacities,
        // temperatures, manufacture date, lifetime, per-cell data) off this
        // node onto its registry children. Older OSes have no such children,
        // so the child read comes back empty and everything below reads as
        // before: the node's own values always win in the merge.
        let children = readChildNodes(of: service)
        let batteryData = BatteryChildNodes.mergedBatteryData(
            node: read("BatteryData") as? [String: Any],
            pack: children.pack,
            banks: children.banks,
            expectedBankCount: children.bankCount
        )

        // Read once, convert once, and keep the "absent" case distinct from a
        // real zero: the pack-detail cross-check needs to know the difference,
        // while the model's own field is non-optional and takes 0 for missing as
        // it always has.
        //
        // The node's `Temperature` is tenths of a Kelvin on a Mac, not
        // centi-Celsius: macOS publishes the raw SmartBattery value. Converting
        // at the edge means `AppleSmartBattery.temperature` means the same thing
        // whichever reader filled it. `VirtualTemperature` is centi-Celsius on
        // every platform and stands in when the main reading is missing or
        // nonsense, which is also how macOS 27's pack-level readings arrive.
        let temperatures = BatteryChildNodes.temperatures(
            nodeTemperatureRaw: optionalIntVal(read("Temperature")),
            nodeVirtualRaw: optionalIntVal(read("VirtualTemperature")),
            pack: children.pack
        )
        let virtualCentiC = temperatures.virtualCentiC
        let temperatureCentiC = temperatures.temperatureCentiC

        let battery = AppleSmartBattery(
            batteryInstalled: true,
            deviceName: (read("DeviceName") as? String) ?? "",
            serial: (read("Serial") as? String) ?? "",
            designCapacity: AppleSmartBatteryMapper.capacity(
                topLevel: read("DesignCapacity"), batteryData: batteryData, key: "DesignCapacity"
            ),
            nominalChargeCapacity: AppleSmartBatteryMapper.capacity(
                topLevel: read("NominalChargeCapacity"), batteryData: batteryData, key: "NominalChargeCapacity"
            ),
            rawMaxCapacity: AppleSmartBatteryMapper.capacity(
                topLevel: read("AppleRawMaxCapacity"), batteryData: batteryData, key: "AppleRawMaxCapacity"
            ),
            rawCurrentCapacity: AppleSmartBatteryMapper.capacity(
                topLevel: read("AppleRawCurrentCapacity"), batteryData: batteryData, key: "AppleRawCurrentCapacity"
            ),
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
                batteryData: batteryData,
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

    /// The pack's `BatteryData` and each bank's (`BankID`, `BatteryData`),
    /// read from `AppleSmartBattery`'s IOService-plane children on macOS 27.
    /// Empty on older OSes. Per-key reads, like the node itself (WhatCable #181).
    /// Only the first pack is read: the node reports one (`BatteryPackCount` 1).
    private static func readChildNodes(of service: io_registry_entry_t) -> (pack: [String: Any]?, banks: [BatteryBankData], bankCount: Int?) {
        var pack: [String: Any]?
        var banks: [BatteryBankData] = []
        var bankCount: Int?
        var foundPack = false
        forEachChild(of: service) { child in
            guard !foundPack, IOObjectConformsTo(child, "AppleSmartBatteryPack") != 0 else { return }
            foundPack = true
            pack = property(child, "BatteryData") as? [String: Any]
            bankCount = optionalIntVal(property(child, "BankCount"))
            forEachChild(of: child) { bank in
                guard IOObjectConformsTo(bank, "AppleSmartBatteryBank") != 0 else { return }
                banks.append(BatteryBankData(
                    bankID: optionalIntVal(property(bank, "BankID")) ?? -1,
                    batteryData: (property(bank, "BatteryData") as? [String: Any]) ?? [:]
                ))
            }
        }
        return (pack, banks, bankCount)
    }

    private static func forEachChild(of entry: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var child = IOIteratorNext(iterator)
        while child != 0 {
            body(child)
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
