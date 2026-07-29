import Foundation
import WhatBatteryCore
import WhatBatteryDarwinBackend
import WhatBatteryAppKit
import WhatBatteryPlugins

// Drives --version, the summary header and the usage text. AppInfo reads the
// shipped Info.plist (walking up from the nested Contents/Helpers binary), so
// this tracks the release instead of drifting from it as a literal did.
let cliVersion = AppInfo.version

@main
struct WhatBatteryCLI {
    @MainActor
    static func main() async {
        bootstrapPlugins(registry: .shared)

        let provider = DarwinSnapshotProvider()
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") {
            printUsage()
            return
        }
        if args.contains("--version") {
            print(cliVersion)
            return
        }

        rejectUnknownFlags(args)

        // Plugin commands (licence, ...) are program modes, not combinable flags.
        let matching = PluginRegistry.shared.cliCommands.filter { $0.matches(args) }
        if matching.count > 1 {
            errln("whatbattery: more than one command matched. Run one at a time.")
            exit(2)
        }
        if let command = matching.first {
            exit(await command.run(args))
        }

        if args.contains("--idevice") {
            runIDevice(json: args.contains("--json"))
            return
        }

        if args.contains("--accessories") {
            await runAccessories(json: args.contains("--json"))
            return
        }

        if args.contains("--json") {
            guard let snapshot = provider.currentSnapshot() else { exitNoBattery(provider) }
            print(encodeJSON(snapshot))
            return
        }

        if args.contains("--watch") {
            await runWatch(provider)
            return
        }

        guard let snapshot = provider.currentSnapshot() else { exitNoBattery(provider) }
        print(renderSummary(snapshot))
        for footer in PluginRegistry.shared.cliOutputFooterContributors {
            if let line = footer() {
                print("\n" + line)
            }
        }
    }
}

// MARK: - Dispatch helpers

@MainActor
private func rejectUnknownFlags(_ args: [String]) {
    var known: Set<String> = ["--json", "--watch", "--idevice", "--accessories", "--version", "--help", "-h"]
    for command in PluginRegistry.shared.cliCommands {
        known.formUnion(command.flagNames)
    }
    // The argument right after --activate is its value (a key), not a flag.
    var skipNext = false
    for arg in args {
        if skipNext { skipNext = false; continue }
        if arg == "--activate" { skipNext = true; continue }
        if arg.hasPrefix("-"), arg != "--", !known.contains(arg) {
            errln("whatbattery: unknown option \(arg)")
            printUsage()
            exit(2)
        }
    }
}

@MainActor
private func runWatch(_ provider: DarwinSnapshotProvider) async {
    while true {
        guard let snapshot = provider.currentSnapshot() else { exitNoBattery(provider) }
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        print(renderSummary(snapshot))
        print("\nRefreshing every 2s. Ctrl-C to stop.")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
}

// Read a tethered/paired iPhone or iPad's battery over the native
// MobileDevice.framework path; see IDeviceBatteryReader.
private func runIDevice(json: Bool) {
    do {
        let result = try IDeviceBatteryReader.readAll()

        // Notes about present-but-unreadable devices go to stderr in both modes,
        // so --json stdout stays a clean snapshot array.
        for device in result.unreadable {
            errln("Note: \(deviceLabel(device)) is connected but its battery could not be read.")
        }

        if result.readings.isEmpty {
            if result.unreadable.isEmpty {
                errln("No readable iPhone/iPad battery found.")
            }
            exit(2)
        }
        if json {
            print(encodeJSON(result.readings.map { $0.snapshot }))
            return
        }
        for (index, reading) in result.readings.enumerated() {
            if index > 0 { print("") }
            let d = reading.device
            print(deviceLabel(d, connection: d.connectionType))
            print(renderSummary(reading.snapshot))
        }
    } catch {
        errln("whatbattery: \(error)")
        exit(2)
    }
}

/// List Bluetooth accessory battery levels (keyboard, mouse, trackpad, AirPods).
/// Devices that report no level show as "battery unavailable". BLE accessories
/// that only publish battery over GATT are filled from that service, matching
/// the app; without Bluetooth permission the GATT half quietly contributes
/// nothing.
private func runAccessories(json: Bool) async {
    let accessories = AccessoryBLEMerge.merge(
        AccessoryBatteryReader.readAll(),
        bleLevels: await BLEBatteryReader.readLevels()
    )
    if json {
        print(encodeJSON(accessories))
        return
    }
    if accessories.isEmpty {
        print("No Bluetooth accessories connected.")
        return
    }
    for accessory in accessories {
        let level = accessory.isAvailable ? accessory.levelSummary : "battery unavailable"
        print("\(accessory.name): \(level)")
    }
}

/// A display label for a device that copes with missing identity fields (a device
/// that failed to connect reports only a UDID). Marketing name when known, else
/// the device name; the iOS fragment is dropped when the version is unknown.
private func deviceLabel(_ d: IDeviceBatteryReader.DeviceInfo, connection: String? = nil) -> String {
    let model = d.marketingName.isEmpty ? d.name : d.marketingName
    // Show the user's device name too when it adds information beyond the model.
    var head = model
    if !d.marketingName.isEmpty, !d.name.isEmpty, d.name != model {
        head = "\(model) · \(d.name)"
    }
    var suffix: [String] = []
    if !d.productVersion.isEmpty { suffix.append("iOS \(d.productVersion)") }
    if let connection, !connection.isEmpty { suffix.append(connection) }
    return suffix.isEmpty ? head : "\(head) (\(suffix.joined(separator: ", ")))"
}

@MainActor
private func exitNoBattery(_ provider: DarwinSnapshotProvider) -> Never {
    errln("No battery on this Mac (desktop, or AppleSmartBattery unavailable).")
    if let input = provider.systemPowerInput() {
        print("DC-in power: " + BatteryFormatter.dcInPower(watts: input.watts, volts: input.volts, amps: input.amps))
    }
    exit(2)
}

// MARK: - Rendering

private func renderSummary(_ snapshot: BatterySnapshot) -> String {
    var lines: [String] = ["WhatBattery \(cliVersion)\n"]
    lines.append(pad("Model") + snapshot.deviceModel)
    lines.append(pad("Health") + BatteryFormatter.health(snapshot))
    lines.append(pad("Charge") + BatteryFormatter.chargeLine(snapshot))
    lines.append(pad("Cycles") + "\(snapshot.cycleCount)" + (snapshot.designCycleCount > 0 ? " (design \(snapshot.designCycleCount))" : ""))
    lines.append(pad("Temperature") + BatteryFormatter.temperature(snapshot.temperatureCelsius))
    lines.append(pad("Power") + BatteryFormatter.powerLine(snapshot))
    lines.append(pad("Voltage") + BatteryFormatter.voltage(snapshot.voltageMillivolts))
    return lines.joined(separator: "\n")
}

private func pad(_ label: String) -> String {
    label.padding(toLength: 14, withPad: " ", startingAt: 0)
}

private func encodeJSON<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return json
}

@MainActor
private func printUsage() {
    var text = """
    whatbattery \(cliVersion)
    Mac battery health and live power.

    Usage:
      whatbattery            Battery summary
      whatbattery --json     Machine-readable snapshot (JSON)
      whatbattery --watch    Live-updating summary (Ctrl-C to stop)
      whatbattery --idevice  Battery of a tethered/paired iPhone or iPad
      whatbattery --accessories  Bluetooth accessory battery levels
      whatbattery --version  Print version
      whatbattery --help     This help
    """
    let pluginHelp = PluginRegistry.shared.cliCommands
        .map { $0.helpLines }
        .joined(separator: "\n")
    if !pluginHelp.isEmpty {
        text += "\n\n    Pro:\n" + pluginHelp
    }
    print(text)
}

private func errln(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
