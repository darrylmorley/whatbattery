import Foundation

/// The App Group bridge between the menu bar app and the widget. The app writes
/// the latest `BatterySnapshot` as JSON; the widget reads it. No IOKit in the
/// widget, it just decodes what the app already computed.
public enum WidgetSharedStore {
    /// Team-prefixed App Group. Team-prefixed identifiers are authorized by the
    /// signing TeamIdentifier alone, so Developer ID builds need no embedded
    /// provisioning profile. Same Apple team as the rest of the suite.
    public static let appGroupID = "M4RUJ7W6MP.app.whatbattery.whatbattery"

    /// The shared JSON file both sides use. Nil when the App Group container is
    /// unavailable, e.g. an unsigned `swift run` dev build with no entitlement.
    public static var sharedFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("batterySnapshot.json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writes the snapshot. Returns false (no-op) when the container is
    /// unavailable, so dev builds degrade quietly instead of crashing.
    @discardableResult
    public static func write(_ snapshot: BatterySnapshot) -> Bool {
        guard let url = sharedFileURL, let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Reads the last snapshot the app wrote, or nil.
    public static func read() -> BatterySnapshot? {
        guard let url = sharedFileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(BatterySnapshot.self, from: data)
    }
}
