import Foundation
import WhatBatteryCore

/// The live macOS implementation that ties the battery reader and the SMC
/// together into a `BatterySnapshot`. The seam the app and CLI consume; a future
/// non-Darwin backend would conform to the same `BatterySnapshotProviding`.
///
/// Not `Sendable`: the live implementation holds an open IOKit connection and is
/// meant to be used from one actor (the app's main actor / the CLI's main
/// thread), not shared across threads.
public protocol BatterySnapshotProviding {
    /// The current battery snapshot, or nil when this Mac has no battery
    /// (desktop) so callers can show the desktop power view instead.
    func currentSnapshot() -> BatterySnapshot?
}

public final class DarwinSnapshotProvider: BatterySnapshotProviding {
    private let smc = SMCPowerReader()

    public init() {}

    public func currentSnapshot() -> BatterySnapshot? {
        let result = AppleSmartBatteryReader.read()
        guard let battery = result.battery, battery.batteryInstalled else { return nil }

        // Live discharge watts from the SMC battery rail; nil on AC or when the
        // SMC can't be read (the builder then falls back to the fuel gauge).
        let dischargeWatts = smc.readBatteryPowerMW().map { Double($0) / 1000 }

        return BatterySnapshotBuilder.build(
            battery: battery,
            deviceModel: SystemInfo.hardwareModel(),
            smcDischargeWatts: dischargeWatts,
            now: Date()
        )
    }

    /// Desktop fallback: the Mac's DC-in power, for machines with no battery.
    public func systemPowerInput() -> SMCSystemPowerInput? {
        smc.readSystemPowerInput()
    }
}
