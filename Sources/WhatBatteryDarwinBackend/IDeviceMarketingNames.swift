import Foundation
import os

/// Marketing names for iPhones, iPads and iPods, read from the table macOS
/// already ships rather than one we type out by hand.
///
/// The device tells us only its `ProductType` ("iPhone10,6"). Lockdown has no
/// key for the human name, so something has to do the lookup. Finder manages it,
/// and this is how: `CoreTypes.bundle` declares one UTI per model, tagged with
/// the product types it covers.
///
///     UTTypeDescription        "iPhone X (Model A1865, A1901, A1902, A1903)"
///     com.apple.device-model-code  ["D22AP", "D221AP", "iPhone10,3", "iPhone10,6", "iPhone"]
///
/// Two reasons to prefer it over our own list. It is far larger (239 product
/// types against the 103 we had, which is what left a user's iPhone X showing as
/// "iPhone10,6"), and Apple updates it with the OS, so a phone released after
/// this build still gets named.
///
/// `IDeviceModelName`'s table stays as the fallback: this is an undocumented
/// private bundle, and if Apple moves or reshapes it the app must degrade to the
/// names it knows rather than to bare identifiers.
public enum IDeviceMarketingNames {
    private static let logger = Logger(subsystem: "app.whatbattery", category: "idevice-names")

    static let bundlePath =
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/MobileDevices.bundle/Contents/Info.plist"

    /// The marketing name for a product type, or nil if the system table has no
    /// entry (or could not be read).
    public static func name(for productType: String) -> String? {
        table[productType]
    }

    /// Parsed once. The file is a few hundred KB and never changes while we are
    /// running. `static let` initialisation is `swift_once`, so concurrent first
    /// touches are safe.
    private static let table: [String: String] = {
        guard let data = FileManager.default.contents(atPath: bundlePath),
              data.count <= maxBytes,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any] else {
            logger.notice("device name table unreadable at \(bundlePath, privacy: .public); using the built-in list")
            return [:]
        }
        let parsed = parse(root)
        if parsed.isEmpty {
            logger.notice("device name table parsed to nothing; its shape has changed, using the built-in list")
        }
        return parsed
    }()

    /// A ceiling on what this process will buffer from a file it does not own,
    /// the same reasoning as `SleepAnalysisReader`'s `maxBytes`. The real file is
    /// well under a megabyte and SIP-protected, so this only adds a bound.
    static let maxBytes = 16 * 1024 * 1024

    /// Pure, so the shape of the file can be tested without depending on which
    /// macOS version happens to be running the tests.
    static func parse(_ root: [String: Any]) -> [String: String] {
        // `as? [Any]` then per-element, not `as? [[String: Any]]`. The
        // whole-array cast is all-or-nothing: one non-dictionary element makes it
        // nil and silently drops all 239 names, which is precisely the "Apple
        // reshaped the file" case this is supposed to survive.
        guard let declarations = root["UTExportedTypeDeclarations"] as? [Any] else { return [:] }
        var table: [String: String] = [:]
        var conflicted: Set<String> = []
        for element in declarations {
            guard let declaration = element as? [String: Any] else { continue }
            guard let description = declaration["UTTypeDescription"] as? String,
                  let tags = declaration["UTTypeTagSpecification"] as? [String: Any],
                  let codes = tags["com.apple.device-model-code"] as? [String] else { continue }
            let name = strippingModelNumbers(description)
            guard !name.isEmpty else { continue }
            for code in codes where code.contains(",") {
                // Only comma-bearing codes. The same list carries board ids
                // ("D22AP") and the bare family ("iPhone"), neither of which a
                // ProductType ever equals, and the bare family would otherwise
                // map to whichever declaration happened to be parsed last.
                if let existing = table[code], existing != name {
                    // Two declarations naming the same product type differently.
                    // No such case exists in the shipped file (222 product types
                    // appear more than once and all agree), so rather than let
                    // parse order pick a winner, drop the entry and let the
                    // built-in table answer for it.
                    conflicted.insert(code)
                    continue
                }
                table[code] = name
            }
        }
        for code in conflicted { table.removeValue(forKey: code) }
        return table
    }

    /// "iPhone X (Model A1865, A1901, A1902, A1903)" -> "iPhone X".
    ///
    /// Apple appends the regulatory model numbers, which are what distinguish the
    /// declarations from one another (one model can have several, split by
    /// region). We key on the product type, which is already unique across them,
    /// so the suffix is noise. It also only ever appears at the end, which is why
    /// this is anchored rather than a general paren strip: "iPad Pro (11-inch)"
    /// must survive intact.
    static func strippingModelNumbers(_ description: String) -> String {
        guard let range = description.range(of: #"\s*\((?:Model|Models)\s[^)]*\)$"#, options: .regularExpression) else {
            return description.trimmingCharacters(in: .whitespaces)
        }
        return String(description[description.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
    }
}
