import XCTest
@testable import WhatBatteryCore

final class BatteryConditionTests: XCTestCase {
    // MARK: - Label mapping

    func testNormalLabel() {
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Normal"), .normal)
    }

    func testServiceRecommendedLabels() {
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Service Recommended"), .serviceRecommended)
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Replace Soon"), .serviceRecommended)
    }

    func testServiceBatteryLabels() {
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Replace Now"), .serviceBattery)
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Service Battery"), .serviceBattery)
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Check Battery"), .serviceBattery)
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Permanent Failure"), .serviceBattery)
    }

    func testUnknownLabel() {
        XCTAssertEqual(BatteryCondition.from(conditionLabel: "Wat"), .unknown)
    }

    // MARK: - system_profiler parsing

    func testParsesConditionFromSystemProfilerOutput() {
        let output = """
        Power:

            Battery Information:
                Model Information:
                    Serial Number: F8YHPU007FN0000VD5
                Health Information:
                    Cycle Count: 42
                    Condition: Normal
                    Maximum Capacity: 100%
        """
        XCTAssertEqual(BatteryCondition.from(systemProfilerOutput: output), .normal)
    }

    func testParsesServiceRecommendedOutput() {
        let output = "        Health Information:\n            Condition: Service Recommended\n"
        XCTAssertEqual(BatteryCondition.from(systemProfilerOutput: output), .serviceRecommended)
    }

    func testNoConditionLineIsUnknown() {
        let output = "Power:\n    AC Charger Information:\n        Connected: Yes\n"
        XCTAssertEqual(BatteryCondition.from(systemProfilerOutput: output), .unknown)
    }

    // MARK: - Display

    func testWarningFlag() {
        XCTAssertFalse(BatteryCondition.normal.isWarning)
        XCTAssertFalse(BatteryCondition.unknown.isWarning)
        XCTAssertTrue(BatteryCondition.serviceRecommended.isWarning)
        XCTAssertTrue(BatteryCondition.serviceBattery.isWarning)
    }

    func testLabels() {
        XCTAssertEqual(BatteryCondition.normal.label, "Normal")
        XCTAssertEqual(BatteryCondition.serviceRecommended.label, "Service Recommended")
        XCTAssertEqual(BatteryCondition.serviceBattery.label, "Service Battery")
    }
}
