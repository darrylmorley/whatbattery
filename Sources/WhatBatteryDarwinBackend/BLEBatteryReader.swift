import CoreBluetooth
import Foundation

/// Reads battery levels for connected BLE accessories over the standard GATT
/// Battery Service (0x180F / characteristic 0x2A19): the route System Settings
/// itself uses for devices like Logitech mice, which appear in
/// `system_profiler` with no battery key at all because they report only over
/// GATT. Verified by `scripts/probe-ble-battery.swift` (an MX Anywhere 2 that
/// showed "battery unavailable" reads its true 90% this way).
///
/// Strictly additive and read-only: `retrieveConnectedPeripherals` touches only
/// devices the system already holds a connection to (no scanning, no pairing),
/// and connecting a second central to them rides the existing link.
///
/// Permission: creating a `CBCentralManager` prompts when Bluetooth TCC is not
/// determined, so this runs only when authorization is already `.allowedAlways`
/// and returns empty otherwise. Users grant that the first time the connect
/// watcher starts; from then on BLE levels appear.
///
/// Deliberately no `Bundle.main` guard (unlike `BluetoothConnectionWatcher`):
/// CoreBluetooth does not hard-crash an unbundled process the way IOBluetooth's
/// notification API does (verified live: the bare `.build` CLI binary reads
/// levels fine once authorized), and the shipped CLI helper's `Bundle.main`
/// does not resolve to the app's Info.plist (see `AppInfo`), so that guard
/// would silently kill the feature there.
public enum BLEBatteryReader {
    /// Battery levels by peripheral name for every connected BLE device that
    /// exposes the GATT battery service. Empty when unauthorized, Bluetooth is
    /// off, or nothing qualifies. Bounded by `timeout`; partial results are
    /// returned rather than discarded.
    public static func readLevels(timeout: TimeInterval = 4) async -> [String: Int] {
        guard CBCentralManager.authorization == .allowedAlways else { return [:] }
        return await withCheckedContinuation { continuation in
            let session = Session(timeout: timeout) { levels in
                continuation.resume(returning: levels)
            }
            session.begin()
        }
    }

    /// One read pass: owns its central manager and delegate state for the
    /// duration, resumes exactly once (reads complete or timeout), then tears
    /// its connections down. A fresh session per call keeps CoreBluetooth's
    /// delegate state machine trivially correct at the cost of a manager
    /// allocation every few minutes, which is nothing.
    private final class Session: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        private let batteryService = CBUUID(string: "180F")
        private let batteryLevel = CBUUID(string: "2A19")
        private let queue = DispatchQueue(label: "app.whatbattery.ble-battery")
        private let timeout: TimeInterval
        private var completion: (([String: Int]) -> Void)?
        private var central: CBCentralManager?
        private var peripherals: [CBPeripheral] = []
        private var pendingReads = 0
        /// Keyed by peripheral identity, not name: two peripherals can share a
        /// name, and attributing either one's level to the name would be a
        /// guess. `finish()` drops ambiguous names entirely.
        private var readings: [UUID: (name: String, level: Int)] = [:]
        /// Keeps the session (the manager's delegate) alive until it finishes.
        private var retainCycle: Session?

        init(timeout: TimeInterval, completion: @escaping ([String: Int]) -> Void) {
            self.timeout = timeout
            self.completion = completion
        }

        func begin() {
            // The timeout is armed before any CoreBluetooth work so the
            // continuation is resumed no matter what the manager does.
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish()
            }
            // All other session state is mutated on `queue` (delegate
            // callbacks and the timeout land there), so setup must happen
            // there too: the manager's first state callback could otherwise
            // race these assignments on the caller's thread. Callbacks are
            // delivered async to the queue, so none can run before this
            // block finishes.
            queue.async {
                guard self.completion != nil else { return } // timed out already
                self.retainCycle = self
                self.central = CBCentralManager(delegate: self, queue: self.queue)
            }
        }

        /// Resume exactly once with whatever was read, then disconnect our
        /// handles. Cancelling our connection interest does not drop the
        /// system's own link to the device (bluetoothd holds its own).
        private func finish() {
            guard let completion else { return }
            self.completion = nil
            for peripheral in peripherals {
                central?.cancelPeripheralConnection(peripheral)
            }
            var counts: [String: Int] = [:]
            for reading in readings.values {
                counts[reading.name, default: 0] += 1
            }
            var levels: [String: Int] = [:]
            for reading in readings.values where counts[reading.name] == 1 {
                levels[reading.name] = reading.level
            }
            completion(levels)
            retainCycle = nil
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            guard central.state == .poweredOn else {
                // Off or unauthorized: nothing to read this pass. Unknown and
                // resetting may still settle to poweredOn, so wait them out
                // under the timeout.
                if central.state != .unknown, central.state != .resetting { finish() }
                return
            }
            peripherals = central.retrieveConnectedPeripherals(withServices: [batteryService])
            guard !peripherals.isEmpty else {
                finish()
                return
            }
            pendingReads = peripherals.count
            for peripheral in peripherals {
                peripheral.delegate = self
                central.connect(peripheral)
            }
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            peripheral.discoverServices([batteryService])
        }

        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            readCompleted()
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            guard let service = peripheral.services?.first(where: { $0.uuid == batteryService }) else {
                readCompleted()
                return
            }
            peripheral.discoverCharacteristics([batteryLevel], for: service)
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == batteryLevel }) else {
                readCompleted()
                return
            }
            peripheral.readValue(for: characteristic)
        }

        func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            // A failed read can still carry a stale cached value; only a
            // clean battery-level read counts.
            if error == nil, characteristic.uuid == batteryLevel,
               let name = peripheral.name, let raw = characteristic.value?.first, raw <= 100 {
                readings[peripheral.identifier] = (name: name, level: Int(raw))
            }
            readCompleted()
        }

        private func readCompleted() {
            pendingReads -= 1
            if pendingReads <= 0 { finish() }
        }
    }
}
