import SwiftUI

/// The battery-health bar, shared by the popover, the main window Overview and
/// the iDevice card so they cannot drift apart.
///
/// A plain linear `ProgressView` made 99.6% and 82% look nearly identical, so
/// the bar carries a tick at Apple's 80% service threshold: the number now has
/// a reference point at a glance. The tick stands taller than the track, so it
/// reads against both the filled and unfilled portion no matter where the fill
/// ends.
public struct HealthBar: View {
    private let percent: Double

    /// Apple's "service recommended" threshold, matching `Theme.healthStatus`.
    private static let serviceThreshold = 0.8

    private static let trackHeight: CGFloat = 6
    private static let tickHeight: CGFloat = 12
    private static let tickWidth: CGFloat = 1.5

    public init(percent: Double) {
        self.percent = percent
    }

    public var body: some View {
        GeometryReader { geo in
            let fraction = min(max(percent, 0), 100) / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: Self.trackHeight)
                // The floor keeps a sliver of fill visible at very low health,
                // but only above zero: a 0% battery must render an empty track,
                // not the same blob a 2% one gets.
                if fraction > 0 {
                    Capsule()
                        .fill(Theme.health(percent))
                        .frame(width: max(Self.trackHeight, geo.size.width * fraction), height: Self.trackHeight)
                }
                Rectangle()
                    .fill(.secondary)
                    .frame(width: Self.tickWidth, height: Self.tickHeight)
                    .offset(x: geo.size.width * Self.serviceThreshold - Self.tickWidth / 2)
            }
            .frame(height: Self.tickHeight)
        }
        .frame(height: Self.tickHeight)
        .help("The mark is 80%, Apple's service threshold.")
        .accessibilityElement()
        .accessibilityLabel("Battery health")
        .accessibilityValue("\(Int(percent.rounded())) percent")
    }
}
