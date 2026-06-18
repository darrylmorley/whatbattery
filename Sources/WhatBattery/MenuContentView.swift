import SwiftUI
import AppKit
import WhatBatteryCore
import WhatBatteryAppKit

/// The dropdown shown when the menu bar icon is clicked.
struct MenuContentView: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject private var proStatus = PluginRegistry.shared.proStatus
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    // Which pane the popover shows. Settings opens here as a pane rather than a
    // separate window. Reset to the main pane whenever the popover closes.
    @State private var pane: Pane = .main

    private enum Pane { case main, settings }

    private var tempUnit: BatteryFormatter.TemperatureUnit {
        temperatureUnit == "F" ? .fahrenheit : .celsius
    }

    var body: some View {
        Group {
            switch pane {
            case .main: mainPane
            case .settings: settingsPane
            }
        }
        .padding(12)
        // One fixed size for both panes so switching to Settings doesn't resize
        // the popover (NSPopover doesn't animate intrinsic SwiftUI size changes).
        // The height grows with the accessory list; Settings absorbs any slack
        // with its Spacer, so the two panes stay the same height.
        .frame(width: 340, height: popoverHeight)
    }

    /// Sized to the main pane: tight on the battery section when no accessories
    /// are connected, growing a row at a time as they are, and capped so a long
    /// list scrolls instead of running off-screen. The Settings form fits itself
    /// to whatever height this gives (see `settingsPane`).
    private static let popoverMaxHeight: CGFloat = 560

    private var popoverHeight: CGFloat {
        let batteryPane: CGFloat = 330
        let accessories = monitor.accessories.isEmpty
            ? 0
            : 26 + CGFloat(monitor.accessories.count) * 24
        return min(Self.popoverMaxHeight, batteryPane + accessories)
    }

    // MARK: - Panes

    private var mainPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WhatBattery")
                .font(.headline)

            if let snapshot = monitor.snapshot {
                header(snapshot)
                Divider()
                details(snapshot)
            } else {
                Text("No battery on this Mac")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            if monitor.accessories.isEmpty {
                Spacer(minLength: 0)
            } else {
                Divider()
                Text("Accessories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Scrolls when the list is long, so the battery header above and
                // the footer below stay put.
                ScrollView {
                    accessoriesList
                }
                .frame(maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button("Back", systemImage: "chevron.left", action: showMain)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Back")
                Text("Settings").font(.headline)
                Spacer()
            }
            // Fit the form to the popover height (which the accessory list sizes),
            // so the grouped form scrolls internally instead of clipping.
            SettingsView(embedded: true, embeddedHeight: popoverHeight - 64)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Navigation

    private func showSettings() {
        // Keep the popover open across outside clicks so licence-key entry isn't
        // lost when the user switches apps to copy the key.
        MenuActions.shared.setPopoverSticky(true)
        pane = .settings
    }

    private func showMain() {
        MenuActions.shared.setPopoverSticky(false)
        pane = .main
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(_ snapshot: BatterySnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(BatteryFormatter.healthPercent(snapshot.healthPercent))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 1) {
                Text("Battery health")
                    .foregroundStyle(.secondary)
                // Capacity detail is Pro; the free dropdown shows the percentage.
                if proStatus.isUnlocked, snapshot.fullChargeCapacitymAh > 0, snapshot.designCapacitymAh > 0 {
                    Text("\(BatteryFormatter.milliampHours(snapshot.fullChargeCapacitymAh)) of \(BatteryFormatter.milliampHours(snapshot.designCapacitymAh))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }

        if let health = snapshot.healthPercent {
            ProgressView(value: min(health, 100), total: 100)
                .tint(Theme.health(health))
                .accessibilityLabel("Battery health")
                .accessibilityValue("\(Int(health.rounded())) percent")
        }
    }

    @ViewBuilder
    private func details(_ snapshot: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Charge", BatteryFormatter.chargeLine(snapshot, includeTimeEstimate: false))
            if let estimate = BatteryFormatter.timeEstimate(snapshot) {
                row(estimate.label, estimate.value)
            }
            row("Cycles", "\(snapshot.cycleCount)")
            row("Temperature", BatteryFormatter.temperature(snapshot.temperatureCelsius, unit: tempUnit))
            row("Power", powerText(snapshot))
            row("Voltage", BatteryFormatter.voltage(snapshot.voltageMillivolts))
        }
    }

    private var accessoriesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(monitor.accessories) { accessory in
                HStack(spacing: 8) {
                    Image(systemName: AccessoryFormatting.symbol(for: accessory.kind))
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(accessory.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if accessory.isAvailable {
                        Text(AccessoryFormatting.levels(accessory))
                            .monospacedDigit()
                    } else {
                        Text("Battery unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        // Plugin-contributed rows (e.g. "Lifetime Analyzer…"). Empty until a
        // plugin registers one.
        ForEach(PluginRegistry.shared.menuItems) { item in
            Button(item.title) { item.action() }
                .buttonStyle(.borderless)
        }
        HStack(spacing: 16) {
            iconButton("macwindow", help: "Open WhatBattery") {
                MenuActions.shared.openMainWindow()
            }
            iconButton("gearshape", help: "Settings") {
                showSettings()
            }
            iconButton("power", help: "Quit WhatBattery") {
                NSApplication.shared.terminate(nil)
            }
            Spacer()
            // Clickable version, opens the GitHub release notes for this build.
            Link("v\(Self.appVersion)", destination: Self.releaseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Release notes on GitHub")
        }
        .padding(.top, 2)
    }

    /// The app version from the bundle, falling back to a dev string.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0-dev"
    }

    /// The GitHub release page for this version. A pre-release/dev build (version
    /// with a "-" suffix) has no tag, so link to the releases list instead.
    static var releaseURL: URL {
        let base = "https://github.com/darrylmorley/whatbattery-app/releases"
        if appVersion.contains("-") {
            return URL(string: base)!
        }
        return URL(string: "\(base)/tag/v\(appVersion)")!
    }

    // The `help` string is both the tooltip and the VoiceOver label: the button
    // stays visually icon-only via `.labelStyle(.iconOnly)` while keeping a real
    // text label for assistive tech.
    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(help, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 15))
            .frame(width: 30, height: 24)
            .contentShape(.rect)
            .buttonStyle(.borderless)
            .help(help)
    }

    // MARK: - Row helper

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    // MARK: - Formatting

    private func powerText(_ snapshot: BatterySnapshot) -> String {
        var text = BatteryFormatter.power(snapshot.powerWatts)
        if let adapter = snapshot.adapter?.label {
            text += "  (\(adapter))"
        }
        return text
    }

}
