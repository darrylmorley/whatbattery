import Foundation

/// Lifetime statistics computed from a set of history samples. Pure and
/// testable; the analyzer UI renders it.
public struct LifetimeSummary: Equatable, Sendable {
    public let sampleCount: Int
    public let firstSample: Date?
    public let lastSample: Date?

    public let minTemperatureC: Double?
    public let avgTemperatureC: Double?
    public let maxTemperatureC: Double?

    public let minVoltageMV: Int?
    public let maxVoltageMV: Int?

    /// Largest charge power seen (positive watts).
    public let maxChargeW: Double?
    /// Largest discharge power seen (magnitude of negative watts).
    public let maxDischargeW: Double?

    public let latestHealthPercent: Double?
    public let latestCycleCount: Int?

    /// The span actually covered by the samples (last minus first).
    public var monitoredSpan: TimeInterval? {
        guard let first = firstSample, let last = lastSample else { return nil }
        return last.timeIntervalSince(first)
    }

    public static let empty = LifetimeSummary(
        sampleCount: 0, firstSample: nil, lastSample: nil,
        minTemperatureC: nil, avgTemperatureC: nil, maxTemperatureC: nil,
        minVoltageMV: nil, maxVoltageMV: nil,
        maxChargeW: nil, maxDischargeW: nil,
        latestHealthPercent: nil, latestCycleCount: nil
    )

    public static func compute(from samples: [BatterySample]) -> LifetimeSummary {
        guard !samples.isEmpty else { return .empty }

        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let temps = samples.map(\.temperatureCelsius)
        let volts = samples.map(\.voltageMillivolts)
        let powers = samples.map(\.powerWatts)
        let charges = powers.filter { $0 > 0 }
        let discharges = powers.filter { $0 < 0 }.map(abs)

        return LifetimeSummary(
            sampleCount: samples.count,
            firstSample: sorted.first?.timestamp,
            lastSample: sorted.last?.timestamp,
            minTemperatureC: temps.min(),
            avgTemperatureC: temps.reduce(0, +) / Double(temps.count),
            maxTemperatureC: temps.max(),
            minVoltageMV: volts.min(),
            maxVoltageMV: volts.max(),
            maxChargeW: charges.max(),
            maxDischargeW: discharges.max(),
            latestHealthPercent: sorted.last?.healthPercent,
            latestCycleCount: sorted.last?.cycleCount
        )
    }
}
