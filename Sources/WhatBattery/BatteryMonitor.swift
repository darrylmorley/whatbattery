import Foundation
import Combine
import WhatBatteryCore
import WhatBatteryDarwinBackend
import WhatBatteryAppKit

/// The app's live battery state. A `@MainActor ObservableObject` so SwiftUI
/// views can bind to `snapshot` and redraw when it changes.
///
/// Refresh is hybrid (see SPEC): the IOKit power-source watcher gives instant
/// updates on plug / unplug / charge change, and a 5-second timer keeps the live
/// power and temperature readings current while the dropdown is open.
@MainActor
final class BatteryMonitor: ObservableObject {
    /// The current battery snapshot, or nil on a desktop Mac with no battery.
    @Published private(set) var snapshot: BatterySnapshot?

    /// The most recent snapshot that actually read, kept after `snapshot` goes
    /// transiently nil. Views that have already established this Mac has a
    /// battery show this rather than emptying out mid-layout; a five-second-old
    /// reading beats a blank gap above an orphaned divider. Lives here, not in a
    /// view's `@State`, so it survives the window being created or reopened
    /// during a nil window.
    @Published private(set) var lastGoodSnapshot: BatterySnapshot?

    /// Desktop fallback: the SMC DC-in rail (`VD0R`/`ID0R`/`PDTR`), refreshed on
    /// the same 5-second tick, but only while no battery has ever been seen.
    /// After the latch it is nil on a laptop and stays that way; before the
    /// latch there is a brief launch window where a laptop can populate it (the
    /// DC-in keys exist on laptops too), which is why every desktop-facing view
    /// gates on `hasBattery`, never on this being non-nil alone.
    @Published private(set) var systemPower: SMCSystemPowerInput?

    /// How long a last-good reading may stand in for a live one: a minute
    /// covers a run of transient misses at the 5-second refresh; past that the
    /// views say "unavailable" rather than presenting minutes-old figures as
    /// current.
    private static let staleAfter: TimeInterval = 60

    /// The snapshot views should render: the live one, or the last good one
    /// while it is still fresh. `Date` is not monotonic, so a negative age
    /// (clock moved back) counts as stale and fails the safe way. Shared by the
    /// window's overview and the popover so their fallback rules cannot drift.
    var displaySnapshot: BatterySnapshot? {
        if let snapshot { return snapshot }
        guard let last = lastGoodSnapshot else { return nil }
        let age = Date().timeIntervalSince(last.timestamp)
        guard age >= 0, age < Self.staleAfter else { return nil }
        return last
    }

    /// Connected Bluetooth accessories and their battery levels. Refreshed
    /// immediately on a Bluetooth connect/disconnect event, plus a slow poll to
    /// keep levels current (the reader runs a `system_profiler` subprocess).
    @Published private(set) var accessories: [Accessory] = []

    private let provider = DarwinSnapshotProvider()
    private var timer: Timer?
    private var accessoryTimer: Timer?
    private var accessoryDebounce: Timer?
    private var watcher: PowerSourceWatcher?
    private var bluetoothWatcher: BluetoothConnectionWatcher?
    private var bluetoothWatchingStarted = false
    /// The last set of widget-visible values pushed, so we only rewrite + reload
    /// the widget when something the widget shows actually changed.
    private var lastWidgetSignature: String?
    /// Ticket for in-flight accessory reads; see `refreshAccessories`.
    private var accessoryReadGeneration = 0

    /// True once a battery has been seen. Latched rather than tracking
    /// `snapshot != nil`, because a transient IOKit miss must not make the main
    /// window announce "No battery on this Mac". A Mac does not gain or lose one
    /// while running.
    private(set) var hasBattery = false

    init() {
        refresh()
        startWatching()
        startTimer()
        // No accessory read here on purpose: at init the plugin hooks are not
        // registered yet, so a read's result would publish into an empty hook
        // array and the first sample would go unrecorded. The app delegate
        // performs the first read right after bootstrapPlugins, exactly like
        // the battery snapshot's post-bootstrap refresh.
        startAccessoryTimer()
        // The Bluetooth watcher is NOT started here: the app delegate starts
        // it at launch when the permission is already granted (or when it is
        // not yet determined and the user enabled the menu bar readout), and
        // the Accessories tab starts it on first open otherwise; see
        // AccessoryWatchLaunchPolicy and applicationDidFinishLaunching.
        // Starting it can show the one-time Bluetooth permission prompt.
    }

    deinit {
        timer?.invalidate()
        accessoryTimer?.invalidate()
        accessoryDebounce?.invalidate()
        bluetoothWatcher?.stop()
    }

    func refresh() {
        snapshot = provider.currentSnapshot()
        if let snapshot {
            hasBattery = true
            lastGoodSnapshot = snapshot
        }
        if !hasBattery {
            systemPower = provider.systemPowerInput()
        } else if systemPower != nil {
            // A battery appeared after a transient launch miss: this is a
            // laptop, so drop the desktop reading rather than leaving it stale.
            systemPower = nil
        }
        updateWidget()
        if let snapshot {
            for hook in PluginRegistry.shared.sampleHooks {
                hook(snapshot)
            }
        }
    }

    private func updateWidget() {
        guard let snapshot else { return }
        // Every widget-visible field belongs in the signature, or the widget
        // shows stale values until an unrelated field moves: the old signature
        // covered only charge/state/health, so temperature, cycles, capacities,
        // the adapter and the time estimates could all sit frozen. Temperature
        // is coarsened to a whole degree to keep reload pushes off the
        // every-tick path; the snapshot itself is persisted every tick either
        // way, so the widget's 5-minute backstop still reads exact values.
        let health = Int((snapshot.healthPercent ?? 0).rounded())
        let signature = [
            "\(snapshot.currentChargePercent)",
            snapshot.chargingState.rawValue,
            "\(health)",
            "\(Int(snapshot.temperatureCelsius.rounded()))",
            "\(snapshot.cycleCount)",
            "\(snapshot.fullChargeCapacitymAh)",
            "\(snapshot.designCapacitymAh)",
            snapshot.adapter?.label ?? "-",
            "\(snapshot.timeToFullMinutes ?? -1)",
            "\(snapshot.timeToEmptyMinutes ?? -1)",
        ].joined(separator: "|")
        let changed = signature != lastWidgetSignature
        lastWidgetSignature = signature
        WidgetDataWriter.update(snapshot, reload: changed)
    }

    private func startWatching() {
        watcher = PowerSourceWatcher { [weak self] in
            // Delivered on the main run loop, so we are already on the main actor.
            MainActor.assumeIsolated { self?.refresh() }
        }
        watcher?.start()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Read accessory levels off the main actor (the reader spawns a
    /// `system_profiler` subprocess), then publish on the main actor.
    ///
    /// Several reads can be in flight at once (the 300s timer, the 1.5s
    /// Bluetooth debounce, and opening the Accessories tab), and they do not
    /// finish in the order they started. Each read takes a ticket and only the
    /// newest one is allowed to publish, so a slow older read cannot overwrite a
    /// newer list.
    func refreshAccessories() {
        accessoryReadGeneration &+= 1
        let generation = accessoryReadGeneration
        // The detached child does the blocking read off the main actor; the
        // surrounding Task is main-actor-isolated (BatteryMonitor is @MainActor),
        // so the assignment lands back on main without capturing self off-actor.
        Task { [weak self] in
            // Two sources, read concurrently: system_profiler for the list and
            // most levels, and the GATT battery service for BLE accessories
            // (Logitech mice and the like) that the profiler lists with no
            // battery key at all. The merge never overrides a profiler level.
            async let profiled = Task.detached(priority: .utility) {
                AccessoryBatteryReader.readAll()
            }.value
            async let bleLevels = BLEBatteryReader.readLevels()
            let accessories = AccessoryBLEMerge.merge(await profiled, bleLevels: await bleLevels)
            guard let self, generation == self.accessoryReadGeneration else { return }
            self.accessories = accessories
            for hook in PluginRegistry.shared.accessorySampleHooks {
                hook(accessories)
            }
        }
    }

    /// Bluetooth connect/disconnect events handle a device appearing or going
    /// away instantly, so this slow poll only has to keep levels fresh and feed
    /// history (a connected device's % drifts silently, with no event to catch it).
    private func startAccessoryTimer() {
        accessoryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessories() }
        }
    }

    /// Start the Bluetooth connect/disconnect watcher, optionally with an
    /// immediate read. Two callers: the app delegate at launch (when the
    /// permission state makes it safe; it passes false because the init-time
    /// read is already in flight) and the Accessories tab on first open (with
    /// the default immediate read). Idempotent, and only counted as started
    /// once registration actually succeeds, so a failed registration retries
    /// on the next call instead of being latched forever.
    func startAccessoryWatchingIfNeeded(refreshImmediately: Bool = true) {
        if refreshImmediately { refreshAccessories() }
        guard !bluetoothWatchingStarted else { return }
        bluetoothWatcher = BluetoothConnectionWatcher { [weak self] in
            // IOBluetooth delivers this on its own coordinator queue, not the main
            // run loop, so hop to the main actor rather than asserting we're on it.
            Task { @MainActor in self?.scheduleAccessoryRefresh() }
        }
        bluetoothWatchingStarted = bluetoothWatcher?.start() ?? false
        if !bluetoothWatchingStarted { bluetoothWatcher = nil }
    }

    /// Debounce a burst of connect/disconnect events (several devices at once, or
    /// a reconnect flap) into a single refresh, and give the device a moment to
    /// register before we read.
    private func scheduleAccessoryRefresh() {
        accessoryDebounce?.invalidate()
        accessoryDebounce = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessories() }
        }
    }
}
