import Foundation

/// The one formatter for accessory runtime strings, shared by the live rows,
/// the Pro history view, and the low-battery alert so they never disagree in
/// style. Pure; ships in the public mirror (no Pro logic here).
public enum AccessoryRuntimeFormatting {
    /// "About 5h left"; for headphones, "About 40m of listening left", the
    /// framing that actually answers the AirPods question. "About" is doing
    /// real work: the discharge rate varies with volume and ANC, so the
    /// estimate is honest but rough.
    public static func timeToEmpty(_ seconds: TimeInterval, kind: Accessory.Kind = .other) -> String {
        kind == .headphones
            ? "About \(duration(seconds)) of listening left"
            : "About \(duration(seconds)) left"
    }

    /// "40m", "5h", "3 days", "3 weeks". Each tier is chosen after rounding,
    /// so a value that rounds up to the next unit is shown in that unit
    /// ("1h", not "60m").
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let hours = Int((seconds / 3_600).rounded())
        if hours < 48 { return "\(hours)h" }
        let days = Int((seconds / 86_400).rounded())
        if days < 14 { return "\(days) days" }
        return "\(Int((seconds / 604_800).rounded())) weeks"
    }
}
