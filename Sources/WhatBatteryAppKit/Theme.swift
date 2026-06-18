import SwiftUI

/// Shared visual constants so the app and its Pro plugins render one uniform
/// design. Colours, corner radii, and the like live here rather than being
/// re-derived per view, so a tweak lands everywhere at once.
public enum Theme {
    /// Corner radius for the standard inset section cards.
    public static let cardCornerRadius: CGFloat = 12

    /// Battery-health colour band, keyed to Apple's service thresholds: amber at
    /// "service recommended" (80%), red when the battery is genuinely poor (60%).
    /// Every health readout shares this so the bands never drift apart.
    public static func health(_ percent: Double) -> Color {
        switch percent {
        case ..<60: return .red
        case ..<80: return .orange
        default: return .green
        }
    }

    /// Charge-level colour band for accessories and live charge: red when nearly
    /// flat, amber when low, green otherwise.
    public static func level(_ percent: Int) -> Color {
        switch percent {
        case ..<15: return .red
        case ..<30: return .orange
        default: return .green
        }
    }
}
