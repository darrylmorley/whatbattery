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

    /// These two were read from IOKit on every refresh and dropped on the floor
    /// before the snapshot; the builder is where that was fixed.
    func testCarriesInstantCurrentAndCriticalFlag() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            designCapacity: 4382,
            nominalChargeCapacity: 4021,
            rawCurrentCapacity: 260,
            currentCapacity: 6,
            maxCapacity: 100,
            voltage: 11200,
            amperage: -1850,
            instantAmperage: -3200,
            externalConnected: false,
            atCriticalLevel: true
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.instantAmperageMilliamps, -3200)
        XCTAssertTrue(snapshot.atCriticalLevel)
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

    /// FullyCharged describes the battery, not the cable, and macOS leaves it
    /// set for a while after the cable is pulled. The cable must therefore be
    /// checked before the fully-charged flag, or an unplugged Mac at 100%
    /// reads as still on power. 13 of 1079 corpus machines were caught in
    /// exactly this state at probe time.
    func testUnpluggedAfterFullChargeDischarges() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 12000,
            amperage: -50,
            fullyCharged: true,
            externalConnected: false
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.chargingState, .discharging)
        // Now discharging, so power is negative rather than the old zero.
        XCTAssertLessThan(snapshot.powerWatts, 0)
    }

    /// The full flag matrix, so the precedence (cable, then fully charged,
    /// then charging, else holding on AC) stays explicit rather than only
    /// implied by individual cases above.
    func testChargingStateFlagMatrix() {
        let cases: [(fullyCharged: Bool, isCharging: Bool, externalConnected: Bool, expected: ChargingState)] = [
            (fullyCharged: false, isCharging: false, externalConnected: false, expected: .discharging),
            (fullyCharged: true, isCharging: false, externalConnected: false, expected: .discharging),
            (fullyCharged: true, isCharging: true, externalConnected: false, expected: .discharging),
            // isCharging true with externalConnected false: the gauge's flags
            // contradicting the cable, which the corpus shows gauges do (9 of
            // 257 charging machines report a negative amperage). The cable
            // check still wins; the charging flag does not override it.
            (fullyCharged: false, isCharging: true, externalConnected: false, expected: .discharging),
            (fullyCharged: true, isCharging: true, externalConnected: true, expected: .full),
            (fullyCharged: true, isCharging: false, externalConnected: true, expected: .full),
            (fullyCharged: false, isCharging: true, externalConnected: true, expected: .charging),
            (fullyCharged: false, isCharging: false, externalConnected: true, expected: .acNoCharge),
        ]
        for testCase in cases {
            let battery = AppleSmartBattery(
                batteryInstalled: true,
                isCharging: testCase.isCharging,
                fullyCharged: testCase.fullyCharged,
                externalConnected: testCase.externalConnected
            )
            XCTAssertEqual(BatterySnapshotBuilder.chargingState(for: battery), testCase.expected, "\(testCase)")
        }
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
    /// The reader stores 0 when neither `Temperature` nor `VirtualTemperature`
    /// gave a usable reading. Passed through as 0.0°C it reads as a cold room,
    /// which is a worse lie than the 454°C the lifetime-scale fix removed: it reached the
    /// display, `--json`, the widget, the temperature alert and the lifetime
    /// minimum, where it would have stood as an all-time low forever.
    func testAbsentTemperatureIsNilRatherThanZeroDegrees() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            designCapacity: 4382,
            nominalChargeCapacity: 4021,
            currentCapacity: 70,
            maxCapacity: 100,
            voltage: 12000,
            temperature: 0,
            externalConnected: false
        )
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery, deviceModel: "Mac16,6", smcDischargeWatts: nil, now: epoch
        )
        XCTAssertNil(snapshot.temperatureCelsius)
    }

    func testRealTemperatureStillArrives() throws {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            designCapacity: 4382,
            nominalChargeCapacity: 4021,
            currentCapacity: 70,
            maxCapacity: 100,
            voltage: 12000,
            temperature: 3385,
            externalConnected: false
        )
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery, deviceModel: "Mac16,6", smcDischargeWatts: nil, now: epoch
        )
        XCTAssertEqual(try XCTUnwrap(snapshot.temperatureCelsius), 33.85, accuracy: 0.001)
    }

}
