import Foundation
import WhatBatteryCore

/// Reads a tethered or WiFi-paired iPhone/iPad's battery from this Mac, the
/// coconutBattery "iPhone/iPad" model. The device's `AppleSmartBattery` node is
/// fetched over the lockdown diagnostics relay (via `MobileDeviceBridge`) and
/// mapped through the same Core model and health math used for the Mac.
///
/// The read path is native (`MobileDevice.framework`, no Python, no bundled
/// libraries), so this is shipping-capable. The relay is a private interface, so
/// a shipping feature must still gate on a per-iOS-version compatibility check.
public enum IDeviceBatteryReader {
    public struct DeviceInfo: Sendable {
        public let udid: String
        public let name: String
        public let productType: String
        public let productVersion: String
        public let serial: String           // the device's hardware serial
        public let connectionType: String   // "USB" or "Network"

        public var marketingName: String { IDeviceModelName.marketingName(for: productType) }
    }

    public struct Reading: Sendable {
        public let device: DeviceInfo
        public let snapshot: BatterySnapshot
    }

    /// The outcome of a read: devices with a usable battery, and devices that were
    /// present and identified but whose battery could not be read or did not pass
    /// field validation (e.g. an iOS version that returns different keys). The
    /// caller can then say "connected, but not readable" instead of "no device".
    public struct ReadResult: Sendable {
        public let readings: [Reading]
        public let unreadable: [DeviceInfo]
    }

    public enum ReaderError: Error, CustomStringConvertible {
        case frameworkUnavailable
        case noDevices

        public var description: String {
            switch self {
            case .frameworkUnavailable:
                return "MobileDevice.framework unavailable on this Mac."
            case .noDevices:
                return "No iPhone/iPad found. Connect one over a data cable and tap Trust, or pair over WiFi."
            }
        }
    }

    /// Read every connected/paired device's battery. Devices whose battery maps
    /// cleanly and passes field validation become `readings`; devices that are
    /// present but unreadable (missing/changed keys, an unexpected iOS shape) are
    /// reported in `unreadable` so the caller can distinguish "connected but not
    /// readable" from "no device at all".
    public static func readAll(now: Date = Date()) throws -> ReadResult {
        guard MobileDeviceBridge.isAvailable else { throw ReaderError.frameworkUnavailable }
        let raw = MobileDeviceBridge.readAll()
        guard !raw.isEmpty else { throw ReaderError.noDevices }

        var readings: [Reading] = []
        var unreadable: [DeviceInfo] = []
        for device in raw {
            let info = deviceInfo(from: device)
            guard let dict = device.batteryDictionary,
                  let battery = AppleSmartBatteryMapper.from(dictionary: dict),
                  battery.isPlausible else {
                unreadable.append(info)
                continue
            }
            let snapshot = BatterySnapshotBuilder.build(
                battery: battery,
                deviceModel: info.marketingName,
                smcDischargeWatts: nil,   // no SMC on an iDevice; builder uses the gauge
                now: now
            )
            readings.append(Reading(device: info, snapshot: snapshot))
        }
        return ReadResult(readings: readings, unreadable: unreadable)
    }

    /// List connected/paired devices without reading their batteries (for a
    /// future GUI device picker).
    public static func listDevices() -> [DeviceInfo] {
        MobileDeviceBridge.readAll().map(deviceInfo(from:))
    }

    private static func deviceInfo(from device: MobileDeviceBridge.RawDevice) -> DeviceInfo {
        DeviceInfo(
            udid: device.udid,
            name: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            productType: device.productType,
            productVersion: device.productVersion,
            serial: device.serial,
            connectionType: device.connectionType
        )
    }
}
