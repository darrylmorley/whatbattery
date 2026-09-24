import Foundation

/// One `AppleSmartBatteryBank` under the battery pack: its `BankID` and its
/// `BatteryData`. A bank whose `BankID` could not be read carries -1.
public struct BatteryBankData {
    public let bankID: Int
    public let batteryData: [String: Any]

    public init(bankID: Int, batteryData: [String: Any]) {
        self.bankID = bankID
        self.batteryData = batteryData
    }
}

/// macOS 27 moved most of the gauge's figures off `AppleSmartBattery` onto its
/// registry children: `AppleSmartBatteryPack` carries the pack-level
/// `BatteryData` (raw capacities, temperatures, manufacture date, lifetime),
/// and each `AppleSmartBatteryBank` carries one series cell group's voltage,
/// Qmax and resistance as single values. This folds them back into the shape
/// the rest of the app already reads. Whatever the battery node itself still
/// carries always wins, so a Mac on an older OS, which has no such children,
/// reads exactly as before.
public enum BatteryChildNodes {
    /// Per-cell keys that used to be arrays on the node and are now one value per bank.
    static let perBankArrayKeys = ["CellVoltage", "Qmax", "WeightedRa"]

    public static func mergedBatteryData(
        node: [String: Any]?,
        pack: [String: Any]?,
        banks: [BatteryBankData],
        expectedBankCount: Int? = nil
    ) -> [String: Any]? {
        var merged = pack ?? [:]
        for (key, value) in node ?? [:] {
            merged[key] = value
        }

        // The arrays are read positionally (cell 2's voltage beside cell 2's
        // capacity), so an unreadable or repeated BankID would misorder every
        // cell after it. Better no array than a wrongly labelled one. A gap in
        // the IDs means a bank was not read, which would shift the cells after it
        // just the same. The pack's own BankCount catches a missing last bank,
        // which contiguity alone cannot.
        let ids = banks.map(\.bankID)
        let banksUsable = !banks.isEmpty
            && ids.sorted() == Array(0..<ids.count)
            && (expectedBankCount == nil || expectedBankCount == ids.count)
        if banksUsable {
            let ordered = banks.sorted { $0.bankID < $1.bankID }
            for key in perBankArrayKeys where !(merged[key] is [Any]) {
                let values = ordered.compactMap { $0.batteryData[key] as? NSNumber }
                if values.count == ordered.count {
                    merged[key] = values
                }
            }
        }
        return merged.isEmpty ? nil : merged
    }

    /// The node's own readings win: its `Temperature` is deci-Kelvin on a Mac
    /// and keeps that conversion. On macOS 27 the node has neither key, so the
    /// pack's `VirtualTemperature` (centi-Celsius on every platform) is used,
    /// and the pack's `Temperature` only as a last resort. That last one is
    /// taken as centi-Celsius, never deci-Kelvin: on the one Mac measured it
    /// equalled `VirtualTemperature` exactly, and as deci-Kelvin it would read
    /// about -3 C on a battery sitting at room temperature.
    public static func temperatures(
        nodeTemperatureRaw: Int?,
        nodeVirtualRaw: Int?,
        pack: [String: Any]?
    ) -> (temperatureCentiC: Int?, virtualCentiC: Int?) {
        func plausible(_ value: Int?) -> Int? {
            value.flatMap { BatteryHealth.isPlausibleCentiCelsius($0) ? $0 : nil }
        }
        func packValue(_ key: String) -> Int? {
            (pack?[key] as? NSNumber)?.intValue
        }
        let virtual = plausible(nodeVirtualRaw) ?? plausible(packValue("VirtualTemperature"))
        let temperature = nodeTemperatureRaw.flatMap { BatteryHealth.centiCelsius(fromDeciKelvin: $0) }
            ?? virtual
            ?? plausible(packValue("Temperature"))
        return (temperature, virtual)
    }
}
