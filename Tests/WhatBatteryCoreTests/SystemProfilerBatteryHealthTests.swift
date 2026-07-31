import XCTest
@testable import WhatBatteryCore

/// The fixture is the real Health Information block from a MacBook Pro (M5) on
/// 2026-07-31, the machine whose 96.9%-vs-99% disagreement prompted showing
/// Apple's figure alongside ours.
final class SystemProfilerBatteryHealthTests: XCTestCase {
    private let realOutput = """
    Power:

        Battery Information:

          Model Information:
              Serial Number: F8YHPU007FN0000VD5
              Device Name: bq40z651
          Charge Information:
              Fully Charged: Yes
              State of Charge (%): 100
          Health Information:
              Cycle Count: 59
              Condition: Normal
              Maximum Capacity: 99%
    """

    func testParsesBothFieldsFromRealOutput() {
        let health = SystemProfilerBatteryHealth.from(systemProfilerOutput: realOutput)
        XCTAssertEqual(health.condition, .normal)
        XCTAssertEqual(health.maximumCapacityPercent, 99)
    }

    func testConditionOnlyOutputStillParses() {
        // Older macOS, or a machine that reports no capacity line.
        let output = "        Health Information:\n            Condition: Service Recommended\n"
        let health = SystemProfilerBatteryHealth.from(systemProfilerOutput: output)
        XCTAssertEqual(health.condition, .serviceRecommended)
        XCTAssertNil(health.maximumCapacityPercent)
    }

    func testNoBatteryOutputIsUnknown() {
        let health = SystemProfilerBatteryHealth.from(systemProfilerOutput: "Power:\n\n    AC Power:\n")
        XCTAssertEqual(health.condition, .unknown)
        XCTAssertNil(health.maximumCapacityPercent)
    }

    func testMalformedCapacityIsDroppedNotGuessed() {
        // A wrong health figure is worse than a missing one.
        let output = "            Condition: Normal\n            Maximum Capacity: unavailable\n"
        let health = SystemProfilerBatteryHealth.from(systemProfilerOutput: output)
        XCTAssertEqual(health.condition, .normal)
        XCTAssertNil(health.maximumCapacityPercent)
    }

    func testOutOfRangeCapacityIsRejected() {
        let output = "            Maximum Capacity: 4200%\n"
        XCTAssertNil(SystemProfilerBatteryHealth.from(systemProfilerOutput: output).maximumCapacityPercent)
    }

    func testConditionShimStillWorksForExistingCallers() {
        XCTAssertEqual(BatteryCondition.from(systemProfilerOutput: realOutput), .normal)
    }
}
