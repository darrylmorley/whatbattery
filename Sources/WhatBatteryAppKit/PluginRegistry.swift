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

    // Called by the monitor on every refresh, on the main actor: the type now
    // says so, so an off-actor caller fails to compile instead of trapping at
    // runtime inside a hook's assumeIsolated. The history plugin registers one
    // and throttles internally to the sampling cadence.
    public private(set) var sampleHooks: [@MainActor @Sendable (BatterySnapshot) -> Void] = []
    public func register(sampleHook: @escaping @MainActor @Sendable (BatterySnapshot) -> Void) {
        sampleHooks.append(sampleHook)
    }

    // Called by the monitor whenever the accessory list refreshes (slow cadence).
    // The Pro module registers one to record history and fire low-battery alerts.
    public private(set) var accessorySampleHooks: [@MainActor @Sendable ([Accessory]) -> Void] = []
    public func register(accessorySampleHook: @escaping @MainActor @Sendable ([Accessory]) -> Void) {
        accessorySampleHooks.append(accessorySampleHook)
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

    // A short advisory pinned above the This Mac overview when the recorded
    // history shows a habit worth acting on. Deliberately has no upsell
    // fallback: an advert at the top of the free app's first screen would be
    // obnoxious, and the section renders nothing when there is nothing to say.
    public private(set) var advisorySectionBuilder: (@MainActor () -> AnyView)?
    public func register(advisorySection: @escaping @MainActor () -> AnyView) {
        advisorySectionBuilder = advisorySection
    }

    // The charging-session / charger-verdict view injected into the main window's
    // This Mac tab, below the Lifetime Analyzer, gated by licence. Nil in the free
    // build (the public mirror's no-op bootstrap never registers it), so the
    // section is simply absent there.
    public private(set) var chargingSectionBuilder: (@MainActor () -> AnyView)?
    public func register(chargingSection: @escaping @MainActor () -> AnyView) {
        chargingSectionBuilder = chargingSection
    }

    // The per-app power ("What's using power") view injected into the main
    // window's This Mac tab below the Overview, gated by licence. Nil in the
    // free build (the public mirror's no-op bootstrap never registers it), so
    // the window shows a Pro upsell instead.
    public private(set) var appPowerSectionBuilder: (@MainActor () -> AnyView)?
    public func register(appPowerSection: @escaping @MainActor () -> AnyView) {
        appPowerSectionBuilder = appPowerSection
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

    // The accessory history/alerts view injected into the main window's
    // Accessories tab below the free live list, gated by licence. Nil in the free
    // build, so the window shows a Pro upsell there instead.
    public private(set) var accessoriesSectionBuilder: (@MainActor () -> AnyView)?
    public func register(accessoriesSection: @escaping @MainActor () -> AnyView) {
        accessoriesSectionBuilder = accessoriesSection
    }

    // A Pro discharge estimate (seconds until empty) for an accessory id, derived
    // from its recorded history. Nil in the free build, and returns nil per-id
    // until there's enough history (or while locked), so the free live card shows
    // the "time till empty" line only when Pro has a real figure.
    public private(set) var accessoryEstimateProvider: (@MainActor (String) -> TimeInterval?)?
    public func register(accessoryEstimateProvider provider: @escaping @MainActor (String) -> TimeInterval?) {
        accessoryEstimateProvider = provider
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
