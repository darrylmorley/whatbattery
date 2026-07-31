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

    private static let table: [String: String] = [
        // iPhone
        "iPhone11,2": "iPhone XS",
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
        // iPad
        "iPad13,16": "iPad Air (5th gen)",
        "iPad13,17": "iPad Air (5th gen)",
        "iPad14,3": "iPad Pro 11-inch (4th gen)",
        "iPad14,5": "iPad Pro 12.9-inch (6th gen)",
        "iPad13,18": "iPad (10th gen)",
        "iPad14,1": "iPad mini (6th gen)",
        "iPad14,2": "iPad mini (6th gen)",
    ]
}
