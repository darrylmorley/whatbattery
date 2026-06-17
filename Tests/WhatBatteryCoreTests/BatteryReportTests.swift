import XCTest
@testable import WhatBatteryCore

final class BatteryReportTests: XCTestCase {
    private func snapshot(
        model: String = "MacBook Pro",
        cycles: Int = 120,
        designCycles: Int = 1000,
        health: Double? = 92,
        serial: String? = "ABC123"
    ) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            designCapacitymAh: 5000,
            fullChargeCapacitymAh: 4600,
            healthPercent: health,
            cycleCount: cycles,
            designCycleCount: designCycles,
            currentChargePercent: 80,
            currentChargemAh: 3680,
            chargingState: .discharging,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: 200,
            voltageMillivolts: 12345,
            amperageMilliamps: -1500,
            powerWatts: -18.5,
            temperatureCelsius: 31.2,
            adapter: nil,
            deviceModel: model,
            batterySerial: serial,
            manufactureDate: nil
        )
    }

    private func summary() -> LifetimeSummary {
        LifetimeSummary.compute(from: [
            BatterySample(timestamp: Date(timeIntervalSince1970: 1_699_000_000), chargePercent: 50, temperatureCelsius: 28, voltageMillivolts: 11900, powerWatts: 30, cycleCount: 119, healthPercent: 92),
            BatterySample(timestamp: Date(timeIntervalSince1970: 1_700_000_000), chargePercent: 80, temperatureCelsius: 33, voltageMillivolts: 12400, powerWatts: -20, cycleCount: 120, healthPercent: 92),
        ])
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_500)

    func testCurrentLinesIncludeKeyFields() {
        let report = BatteryReport.make(snapshot: snapshot(), summary: nil, generatedAt: now, appVersion: "1.0")
        let labels = report.currentLines.map(\.label)
        XCTAssertEqual(labels, ["Health", "Charge", "Cycles", "Temperature", "Power", "Voltage", "Battery Serial"])
        XCTAssertTrue(report.currentLines.first { $0.label == "Cycles" }?.value.contains("120") ?? false)
    }

    func testSerialOmittedWhenNil() {
        let report = BatteryReport.make(snapshot: snapshot(serial: nil), summary: nil, generatedAt: now, appVersion: "1.0")
        XCTAssertFalse(report.currentLines.contains { $0.label == "Battery Serial" })
    }

    func testNilSummaryYieldsNoLifetimeLines() {
        let report = BatteryReport.make(snapshot: snapshot(), summary: nil, generatedAt: now, appVersion: "1.0")
        XCTAssertTrue(report.lifetimeLines.isEmpty)
    }

    func testSummaryPopulatesLifetimeLines() {
        let report = BatteryReport.make(snapshot: snapshot(), summary: summary(), generatedAt: now, appVersion: "1.0")
        let labels = report.lifetimeLines.map(\.label)
        XCTAssertTrue(labels.contains("Temperature"))
        XCTAssertTrue(labels.contains("Peak charge"))
        XCTAssertTrue(labels.contains("Peak discharge"))
        XCTAssertTrue(labels.contains("Readings"))
    }

    func testPlainTextContainsModelAndSections() {
        let report = BatteryReport.make(snapshot: snapshot(), summary: summary(), generatedAt: now, appVersion: "1.2.3")
        let text = report.plainText
        XCTAssertTrue(text.contains("MacBook Pro"))
        XCTAssertTrue(text.contains("WhatBattery 1.2.3"))
        XCTAssertTrue(text.contains("Current"))
        XCTAssertTrue(text.contains("Lifetime"))
    }

    func testPlainTextOmitsLifetimeWhenNoHistory() {
        let report = BatteryReport.make(snapshot: snapshot(), summary: nil, generatedAt: now, appVersion: "1.0")
        XCTAssertFalse(report.plainText.contains("Lifetime"))
    }
}
