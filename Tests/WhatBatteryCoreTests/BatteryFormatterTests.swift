import XCTest
@testable import WhatBatteryCore

final class BatteryFormatterTests: XCTestCase {
    func testHealthPercentKeepsOneDecimal() {
        // The bug this guards: 99.5% must not round up to a misleading "100%".
        XCTAssertEqual(BatteryFormatter.healthPercent(99.536), "99.5%")
        XCTAssertEqual(BatteryFormatter.healthPercent(97.1), "97.1%")
    }

    func testHealthPercentCapsAtOneHundred() {
        // A new battery can read slightly over design; cap the display at 100.
        XCTAssertEqual(BatteryFormatter.healthPercent(100.4), "100.0%")
        XCTAssertEqual(BatteryFormatter.healthPercent(100.0), "100.0%")
    }

    func testHealthPercentUnknown() {
        XCTAssertEqual(BatteryFormatter.healthPercent(nil), "unknown")
    }

    func testHealthLineUsesOneDecimal() {
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            designCapacitymAh: 6249,
            fullChargeCapacitymAh: 6220,
            healthPercent: 6220.0 / 6249.0 * 100,
            cycleCount: 42,
            designCycleCount: 1000,
            currentChargePercent: 100,
            currentChargemAh: 6220,
            chargingState: .full,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: nil,
            voltageMillivolts: 13222,
            amperageMilliamps: 0,
            powerWatts: 0,
            temperatureCelsius: 30,
            adapter: nil,
            deviceModel: "Mac17,2",
            batterySerial: nil,
            manufactureDate: nil
        )
        let line = BatteryFormatter.health(snapshot)
        XCTAssertTrue(line.hasPrefix("99.5%"), "expected 99.5% prefix, got: \(line)")
        XCTAssertTrue(line.contains("6,220"))
        XCTAssertTrue(line.contains("6,249"))
    }
}
