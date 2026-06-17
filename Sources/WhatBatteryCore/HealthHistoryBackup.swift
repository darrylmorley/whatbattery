import Foundation

/// A portable backup of the long-term health history: a versioned JSON envelope
/// around the records, so history can move between Macs or survive a reinstall.
/// Pure and testable; the Pro backup/restore UI calls into here.
public struct HealthHistoryBackup: Codable, Equatable, Sendable {
    /// Bump when the on-disk shape changes incompatibly. The decoder accepts any
    /// version it can map; the field is here so a future format can branch.
    public static let currentVersion = 1

    public let version: Int
    public let records: [HealthRecord]

    public init(records: [HealthRecord], version: Int = HealthHistoryBackup.currentVersion) {
        self.version = version
        self.records = records
    }

    /// Encode records into a pretty-printed, sorted JSON backup with ISO 8601
    /// dates (the same conventions as the other exports).
    public static func encode(_ records: [HealthRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(HealthHistoryBackup(records: records))
    }

    /// Decode a backup file back into records. Throws if the data is not a valid
    /// backup envelope.
    public static func decode(_ data: Data) throws -> [HealthRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HealthHistoryBackup.self, from: data).records
    }
}
