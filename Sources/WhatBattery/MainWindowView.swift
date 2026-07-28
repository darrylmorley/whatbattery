import SwiftUI
import WhatBatteryCore
import WhatBatteryAppKit
import WhatBatteryDarwinBackend

/// The main window opened from the menu bar dropdown. Four tabs: "This Mac" (a
/// free live Overview plus the Pro history and charging sections), "iPhone /
/// iPad" (the Pro iDevice battery view), "Accessories" (free live levels plus
/// Pro history), and "History" (long-term per-device health, Pro).
///
/// Deliberately does **not** observe `monitor`. The monitor republishes every 5
/// seconds, and this body builds the Pro sections by calling the registry's
/// `AnyView` builders. SwiftUI cannot see inside an `AnyView` to prove its
/// content is unchanged, so re-running this body made both Lifetime Analyzer
/// charts, the charging cards and the health history re-evaluate on every tick.
/// The live values are read by the small child views below, which observe the
/// monitor themselves and so re-render alone.
struct MainWindowView: View {
    let monitor: BatteryMonitor
    @ObservedObject private var proStatus = PluginRegistry.shared.proStatus
    @ObservedObject private var updates = UpdateChecker.shared
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    @AppStorage(FontScale.key) private var fontScale = FontScale.defaultValue
    @State private var selectedTab: Tab = .mac
    /// Whether to show the battery sections at all. Seeded from the monitor's
    /// first (synchronous) read and latched on, so a transient IOKit miss cannot
    /// collapse the tab into the desktop-Mac message. A Mac does not gain or
    /// lose a battery while running.
    @State private var hasBattery: Bool

    init(monitor: BatteryMonitor) {
        self.monitor = monitor
        _hasBattery = State(initialValue: monitor.hasBattery)
    }

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
        // Covers the one case the seed above cannot: the first IOKit read came
        // back empty on a Mac that does have a battery. `hasBattery` is not
        // published (the whole point is that this view does not observe the
        // monitor), so nothing would re-render on a later success. Polls until
        // it latches or the window closes, rather than giving up after a fixed
        // few tries and stranding the window on "No battery on this Mac". On a
        // real desktop this is one Bool read every five seconds, forever, which
        // is cheaper than the observation it replaces.
        .task {
            while !hasBattery, !Task.isCancelled {
                if monitor.hasBattery { hasBattery = true; break }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - This Mac

    private var macTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let update = updates.available {
                    UpdateBanner(update: update)
                }
                if hasBattery {
                    // The only part of this tab tied to the 5-second refresh.
                    LiveOverviewSection(monitor: monitor, tempUnit: tempUnit, isPro: proStatus.isUnlocked)
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
                // Observes the monitor on its own, for the same reason as the
                // This Mac tab: the Pro section below must not be rebuilt every
                // time an accessory level lands.
                LiveAccessoriesSection(monitor: monitor)
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

// MARK: - Live sections
//
// These exist purely to confine observation of `BatteryMonitor`. Each one
// re-renders when the monitor republishes; their siblings in `MainWindowView`,
// including the expensive Pro subtrees, do not.

private struct LiveOverviewSection: View {
    @ObservedObject var monitor: BatteryMonitor
    let tempUnit: BatteryFormatter.TemperatureUnit
    let isPro: Bool
    /// How long a last-good reading may stand in for a live one. The monitor
    /// refreshes every 5 seconds, so a minute covers a run of transient misses.
    /// Past that the card would be presenting a minutes-old temperature,
    /// wattage and charge as current, with nothing on screen saying otherwise,
    /// so it says it cannot read instead.
    private static let staleAfter: TimeInterval = 60

    var body: some View {
        // The parent only renders this section once a battery has been seen, so
        // going empty on a transient nil would leave a blank gap above an
        // orphaned divider and the Pro sections. The fallback lives on the
        // monitor rather than in `@State` here, so it is already populated when
        // this view is created, including when the window is first opened
        // during a nil.
        if let snapshot = displaySnapshot {
            OverviewCard(snapshot: snapshot, tempUnit: tempUnit, isPro: isPro)
        } else {
            ContentUnavailableView(
                "Battery reading unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("WhatBattery can't read this Mac's battery right now. This usually clears on its own.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    private var displaySnapshot: BatterySnapshot? {
        if let live = monitor.snapshot { return live }
        guard let last = monitor.lastGoodSnapshot else { return nil }
        // `Date` is not monotonic, so a negative age is reachable: move the Mac's
        // clock back and a bare `age < staleAfter` would call an old reading
        // fresh until wall time caught up, potentially for hours. Treating a
        // negative age as stale fails the safe way, and costs nothing, since the
        // next successful read replaces this within five seconds anyway.
        let age = Date().timeIntervalSince(last.timestamp)
        guard age >= 0, age < Self.staleAfter else { return nil }
        return last
    }
}

private struct LiveAccessoriesSection: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        AccessoriesCard(accessories: monitor.accessories)
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
        // The big number, "Battery health", the capacity line and the device
        // name are four separate VoiceOver stops otherwise, read as disconnected
        // fragments. Combined they announce as one sentence.
        .accessibilityElement(children: .combine)
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
        BatteryFormatter.powerLine(snapshot)
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
