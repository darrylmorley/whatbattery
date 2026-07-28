import Foundation
import WhatBatteryCore

/// Presentation helpers for accessories, shared by the dropdown and the main
/// window so the icons and level strings stay consistent.
enum AccessoryFormatting {
    /// SF Symbol for an accessory kind.
    static func symbol(for kind: Accessory.Kind) -> String {
        switch kind {
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "trackpad"
        case .headphones: return "headphones"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    /// "63%" for a single-cell device, or "L 69%  R 75%  Case 80%" for AirPods.
    static func levels(_ accessory: Accessory) -> String {
        accessory.levelSummary
    }

    /// "About 5h left" from a projected time-to-empty in seconds; for
    /// headphones, "About 5h of listening left", the framing that actually
    /// answers the AirPods question. "About" is doing real work here: the
    /// discharge rate varies with volume and ANC, so the estimate is honest
    /// but rough.
    static func timeToEmpty(_ seconds: TimeInterval, kind: Accessory.Kind = .other) -> String {
        kind == .headphones
            ? "About \(duration(seconds)) of listening left"
            : "About \(duration(seconds)) left"
    }

    /// "<1h", "5h", "3 days", "3 weeks".
    private static func duration(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours < 1 { return "<1h" }
        if hours < 48 { return "\(Int(hours.rounded()))h" }
        let days = hours / 24
        if days < 14 { return "\(Int(days.rounded())) days" }
        return "\(Int((days / 7).rounded())) weeks"
    }
}
