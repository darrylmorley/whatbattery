import Foundation

/// The family a connected iOS device belongs to. Drives the icon and the label
/// on the iPhone / iPad tab, which otherwise calls every device an iPhone.
public enum IDeviceKind: String, Sendable, CaseIterable {
    case iPhone, iPad, iPod, unknown

    /// SF Symbol for the family. An unrecognised device gets the neutral
    /// generic-device glyph rather than a wrong-but-confident iPhone.
    public var symbolName: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .iPod: return "ipodtouch"
        case .unknown: return "ipad.and.iphone"
        }
    }

    /// Fallback title when there is no device to name yet.
    public var label: String {
        switch self {
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .iPod: return "iPod touch"
        case .unknown: return "iPhone / iPad"
        }
    }

    /// Stand-in for a device that reports no name of its own. Distinct from
    /// `label` because this one stands where a real name would go in a
    /// sentence, so the unknown case has to be a noun, not a pair of options.
    public var fallbackName: String {
        self == .unknown ? "Device" : label
    }
}

/// Maps an iOS device's `ProductType` identifier (e.g. "iPhone12,1") to a
/// human marketing name (e.g. "iPhone 11"). Covers recent iPhones and iPads;
/// unknown identifiers fall back to the raw identifier so nothing is ever blank.
///
/// Pure data, kept small on purpose: a full device database can replace this
/// later if the iDevice feature ships. The fallback keeps it safe meanwhile.
public enum IDeviceModelName {
    /// The name to show when a system-provided one is also available.
    ///
    /// The system table (see `IDeviceMarketingNames` in the Darwin backend) is
    /// broader and Apple keeps it current, so it leads. It is not always more
    /// precise, though: macOS calls both `iPhone8,4` and `iPhone12,8` plain
    /// "iPhone SE", where this table distinguishes the 2016 model from the 2020
    /// one. Taking the system name unconditionally silently dropped that, and
    /// two different phones rendered the same string.
    ///
    /// So the more specific name wins, defined as one being a strict extension
    /// of the other: "iPhone SE (2nd gen)" begins with "iPhone SE", so it is the
    /// same model said in more detail rather than a disagreement. Anything else
    /// is a disagreement, and there the system is authoritative.
    public static func marketingName(for productType: String, systemName: String?) -> String {
        guard let systemName, !systemName.isEmpty else { return marketingName(for: productType) }
        guard let ours = table[productType], ours.hasPrefix(systemName) else { return systemName }
        return ours
    }

    public static func marketingName(for productType: String) -> String {
        if let known = table[productType] { return known }
        // An identity read can fail on the product type alone, leaving it
        // empty. Returning it raw would hand the UI a blank title, so the
        // "never blank" promise above needs the empty case spelled out.
        return productType.isEmpty ? kind(for: productType).fallbackName : productType
    }

    /// Which family a `ProductType` belongs to, so the UI can say "iPad" with an
    /// iPad icon rather than labelling everything an iPhone. Derived from the
    /// identifier prefix, which Apple has kept stable, so an unknown model still
    /// resolves to the right family.
    public static func kind(for productType: String) -> IDeviceKind {
        let id = productType.lowercased()
        if id.hasPrefix("ipad") { return .iPad }
        if id.hasPrefix("iphone") { return .iPhone }
        if id.hasPrefix("ipod") { return .iPod }
        return .unknown
    }

    /// Only identifiers whose marketing name is certain. The fallback prints the
    /// raw identifier, which is ugly but never wrong, and that is the right trade
    /// for a device this app cannot see to check. Guessing a name here would put
    /// a confident wrong label on somebody's phone.
    private static let table: [String: String] = [
        // iPhone. The table used to start at the XS, so every iPhone 8 and X
        // showed as its raw identifier: a user reported his iPhone X listed as
        // "iPhone10,6" beside a correctly named iPhone 15 Pro Max.
        "iPhone8,1": "iPhone 6s",
        "iPhone8,2": "iPhone 6s Plus",
        "iPhone8,4": "iPhone SE (1st gen)",
        "iPhone9,1": "iPhone 7",
        "iPhone9,3": "iPhone 7",
        "iPhone9,2": "iPhone 7 Plus",
        "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8",
        "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus",
        "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X",
        "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd gen)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        // iPad. Same gap as the iPhones had: an iPad old enough to still be on
        // iPadOS 17 was named by its identifier.
        "iPad6,11": "iPad (5th gen)",
        "iPad6,12": "iPad (5th gen)",
        "iPad7,5": "iPad (6th gen)",
        "iPad7,6": "iPad (6th gen)",
        "iPad7,11": "iPad (7th gen)",
        "iPad7,12": "iPad (7th gen)",
        "iPad11,6": "iPad (8th gen)",
        "iPad11,7": "iPad (8th gen)",
        "iPad12,1": "iPad (9th gen)",
        "iPad12,2": "iPad (9th gen)",
        "iPad13,18": "iPad (10th gen)",
        "iPad13,19": "iPad (10th gen)",
        "iPad11,1": "iPad mini (5th gen)",
        "iPad11,2": "iPad mini (5th gen)",
        "iPad14,1": "iPad mini (6th gen)",
        "iPad14,2": "iPad mini (6th gen)",
        "iPad11,3": "iPad Air (3rd gen)",
        "iPad11,4": "iPad Air (3rd gen)",
        "iPad13,1": "iPad Air (4th gen)",
        "iPad13,2": "iPad Air (4th gen)",
        "iPad13,16": "iPad Air (5th gen)",
        "iPad13,17": "iPad Air (5th gen)",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)",
        "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad7,1": "iPad Pro 12.9-inch (2nd gen)",
        "iPad7,2": "iPad Pro 12.9-inch (2nd gen)",
        "iPad7,3": "iPad Pro 10.5-inch",
        "iPad7,4": "iPad Pro 10.5-inch",
        "iPad8,1": "iPad Pro 11-inch (1st gen)",
        "iPad8,2": "iPad Pro 11-inch (1st gen)",
        "iPad8,3": "iPad Pro 11-inch (1st gen)",
        "iPad8,4": "iPad Pro 11-inch (1st gen)",
        "iPad8,5": "iPad Pro 12.9-inch (3rd gen)",
        "iPad8,6": "iPad Pro 12.9-inch (3rd gen)",
        "iPad8,7": "iPad Pro 12.9-inch (3rd gen)",
        "iPad8,8": "iPad Pro 12.9-inch (3rd gen)",
        "iPad8,9": "iPad Pro 11-inch (2nd gen)",
        "iPad8,10": "iPad Pro 11-inch (2nd gen)",
        "iPad8,11": "iPad Pro 12.9-inch (4th gen)",
        "iPad8,12": "iPad Pro 12.9-inch (4th gen)",
        "iPad13,4": "iPad Pro 11-inch (3rd gen)",
        "iPad13,5": "iPad Pro 11-inch (3rd gen)",
        "iPad13,6": "iPad Pro 11-inch (3rd gen)",
        "iPad13,7": "iPad Pro 11-inch (3rd gen)",
        "iPad13,8": "iPad Pro 12.9-inch (5th gen)",
        "iPad13,9": "iPad Pro 12.9-inch (5th gen)",
        "iPad13,10": "iPad Pro 12.9-inch (5th gen)",
        "iPad13,11": "iPad Pro 12.9-inch (5th gen)",
        "iPad14,3": "iPad Pro 11-inch (4th gen)",
        "iPad14,4": "iPad Pro 11-inch (4th gen)",
        "iPad14,5": "iPad Pro 12.9-inch (6th gen)",
        "iPad14,6": "iPad Pro 12.9-inch (6th gen)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        "iPad16,1": "iPad mini (A17 Pro)",
        "iPad16,2": "iPad mini (A17 Pro)",
        // iPod touch
        "iPod9,1": "iPod touch (7th gen)",
    ]

    /// The table itself, so a test can assert properties of every entry rather
    /// than of the handful somebody remembered to spell out.
    static var tableForTesting: [String: String] { table }
}
