import SwiftUI

/// Whether the tab hosting this view is the frontmost tab. Views that run
/// their own polling loops (the per-app pid walk on the Apps tab, the
/// charge-habits SQLite reload on This Mac) read this to pause while the user
/// is on another tab: TabView keeps non-selected tabs mounted, so without an
/// explicit signal those loops would keep running for a tab nobody is looking
/// at. The host window sets it per section, keyed to that section's own tab;
/// same pattern, and same reasoning, as `IDeviceTabActiveKey` and
/// `ChargingTabActiveKey` (which stay tab-specific because their consumers
/// only ever live on those tabs).
///
/// Defaults to `true` so a host that does not set it (tests, a non-tab embed)
/// polls normally.
public struct HostTabActiveKey: EnvironmentKey {
    public static let defaultValue = true
}

public extension EnvironmentValues {
    var hostTabActive: Bool {
        get { self[HostTabActiveKey.self] }
        set { self[HostTabActiveKey.self] = newValue }
    }
}
