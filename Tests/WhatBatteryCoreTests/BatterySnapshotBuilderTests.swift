import XCTest
@testable import WhatBatteryCore

final class BatterySnapshotBuilderTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)

    func testDischargingStateAndNegativePower() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            designCapacity: 4382,
            nominalChargeCapacity: 4021,
            rawCurrentCapacity: 2800,
            currentCapacity: 70,
            maxCapacity: 100,
            cycleCount: 214,
            voltage: 12000,
            amperage: -2000,
            externalConnected: false,
            timeToEmptyMinutes: 180
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "Mac16,6", smcDischargeWatts: 18.5, now: epoch)

        XCTAssertEqual(snapshot.chargingState, .discharging)
        // Prefers the SMC live discharge rail, negated.
        XCTAssertEqual(snapshot.powerWatts, -18.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.timeToEmptyMinutes, 180)
        XCTAssertNil(snapshot.timeToFullMinutes)
        XCTAssertEqual(snapshot.currentChargePercent, 70)
    }

    func testDischargingFallsBackToGaugeWhenNoSMC() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 12000,   // 12 V
            amperage: -2000,  // -2 A -> 24 W magnitude
            externalConnected: false
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.powerWatts, -24.0, accuracy: 0.0001)
    }

    func testChargingUsesChargerData() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 12000,
            amperage: 1000,
            isCharging: true,
            externalConnected: true,
            timeToFullMinutes: 47,
            chargerData: ChargerData(chargingVoltageMV: 20000, chargingCurrentMA: 3000)
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.chargingState, .charging)
        // 20 V * 3 A = 60 W, positive.
        XCTAssertEqual(snapshot.powerWatts, 60.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.timeToFullMinutes, 47)
    }

    func testFullyChargedIsZeroPower() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 12000,
            amperage: 0,
            fullyCharged: true,
            externalConnected: true
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.chargingState, .full)
        XCTAssertEqual(snapshot.powerWatts, 0)
    }

    func testHealthUsesNominalNotMaxCapacity() {
        // maxCapacity is a percentage on Apple Silicon; health must ignore it.
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            designCapacity: 5000,
            nominalChargeCapacity: 4500,
            currentCapacity: 80,
            maxCapacity: 100
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.healthPercent!, 90.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.fullChargeCapacitymAh, 4500)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let battery = AppleSmartBattery(batteryInstalled: true, designCapacity: 5000, nominalChargeCapacity: 4500)
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BatterySnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}
