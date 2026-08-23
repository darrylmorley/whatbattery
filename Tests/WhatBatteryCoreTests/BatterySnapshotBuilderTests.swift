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

    func testChargingUsesThePacksOwnVoltageAndCurrent() {
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
        // 12 V * 1 A = 12 W. ChargerData is deliberately ignored: it used to win
        // here and would have said 60 W.
        XCTAssertEqual(snapshot.powerWatts, 12.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.timeToFullMinutes, 47)
    }

    /// The real numbers off this Mac while charging, which is where the bug was
    /// found: ChargingVoltage is per-cell (4.047 V on a pack sitting at 12.0 V),
    /// so the old formula reported 23.3 W for a charge measured at 54.7 W by
    /// sampling the pack's own capacity over 90 seconds.
    func testChargingPowerIsNotUnderstatedByTheCellCount() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            deviceName: "bq40z651",
            designCapacity: 6249,
            nominalChargeCapacity: 5949,
            voltage: 11999,
            amperage: 5405,
            isCharging: true,
            externalConnected: true,
            chargerData: ChargerData(chargingVoltageMV: 4047, chargingCurrentMA: 5751)
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "Mac17,2", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.powerWatts, 64.85, accuracy: 0.05)
        XCTAssertGreaterThan(snapshot.powerWatts, 50, "the old per-cell formula gave 23.3 W here")
    }

    /// The gauge can report IsCharging while the current is still flowing out.
    /// Taking the magnitude would call that charge power and, because nothing
    /// ever washes a peak out, it would sit in the lifetime figures forever.
    func testChargingWithCurrentStillFlowingOutIsNotAReading() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 12000,
            amperage: -2000,
            isCharging: true,
            externalConnected: true
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.chargingState, .charging)
        XCTAssertEqual(snapshot.powerWatts, 0, "a self-contradicting reading must not become +24 W")
    }

    /// The mirror of the charging case, and just as real: 3 of 179 discharging
    /// machines in the corpus report a positive current. The SMC rail normally
    /// covers for it, so the guard only matters when that read is unavailable,
    /// which is exactly when nothing else would catch it.
    func testDischargingWithCurrentFlowingInIsNotAReading() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 12517,
            amperage: 3426,          // positive while unplugged: contradicts itself
            externalConnected: false
        )
        let snapshot = BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: epoch)
        XCTAssertEqual(snapshot.chargingState, .discharging)
        XCTAssertEqual(snapshot.powerWatts, 0, "must not become a -42.9 W lifetime peak")

        // With the SMC's own measurement present, that is what we report.
        XCTAssertEqual(
            BatterySnapshotBuilder.build(battery: battery, deviceModel: "x", smcDischargeWatts: 12.0, now: epoch).powerWatts,
            -12.0, accuracy: 0.0001
        )
    }

    /// A current wrapped into an unsigned field would price a 12 V pack in the
    /// hundreds of watts and poison every peak that touches it.
    func testImplausibleCurrentIsRefusedInBothDirections() {
        let wrapped = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 11999,
            amperage: 63536,   // -2000 mA packed into unsigned 16 bits
            isCharging: true,
            externalConnected: true
        )
        XCTAssertEqual(
            BatterySnapshotBuilder.build(battery: wrapped, deviceModel: "x", smcDischargeWatts: nil, now: epoch).powerWatts,
            0, "762 W is not a battery"
        )

        let discharging = AppleSmartBattery(
            batteryInstalled: true,
            voltage: 11999,
            amperage: 63536,
            externalConnected: false
        )
        XCTAssertEqual(
            BatterySnapshotBuilder.build(battery: discharging, deviceModel: "x", smcDischargeWatts: nil, now: epoch).powerWatts,
            0
        )
        // The SMC rail is measured independently, so it still wins when present.
        XCTAssertEqual(
            BatterySnapshotBuilder.build(battery: discharging, deviceModel: "x", smcDischargeWatts: 18.5, now: epoch).powerWatts,
            -18.5, accuracy: 0.0001
        )
    }

    /// The real figures stay inside the guard: the corpus tops out at a 6825 mA
    /// charge and a 4852 mA draw.
    func testRealWorldCurrentsAreNotRefused() {
        XCTAssertTrue(BatterySnapshotBuilder.isPlausibleCurrent(6825))
        XCTAssertTrue(BatterySnapshotBuilder.isPlausibleCurrent(-4852))
        XCTAssertTrue(BatterySnapshotBuilder.isPlausibleCurrent(25_000))
        XCTAssertFalse(BatterySnapshotBuilder.isPlausibleCurrent(25_001))
        XCTAssertFalse(BatterySnapshotBuilder.isPlausibleCurrent(63_536))
        // The extremes must be refused, not trapped on: abs(Int.min) crashes,
        // and a value this malformed is the guard's whole reason to exist.
        XCTAssertFalse(BatterySnapshotBuilder.isPlausibleCurrent(Int.min))
        XCTAssertFalse(BatterySnapshotBuilder.isPlausibleCurrent(Int.max))
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
