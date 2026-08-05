import SwiftUI

/// Whether the Sleep tab is the frontmost tab. The Sleep view reads this to
/// pause its two reload loops (the `pmset -g log` read and the assertions read)
/// when the user is on another tab: TabView keeps non-selected tabs mounted, so
/// without an explicit signal those loops would keep launching subprocesses for
/// a tab nobody is looking at. Same pattern, and same reasoning, as
/// `IDeviceTabActiveKey` and `ChargingTabActiveKey`.
///
/// Defaults to `true` so a host that does not set it (tests, a non-tab embed)
/// polls normally.
public struct SleepTabActiveKey: EnvironmentKey {
    public static let defaultValue = true
}

public extension EnvironmentValues {
    var sleepTabActive: Bool {
        get { self[SleepTabActiveKey.self] }
        set { self[SleepTabActiveKey.self] = newValue }
    }
}
