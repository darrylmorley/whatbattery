import SwiftUI

/// The standard inset section card: padded content on a subtle hierarchical fill
/// with the shared corner radius. Replaces hand-rolled
/// `RoundedRectangle(...).fill(Color.secondary.opacity(...))` so every Pro card
/// (runway, charging) shares one look and adapts to the system's fill levels.
public struct CardBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(12)
            .background(.quaternary, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}

public extension View {
    /// Wraps the view in the standard inset card (padding plus a subtle rounded
    /// fill). See `CardBackground`.
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}
