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

    private let provider = DarwinSnapshotProvider()
    private var timer: Timer?
    private var watcher: PowerSourceWatcher?
    /// The last set of widget-visible values pushed, so we only rewrite + reload
    /// the widget when something the widget shows actually changed.
    private var lastWidgetSignature: String?

    var hasBattery: Bool { snapshot != nil }

    init() {
        refresh()
        startWatching()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        snapshot = provider.currentSnapshot()
        updateWidget()
        if let snapshot {
            for hook in PluginRegistry.shared.sampleHooks {
                hook(snapshot)
            }
        }
    }

    private func updateWidget() {
        guard let snapshot else { return }
        let health = Int((snapshot.healthPercent ?? 0).rounded())
        let signature = "\(snapshot.currentChargePercent)|\(snapshot.chargingState.rawValue)|\(health)"
        guard signature != lastWidgetSignature else { return }
        lastWidgetSignature = signature
        WidgetDataWriter.update(snapshot)
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
}
