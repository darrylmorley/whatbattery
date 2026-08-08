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

    private static func encoder(includeProDetail: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if !includeProDetail {
            encoder.userInfo[.omitProDetail] = true
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writes the snapshot. Returns false (no-op) when the container is
    /// unavailable, so dev builds degrade quietly instead of crashing.
    ///
    /// `includeProDetail` carries the licence state. The widget extension cannot
    /// check a licence itself, so the Pro figures are withheld here, at the only
    /// point that knows: an unlicensed write leaves them out of the file
    /// entirely, and the widget's own `> 0` guard drops the capacity line.
    /// Without this the widget would print figures the window beside it hides.
    ///
    /// Deliberately not defaulted. This is the parameter that decides whether
    /// paid data lands in a file a free build can read, and a default would make
    /// forgetting it fail open and silently. Every caller states its intent.
    @discardableResult
    public static func write(_ snapshot: BatterySnapshot, includeProDetail: Bool) -> Bool {
        let encoder = encoder(includeProDetail: includeProDetail)
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
