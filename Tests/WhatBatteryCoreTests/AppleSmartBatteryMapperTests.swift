import XCTest
@testable import WhatBatteryCore

/// The fixture is a trimmed copy of a real iPhone 11 (iOS 26.6) AppleSmartBattery
/// read over the pymobiledevice3 diagnostics relay on 2026-06-16, so the mapper
/// is tested against the actual shape an iDevice returns.
final class AppleSmartBatteryMapperTests: XCTestCase {
    private func iPhone11Fixture() -> [String: Any] {
        [
            "DesignCapacity": 3092,
            "AppleRawMaxCapacity": 2633,
            "NominalChargeCapacity": 2564,
            "MaxCapacity": 100,            // Apple Silicon pin; must be ignored
            "AppleRawCurrentCapacity": 219,
            "CurrentCapacity": 9,
            "CycleCount": 768,
            "Temperature": 3550,
            "AppleRawBatteryVoltage": 3879,
            "Voltage": 0,                 // iDevice may report 0 here; fall back to raw
            "Amperage": 1476,
            "IsCharging": true,
            "FullyCharged": false,
            "AppleRawExternalConnected": true,
            "AvgTimeToEmpty": 55,
            "TimeRemaining": 42,          // iOS unified estimate; to-full while charging
            "AdapterDetails": [
                "Watts": 12,
                "AdapterVoltage": 5000,
                "Current": 2400,
                "Description": "usb host",
                "IsWireless": false,
            ] as [String: Any],
        ]
    }

    func testMapsRealIDeviceReadIntoModel() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))

        XCTAssertTrue(battery.batteryInstalled)
        XCTAssertEqual(battery.designCapacity, 3092)
        XCTAssertEqual(battery.nominalChargeCapacity, 2564)
        XCTAssertEqual(battery.rawMaxCapacity, 2633)
        XCTAssertEqual(battery.cycleCount, 768)
        XCTAssertEqual(battery.currentCapacity, 9)
        XCTAssertEqual(battery.maxCapacity, 100)
        XCTAssertTrue(battery.isCharging)
        XCTAssertTrue(battery.externalConnected)   // from AppleRawExternalConnected
        XCTAssertEqual(battery.temperature, 3550)
    }

    func testVoltageFallsBackToRawWhenVoltageIsZero() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        XCTAssertEqual(battery.voltage, 3879)
    }

    func testFullChargeCapacityPrefersNominal() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        XCTAssertEqual(battery.fullChargeCapacitymAh, 2564)
    }

    func testHealthMathMatchesSettingsMaximumCapacity() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        let health = try XCTUnwrap(BatteryHealth.healthPercent(
            fullChargemAh: battery.fullChargeCapacitymAh,
            designmAh: battery.designCapacity
        ))
        XCTAssertEqual(health, 82.9, accuracy: 0.1)
    }

    func testAdapterParsed() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        let adapter = try XCTUnwrap(battery.adapter)
        XCTAssertEqual(adapter.watts, 12)
        XCTAssertEqual(adapter.description, "usb host")
        XCTAssertEqual(adapter.isWireless, false)
    }

    func testEndToEndSnapshotBuild() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery,
            deviceModel: "iPhone 11",
            smcDischargeWatts: nil,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(snapshot.deviceModel, "iPhone 11")
        XCTAssertEqual(snapshot.cycleCount, 768)
        XCTAssertEqual(snapshot.currentChargePercent, 9)
        XCTAssertEqual(snapshot.chargingState, .charging)
        XCTAssertEqual(try XCTUnwrap(snapshot.healthPercent), 82.9, accuracy: 0.1)
    }

    func testTimeRemainingMappedFromUnifiedKey() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        XCTAssertEqual(battery.timeRemainingMinutes, 42)
    }

    func testTimeToFullFallsBackToTimeRemainingWhenCharging() throws {
        // The iDevice node has no AvgTimeToFull, only TimeRemaining, so a charging
        // snapshot's time-to-full must come from TimeRemaining.
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery,
            deviceModel: "iPhone 11",
            smcDischargeWatts: nil,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(snapshot.timeToFullMinutes, 42)
        XCTAssertNil(snapshot.timeToEmptyMinutes)   // not discharging
    }

    func testAvgTimeToFullWinsOverTimeRemaining() throws {
        // When the Mac-style AvgTimeToFull is present it takes precedence over the
        // unified TimeRemaining fallback.
        var dict = iPhone11Fixture()
        dict["AvgTimeToFull"] = 17
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: dict))
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery,
            deviceModel: "iPhone 11",
            smcDischargeWatts: nil,
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(snapshot.timeToFullMinutes, 17)
    }

    func testReturnsNilForNonBatteryDictionary() {
        XCTAssertNil(AppleSmartBatteryMapper.from(dictionary: ["SomethingElse": 1]))
    }

    func testRealIDeviceReadIsPlausible() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone11Fixture()))
        XCTAssertTrue(battery.isPlausible)
    }

    func testImplausibleWhenNoDesignCapacity() {
        let battery = AppleSmartBattery(designCapacity: 0, nominalChargeCapacity: 2564)
        XCTAssertFalse(battery.isPlausible)
    }

    func testImplausibleWhenNoFullChargeCapacity() {
        let battery = AppleSmartBattery(designCapacity: 3092)
        XCTAssertFalse(battery.isPlausible)
    }

    func testImplausibleWhenHealthAbsurdlyHigh() {
        // Full-charge far above design means a misread key, not a battery.
        let battery = AppleSmartBattery(designCapacity: 3092, nominalChargeCapacity: 30920)
        XCTAssertFalse(battery.isPlausible)
    }

    func testImplausibleWhenHealthNearZero() {
        // A near-zero ratio signals a misread key, not a battery.
        let battery = AppleSmartBattery(designCapacity: 3092, nominalChargeCapacity: 20)
        XCTAssertFalse(battery.isPlausible)
    }

    func testPlausibleWhenDeeplyWornButReal() {
        // A genuinely worn battery (single-digit %) must still pass: the floor is
        // a garbage sentinel, not a health threshold.
        let battery = AppleSmartBattery(designCapacity: 3092, nominalChargeCapacity: 280)
        XCTAssertTrue(battery.isPlausible)
    }

    func testPlausibleAtSlightlyOverDesign() {
        // A new battery can read just over 100% health; that must still pass.
        let battery = AppleSmartBattery(designCapacity: 3000, nominalChargeCapacity: 3100)
        XCTAssertTrue(battery.isPlausible)
    }

    func testMarketingNameLookupAndFallback() {
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone12,1"), "iPhone 11")
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone99,9"), "iPhone99,9")
    }
}
