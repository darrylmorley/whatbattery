import SwiftUI

/// Whether the iPhone/iPad tab is the frontmost tab. The iDevice view reads this
/// to pause its battery poll when the user is on another tab. The poll does a
/// real connect/read/teardown against the device every few seconds, so it must
/// not run for a tab nobody is looking at. TabView keeps non-selected tabs alive
/// and its `.task`/`onAppear` lifecycle is version-dependent, so visibility is
/// signalled explicitly through the environment rather than inferred.
///
/// Defaults to `true` so a host that does not set it (tests, a non-tab embed)
/// polls normally.
public struct IDeviceTabActiveKey: EnvironmentKey {
    public static let defaultValue = true
}

public extension EnvironmentValues {
    var iDeviceTabActive: Bool {
        get { self[IDeviceTabActiveKey.self] }
        set { self[IDeviceTabActiveKey.self] = newValue }
    }
}
