import Foundation

/// A menu row a plugin adds to the menu bar dropdown (e.g. "Lifetime Analyzer…").
public struct PluginMenuItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let action: @MainActor @Sendable () -> Void

    public init(id: String, title: String, action: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.title = title
        self.action = action
    }
}
