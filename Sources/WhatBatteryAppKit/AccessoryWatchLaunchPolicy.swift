import CoreBluetooth

/// Whether the Bluetooth accessory watcher should start at app launch, rather
/// than lazily on the Accessories tab. Pure so the four-state truth table is
/// unit-testable.
///
/// - Granted permission: start; it cannot prompt.
/// - Not determined + the user enabled the menu bar accessory readout: start;
///   the one-time prompt is justified by a feature they switched on.
/// - Denied or restricted: never start; registration cannot deliver authorized
///   notifications, and macOS will not re-prompt after an explicit deny, so
///   there is nothing to gain.
public enum AccessoryWatchLaunchPolicy {
    public static func shouldStartAtLaunch(
        authorization: CBManagerAuthorization,
        readoutEnabled: Bool
    ) -> Bool {
        switch authorization {
        case .allowedAlways: return true
        case .notDetermined: return readoutEnabled
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
}
