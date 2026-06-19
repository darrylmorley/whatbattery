import SwiftUI

/// A small coloured status capsule, e.g. "Underpowered charger" or "Wearing
/// faster than usual". One definition so every pill matches. Uses `.caption`
/// rather than the system's extremely small `.caption2`.
public struct StatusPill: View {
    private let text: String
    private let tint: Color

    public init(_ text: String, tint: Color = .orange) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .scaledFont(.caption, weight: .semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.2), in: .capsule)
            .foregroundStyle(tint)
    }
}
