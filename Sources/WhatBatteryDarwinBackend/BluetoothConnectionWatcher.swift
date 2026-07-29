import Foundation
import IOBluetooth

/// Fires a callback whenever a Bluetooth device connects or disconnects, so the
/// accessory list can refresh straight away instead of waiting for the slow poll.
///
/// The connection-notification API is behind the Bluetooth privacy gate: macOS
/// hard-crashes a process that calls it without `NSBluetoothAlwaysUsageDescription`
/// in its Info.plist, and prompts the user once for permission when it does have
/// the key. So we only register from a bundled app (which has the key); a bare
/// `swift run` with no Info.plist falls back to the poll.
///
/// Threading: Apple does not document which queue IOBluetooth notifications
/// arrive on, so every mutation of the registration table is funnelled onto the
/// main queue, and `start()` / `stop()` must be called from the main thread.
/// The owner must call `stop()` before releasing the watcher.
public final class BluetoothConnectionWatcher: NSObject {
    private let onChange: () -> Void
    private var connectNotification: IOBluetoothUserNotification?
    /// Live disconnect registrations keyed by device address, so registration
    /// is idempotent: a device seeded at start and racing its own connect
    /// event can never hold two live tokens.
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
    }

    /// Returns true when the connect notification actually registered: Apple
    /// documents that registration can return nil on error, and the caller
    /// must not consider watching started on that path. Main thread only.
    @discardableResult
    public func start() -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        guard connectNotification != nil else { return false }

        // Devices that are ALREADY connected when we start never fire the
        // connect notification, so without this seeding their disconnects went
        // unobserved and the list only corrected at the slow poll (AirPods
        // connected before launch stayed shown after going into the case).
        // Synchronous on purpose: a passive walk of the paired list is tiny
        // next to the registration call that just preceded it.
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            registerDisconnect(for: device)
        }
        return true
    }

    /// Main thread only.
    public func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Hop to main before touching the registration table; the delivery
        // queue is undocumented.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onChange()
            // Catch this device disconnecting too, so unplugging refreshes as
            // quickly as plugging in.
            self.registerDisconnect(for: device)
        }
    }

    /// Register a disconnect notification for a device, once. Main thread only.
    /// The handler unregisters it when it fires and a reconnect registers a
    /// fresh one, so the table never grows unbounded. If the device managed to
    /// disconnect between the caller's check and registration, the missed
    /// event is synthesized: unregister and report a change.
    private func registerDisconnect(for device: IOBluetoothDevice) {
        let key = device.addressString ?? "unknown-\(ObjectIdentifier(device).hashValue)"
        guard disconnectNotifications[key] == nil else { return }
        guard let token = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) else { return }
        disconnectNotifications[key] = token
        if !device.isConnected() {
            token.unregister()
            disconnectNotifications[key] = nil
            onChange()
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            notification.unregister()
            if let key = self.disconnectNotifications.first(where: { $0.value === notification })?.key {
                self.disconnectNotifications[key] = nil
            }
            self.onChange()
        }
    }
}
