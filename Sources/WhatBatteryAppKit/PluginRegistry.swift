import SwiftUI
import WhatBatteryCore

/// The Pro unlock state, observable by the app without it knowing anything about
/// the licence implementation. The Pro module (`WhatBatteryPlugins`) drives this;
/// in the public/free build nothing sets it, so it stays `false`. This is the one
/// seam the app uses to gate Pro detail, keeping every licence symbol inside the
/// Pro module so the app compiles against the no-op public stub.
@MainActor
public final class ProStatus: ObservableObject {
    @Published public var isUnlocked: Bool = false
    public init() {}
}

/// Where plugins register their extension points. Built free of IOKit so both
/// the app and the CLI can own the shared registry. `@MainActor` because the
/// app touches it from the main actor (menu, settings, launch).
@MainActor
public final class PluginRegistry {
    public static let shared = PluginRegistry()

    public init() {}

    /// Pro unlock state, set by the Pro module and observed by the app.
    public let proStatus = ProStatus()

    // Run once at launch (licence revalidation, history sampler start).
    public private(set) var launchHooks: [() async -> Void] = []
    public func register(launchHook: @escaping () async -> Void) {
        launchHooks.append(launchHook)
    }

    // Called by the monitor on every refresh. The history plugin registers one
    // and throttles internally to the sampling cadence.
    public private(set) var sampleHooks: [@Sendable (BatterySnapshot) -> Void] = []
    public func register(sampleHook: @escaping @Sendable (BatterySnapshot) -> Void) {
        sampleHooks.append(sampleHook)
    }

    // Rows added to the menu bar dropdown footer.
    public private(set) var menuItems: [PluginMenuItem] = []
    public func register(menuItem: PluginMenuItem) {
        menuItems.append(menuItem)
    }

    // Sections injected into Settings (licence, notifications).
    public private(set) var settingsSections: [@MainActor () -> AnyView] = []
    public func register(settingsSection: @escaping @MainActor () -> AnyView) {
        settingsSections.append(settingsSection)
    }

    // The History view injected into the main window, gated by licence.
    public private(set) var historySectionBuilder: (@MainActor () -> AnyView)?
    public func register(historySection: @escaping @MainActor () -> AnyView) {
        historySectionBuilder = historySection
    }

    // The iPhone/iPad view injected into the main window's iDevice tab, gated by
    // licence. Nil in the free build (the public mirror's no-op bootstrap never
    // registers it), so the window shows a Pro upsell instead.
    public private(set) var iDeviceSectionBuilder: (@MainActor () -> AnyView)?
    public func register(iDeviceSection: @escaping @MainActor () -> AnyView) {
        iDeviceSectionBuilder = iDeviceSection
    }

    // The long-term Battery Health History view injected into the main window's
    // History tab, gated by licence. Nil in the free build (the public mirror's
    // no-op bootstrap never registers it), so the window shows a Pro upsell.
    public private(set) var healthHistorySectionBuilder: (@MainActor () -> AnyView)?
    public func register(healthHistorySection: @escaping @MainActor () -> AnyView) {
        healthHistorySectionBuilder = healthHistorySection
    }

    // CLI subcommands.
    public private(set) var cliCommands: [CLICommand] = []
    public func register(cliCommand: CLICommand) {
        cliCommands.append(cliCommand)
    }

    // Footer lines appended to plain CLI output (e.g. the unlicensed-Pro hint).
    // Each returns nil when it has nothing to say.
    public private(set) var cliOutputFooterContributors: [@MainActor () -> String?] = []
    public func register(cliOutputFooter: @escaping @MainActor () -> String?) {
        cliOutputFooterContributors.append(cliOutputFooter)
    }
}
