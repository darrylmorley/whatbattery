import XCTest
@testable import WhatBatteryCore

final class LifetimeSummaryTests: XCTestCase {
    private func sample(
        at t: TimeInterval,
        temp: Double,
        voltage: Int,
        power: Double,
        cycles: Int = 50,
        health: Double? = 95
    ) -> BatterySample {
        BatterySample(
            timestamp: Date(timeIntervalSince1970: t),
            chargePercent: 50,
            temperatureCelsius: temp,
            voltageMillivolts: voltage,
            powerWatts: power,
            cycleCount: cycles,
            healthPercent: health
        )
    }

    func testEmptyIsAllNil() {
        let summary = LifetimeSummary.compute(from: [])
        XCTAssertEqual(summary, .empty)
        XCTAssertEqual(summary.sampleCount, 0)
        XCTAssertNil(summary.monitoredSpan)
    }

    func testAggregates() {
        let samples = [
            sample(at: 100, temp: 20, voltage: 11_500, power: 30),    // charging
            sample(at: 200, temp: 35, voltage: 12_500, power: -18),   // discharging
            sample(at: 300, temp: 25, voltage: 12_000, power: -5),
        ]
        let s = LifetimeSummary.compute(from: samples)

        XCTAssertEqual(s.sampleCount, 3)
        XCTAssertEqual(s.minTemperatureC, 20)
        XCTAssertEqual(s.maxTemperatureC, 35)
        XCTAssertEqual(s.avgTemperatureC!, 26.666, accuracy: 0.01)
        XCTAssertEqual(s.minVoltageMV, 11_500)
        XCTAssertEqual(s.maxVoltageMV, 12_500)
        XCTAssertEqual(s.maxChargeW, 30)        // only positive
        XCTAssertEqual(s.maxDischargeW, 18)     // magnitude of most-negative
        XCTAssertEqual(s.monitoredSpan, 200)    // 300 - 100
    }

    func testLatestUsesNewestByTimestampNotOrder() {
        // Out-of-order input; latest health/cycles must come from newest ts.
        let samples = [
            sample(at: 300, temp: 25, voltage: 12_000, power: -5, cycles: 60, health: 90),
            sample(at: 100, temp: 20, voltage: 11_500, power: 30, cycles: 40, health: 99),
        ]
        let s = LifetimeSummary.compute(from: samples)
        XCTAssertEqual(s.latestCycleCount, 60)
        XCTAssertEqual(s.latestHealthPercent, 90)
    }

    func testHandlesNoChargeOrNoDischarge() {
        let onlyDischarge = [sample(at: 100, temp: 25, voltage: 12_000, power: -10)]
        let s = LifetimeSummary.compute(from: onlyDischarge)
        XCTAssertNil(s.maxChargeW)
        XCTAssertEqual(s.maxDischargeW, 10)
    }

    func testOnlyChargingHasNilDischarge() {
        let s = LifetimeSummary.compute(from: [sample(at: 100, temp: 25, voltage: 12_000, power: 12)])
        XCTAssertEqual(s.maxChargeW, 12)
        XCTAssertNil(s.maxDischargeW)
    }

    func testAllZeroPowerHasNilPeaks() {
        let samples = [
            sample(at: 100, temp: 25, voltage: 12_000, power: 0),
            sample(at: 200, temp: 25, voltage: 12_000, power: 0),
        ]
        let s = LifetimeSummary.compute(from: samples)
        XCTAssertNil(s.maxChargeW)
        XCTAssertNil(s.maxDischargeW)
    }

    func testSingleSampleSpanIsZero() {
        let s = LifetimeSummary.compute(from: [sample(at: 500, temp: 22, voltage: 12_000, power: -5)])
        XCTAssertEqual(s.sampleCount, 1)
        XCTAssertEqual(s.monitoredSpan, 0)
        XCTAssertEqual(s.minTemperatureC, 22)
        XCTAssertEqual(s.avgTemperatureC, 22)
        XCTAssertEqual(s.maxTemperatureC, 22)
    }
}
