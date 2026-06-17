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

    func testMinutesOrNilTreatsSentinelsAsNil() {
        XCTAssertNil(BatteryHealth.minutesOrNil(0))
        XCTAssertNil(BatteryHealth.minutesOrNil(65535))
        XCTAssertEqual(BatteryHealth.minutesOrNil(47), 47)
    }
}
