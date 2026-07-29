import Foundation
import IOBluetooth

/// Fires a callback whenever a Bluetooth device connects or disconnects, so the
/// accessory list can refresh straight away instead of waiting for the slow poll.
/// Delivered on the main run loop.
///
/// The connection-notification API is behind the Bluetooth privacy gate: macOS
/// hard-crashes a process that calls it without `NSBluetoothAlwaysUsageDescription`
/// in its Info.plist, and prompts the user once for permission when it does have
/// the key. So we only register from a bundled app (which has the key); a bare
/// `swift run` with no Info.plist falls back to the poll.
public final class BluetoothConnectionWatcher: NSObject {
    private let onChange: () -> Void
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [IOBluetoothUserNotification] = []

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
    }

    /// Returns true when the connect notification actually registered: Apple
    /// documents that registration can return nil on error, and the caller
    /// must not consider watching started on that path.
    @discardableResult
    public func start() -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        return connectNotification != nil
    }

    public func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onChange()
        // Catch this device disconnecting too, so unplugging refreshes as quickly
        // as plugging in. Tracked so stop() can unregister it.
        if let disconnect = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
            disconnectNotifications.append(disconnect)
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        disconnectNotifications.removeAll { $0 === notification }
        onChange()
    }
}
