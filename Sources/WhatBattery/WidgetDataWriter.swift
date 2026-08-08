import Foundation
import WidgetKit
import WhatBatteryCore

/// Pushes the current battery snapshot to the App Group container and asks
/// WidgetKit to refresh.
///
/// Persist and reload are separate on purpose: the snapshot file is written on
/// every refresh (cheap, and it keeps the widget's own 5-minute timeline
/// backstop reading fresh values, including the ones too fine-grained to spend
/// a reload on), while `reloadAllTimelines()` is pushed only when the caller
/// says something coarse changed, because WidgetKit budgets reloads.
enum WidgetDataWriter {
    /// Persist the snapshot; push a WidgetKit reload only when asked. Returns
    /// whether the file was actually written, so the caller can tell a real
    /// update from a no-op and avoid recording state for a write that never
    /// landed.
    /// `includeProDetail` is the caller's licence state: see
    /// `WidgetSharedStore.write`.
    @discardableResult
    static func update(_ snapshot: BatterySnapshot, reload: Bool, includeProDetail: Bool) -> Bool {
        guard WidgetSharedStore.write(snapshot, includeProDetail: includeProDetail) else { return false }
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return true
    }
}
