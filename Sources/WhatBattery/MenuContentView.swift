import SwiftUI
import AppKit
import WhatBatteryCore
import WhatBatteryAppKit

/// The dropdown shown when the menu bar icon is clicked.
struct MenuContentView: View {
    @ObservedObject var monitor: BatteryMonitor
    /// Height available on the display the popover will actually appear on,
    /// passed in by the delegate from the status item's own window. Cannot be
    /// derived here: `NSScreen.main` is the focused display, which on a
    /// multi-monitor Mac is often not the one holding the menu bar item, so
    /// deriving it locally could size the popover for a taller screen than the
    /// one it opens on. Nil falls back to `NSScreen.main`.
    var availableHeight: CGFloat?
    @ObservedObject private var proStatus = PluginRegistry.shared.proStatus
    @ObservedObject private var updates = UpdateChecker.shared
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    @AppStorage(FontScale.key) private var fontScale = FontScale.defaultValue
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
        .frame(width: popoverWidth, height: popoverHeight)
        .environment(\.fontScale, FontScale.clamp(fontScale))
    }

    /// Sized to the main pane: tight on the battery section when no accessories
    /// are connected, growing a row at a time as they are, and capped so a long
    /// list scrolls instead of running off-screen. The Settings form fits itself
    /// to whatever height this gives (see `settingsPane`).
    private static let popoverMaxHeight: CGFloat = 560
    private static let popoverBaseWidth: CGFloat = 340
    private static let batteryPaneHeight: CGFloat = 330

    /// Every popover dimension is measured at 100% text and multiplied by the
    /// user's font scale. The frame used to be fixed while the slider went to
    /// 140%, so large-text users got clipped content and truncated values in a
    /// popover that never grew to hold them.
    private var scale: CGFloat { CGFloat(FontScale.clamp(fontScale)) }

    private var popoverWidth: CGFloat { Self.popoverBaseWidth * scale }

    private var popoverHeight: CGFloat {
        let accessories = monitor.accessories.isEmpty
            ? 0
            : 26 + CGFloat(monitor.accessories.count) * 24
        let wanted = min(Self.popoverMaxHeight, Self.batteryPaneHeight + accessories) * scale
        // The 560 cap is measured at 100% text, so scaling it lets a full
        // accessory list at 140% ask for 784pt, which overflows a short display.
        // The screen gets the final say. Losing height is safe rather than
        // clipping: the accessory list is the only flexible row in `mainPane`,
        // so a shorter frame shrinks its ScrollView and the battery header and
        // footer stay put.
        guard let visible = availableHeight ?? NSScreen.main?.visibleFrame.height else { return wanted }
        // No floor above the ceiling: an earlier `max(batteryPaneHeight, ...)`
        // here re-created the very overflow it was guarding against, since 330
        // is unscaled and beats `visible - 24` on any display shorter than
        // 354pt. The screen bound always wins; `max(0,)` only stops a negative.
        return min(wanted, max(0, visible - 24))
    }

    // MARK: - Panes

    private var mainPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WhatBattery")
                .scaledFont(.headline)

            // Same freshness-bounded fallback as the window's overview, and the
            // desktop branch gates on the latched hasBattery, not on a nil
            // snapshot: the DC-in SMC keys exist on laptops too, so a transient
            // read miss at launch could otherwise show "No battery" with a
            // perfectly real DC-in line under it.
            if let snapshot = monitor.displaySnapshot {
                header(snapshot)
                Divider()
                details(snapshot)
            } else if monitor.hasBattery {
                Text("Battery reading unavailable right now")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                Text("No battery on this Mac")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                // Desktop: the DC-in rail is still worth a line, matching the
                // CLI's no-battery fallback.
                if let power = monitor.systemPower {
                    Text("DC-in: " + BatteryFormatter.dcInPower(watts: power.watts, volts: power.volts, amps: power.amps))
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if monitor.accessories.isEmpty {
                Spacer(minLength: 0)
            } else {
                Divider()
                Text("Accessories")
                    .scaledFont(.caption)
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
                Text("Settings").scaledFont(.headline)
                Spacer()
            }
            // Fit the form to the popover height (which the accessory list sizes),
            // so the grouped form scrolls internally instead of clipping. The 64
            // is the header row plus padding above, which scales with the text.
            SettingsView(embedded: true, embeddedHeight: max(0, popoverHeight - 64 * scale))
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
                .scaledFont(size: 34, weight: .semibold, design: .rounded)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 1) {
                Text("Battery health")
                    .foregroundStyle(.secondary)
                // Capacity detail is Pro; the free dropdown shows the percentage.
                if proStatus.isUnlocked, snapshot.fullChargeCapacitymAh > 0, snapshot.designCapacitymAh > 0 {
                    Text("\(BatteryFormatter.milliampHours(snapshot.fullChargeCapacitymAh)) of \(BatteryFormatter.milliampHours(snapshot.designCapacitymAh))")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }

        if let health = snapshot.healthPercent {
            HealthBar(percent: health)
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
                .scaledFont(.callout)
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
            if let update = updates.available {
                // An update is available: nudge to the main window, where the
                // banner hosts the install flow (the popover is transient and
                // would dismiss mid-install).
                Button("Update to v\(update.version)") {
                    MenuActions.shared.openMainWindow()
                }
                .buttonStyle(.borderless)
                .scaledFont(.caption)
                .help("Open WhatBattery to install the update")
            } else {
                // Clickable version, opens the GitHub release notes for this build.
                Link("v\(Self.appVersion)", destination: Self.releaseURL)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .help("Release notes on GitHub")
            }
        }
        .padding(.top, 2)
    }

    /// The app version from the bundle, falling back to a dev string.
    static var appVersion: String { AppInfo.version }

    /// The GitHub release page for this version. A pre-release/dev build has no
    /// tag, so this links to the releases list instead.
    static var releaseURL: URL { AppInfo.releaseURL }

    // The `help` string is both the tooltip and the VoiceOver label: the button
    // stays visually icon-only via `.labelStyle(.iconOnly)` while keeping a real
    // text label for assistive tech.
    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(help, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .scaledFont(size: 15)
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
        .scaledFont(.callout)
    }

    // MARK: - Formatting

    private func powerText(_ snapshot: BatterySnapshot) -> String {
        BatteryFormatter.powerLine(snapshot)
    }

}
