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

    // MARK: - Power line

    private func snapshot(watts: Double, state: ChargingState, adapter: AdapterInfo?) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            designCapacitymAh: 6249,
            fullChargeCapacitymAh: 6220,
            healthPercent: 99.5,
            cycleCount: 42,
            designCycleCount: 1000,
            currentChargePercent: 100,
            currentChargemAh: 6220,
            chargingState: state,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: nil,
            voltageMillivolts: 13222,
            amperageMilliamps: 0,
            powerWatts: watts,
            temperatureCelsius: 30,
            adapter: adapter,
            deviceModel: "Mac17,2",
            batterySerial: nil,
            manufactureDate: nil
        )
    }

    /// The reason this exists: "0.0 W  (100W pd charger)" is correct but reads
    /// as a fault next to a 100W label, so a zero reading on AC has to say why.
    func testPowerLineExplainsZeroWattsOnAC() {
        let charger = AdapterInfo(watts: 100, name: "pd charger")
        XCTAssertEqual(
            BatteryFormatter.powerLine(snapshot(watts: 0, state: .full, adapter: charger)),
            "0.0 W, fully charged  (100W pd charger)"
        )
        XCTAssertEqual(
            BatteryFormatter.powerLine(snapshot(watts: 0, state: .acNoCharge, adapter: charger)),
            "0.0 W, not charging  (100W pd charger)"
        )
    }

    func testPowerLineLeavesRealReadingsAlone() {
        let charger = AdapterInfo(watts: 100, name: "pd charger")
        XCTAssertEqual(
            BatteryFormatter.powerLine(snapshot(watts: 58.2, state: .charging, adapter: charger)),
            "+58.2 W  (100W pd charger)"
        )
        XCTAssertEqual(
            BatteryFormatter.powerLine(snapshot(watts: -8.5, state: .discharging, adapter: nil)),
            "-8.5 W"
        )
    }

    /// Discharging at a rate that rounds to 0.0 W must not claim to be charged:
    /// only the on-AC states earn an explanation.
    func testPowerLineDoesNotExplainZeroWhileDischarging() {
        XCTAssertEqual(
            BatteryFormatter.powerLine(snapshot(watts: -0.01, state: .discharging, adapter: nil)),
            "-0.0 W"
        )
    }

    func testPowerLineHonoursTheReportSeparator() {
        let charger = AdapterInfo(watts: 100, name: "pd charger")
        XCTAssertEqual(
            BatteryFormatter.powerLine(snapshot(watts: 58.2, state: .charging, adapter: charger), adapterSeparator: " "),
            "+58.2 W (100W pd charger)"
        )
    }
}
