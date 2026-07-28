import SwiftUI

/// Whether the Charging tab is the frontmost tab. The charging view reads this
/// to pause its 5-second reload when the user is on another tab: TabView keeps
/// non-selected tabs mounted, so without an explicit signal the poll would keep
/// hitting SQLite for a tab nobody is looking at. Same pattern, and same
/// reasoning, as `IDeviceTabActiveKey`.
///
/// Defaults to `true` so a host that does not set it (tests, a non-tab embed)
/// polls normally.
public struct ChargingTabActiveKey: EnvironmentKey {
    public static let defaultValue = true
}

public extension EnvironmentValues {
    var chargingTabActive: Bool {
        get { self[ChargingTabActiveKey.self] }
        set { self[ChargingTabActiveKey.self] = newValue }
    }
}
