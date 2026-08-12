import SwiftUI

/// The standard inset section card: padded content on a subtle hierarchical fill
/// with the shared corner radius. Replaces hand-rolled
/// `RoundedRectangle(...).fill(Color.secondary.opacity(...))` so every Pro card
/// (runway, charging) shares one look and adapts to the system's fill levels.
public struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(12)
            // Dark keeps the quaternary lift (a lighter card on a darker
            // window, the platform convention, and it reads well). Light
            // inverts that convention if given the same fill: quaternary
            // renders as a flat mid-grey slab on the white window. So light
            // uses the fainter quinary fill and lets a hairline edge define
            // the card instead of the grey.
            .background(
                colorScheme == .dark ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary),
                in: .rect(cornerRadius: Theme.cardCornerRadius)
            )
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                        .strokeBorder(.separator, lineWidth: 1)
                }
            }
    }
}

public extension View {
    /// Wraps the view in the standard inset card (padding plus a subtle rounded
    /// fill). See `CardBackground`.
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}
