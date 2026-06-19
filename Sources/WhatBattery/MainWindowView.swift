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
    @ObservedObject private var updates = UpdateChecker.shared
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    @AppStorage(FontScale.key) private var fontScale = FontScale.defaultValue
    @State private var selectedTab: Tab = .mac

    private enum Tab: Hashable { case mac, iDevice, accessories, history }

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
            accessoriesTab
                .tabItem { Label("Accessories", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.accessories)
            historyTab
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .frame(minWidth: 600, minHeight: 440)
        .environment(\.fontScale, FontScale.clamp(fontScale))
        .navigationTitle("WhatBattery")
        // Start the Bluetooth watcher (and the one-time permission prompt) only
        // when the user actually opens the Accessories tab.
        .onChange(of: selectedTab) { _, tab in
            if tab == .accessories { monitor.startAccessoryWatchingIfNeeded() }
        }
    }

    // MARK: - This Mac

    private var macTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let update = updates.available {
                    UpdateBanner(update: update)
                }
                if let snapshot = monitor.snapshot {
                    OverviewCard(snapshot: snapshot, tempUnit: tempUnit, isPro: proStatus.isUnlocked)
                    Divider()
                    historySection
                    chargingSection
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
            UpsellCard(
                title: "WhatBattery Pro",
                systemImage: "lock.fill",
                message: "Unlock lifetime history and the Battery Lifetime Analyzer, threshold notifications, and data export."
            )
        }
    }

    @ViewBuilder
    private var chargingSection: some View {
        // The charging-session view is Pro and lives in the plugins module, so the
        // builder is nil in the free build. The history section above already
        // carries the Pro upsell when locked, so this is simply absent then.
        if proStatus.isUnlocked, let build = PluginRegistry.shared.chargingSectionBuilder {
            Divider()
            build()
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

    // MARK: - Accessories (free: live levels)

    private var accessoriesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AccessoriesCard(accessories: monitor.accessories)
                Divider()
                accessoriesProSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var accessoriesProSection: some View {
        // History + low-battery alerts are Pro and live in the plugins module, so
        // the builder is nil in the free build, which shows the upsell instead.
        if proStatus.isUnlocked, let build = PluginRegistry.shared.accessoriesSectionBuilder {
            build()
        } else {
            UpsellCard(
                title: "Accessory history and alerts",
                systemImage: "lock.fill",
                message: "Track each accessory's battery over time and get a low-battery alert before your keyboard, mouse, or AirPods die. A WhatBattery Pro feature."
            )
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
            UpsellCard(
                title: "Battery Health History",
                systemImage: "lock.fill",
                message: "Track how your battery health and cycles change over months and years, for this Mac and any iPhone or iPad you connect. A WhatBattery Pro feature."
            )
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
            UpsellCard(
                title: "iPhone / iPad battery",
                systemImage: "lock.fill",
                message: "Check the battery health, cycle count, and live charge of a connected iPhone or iPad, right from your Mac. A WhatBattery Pro feature."
            )
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
                    .tint(Theme.health(health))
                    .accessibilityLabel("Battery health")
                    .accessibilityValue("\(Int(health.rounded())) percent")
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
                .scaledFont(size: 48, weight: .bold, design: .rounded)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text("Battery health").foregroundStyle(.secondary)
                // Capacity detail is a Pro touch; the free app shows the health
                // percentage only.
                if isPro, snapshot.fullChargeCapacitymAh > 0, snapshot.designCapacitymAh > 0 {
                    Text("\(BatteryFormatter.milliampHours(snapshot.fullChargeCapacitymAh)) of \(BatteryFormatter.milliampHours(snapshot.designCapacitymAh)) design")
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(deviceTitle).scaledFont(.caption).foregroundStyle(.tertiary)
                if let subtitle = deviceSubtitle {
                    Text(subtitle).scaledFont(.caption).foregroundStyle(.tertiary)
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
        .scaledFont(.callout)
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

// MARK: - Accessories (free)

private struct AccessoriesCard: View {
    let accessories: [Accessory]

    var body: some View {
        if accessories.isEmpty {
            ContentUnavailableView(
                "No accessories connected",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Connect a Bluetooth keyboard, mouse, trackpad, or AirPods to see their battery here. Many third-party devices don't report a level.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Accessories").scaledFont(.headline)
                ForEach(accessories) { accessory in
                    row(accessory)
                    if accessory.id != accessories.last?.id { Divider() }
                }
                Text("Accessories report a charge level only, not health or cycles. Levels refresh every couple of minutes.")
                    .scaledFont(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func row(_ accessory: Accessory) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: AccessoryFormatting.symbol(for: accessory.kind))
                .scaledFont(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessory.name)
                if accessory.isAvailable {
                    Text(AccessoryFormatting.levels(accessory))
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    // Pro: projected time till empty, shown only once the sampler
                    // has enough history. Read the seam inline (nil in the free
                    // build, and gated on the licence) rather than capturing it at
                    // view-init, so it's never a stale snapshot of the registry.
                    if let seconds = PluginRegistry.shared.accessoryEstimateProvider?(accessory.id) {
                        Text(AccessoryFormatting.timeToEmpty(seconds))
                            .scaledFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Battery unavailable")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let lowest = accessory.lowestPercent {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(lowest)%")
                        .scaledFont(.title3).monospacedDigit()
                        .foregroundStyle(Theme.level(lowest))
                    ProgressView(value: Double(lowest), total: 100)
                        .tint(Theme.level(lowest))
                        .frame(width: 80)
                        // The "%" text above already states the level; labelling the
                        // bar too would make VoiceOver announce the number twice.
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
