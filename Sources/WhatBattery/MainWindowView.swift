import SwiftUI
import WhatBatteryCore
import WhatBatteryAppKit
import WhatBatteryDarwinBackend

/// The main window opened from the menu bar dropdown. Seven tabs: "This Mac" (a
/// free live Overview plus the Pro history section), "Apps" (the Pro per-app
/// power monitor, live and historical), "Charging" (the Pro charging sessions
/// and charger verdict), "Sleep" (the Pro sleep/wake analysis: overnight drain,
/// wake reasons, what's holding the Mac awake now), "iPhone / iPad" (the Pro
/// iDevice battery view), "Accessories" (free live levels plus Pro history),
/// and "History" (long-term per-device health, Pro).
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

    private enum Tab: Hashable { case mac, apps, charging, sleep, iDevice, accessories, history }

    private var tempUnit: BatteryFormatter.TemperatureUnit {
        temperatureUnit == "F" ? .fahrenheit : .celsius
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            macTab
                .tabItem { Label("This Mac", systemImage: "laptopcomputer") }
                .tag(Tab.mac)
            appsTab
                .tabItem { Label("Apps", systemImage: "gauge.with.needle") }
                .tag(Tab.apps)
            chargingTab
                .tabItem { Label("Charging", systemImage: "bolt.fill") }
                .tag(Tab.charging)
            sleepTab
                .tabItem { Label("Sleep", systemImage: "moon.zzz.fill") }
                .tag(Tab.sleep)
            iDeviceTab
                .tabItem { Label("iPhone / iPad", systemImage: "iphone") }
                .tag(Tab.iDevice)
            accessoriesTab
                .tabItem { Label("Accessories", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.accessories)
            historyTab
                // "Health", not "History": three tabs show historical data, so
                // the old name said nothing about which history this one holds.
                .tabItem { Label("Health", systemImage: "heart.text.square") }
                .tag(Tab.history)
        }
        // 840 fits seven tab labels; 760 was sized for six, 680 for five, 600
        // for four.
        .frame(minWidth: 840, minHeight: 440)
        .environment(\.fontScale, FontScale.clamp(fontScale))
        .navigationTitle("WhatBattery")
        // Fallback start for the Bluetooth watcher (and its one-time
        // permission prompt): the app delegate already starts it at launch
        // when the permission state allows; this covers everyone else the
        // moment they actually look at accessories.
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
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if let update = updates.available {
                    UpdateBanner(update: update)
                }
                if hasBattery {
                    // The only part of this tab tied to the 5-second refresh.
                    LiveOverviewSection(monitor: monitor, tempUnit: tempUnit, isPro: proStatus.isUnlocked)
                        // Carries the advisory banner, which reads this to pause
                        // its own reload. Without it the flag defaults to true
                        // and the banner keeps querying for a hidden tab.
                        .environment(\.hostTabActive, selectedTab == .mac)
                    // No divider: each section carries its own edge now.
                    historySection
                } else {
                    // Desktop: no health to report, but the SMC DC-in rail is
                    // still live, so show the power view SPEC asks for instead
                    // of a bare empty state (the CLI has done this all along).
                    DesktopPowerSection(monitor: monitor)
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
                // Pauses the charge-habits reload while another tab is
                // frontmost (ChargeHabitsView reads this via hostTabActive;
                // LifetimeAnalyzerView has its own unconditional loop and
                // ignores it, a pre-existing gap).
                .environment(\.hostTabActive, selectedTab == .mac)
        } else {
            UpsellCard(
                title: "WhatBattery Pro",
                systemImage: "lock.fill",
                message: "Unlock lifetime history and the Battery Lifetime Analyzer, threshold notifications, and data export."
            )
        }
    }

    // MARK: - Apps

    private var appsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                appsSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var appsSection: some View {
        // Per-app drain is Pro and lives in the plugins module, so the builder
        // is nil in the free build; as its own tab it carries its own upsell.
        // Deliberately no hasBattery gate: the kernel's energy counters exist
        // on desktops too (inside This Mac this section sat behind the battery
        // gate and desktop Macs never saw it).
        if proStatus.isUnlocked, let build = PluginRegistry.shared.appPowerSectionBuilder {
            build()
                // Pauses the per-app pid walk while another tab is frontmost.
                .environment(\.hostTabActive, selectedTab == .apps)
        } else {
            UpsellCard(
                title: "WhatBattery Pro",
                systemImage: "lock.fill",
                message: "Unlock the per-app power monitor: which apps are working the chip hardest right now, and which used the most energy over the day."
            )
        }
    }

    // MARK: - Charging

    private var chargingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                chargingSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var chargingSection: some View {
        // Inside This Mac this section sat behind the hasBattery gate; as its
        // own tab it must carry the gate itself, or a desktop Mac would be told
        // to "plug in" a battery it does not have.
        if !hasBattery {
            ContentUnavailableView(
                "No battery to charge",
                systemImage: "bolt.slash",
                description: Text("Charging sessions describe a battery filling up. This Mac runs straight from mains power.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if proStatus.isUnlocked, let build = PluginRegistry.shared.chargingSectionBuilder {
            build()
                // Pauses the 5s reload while another tab is frontmost.
                .environment(\.chargingTabActive, selectedTab == .charging)
                // The habits card moved here from This Mac and pauses on the
                // generic host flag, so this tab has to set that one too.
                .environment(\.hostTabActive, selectedTab == .charging)
        } else {
            UpsellCard(
                title: "Charging sessions",
                systemImage: "lock.fill",
                message: "See each charge as a session: peak and sustained wattage, a verdict on whether your charger keeps up with your Mac, and a comparison across the chargers you use. A WhatBattery Pro feature."
            )
        }
    }

    // MARK: - Sleep

    private var sleepTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                sleepSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var sleepSection: some View {
        // Sleep/wake analysis is Pro and lives in the plugins module, so the
        // builder is nil in the free public build. Deliberately no hasBattery
        // gate here (unlike Charging): a desktop Mac still sleeps and wakes, it
        // just has no drain figure to report, which the Sleep view already
        // handles by omitting the figure rather than showing a fake one.
        if proStatus.isUnlocked, let build = PluginRegistry.shared.sleepSectionBuilder {
            build()
                // Pauses the pmset reload loops while another tab is frontmost.
                .environment(\.sleepTabActive, selectedTab == .sleep)
        } else {
            UpsellCard(
                title: "Sleep & overnight drain",
                systemImage: "lock.fill",
                message: "See how much charge you lost overnight, how long your Mac slept, how often it woke and why, and what's holding it awake right now. A WhatBattery Pro feature."
            )
        }
    }

    // MARK: - iPhone / iPad

    private var iDeviceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                iDeviceSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Accessories (free: live levels)

    private var accessoriesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                // Observes the monitor on its own, for the same reason as the
                // This Mac tab: the Pro section below must not be rebuilt every
                // time an accessory level lands.
                SectionCard { LiveAccessoriesSection(monitor: monitor) }
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
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
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

    var body: some View {
        // The parent only renders this section once a battery has been seen, so
        // going empty on a transient nil would leave a blank gap above an
        // orphaned divider and the Pro sections. The freshness-bounded fallback
        // lives on the monitor (shared with the popover), so it is already
        // populated when this view is created, including when the window is
        // first opened during a nil.
        if let snapshot = monitor.displaySnapshot {
            // Above the card, not buried below it: the whole point is that the
            // advice reaches someone who never scrolls this tab.
            if isPro, let advisory = PluginRegistry.shared.advisorySectionBuilder {
                advisory()
            }
            SectionCard {
                OverviewCard(snapshot: snapshot, tempUnit: tempUnit, isPro: isPro)
            }
        } else {
            ContentUnavailableView(
                "Battery reading unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("WhatBattery can't read this Mac's battery right now. This usually clears on its own.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }
}

private struct LiveAccessoriesSection: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        AccessoriesCard(accessories: monitor.accessories)
    }
}

/// The desktop-Mac face of the This Mac tab: no battery to report, but the SMC
/// DC-in rail is live, so surface it as a small power view (the SPEC edge case)
/// rather than only an empty state. Falls back to the plain explanation when
/// the SMC gives nothing.
private struct DesktopPowerSection: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        if let power = monitor.systemPower {
            VStack(alignment: .leading, spacing: 14) {
                Label("Power", systemImage: "powerplug").scaledFont(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("DC-in").foregroundStyle(.secondary).gridColumnAlignment(.leading)
                        Text(String(format: "%.1f W", power.watts)).monospacedDigit()
                    }
                    GridRow {
                        Text("Voltage").foregroundStyle(.secondary)
                        Text(String(format: "%.2f V", power.volts)).monospacedDigit()
                    }
                    GridRow {
                        Text("Current").foregroundStyle(.secondary)
                        Text(String(format: "%.2f A", power.amps)).monospacedDigit()
                    }
                }
                .scaledFont(.callout)
                Text("This Mac has no battery. These figures are the DC input feeding the logic board, refreshed every few seconds.")
                    .scaledFont(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView(
                "No battery on this Mac",
                systemImage: "bolt.slash",
                description: Text("WhatBattery reports laptop battery health. Desktops have no battery.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
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
    @State private var appleHealth: SystemProfilerBatteryHealth = .unknown

    private var condition: BatteryCondition { appleHealth.condition }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let health = snapshot.healthPercent {
                HealthBar(percent: health)
            }

            grid
        }
        .task {
            identity = MacIdentity.read()
            // system_profiler blocks briefly, so read it off the main actor.
            appleHealth = await Task.detached(priority: .userInitiated) {
                BatteryConditionReader.readHealth()
            }.value
        }
    }

    /// The health figure on the left, this Mac's identity on the right. The
    /// supporting lines used to stack under "Battery health" in one grey column
    /// of five, where the device name (the thing that says which machine you
    /// are looking at) ended up the faintest line on the screen.
    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(BatteryFormatter.healthPercent(snapshot.healthPercent))
                        .scaledFont(size: 44, weight: .bold, design: .rounded)
                        .monospacedDigit()
                    Text("Battery health")
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
                // Capacity detail is a Pro touch; the free app shows the health
                // percentage only.
                if isPro, snapshot.fullChargeCapacitymAh > 0, snapshot.designCapacitymAh > 0 {
                    Text("\(BatteryFormatter.milliampHours(snapshot.fullChargeCapacitymAh)) of \(BatteryFormatter.milliampHours(snapshot.designCapacitymAh)) design")
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
                // What macOS itself reports, when it differs from our unrounded
                // figure. Anyone who cross-checks System Settings will see the
                // gap; better they see it explained here than conclude we are
                // wrong. Ours is the gauge's raw estimate, Apple's is rounded
                // and smoothed.
                if let appleLine {
                    Text(appleLine).scaledFont(.caption).foregroundStyle(.tertiary)
                }
            }
            // The big number, "Battery health" and the capacity line are
            // separate VoiceOver stops otherwise, read as disconnected
            // fragments. Combined they announce as one sentence.
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(deviceTitle).scaledFont(.callout, weight: .medium)
                if let subtitle = deviceSubtitle {
                    Text(subtitle).scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var grid: some View {
        MetricGrid {
            if condition != .unknown {
                MetricTile("Condition") {
                    // A pill, not coloured text: the vivid status colours are
                    // roughly 2:1 on a light window, and the capsule carries
                    // the state without leaning on the glyph strokes.
                    StatusPill(condition.label, status: conditionStatus)
                }
            }
            tile("Charge", BatteryFormatter.chargeLine(snapshot, includeTimeEstimate: false))
            if let estimate = BatteryFormatter.timeEstimate(snapshot) {
                tile(estimate.label, estimate.value)
            }
            tile("Cycles", "\(snapshot.cycleCount)")
            tile("Temperature", BatteryFormatter.temperature(snapshot.temperatureCelsius, unit: tempUnit))
            tile("Power", power)
            if let adapter = snapshot.adapter?.label {
                tile("Charger", adapter)
            }
            tile("Voltage", BatteryFormatter.voltage(snapshot.voltageMillivolts))
            // Identity extras are a Pro touch, like the capacity line.
            if isPro {
                // A serial is a long unbroken string; at tile width it wrapped
                // mid-token. Smaller and monospaced keeps it on one line and
                // reads as an identifier rather than a reading.
                if let serial = snapshot.batterySerial {
                    MetricTile("Battery serial") {
                        Text(serial)
                            .scaledFont(.caption, design: .monospaced)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .textSelection(.enabled)
                    }
                }
                if let identity { tile("Low Power Mode", identity.lowPowerMode ? "Enabled" : "Disabled") }
            }
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        MetricTile(label) {
            Text(value).scaledFont(.callout, monospacedDigit: true)
        }
    }

    private var deviceTitle: String {
        if let name = identity?.marketingName, !name.isEmpty { return name }
        return snapshot.deviceModel
    }

    /// "macOS reports 99%", shown only when Apple's whole-percent figure and our
    /// unrounded one would actually read differently. When they agree there is
    /// nothing to reconcile and the line is noise.
    private var appleLine: String? {
        guard let apple = appleHealth.maximumCapacityPercent else { return nil }
        guard let ours = snapshot.healthPercent, Int(ours.rounded()) != apple else { return nil }
        return "macOS reports \(apple)%"
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

    /// The reading alone. The charger gets its own tile, so trailing it here
    /// only made this one cell wrap and knocked the row out of line.
    private var power: String {
        BatteryFormatter.powerLine(snapshot, includeAdapter: false)
    }

    private var conditionStatus: Theme.Status {
        switch condition {
        case .normal: return .good
        case .serviceRecommended: return .warning
        // .unknown never reaches here (the row is hidden), so it shares the
        // cautious band rather than inventing a fourth.
        case .serviceBattery, .unknown: return .critical
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

    /// The per-cell breakdown, or nil when it would just repeat the headline
    /// percentage (a device with one cell).
    private func detailedLevels(_ accessory: Accessory) -> String? {
        let summary = AccessoryFormatting.levels(accessory)
        guard let lowest = accessory.lowestPercent, summary != "\(lowest)%" else { return nil }
        return summary
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
                    // Only when it says more than the big readout on the right
                    // does. A single-cell mouse printed "90%" twice on one row;
                    // AirPods genuinely need the per-bud breakdown.
                    if let levels = detailedLevels(accessory) {
                        Text(levels)
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    // Pro: projected time till empty, shown only once the sampler
                    // has enough history. Read the seam inline (nil in the free
                    // build, and gated on the licence) rather than capturing it at
                    // view-init, so it's never a stale snapshot of the registry.
                    if let seconds = PluginRegistry.shared.accessoryEstimateProvider?(accessory.id) {
                        Text(AccessoryFormatting.timeToEmpty(seconds, kind: accessory.kind))
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
                    // Text-grade variant: the vivid band colour is unreadable
                    // as text on a light window. The bar below keeps the vivid
                    // fill, so the colour signal is not lost.
                    Text("\(lowest)%")
                        .scaledFont(.title3).monospacedDigit()
                        .foregroundStyle(Theme.levelText(lowest))
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
