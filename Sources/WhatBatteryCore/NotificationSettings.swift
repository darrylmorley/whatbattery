import Foundation

/// User-configured thresholds for battery notifications. Pure value type so the
/// evaluator stays testable; the Plugins target persists it in UserDefaults and
/// the settings UI edits it.
///
/// Everything is off by default: alerts are opt-in, so a fresh install never
/// nags and never needs notification permission until the user enables one.
public struct NotificationSettings: Codable, Equatable, Sendable {
    public var chargeHighEnabled: Bool
    public var chargeHighThreshold: Int

    public var chargeLowEnabled: Bool
    public var chargeLowThreshold: Int

    public var temperatureHighEnabled: Bool
    public var temperatureHighThreshold: Double

    public var healthMilestoneEnabled: Bool
    public var healthMilestoneThreshold: Int

    public init(
        chargeHighEnabled: Bool = false,
        chargeHighThreshold: Int = 80,
        chargeLowEnabled: Bool = false,
        chargeLowThreshold: Int = 20,
        temperatureHighEnabled: Bool = false,
        temperatureHighThreshold: Double = 40,
        healthMilestoneEnabled: Bool = false,
        healthMilestoneThreshold: Int = 80
    ) {
        self.chargeHighEnabled = chargeHighEnabled
        self.chargeHighThreshold = chargeHighThreshold
        self.chargeLowEnabled = chargeLowEnabled
        self.chargeLowThreshold = chargeLowThreshold
        self.temperatureHighEnabled = temperatureHighEnabled
        self.temperatureHighThreshold = temperatureHighThreshold
        self.healthMilestoneEnabled = healthMilestoneEnabled
        self.healthMilestoneThreshold = healthMilestoneThreshold
    }

    public static let `default` = NotificationSettings()

    /// True when at least one rule is enabled, so the caller can skip work (and
    /// avoid prompting for permission) when nothing is configured.
    public var anyEnabled: Bool {
        chargeHighEnabled || chargeLowEnabled || temperatureHighEnabled || healthMilestoneEnabled
    }
}
