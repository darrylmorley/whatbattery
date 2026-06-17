import SwiftUI
import WhatBatteryCore
import WhatBatteryAppKit
import WhatBatteryDarwinBackend

/// The main window opened from the menu bar dropdown. Two tabs, the coconutBattery
/// model: "This Mac" (a free live Overview plus the Pro history section) and
/// "iPhone / iPad" (the Pro iDevice battery view).
struct MainWindowView: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject private var proStatus = PluginRegistry.shared.proStatus
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    @State private var selectedTab: Tab = .mac

    private enum Tab: Hashable { case mac, iDevice, history }

    private var tempUnit: BatteryFormatter.TemperatureUnit {
        temperatureUnit == "F" ? .fahrenheit : .celsius
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            macTab
                .tabItem { Label("This Mac", systemImage: "laptopcomputer") }
                .tag(Tab.mac)
            iDeviceTab
                .tabItem { Label("iPhone / iPad", systemImage: "iphone") }
                .tag(Tab.iDevice)
            historyTab
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .frame(minWidth: 480, minHeight: 440)
        .navigationTitle("WhatBattery")
    }

    // MARK: - This Mac

    private var macTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let snapshot = monitor.snapshot {
                    OverviewCard(snapshot: snapshot, tempUnit: tempUnit, isPro: proStatus.isUnlocked)
                    Divider()
                    historySection
                } else {
                    ContentUnavailableView(
                        "No battery on this Mac",
                        systemImage: "bolt.slash",
                        description: Text("WhatBattery reports laptop battery health. Desktops have no battery.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if proStatus.isUnlocked, let build = PluginRegistry.shared.historySectionBuilder {
            build()
        } else {
            ProUpsellCard()
        }
    }

    // MARK: - iPhone / iPad

    private var iDeviceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iDeviceSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - History

    private var historyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                healthHistorySection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var healthHistorySection: some View {
        // Long-term health history is Pro and lives in the plugins module, so the
        // builder is nil in the free public build. Either gate shows the upsell.
        if proStatus.isUnlocked, let build = PluginRegistry.shared.healthHistorySectionBuilder {
            build()
        } else {
            HealthHistoryUpsellCard()
        }
    }

    @ViewBuilder
    private var iDeviceSection: some View {
        // The iDevice read is Pro and lives in the plugins module, so the builder
        // is nil in the free public build. Either gate (locked, or no builder)
        // shows the upsell. The active flag pauses the view's device poll whenever
        // another tab is frontmost.
        if proStatus.isUnlocked, let build = PluginRegistry.shared.iDeviceSectionBuilder {
            build()
                .environment(\.iDeviceTabActive, selectedTab == .iDevice)
        } else {
            IDeviceUpsellCard()
        }
    }
}

// MARK: - Overview (free)

private struct OverviewCard: View {
    let snapshot: BatterySnapshot
    let tempUnit: BatteryFormatter.TemperatureUnit
    let isPro: Bool
    // Device identity and service condition, read once when the card appears (the
    // detail that used to sit behind a "Battery Info" popover, now inline).
    @State private var identity: MacIdentity?
    @State private var condition: BatteryCondition = .unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let health = snapshot.healthPercent {
                ProgressView(value: min(health, 100), total: 100)
                    .tint(healthColor(health))
            }

            grid
        }
        .task {
            identity = MacIdentity.read()
            // system_profiler blocks briefly, so read condition off the main actor.
            condition = await Task.detached(priority: .userInitiated) {
                BatteryConditionReader.read()
            }.value
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(BatteryFormatter.healthPercent(snapshot.healthPercent))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text("Battery health").foregroundStyle(.secondary)
                // Capacity detail is a Pro touch; the free app shows the health
                // percentage only.
                if isPro, snapshot.fullChargeCapacitymAh > 0, snapshot.designCapacitymAh > 0 {
                    Text("\(BatteryFormatter.milliampHours(snapshot.fullChargeCapacitymAh)) of \(BatteryFormatter.milliampHours(snapshot.designCapacitymAh)) design")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(deviceTitle).font(.caption).foregroundStyle(.tertiary)
                if let subtitle = deviceSubtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            if condition != .unknown {
                GridRow {
                    Text("Condition").foregroundStyle(.secondary).gridColumnAlignment(.leading)
                    Text(condition.label).foregroundStyle(conditionColor)
                }
            }
            row("Charge", BatteryFormatter.chargeLine(snapshot, includeTimeEstimate: false))
            if let estimate = BatteryFormatter.timeEstimate(snapshot) {
                row(estimate.label, estimate.value)
            }
            row("Cycles", "\(snapshot.cycleCount)")
            row("Temperature", BatteryFormatter.temperature(snapshot.temperatureCelsius, unit: tempUnit))
            row("Power", power)
            row("Voltage", BatteryFormatter.voltage(snapshot.voltageMillivolts))
            // Identity extras are a Pro touch, like the capacity line.
            if isPro {
                if let serial = snapshot.batterySerial { row("Battery Serial", serial) }
                if let identity { row("Low Power Mode", identity.lowPowerMode ? "Enabled" : "Disabled") }
            }
        }
        .font(.callout)
    }

    private var deviceTitle: String {
        if let name = identity?.marketingName, !name.isEmpty { return name }
        return snapshot.deviceModel
    }

    /// "Mac17,2 (A3434) · Apple M5", omitting whatever is unavailable.
    private var deviceSubtitle: String? {
        guard let identity else { return nil }
        var parts: [String] = []
        var model = identity.modelIdentifier
        if !identity.modelNumber.isEmpty {
            model += model.isEmpty ? identity.modelNumber : " (\(identity.modelNumber))"
        }
        if !model.isEmpty { parts.append(model) }
        if !identity.chip.isEmpty { parts.append(identity.chip) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var power: String {
        var text = BatteryFormatter.power(snapshot.powerWatts)
        if let adapter = snapshot.adapter?.label { text += "  (\(adapter))" }
        return text
    }

    private var conditionColor: Color {
        switch condition {
        case .normal: return .green
        case .serviceRecommended: return .orange
        case .serviceBattery: return .red
        case .unknown: return .secondary
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value)
        }
    }

    private func healthColor(_ health: Double) -> Color {
        switch health {
        case ..<60: return .red
        case ..<80: return .orange
        default: return .green
        }
    }
}

/// Session-fixed Mac identity, read once from `SystemInfo` + `ProcessInfo`.
private struct MacIdentity {
    let marketingName: String
    let modelIdentifier: String
    let modelNumber: String
    let chip: String
    let lowPowerMode: Bool

    static func read() -> MacIdentity {
        MacIdentity(
            marketingName: SystemInfo.marketingName(),
            modelIdentifier: SystemInfo.hardwareModel(),
            modelNumber: SystemInfo.regulatoryModelNumber(),
            chip: SystemInfo.chip(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

// MARK: - History (locked: upsell)

private struct ProUpsellCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("WhatBattery Pro", systemImage: "lock.fill").font(.headline)
            Text("Unlock lifetime history and the Battery Lifetime Analyzer, threshold notifications, and data export.")
                .foregroundStyle(.secondary)
            Link("Get WhatBattery Pro", destination: URL(string: "https://whatbattery.app/pro")!)
                .font(.callout)
            Text("Already have a key? Add it in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - History (locked: upsell)

private struct HealthHistoryUpsellCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Battery Health History", systemImage: "lock.fill").font(.headline)
            Text("Track how your battery health and cycles change over months and years, for this Mac and any iPhone or iPad you connect. A WhatBattery Pro feature.")
                .foregroundStyle(.secondary)
            Link("Get WhatBattery Pro", destination: URL(string: "https://whatbattery.app/pro")!)
                .font(.callout)
            Text("Already have a key? Add it in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - iDevice (locked: upsell)

private struct IDeviceUpsellCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iPhone / iPad battery", systemImage: "lock.fill").font(.headline)
            Text("Check the battery health, cycle count, and live charge of a connected iPhone or iPad, right from your Mac. A WhatBattery Pro feature.")
                .foregroundStyle(.secondary)
            Link("Get WhatBattery Pro", destination: URL(string: "https://whatbattery.app/pro")!)
                .font(.callout)
            Text("Already have a key? Add it in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
