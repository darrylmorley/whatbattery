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
        BatteryEntry(date: Date(), snapshot: WidgetSharedStore.read())
    }
}
