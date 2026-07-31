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

    /// "About 5h left" / "About 40m of listening left" for headphones.
    static func timeToEmpty(_ seconds: TimeInterval, kind: Accessory.Kind = .other) -> String {
        AccessoryRuntimeFormatting.timeToEmpty(seconds, kind: kind)
    }
}
