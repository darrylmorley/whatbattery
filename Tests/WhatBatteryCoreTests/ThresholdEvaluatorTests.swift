import XCTest
@testable import WhatBatteryCore

final class ThresholdEvaluatorTests: XCTestCase {
    private func snapshot(charge: Int, temp: Double = 25, health: Double? = 95) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            designCapacitymAh: 5000,
            fullChargeCapacitymAh: 4500,
            healthPercent: health,
            cycleCount: 10,
            designCycleCount: 1000,
            currentChargePercent: charge,
            currentChargemAh: 4000,
            chargingState: .charging,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: nil,
            voltageMillivolts: 12000,
            amperageMilliamps: 1000,
            powerWatts: 12,
            temperatureCelsius: temp,
            adapter: nil,
            deviceModel: "Mac",
            batterySerial: nil,
            manufactureDate: nil
        )
    }

    func testNoAlertsWhenAllDisabled() {
        let e = ThresholdEvaluator()
        XCTAssertTrue(e.evaluate(snapshot(charge: 100, temp: 99), settings: .default).isEmpty)
    }

    func testChargeHighFiresOncePerCrossing() {
        let e = ThresholdEvaluator()
        var s = NotificationSettings.default
        s.chargeHighEnabled = true
        s.chargeHighThreshold = 80

        XCTAssertTrue(e.evaluate(snapshot(charge: 70), settings: s).isEmpty)   // below
        XCTAssertEqual(e.evaluate(snapshot(charge: 82), settings: s), [.chargeHigh(82)])  // rising edge
        XCTAssertTrue(e.evaluate(snapshot(charge: 90), settings: s).isEmpty)   // still high, no re-fire
        XCTAssertTrue(e.evaluate(snapshot(charge: 75), settings: s).isEmpty)   // dropped, re-arm
        XCTAssertEqual(e.evaluate(snapshot(charge: 85), settings: s), [.chargeHigh(85)])  // fires again
    }

    func testChargeLowFiresOnRisingEdge() {
        let e = ThresholdEvaluator()
        var s = NotificationSettings.default
        s.chargeLowEnabled = true
        s.chargeLowThreshold = 20

        XCTAssertTrue(e.evaluate(snapshot(charge: 30), settings: s).isEmpty)
        XCTAssertEqual(e.evaluate(snapshot(charge: 18), settings: s), [.chargeLow(18)])
        XCTAssertTrue(e.evaluate(snapshot(charge: 10), settings: s).isEmpty)  // still low
        XCTAssertTrue(e.evaluate(snapshot(charge: 25), settings: s).isEmpty)  // recovered
        XCTAssertEqual(e.evaluate(snapshot(charge: 15), settings: s), [.chargeLow(15)])
    }

    func testTemperatureHigh() {
        let e = ThresholdEvaluator()
        var s = NotificationSettings.default
        s.temperatureHighEnabled = true
        s.temperatureHighThreshold = 40

        XCTAssertTrue(e.evaluate(snapshot(charge: 50, temp: 38), settings: s).isEmpty)
        XCTAssertEqual(e.evaluate(snapshot(charge: 50, temp: 41), settings: s), [.temperatureHigh(41)])
        XCTAssertTrue(e.evaluate(snapshot(charge: 50, temp: 42), settings: s).isEmpty)
    }

    func testHealthMilestoneCarriesThresholdNotLiveValue() {
        let e = ThresholdEvaluator()
        var s = NotificationSettings.default
        s.healthMilestoneEnabled = true
        s.healthMilestoneThreshold = 80

        XCTAssertTrue(e.evaluate(snapshot(charge: 50, health: 85), settings: s).isEmpty)
        XCTAssertEqual(e.evaluate(snapshot(charge: 50, health: 79), settings: s), [.healthBelow(80)])
    }

    func testMissingHealthDoesNotFireAndReArms() {
        let e = ThresholdEvaluator()
        var s = NotificationSettings.default
        s.healthMilestoneEnabled = true
        s.healthMilestoneThreshold = 80

        XCTAssertEqual(e.evaluate(snapshot(charge: 50, health: 79), settings: s), [.healthBelow(80)])
        XCTAssertTrue(e.evaluate(snapshot(charge: 50, health: nil), settings: s).isEmpty)  // no reading, re-arms
        XCTAssertEqual(e.evaluate(snapshot(charge: 50, health: 78), settings: s), [.healthBelow(80)])  // fires again
    }

    func testDisablingRuleReArmsIt() {
        let e = ThresholdEvaluator()
        var s = NotificationSettings.default
        s.chargeHighEnabled = true
        s.chargeHighThreshold = 80

        XCTAssertEqual(e.evaluate(snapshot(charge: 90), settings: s), [.chargeHigh(90)])
        s.chargeHighEnabled = false
        XCTAssertTrue(e.evaluate(snapshot(charge: 95), settings: s).isEmpty)  // disabled
        s.chargeHighEnabled = true
        XCTAssertEqual(e.evaluate(snapshot(charge: 95), settings: s), [.chargeHigh(95)])  // re-fires
    }

    func testMultipleAlertsTogether() {
        let e = ThresholdEvaluator()
        var s = NotificationSettings.default
        s.chargeLowEnabled = true
        s.chargeLowThreshold = 20
        s.temperatureHighEnabled = true
        s.temperatureHighThreshold = 40

        let fired = e.evaluate(snapshot(charge: 15, temp: 45), settings: s)
        XCTAssertEqual(Set(fired.map(\.kind)), [.chargeLow, .temperatureHigh])
    }
}
