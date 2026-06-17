import Foundation
import IOKit

/// Small system identity reads via sysctl and IOKit. All read-only.
public enum SystemInfo {
    /// The Mac's model identifier, e.g. "Mac17,2". Empty string if unavailable.
    public static func hardwareModel() -> String {
        sysctlString("hw.model")
    }

    /// The Mac's hardware serial number (the stable per-device key for health
    /// history, the same identifier coconutBattery keys on). Empty if it can't be
    /// read.
    public static func hardwareSerial() -> String {
        platformExpertString(kIOPlatformSerialNumberKey)
    }

    /// The chip, e.g. "Apple M5". Empty if unavailable.
    public static func chip() -> String {
        sysctlString("machdep.cpu.brand_string")
    }

    /// The marketing name, e.g. "MacBook Pro (14-inch, M5)". Read from the device
    /// tree's `product` node. Empty if unavailable.
    public static func marketingName() -> String {
        registryString(path: "IODeviceTree:/product", key: "product-name")
    }

    /// The regulatory model number, e.g. "A3434" (what coconutBattery shows as the
    /// "Model"). Empty if unavailable.
    public static func regulatoryModelNumber() -> String {
        platformExpertString("regulatory-model-number")
    }

    // MARK: - Helpers

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    /// A string property of the `IOPlatformExpertDevice` service.
    private static func platformExpertString(_ key: String) -> String {
        let expert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard expert != 0 else { return "" }
        defer { IOObjectRelease(expert) }
        return propertyString(entry: expert, key: key)
    }

    /// A string property of an IORegistry entry addressed by path.
    private static func registryString(path: String, key: String) -> String {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return "" }
        defer { IOObjectRelease(entry) }
        return propertyString(entry: entry, key: key)
    }

    /// Read a registry property as text. Some identity values are stored as a
    /// proper string; others (device-tree nodes) are a NUL-terminated C string
    /// inside a data blob, so handle both.
    private static func propertyString(entry: io_registry_entry_t, key: String) -> String {
        guard let property = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return ""
        }
        return decodeProperty(property.takeRetainedValue())
    }

    /// Turn a registry property value into text. Some identity values are a proper
    /// string; others (device-tree nodes) are a NUL-terminated C string inside a
    /// data blob, so handle both and strip the trailing NUL padding. Anything else
    /// yields an empty string. Internal so it can be unit-tested without IOKit.
    static func decodeProperty(_ value: Any) -> String {
        if let string = value as? String {
            return string.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
        if let data = value as? Data {
            let bytes = data.prefix { $0 != 0 }
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }
        return ""
    }
}
