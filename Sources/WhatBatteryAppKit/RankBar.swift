import SwiftUI

/// A bar behind a row, scaled to that row's share of the largest value.
///
/// A ranked list of numbers makes the reader compare them; a bar shows the
/// answer before any of them are read. Kept behind the content rather than
/// beside it so the row stays one line and the figures stay aligned.
public struct RankBar: ViewModifier {
    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = fraction
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        content.background(alignment: .leading) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(0.16))
                    .frame(width: geometry.size.width * clamped)
            }
        }
        .accessibilityHidden(false)
    }

    /// Guards against a NaN or a negative from an empty or odd data set, either
    /// of which would trap when SwiftUI resolves the frame.
    private var clamped: Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }
}

public extension View {
    func rankBar(fraction: Double, tint: Color = .accentColor) -> some View {
        modifier(RankBar(fraction: fraction, tint: tint))
    }
}
