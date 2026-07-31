import XCTest
@testable import WhatBatteryCore

final class AccessoryRuntimeFormattingTests: XCTestCase {
    func testMinutesTier() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(40 * 60), "40m")
    }

    func testMinutesTierNeverSaysZero() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(10), "1m")
    }

    func testHoursTier() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(5 * 3_600), "5h")
    }

    func testDaysTier() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(3 * 86_400), "3 days")
    }

    func testWeeksTier() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(21 * 86_400), "3 weeks")
    }

    func testBoundaryRoundingPromotesToTheNextUnit() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(59.6 * 60), "1h")
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(47.9 * 3_600), "2 days")
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(13.9 * 86_400), "2 weeks")
    }

    func testJustBelowBoundariesStayInTheirUnit() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(59.4 * 60), "59m")
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(47.4 * 3_600), "47h")
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(13.4 * 86_400), "13 days")
    }

    func testZeroAndNegativeFloorAtOneMinute() {
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(0), "1m")
        XCTAssertEqual(AccessoryRuntimeFormatting.duration(-300), "1m")
    }

    func testTimeToEmptyDefaultFraming() {
        XCTAssertEqual(AccessoryRuntimeFormatting.timeToEmpty(5 * 3_600), "About 5h left")
    }

    func testTimeToEmptyListeningFramingForHeadphones() {
        XCTAssertEqual(
            AccessoryRuntimeFormatting.timeToEmpty(40 * 60, kind: .headphones),
            "About 40m of listening left"
        )
    }

    func testTimeToEmptyNonHeadphoneKindsUseDefaultFraming() {
        XCTAssertEqual(
            AccessoryRuntimeFormatting.timeToEmpty(2 * 86_400, kind: .mouse),
            "About 2 days left"
        )
    }
}
