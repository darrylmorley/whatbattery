import Foundation

/// Turns a stream of snapshots into discrete alerts, firing each rule once per
/// crossing rather than on every refresh. A rule "arms" when its condition is
/// false and "fires + disarms" on the rising edge into true; it re-arms only
/// after the value crosses back, so a value hovering at the threshold (or a 5s
/// refresh tick) does not spam the user.
///
/// Pure and platform-free: holds only the set of currently-tripped rule kinds.
/// Stateful, so the owner keeps one instance across refreshes (not Sendable;
/// used on the main actor by the notification manager).
public final class ThresholdEvaluator {
    private var active: Set<BatteryAlert.Kind> = []

    public init() {}

    /// Evaluate one snapshot against the settings, mutating internal crossing
    /// state and returning the alerts that should fire now (usually none).
    public func evaluate(_ snapshot: BatterySnapshot, settings: NotificationSettings) -> [BatteryAlert] {
        var fired: [BatteryAlert] = []

        let charge = snapshot.currentChargePercent
        let temp = snapshot.temperatureCelsius

        edge(
            .chargeHigh,
            condition: settings.chargeHighEnabled && charge >= settings.chargeHighThreshold,
            alert: .chargeHigh(charge),
            into: &fired
        )

        edge(
            .chargeLow,
            condition: settings.chargeLowEnabled && charge <= settings.chargeLowThreshold,
            alert: .chargeLow(charge),
            into: &fired
        )

        edge(
            .temperatureHigh,
            condition: settings.temperatureHighEnabled && temp >= settings.temperatureHighThreshold,
            alert: .temperatureHigh(temp),
            into: &fired
        )

        if let health = snapshot.healthPercent {
            edge(
                .healthBelow,
                condition: settings.healthMilestoneEnabled && health < Double(settings.healthMilestoneThreshold),
                alert: .healthBelow(settings.healthMilestoneThreshold),
                into: &fired
            )
        } else {
            // No health reading: treat the rule as not tripped so it re-arms.
            active.remove(.healthBelow)
        }

        return fired
    }

    /// Fire on the rising edge (condition true and not already active); clear the
    /// active flag when the condition is false so the rule can fire again later.
    private func edge(
        _ kind: BatteryAlert.Kind,
        condition: Bool,
        alert: @autoclosure () -> BatteryAlert,
        into fired: inout [BatteryAlert]
    ) {
        if condition {
            if !active.contains(kind) {
                active.insert(kind)
                fired.append(alert())
            }
        } else {
            active.remove(kind)
        }
    }
}
