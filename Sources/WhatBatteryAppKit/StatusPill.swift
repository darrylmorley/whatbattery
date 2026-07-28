import SwiftUI

/// A small coloured status capsule, e.g. "Underpowered charger" or "Wearing
/// faster than usual". One definition so every pill matches. Uses `.caption`
/// rather than the system's extremely small `.caption2`.
///
/// The capsule background uses the vivid band colour; the text uses the
/// text-grade variant, because the vivid system colours are roughly 2:1 as
/// text on a light window and unreadable at caption size.
public struct StatusPill: View {
    private let text: String
    private let status: Theme.Status

    public init(_ text: String, status: Theme.Status = .warning) {
        self.text = text
        self.status = status
    }

    public var body: some View {
        Text(text)
            .scaledFont(.caption, weight: .semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.color(status).opacity(0.2), in: .capsule)
            .foregroundStyle(Theme.textColor(status))
    }
}
