import Foundation

/// A CLI subcommand contributed by a plugin (licence, history export, ...). The
/// free build registers none; the private Pro plugin registers its commands in
/// `bootstrapPlugins`.
public protocol CLICommand: Sendable {
    /// Flags that trigger this command, e.g. `["--activate"]`.
    var flagNames: [String] { get }
    /// Help lines shown under `--help`.
    var helpLines: String { get }
    /// Run the command and return a process exit code (0 success, nonzero
    /// failure). `@MainActor` so commands can touch the main-actor licence
    /// manager; `async` because licence commands hit the network.
    @MainActor func run(_ args: [String]) async -> Int32
}

public extension CLICommand {
    /// True when any of the command's flags appears in the arguments.
    func matches(_ args: [String]) -> Bool {
        args.contains { flagNames.contains($0) }
    }
}
