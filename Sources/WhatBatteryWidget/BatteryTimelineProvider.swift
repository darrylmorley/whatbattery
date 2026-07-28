import Foundation
import WidgetKit
import WhatBatteryCore

struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?

    /// Sample data for the widget gallery / previews.
    static let placeholder = BatteryEntry(
        date: Date(),
        snapshot: BatterySnapshot(
            timestamp: Date(),
            designCapacitymAh: 6249,
            fullChargeCapacitymAh: 6221,
            healthPercent: 99.5,
            cycleCount: 42,
            designCycleCount: 1000,
            currentChargePercent: 78,
            currentChargemAh: 4800,
            chargingState: .charging,
            timeToFullMinutes: 47,
            timeToEmptyMinutes: nil,
            voltageMillivolts: 13228,
            amperageMilliamps: 1500,
            powerWatts: 38.6,
            temperatureCelsius: 30.1,
            adapter: AdapterInfo(watts: 100, description: "pd charger"),
            deviceModel: "Mac17,2",
            batterySerial: nil,
            manufactureDate: nil
        )
    )
}

/// Reads the snapshot the app cached in the App Group container. The widget
/// never touches IOKit itself: a sandboxed extension can't open AppleSMC, so all
/// data flows from the running app.
struct BatteryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        // The app pushes a reload whenever values change; this 5-minute backstop
        // keeps the widget fresh if the app is closed.
        let timeline = Timeline(entries: [currentEntry()], policy: .after(Date().addingTimeInterval(300)))
        completion(timeline)
    }

    private func currentEntry() -> BatteryEntry {
        // A snapshot only stays fresh while the app is running to rewrite it.
        // If it stops (quit, crash, no launch-at-login), every 5-minute refresh
        // would re-serve the same file forever, presenting hours-old charge
        // and health as current. Past a grace of a few missed backstops, show
        // the honest empty state instead of stale numbers.
        let snapshot = WidgetSharedStore.read()
        if let snapshot, Date().timeIntervalSince(snapshot.timestamp) > Self.staleAfter {
            return BatteryEntry(date: Date(), snapshot: nil)
        }
        return BatteryEntry(date: Date(), snapshot: snapshot)
    }

    /// Three missed 5-minute backstops: enough slack for sleep/wake and reload
    /// throttling, short enough that dead data never masquerades as live.
    private static let staleAfter: TimeInterval = 15 * 60
}
