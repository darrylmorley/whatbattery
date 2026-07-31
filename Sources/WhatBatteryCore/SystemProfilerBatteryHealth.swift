import Foundation

/// What macOS itself says about the battery, from the Health Information block
/// of `system_profiler SPPowerDataType`:
///
/// ```
/// Health Information:
///     Cycle Count: 59
///     Condition: Normal
///     Maximum Capacity: 99%
/// ```
///
/// Both values matter, for different reasons. The condition is Apple's service
/// verdict. The capacity percentage is the number the user sees in System
/// Settings, and it routinely differs from the health we compute ourselves:
/// ours is `NominalChargeCapacity / DesignCapacity` unrounded, which is the
/// gauge's own revisable estimate and moves about a point day to day, while
/// Apple's is whole-percent and steady. Showing only ours means anyone who
/// cross-checks Settings concludes we are broken, so we show both and let the
/// gap explain itself.
public struct SystemProfilerBatteryHealth: Equatable, Sendable {
    public let condition: BatteryCondition
    /// Apple's "Maximum Capacity", whole percent. Nil when the line is absent
    /// (older macOS, no battery, or a parse we did not recognise).
    public let maximumCapacityPercent: Int?

    public static let unknown = SystemProfilerBatteryHealth(condition: .unknown, maximumCapacityPercent: nil)

    public init(condition: BatteryCondition, maximumCapacityPercent: Int?) {
        self.condition = condition
        self.maximumCapacityPercent = maximumCapacityPercent
    }

    /// One pass over the output, picking up both fields. Labels are matched
    /// anywhere in the text rather than by tracking the enclosing block: each
    /// appears once in `SPPowerDataType`, and a state machine would be more to
    /// get wrong than it saves.
    public static func from(systemProfilerOutput output: String) -> SystemProfilerBatteryHealth {
        var condition = BatteryCondition.unknown
        var capacity: Int?

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let value = value(of: "Condition:", in: line) {
                condition = BatteryCondition.from(conditionLabel: value)
            } else if let value = value(of: "Maximum Capacity:", in: line) {
                capacity = percent(from: value)
            }
        }
        return SystemProfilerBatteryHealth(condition: condition, maximumCapacityPercent: capacity)
    }

    private static func value(of label: String, in line: String) -> String? {
        guard line.hasPrefix(label) else { return nil }
        return line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
    }

    /// "99%" -> 99. Anything that is not a plain percentage is dropped rather
    /// than guessed at: a wrong health figure is worse than a missing one.
    private static func percent(from value: String) -> Int? {
        let digits = value.prefix { $0.isNumber }
        guard !digits.isEmpty, let parsed = Int(digits), (0...100).contains(parsed) else { return nil }
        return parsed
    }
}
