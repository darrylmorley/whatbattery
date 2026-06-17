import Foundation
import WidgetKit
import WhatBatteryCore

/// Pushes the current battery snapshot to the App Group container and asks
/// WidgetKit to refresh. `reloadAllTimelines()` is a no-op when no widget is
/// installed, so this is cheap to call.
enum WidgetDataWriter {
    static func update(_ snapshot: BatterySnapshot) {
        guard WidgetSharedStore.write(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
