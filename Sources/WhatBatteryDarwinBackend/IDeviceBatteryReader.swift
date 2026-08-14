import Foundation
import WhatBatteryCore

/// Reads a tethered or WiFi-paired iPhone/iPad's battery from this Mac. The
/// device's `AppleSmartBattery` node is fetched over the lockdown diagnostics
/// relay (via `MobileDeviceBridge`) and mapped through the same Core model and
/// health math used for the Mac.
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

        /// The system's table leads, so the name matches what Finder shows and a
        /// device released after this build is still named. `IDeviceModelName`
        /// covers the case where that private bundle has moved or changed shape,
        /// and keeps the more specific name where it has one (macOS calls both
        /// iPhone SE generations plain "iPhone SE").
        public var marketingName: String {
            IDeviceModelName.marketingName(
                for: productType,
                systemName: IDeviceMarketingNames.name(for: productType)
            )
        }
        public var kind: IDeviceKind { IDeviceModelName.kind(for: productType) }
    }

    /// Why a connected device gave no usable battery.
    ///
    /// The states were indistinguishable before: everything that failed for any
    /// reason arrived as "connected but not readable", which is no use to
    /// anybody trying to work out whether an iPad is unsupported, locked, or
    /// simply was not reached. A user reported an iPad missing from the app
    /// while Finder listed it, and the app could not say which of these it was.
    public enum UnreadableReason: Error, Sendable, Equatable {
        /// Connect or the lockdown session failed. Usually locked, not trusted,
        /// or reachable to Finder over WiFi but not to us right now.
        case notReached
        /// Reached, but the diagnostics relay returned nothing for the battery.
        case relaySilent
        /// The relay answered in a shape the mapper does not recognise.
        case unrecognisedShape
        /// Mapped, but the values are not a battery we would believe.
        case implausibleValues

        public var description: String {
            switch self {
            case .notReached:
                // Deliberately not "connected but could not be reached", which
                // is how this used to compose and reads as a contradiction. It
                // is connected in the sense the Mac can see it, and unreachable
                // in the sense lockdown would not open a session.
                //
                // "Locked" was in here and came out again. Testing a locked
                // iPhone showed it either reads normally or leaves the device
                // list altogether (a locked device stops advertising over WiFi,
                // and a device that is not listed cannot be reported here at
                // all). It never once sat in the list refusing a connection, so
                // naming it sent people to check the one thing ruled out.
                return "did not accept a connection (it may not be trusted on this Mac, or it dropped off the network)"
            case .relaySilent:
                return "was reached but reported no battery"
            case .unrecognisedShape:
                return "reported its battery in a shape this version does not recognise"
            case .implausibleValues:
                return "reported battery values that did not look right"
            }
        }
    }

    /// A device that is present but gave no usable battery, and why.
    public struct Unreadable: Sendable {
        public let device: DeviceInfo
        public let reason: UnreadableReason
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
        public let unreadable: [Unreadable]

        /// The devices alone, for callers that only need to name them.
        public var unreadableDevices: [DeviceInfo] { unreadable.map(\.device) }
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
        var unreadable: [Unreadable] = []
        for device in raw {
            let info = deviceInfo(from: device)
            let battery: AppleSmartBattery
            switch classify(
                reached: device.reached,
                batteryDictionary: device.batteryDictionary,
                isPMUSourced: device.batteryIsPMUSourced
            ) {
            case .failure(let reason):
                unreadable.append(Unreadable(device: info, reason: reason))
                continue
            case .success(let mapped):
                battery = mapped
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

    /// A usable battery, or why there is not one. Split out from `readAll` so
    /// the classification can be tested without a device on the other end of a
    /// cable, which is the only reason it was previously untestable.
    ///
    /// `reached` comes from the bridge, which knows whether connect and the
    /// lockdown session actually succeeded. An earlier version inferred it from
    /// an empty product type, which is a side effect of a different call: a
    /// locked device that still answered `ProductType` would have been reported
    /// as "reached but reported no battery", sending its owner looking in the
    /// wrong place. That is the exact failure this reason exists to end, so it
    /// is not inferred from anything.
    static func classify(
        reached: Bool,
        batteryDictionary: [String: Any]?,
        isPMUSourced: Bool = false
    ) -> Result<AppleSmartBattery, UnreadableReason> {
        guard let dict = batteryDictionary else {
            return .failure(reached ? .relaySilent : .notReached)
        }
        guard let battery = AppleSmartBatteryMapper.from(dictionary: dict, isPMUSourced: isPMUSourced) else {
            return .failure(.unrecognisedShape)
        }
        guard battery.isPlausible else { return .failure(.implausibleValues) }
        return .success(battery)
    }

    /// List connected/paired devices without reading their batteries (for a
    /// future GUI device picker).
    public static func listDevices() -> [DeviceInfo] {
        MobileDeviceBridge.readAll().map(deviceInfo(from:))
    }

    private static func deviceInfo(from device: MobileDeviceBridge.RawDevice) -> DeviceInfo {
        DeviceInfo(
            udid: device.udid,
            // A device that reports no name must not be guessed at: calling an
            // unnamed iPad "iPhone" is exactly the confusion this view exists
            // to avoid. Fall back to its own family instead.
            name: device.deviceName.isEmpty
                ? IDeviceModelName.kind(for: device.productType).fallbackName
                : device.deviceName,
            productType: device.productType,
            productVersion: device.productVersion,
            serial: device.serial,
            connectionType: device.connectionType
        )
    }
}
