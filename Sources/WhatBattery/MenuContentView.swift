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
    // The main pane's own height with nothing stretched, measured from a hidden
    // copy (see `body`). Nil until the first layout.
    @State private var naturalHeight: CGFloat?

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
        // A hidden copy of the main pane at its natural height, with the
        // accessory list unscrolled. Measuring this, rather than estimating row
        // heights, is what stops the popover leaving a blank gap above the
        // footer when a row is absent (no time estimate when full or on AC).
        .background(alignment: .top) {
            mainPaneContent(scrollsAccessories: false)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { naturalHeight = $0 }
        }
        .padding(Self.panePadding)
        // One fixed size for both panes so switching to Settings doesn't resize
        // the popover (NSPopover doesn't animate intrinsic SwiftUI size changes).
        // The height follows the main pane's content; Settings fits itself to it.
        .frame(width: popoverWidth, height: popoverHeight)
        .environment(\.fontScale, FontScale.clamp(fontScale))
    }

    /// Sized to the main pane's measured content, and capped so a long
    /// accessory list scrolls instead of running off-screen. The Settings form
    /// fits itself to whatever height this gives (see `settingsPane`).
    private static let popoverMaxHeight: CGFloat = 560
    private static let popoverBaseWidth: CGFloat = 340
    /// Inset on every side of both panes. The measured height excludes it.
    private static let panePadding: CGFloat = 12
    /// Used only before the first measurement lands.
    private static let fallbackHeight: CGFloat = 330

    /// Every popover dimension is measured at 100% text and multiplied by the
    /// user's font scale. The frame used to be fixed while the slider went to
    /// 140%, so large-text users got clipped content and truncated values in a
    /// popover that never grew to hold them.
    private var scale: CGFloat { CGFloat(FontScale.clamp(fontScale)) }

    private var popoverWidth: CGFloat { Self.popoverBaseWidth * scale }

    private var popoverHeight: CGFloat {
        // `naturalHeight` is measured at the current text size, so only the cap
        // and the fallback need scaling.
        let content = naturalHeight.map { $0 + Self.panePadding * 2 } ?? Self.fallbackHeight * scale
        let wanted = min(Self.popoverMaxHeight * scale, content)
        // The 560 cap is measured at 100% text, so scaling it lets a full
        // accessory list at 140% ask for 784pt, which overflows a short display.
        // The screen gets the final say. Losing height is safe rather than
        // clipping: the accessory list is the only flexible row in `mainPane`,
        // so a shorter frame shrinks its ScrollView and the battery header and
        // footer stay put.
        guard let visible = availableHeight ?? NSScreen.main?.visibleFrame.height else { return wanted }
        // No floor above the ceiling: an earlier `max(330, ...)` here re-created
        // the very overflow it was guarding against, since 330 is unscaled and
        // beats `visible - 24` on any display shorter than 354pt. The screen
        // bound always wins; `max(0,)` only stops a negative.
        return min(wanted, max(0, visible - 24))
    }

    // MARK: - Panes

    private var mainPane: some View {
        mainPaneContent(scrollsAccessories: true)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    /// `scrollsAccessories: false` lays the accessory list out in full, for the
    /// hidden copy that measures the pane's natural height.
    private func mainPaneContent(scrollsAccessories: Bool) -> some View {
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
                if scrollsAccessories {
                    // Scrolls when the list is long, so the battery header above
                    // and the footer below stay put.
                    ScrollView {
                        accessoriesList
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    accessoriesList
                }
            }

            Divider()
            footer
        }
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
        HStack(spacing: 12) {
            iconButton("macwindow", title: "Open", help: "Open WhatBattery") {
                MenuActions.shared.openMainWindow()
            }
            iconButton("gearshape", title: "Settings", help: "Settings") {
                showSettings()
            }
            iconButton("power", title: "Quit", help: "Quit WhatBattery") {
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

    // An icon with a short caption under it. The icons used to stand alone,
    // named only by their tooltips. The caption sits under the icon rather than
    // beside it so the row still fits the "Update to vX" button on the right.
    // `help` is the tooltip and the VoiceOver label, which keeps the longer name.
    private func iconButton(_ symbol: String, title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .scaledFont(size: 15)
                    .frame(height: 18)
                Text(title)
                    .scaledFont(.caption2)
            }
            .frame(minWidth: 36)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
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
