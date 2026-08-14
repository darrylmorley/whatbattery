import XCTest
@testable import WhatBatteryCore

final class BatteryHealthTests: XCTestCase {
    func testHealthPercentNormal() {
        let health = BatteryHealth.healthPercent(fullChargemAh: 4021, designmAh: 4382)
        XCTAssertNotNil(health)
        XCTAssertEqual(health!, 91.76, accuracy: 0.01)
    }

    func testHealthPercentReturnsNilForZeroDesign() {
        XCTAssertNil(BatteryHealth.healthPercent(fullChargemAh: 4000, designmAh: 0))
    }

    func testHealthPercentReturnsNilForZeroFullCharge() {
        XCTAssertNil(BatteryHealth.healthPercent(fullChargemAh: 0, designmAh: 4382))
    }

    func testChargePercentTrustsAppleSiliconPercentMode() {
        // maxCapacity == 100 means CurrentCapacity is already a percentage.
        let pct = BatteryHealth.chargePercent(
            currentCapacityPercent: 68,
            maxCapacityPercent: 100,
            currentmAh: 0,
            fullChargemAh: 0
        )
        XCTAssertEqual(pct, 68)
    }

    func testChargePercentFallsBackTomAhRatio() {
        let pct = BatteryHealth.chargePercent(
            currentCapacityPercent: 0,
            maxCapacityPercent: 0,
            currentmAh: 2000,
            fullChargemAh: 4000
        )
        XCTAssertEqual(pct, 50)
    }

    func testChargePercentClampsToHundred() {
        let pct = BatteryHealth.chargePercent(
            currentCapacityPercent: 0,
            maxCapacityPercent: 0,
            currentmAh: 5000,
            fullChargemAh: 4000
        )
        XCTAssertEqual(pct, 100)
    }

    func testCelsiusConversion() {
        XCTAssertEqual(BatteryHealth.celsius(fromCentiCelsius: 3140), 31.4, accuracy: 0.001)
    }

    /// macOS publishes `Temperature` in the raw SmartBattery format, tenths of a
    /// Kelvin, not centi-Celsius. Read the wrong way this Mac showed 30.70°C
    /// while its own `VirtualTemperature` said 33.89°C.
    func testTemperatureIsDeciKelvinOnAMac() throws {
        XCTAssertEqual(try XCTUnwrap(BatteryHealth.centiCelsius(fromDeciKelvin: 3070)), 3385)
        XCTAssertEqual(
            BatteryHealth.celsius(fromCentiCelsius: try XCTUnwrap(BatteryHealth.centiCelsius(fromDeciKelvin: 3070))),
            33.85, accuracy: 0.001
        )
        // Freezing point, the conversion's anchor.
        XCTAssertEqual(try XCTUnwrap(BatteryHealth.centiCelsius(fromDeciKelvin: 2731)), -5)
        // The corpus extremes, which under the old reading were a nonsensically
        // narrow 29.31°C to 31.94°C.
        XCTAssertEqual(try XCTUnwrap(BatteryHealth.centiCelsius(fromDeciKelvin: 2931)), 1995)
        XCTAssertEqual(try XCTUnwrap(BatteryHealth.centiCelsius(fromDeciKelvin: 3194)), 4625)
    }

    /// Absent or impossible readings come back as nil, so a caller can tell them
    /// from a genuine 0°C.
    func testImpossibleTemperaturesAreRefused() {
        XCTAssertNil(BatteryHealth.centiCelsius(fromDeciKelvin: 0))
        XCTAssertNil(BatteryHealth.centiCelsius(fromDeciKelvin: -50))
        XCTAssertNil(BatteryHealth.centiCelsius(fromDeciKelvin: 100))     // -263°C
        XCTAssertNil(BatteryHealth.centiCelsius(fromDeciKelvin: 65535))   // the SMBus sentinel
        // Malformed input must refuse, not trap: the multiply used to overflow
        // before the plausibility band could reject it.
        XCTAssertNil(BatteryHealth.centiCelsius(fromDeciKelvin: Int.max))
        XCTAssertNil(BatteryHealth.centiCelsius(fromDeciKelvin: Int.max / 9))
    }

    func testPlausibleCentiCelsiusBounds() {
        XCTAssertTrue(BatteryHealth.isPlausibleCentiCelsius(3385))
        XCTAssertTrue(BatteryHealth.isPlausibleCentiCelsius(-3900))    // a cold car
        XCTAssertTrue(BatteryHealth.isPlausibleCentiCelsius(9900))     // a hot dashboard
        XCTAssertFalse(BatteryHealth.isPlausibleCentiCelsius(-4001))
        XCTAssertFalse(BatteryHealth.isPlausibleCentiCelsius(10_001))
    }

    func testMinutesOrNilTreatsSentinelsAsNil() {
        XCTAssertNil(BatteryHealth.minutesOrNil(0))
        XCTAssertNil(BatteryHealth.minutesOrNil(65535))
        XCTAssertEqual(BatteryHealth.minutesOrNil(47), 47)
    }
}
