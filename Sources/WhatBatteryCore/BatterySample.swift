import Foundation

/// One persisted point in the battery's lifetime history. Written by the Pro
/// history sampler, read by the Lifetime Analyzer.
public struct BatterySample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let chargePercent: Int
    public let temperatureCelsius: Double
    public let voltageMillivolts: Int
    public let powerWatts: Double
    public let cycleCount: Int
    public let healthPercent: Double?

    public init(
        timestamp: Date,
        chargePercent: Int,
        temperatureCelsius: Double,
        voltageMillivolts: Int,
        powerWatts: Double,
        cycleCount: Int,
        healthPercent: Double?
    ) {
        self.timestamp = timestamp
        self.chargePercent = chargePercent
        self.temperatureCelsius = temperatureCelsius
        self.voltageMillivolts = voltageMillivolts
        self.powerWatts = powerWatts
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
    }

    /// Distil a live snapshot into a history sample.
    public init(snapshot: BatterySnapshot) {
        self.init(
            timestamp: snapshot.timestamp,
            chargePercent: snapshot.currentChargePercent,
            temperatureCelsius: snapshot.temperatureCelsius,
            voltageMillivolts: snapshot.voltageMillivolts,
            powerWatts: snapshot.powerWatts,
            cycleCount: snapshot.cycleCount,
            healthPercent: snapshot.healthPercent
        )
    }
}
