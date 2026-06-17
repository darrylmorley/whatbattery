import Foundation

/// Which kind of device a health record belongs to. The History view groups
/// records into a "Macs" section and an "iPhone / iPad" section, the same split
/// coconutBattery uses.
public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case mac
    case iDevice
}

/// One point in a device's long-term health history: a sparse, identity-rich
/// snapshot of how worn the battery is, saved roughly once a day per device.
///
/// This is deliberately not the same as `BatterySample` (the dense 5-minute
/// telemetry stream behind the Lifetime Analyzer). A health record is about the
/// slow decay trend over months and years, so it carries device identity (to key
/// many Macs and iPhones over time) and the health-relevant fields only.
public struct HealthRecord: Codable, Equatable, Sendable, Identifiable {
    /// A stable per-device identifier (a Mac's hardware serial, an iDevice's
    /// UDID). Records for one physical device share this, so its history is one
    /// continuous series even as the OS version or name changes.
    public let deviceID: String
    public let kind: DeviceKind

    public let date: Date
    public let model: String          // e.g. "Mac17,2" or marketing name
    public let name: String           // the user's device name
    public let osVersion: String
    public let serial: String         // the device's hardware serial (may differ from deviceID)

    public let cycleCount: Int
    public let healthPercent: Double?
    public let designCapacitymAh: Int
    public let fullChargeCapacitymAh: Int

    /// Unique per device per timestamp; a device only stores one record a day, so
    /// this is stable enough to drive a SwiftUI list.
    public var id: String { "\(deviceID)@\(date.timeIntervalSince1970)" }

    public init(
        deviceID: String,
        kind: DeviceKind,
        date: Date,
        model: String,
        name: String,
        osVersion: String,
        serial: String = "",
        cycleCount: Int,
        healthPercent: Double?,
        designCapacitymAh: Int,
        fullChargeCapacitymAh: Int
    ) {
        self.deviceID = deviceID
        self.kind = kind
        self.date = date
        self.model = model
        self.name = name
        self.osVersion = osVersion
        self.serial = serial
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.designCapacitymAh = designCapacitymAh
        self.fullChargeCapacitymAh = fullChargeCapacitymAh
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID, kind, date, model, name, osVersion, serial
        case cycleCount, healthPercent, designCapacitymAh, fullChargeCapacitymAh
    }

    /// Custom decode so a backup written before `serial` existed still restores:
    /// the synthesized `Decodable` would throw on the missing key, but a health
    /// backup must stay forward/backward compatible.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        kind = try container.decode(DeviceKind.self, forKey: .kind)
        date = try container.decode(Date.self, forKey: .date)
        model = try container.decode(String.self, forKey: .model)
        name = try container.decode(String.self, forKey: .name)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        serial = try container.decodeIfPresent(String.self, forKey: .serial) ?? ""
        cycleCount = try container.decode(Int.self, forKey: .cycleCount)
        healthPercent = try container.decodeIfPresent(Double.self, forKey: .healthPercent)
        designCapacitymAh = try container.decode(Int.self, forKey: .designCapacitymAh)
        fullChargeCapacitymAh = try container.decode(Int.self, forKey: .fullChargeCapacitymAh)
    }
}
