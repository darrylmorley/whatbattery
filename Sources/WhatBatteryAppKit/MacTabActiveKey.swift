import SwiftUI

/// Whether the This Mac tab is the frontmost tab. The per-app power view reads
/// this to pause its pid walk when the user is on another tab: TabView keeps
/// non-selected tabs mounted, so without an explicit signal the 4-second
/// `proc_listpids` + `proc_pid_rusage` sweep would keep running for a tab
/// nobody is looking at. Same pattern, and same reasoning, as
/// `IDeviceTabActiveKey` and `ChargingTabActiveKey`.
///
/// Defaults to `true` so a host that does not set it (tests, a non-tab embed)
/// polls normally.
public struct MacTabActiveKey: EnvironmentKey {
    public static let defaultValue = true
}

public extension EnvironmentValues {
    var macTabActive: Bool {
        get { self[MacTabActiveKey.self] }
        set { self[MacTabActiveKey.self] = newValue }
    }
}
