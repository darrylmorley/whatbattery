import SwiftUI

/// One reading: a quiet label with the value under it.
///
/// The window used to list these as label-then-value rows pinned to the left
/// margin, which left most of a 760pt window empty and made eight readings a
/// column of text to scan top to bottom. Stacked tiles flow across the width
/// instead, and putting the value on its own line lets it carry weight without
/// fighting the label.
public struct MetricTile<Value: View>: View {
    private let label: String
    private let value: Value

    public init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension MetricTile where Value == Text {
    /// The common case: a plain string reading.
    init(_ label: String, _ value: String) {
        self.init(label) {
            Text(value)
        }
    }
}

/// Tiles laid out across the available width, wrapping as the window narrows.
/// `minimum` is per column, so a wider window gets more columns rather than
/// wider ones.
public struct MetricGrid<Content: View>: View {
    private let minimum: CGFloat
    private let content: Content

    public init(minimum: CGFloat = 150, @ViewBuilder content: () -> Content) {
        self.minimum = minimum
        self.content = content()
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum), spacing: 20, alignment: .leading)],
            alignment: .leading,
            spacing: 14
        ) {
            content
        }
    }
}
