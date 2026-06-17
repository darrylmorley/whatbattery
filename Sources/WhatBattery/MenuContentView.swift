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
        // Height is sized to the taller settings pane.
        .frame(width: 340, height: 400)
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

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { showMain() } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back")
                Text("Settings").font(.headline)
                Spacer()
            }
            SettingsView(embedded: true)
            Spacer(minLength: 0)
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
                .tint(healthColor(health))
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

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
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

    private func healthColor(_ health: Double) -> Color {
        switch health {
        case ..<60: return .red
        case ..<80: return .orange
        default: return .green
        }
    }
}
