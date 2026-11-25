import SwiftUI

/// The standard inset card: padded content with the shared corner radius,
/// used for a card inside a `SectionCard` (or, for the advisory banner, on the
/// window itself).
///
/// It uses the same surface and hairline as `SectionCard`. A grey fill was
/// designed for cards sitting on the grey window, and once every section moved
/// onto a white `SectionCard` it rendered as a grey box inside a white one.
/// The matching surface keeps a nested card as an outlined panel, and a card
/// on the window as a white card beside the sections.
public struct CardBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Theme.cardSurface, in: .rect(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

public extension View {
    /// Wraps the view in the standard inset card (padding, the card surface and
    /// a hairline edge). See `CardBackground`.
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}
