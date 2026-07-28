import SwiftUI
import AppKit

/// Shared visual constants so the app and its Pro plugins render one uniform
/// design. Colours, corner radii, and the like live here rather than being
/// re-derived per view, so a tweak lands everywhere at once.
public enum Theme {
    /// Corner radius for the standard inset section cards.
    public static let cardCornerRadius: CGFloat = 12

    /// The three status bands every coloured readout maps into. Keeping the
    /// band, not the colour, as the shared currency means a view can ask for
    /// the right *variant* (vivid for a fill, text-grade for a label) without
    /// each site re-deriving thresholds.
    public enum Status {
        case good, warning, critical
    }

    /// Battery-health band, keyed to Apple's service thresholds: warning at
    /// "service recommended" (80%), critical when the battery is genuinely
    /// poor (60%). Every health readout shares this so the bands never drift.
    public static func healthStatus(_ percent: Double) -> Status {
        switch percent {
        case ..<60: return .critical
        case ..<80: return .warning
        default: return .good
        }
    }

    /// Charge-level band for accessories and live charge: critical when nearly
    /// flat, warning when low, good otherwise.
    public static func levelStatus(_ percent: Int) -> Status {
        switch percent {
        case ..<15: return .critical
        case ..<30: return .warning
        default: return .good
        }
    }

    /// Vivid variant: progress fills, bar tints, capsule backgrounds. NOT for
    /// text on a window background; see `textColor(_:)`.
    public static func color(_ status: Status) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    /// Text-grade variant: dark enough to read as running text. The vivid
    /// system colours are roughly 2:1 against a light window (well under the
    /// 4.5:1 minimum), so the light appearance blends them toward black; the
    /// dark appearance leaves them alone, where they already pass against the
    /// dark background.
    public static func textColor(_ status: Status) -> Color {
        switch status {
        case .good: return dynamic(NSColor.systemGreen, darkenedBy: 0.5)
        case .warning: return dynamic(NSColor.systemOrange, darkenedBy: 0.45)
        case .critical: return dynamic(NSColor.systemRed, darkenedBy: 0.3)
        }
    }

    /// The vivid health colour for a percentage (fills and tints).
    public static func health(_ percent: Double) -> Color {
        color(healthStatus(percent))
    }

    /// The vivid charge-level colour for a percentage (fills and tints).
    public static func level(_ percent: Int) -> Color {
        color(levelStatus(percent))
    }

    /// Text-grade health colour for a percentage.
    public static func healthText(_ percent: Double) -> Color {
        textColor(healthStatus(percent))
    }

    /// Text-grade charge-level colour for a percentage.
    public static func levelText(_ percent: Int) -> Color {
        textColor(levelStatus(percent))
    }

    /// An appearance-tracking colour: the system colour blended toward black in
    /// light mode, untouched in dark. Built on an `NSColor` dynamic provider so
    /// it follows live appearance switches, which a captured `Color` would not.
    private static func dynamic(_ base: NSColor, darkenedBy fraction: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark { return base }
            guard let blended = base.blended(withFraction: fraction, of: .black) else {
                // Verified non-nil for the system colours used today; a future
                // colour swap could hit a space blended() cannot handle, and a
                // silent fallback would quietly reintroduce the 2:1 contrast
                // this exists to fix. Fail loudly in debug, vivid in release.
                assertionFailure("Theme.dynamic: blended(withFraction:) failed for \(base)")
                return base
            }
            return blended
        }))
    }
}
