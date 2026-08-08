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
            batterySerial: nil
        )
        let line = BatteryFormatter.health(snapshot)
        XCTAssertTrue(line.hasPrefix("99.5%"), "expected 99.5% prefix, got: \(line)")
        XCTAssertTrue(line.contains("6,220"))
        XCTAssertTrue(line.contains("6,249"))
    }

    /// The app hides the raw capacities behind a licence, so the CLI has to be
    /// able to hide them too. The percentage itself is free either way.
    func testHealthLineWithoutCapacitiesIsPercentageOnly() {
        let line = BatteryFormatter.health(
            snapshot(watts: 0, state: .full, adapter: nil),
            includeCapacities: false
        )
        XCTAssertEqual(line, "99.5%")
    }

    // MARK: - Current

    func testCurrentLineShowsSignedAmps() {
        XCTAssertEqual(BatteryFormatter.current(snapshot(amperage: -1850, instant: -1850)), "-1.85 A")
        XCTAssertEqual(BatteryFormatter.current(snapshot(amperage: 1500, instant: 1500)), "+1.50 A")
        XCTAssertEqual(BatteryFormatter.current(snapshot(amperage: 0, instant: 0)), "0.00 A")
    }

    /// The unaveraged reading earns its place only when the load has actually
    /// moved; small gaps are rounding noise between two views of one number.
    func testCurrentLineAddsInstantOnlyWhenItDiffers() {
        XCTAssertEqual(BatteryFormatter.current(snapshot(amperage: -1850, instant: -1900)), "-1.85 A")
        XCTAssertEqual(BatteryFormatter.current(snapshot(amperage: -1850, instant: -3200)), "-1.85 A, -3.20 A now")
    }

    /// A gauge that reports no instant figure at all must not read as 0 A of
    /// draw sitting next to a real one.
    func testCurrentLineIgnoresAbsentInstantReading() {
        XCTAssertEqual(BatteryFormatter.current(snapshot(amperage: -1850, instant: 0)), "-1.85 A")
    }

    // MARK: - Charge line

    /// The gauge's own critical flag, which can fire at a percentage that still
    /// looks comfortable, so the line has to say so.
    func testChargeLineSurfacesCriticalFlag() {
        let critical = snapshot(amperage: -1850, instant: -1850, state: .discharging, atCriticalLevel: true)
        XCTAssertEqual(BatteryFormatter.chargeLine(critical), "6%, on battery, critically low")

        let normal = snapshot(amperage: -1850, instant: -1850, state: .discharging, atCriticalLevel: false)
        XCTAssertEqual(BatteryFormatter.chargeLine(normal), "6%, on battery")
    }

    private func snapshot(
        amperage: Int,
        instant: Int,
        state: ChargingState = .discharging,
        atCriticalLevel: Bool = false
    ) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            designCapacitymAh: 6249,
            fullChargeCapacitymAh: 6220,
            healthPercent: 99.5,
            cycleCount: 42,
            designCycleCount: 1000,
            currentChargePercent: 6,
            currentChargemAh: 380,
            chargingState: state,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: nil,
            atCriticalLevel: atCriticalLevel,
            voltageMillivolts: 13222,
            amperageMilliamps: amperage,
            instantAmperageMilliamps: instant,
            powerWatts: -24.5,
            temperatureCelsius: 30,
            adapter: nil,
            deviceModel: "Mac17,2",
            batterySerial: nil
        )
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
            batterySerial: nil
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
