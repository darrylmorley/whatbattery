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

    /// A real iPhone 15 (iOS 26.6) read over the relay on 2026-08-08, charging.
    /// Captured specifically to settle the question the Mac temperature correction left open, since the
    /// probe corpus contains no iDevice dumps at all.
    private func iPhone15Fixture() -> [String: Any] {
        [
            "DesignCapacity": 3329,
            "NominalChargeCapacity": 3331,
            "AppleRawCurrentCapacity": 2045,
            "CycleCount": 90,
            "Temperature": 2809,
            "VirtualTemperature": 2550,
            "Voltage": 4205,
            "Amperage": 1504,
            "InstantAmperage": 1491,
            "IsCharging": true,
            // Trimmed from the original capture, which is why chargingState's
            // cable-first ordering (DAR fix) exposed the gap: a real charging
            // phone is always externally connected, but the fixture omitted
            // the key entirely, so it silently relied on IsCharging alone.
            "AppleRawExternalConnected": true,
            "AtCriticalLevel": false,
            "BatteryData": [
                "CellVoltage": [4205],
                "LifetimeData": [
                    "MinimumTemperature": 86,
                    "MaximumTemperature": 452,
                    "AverageTemperature": 20,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    /// iOS publishes `Temperature` in centi-Celsius, unlike macOS, because iOS
    /// falls under `!TARGET_OS_OSX` in Apple's driver and gets the conversion
    /// applied on-device. So the mapper must NOT convert from deci-Kelvin the
    /// way the Mac reader does.
    ///
    /// The raw value proves it on its own: 2809 read as centi-Celsius is 28.1°C,
    /// which is what a charging phone feels like. Read as deci-Kelvin it is
    /// 7.8°C, which it plainly was not.
    func testIDeviceTemperatureIsCentiCelsiusNotDeciKelvin() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone15Fixture()))
        XCTAssertEqual(battery.temperature, 2809, "passed through, not converted")

        let snapshot = BatterySnapshotBuilder.build(
            battery: battery, deviceModel: "iPhone15,4", smcDischargeWatts: nil,
            now: Date(timeIntervalSince1970: 1_786_000_000)
        )
        XCTAssertEqual(try XCTUnwrap(snapshot.temperatureCelsius), 28.09, accuracy: 0.001)
    }

    /// The same phone reports its LIFETIME extremes in deci-degrees, so it needs
    /// the deci-degree scale resolution as much as an M1 does, and the cross-check
    /// gets a current reading in the units it expects.
    func testIDeviceLifetimeTemperaturesAreResolvedAsDeciDegrees() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone15Fixture()))
        let lifetime = try XCTUnwrap(battery.packDetail?.lifetime)
        XCTAssertEqual(lifetime.minimumTemperatureC, 9)      // 8.6, not 86
        XCTAssertEqual(lifetime.maximumTemperatureC, 45)     // 45.2, not 452
        // The average is whole degrees on this device, and only fits the range
        // when the pair has been normalised.
        XCTAssertEqual(try XCTUnwrap(lifetime.averageTemperatureC), 20, accuracy: 0.001)
    }

    /// One cell, so pack voltage and per-cell voltage are the same number, and
    /// charge power comes out right from the pack figures.
    func testIDeviceChargePowerFromThePack() throws {
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: iPhone15Fixture()))
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery, deviceModel: "iPhone15,4", smcDischargeWatts: nil,
            now: Date(timeIntervalSince1970: 1_786_000_000)
        )
        XCTAssertEqual(snapshot.powerWatts, 6.32, accuracy: 0.02)   // 4.205 V * 1.504 A
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

    func testMarketingNameIsNeverBlank() {
        // A failed identity read leaves the product type empty; a blank name
        // would render as a blank title in the UI.
        XCTAssertFalse(IDeviceModelName.marketingName(for: "").isEmpty)
    }

    func testKindFromProductTypePrefix() {
        XCTAssertEqual(IDeviceModelName.kind(for: "iPad13,4"), .iPad)
        XCTAssertEqual(IDeviceModelName.kind(for: "iPhone12,1"), .iPhone)
        XCTAssertEqual(IDeviceModelName.kind(for: "iPod9,1"), .iPod)
    }

    func testKindResolvesUnknownModelsByFamily() {
        // A model too new for the name table still has to get the right icon.
        XCTAssertEqual(IDeviceModelName.kind(for: "iPad99,9"), .iPad)
        XCTAssertEqual(IDeviceModelName.kind(for: "Watch7,1"), .unknown)
        XCTAssertEqual(IDeviceModelName.kind(for: ""), .unknown)
    }

    func testEveryKindHasASymbolAndLabel() {
        for kind in IDeviceKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty)
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.fallbackName.isEmpty)
        }
    }

    func testFallbackNameIsANounNotAPairOfOptions() {
        // It stands where a real device name goes ("<name> is connected"), so
        // an unnamed iPad must never fall back to "iPhone".
        XCTAssertEqual(IDeviceKind.iPad.fallbackName, "iPad")
        XCTAssertEqual(IDeviceKind.iPhone.fallbackName, "iPhone")
        XCTAssertEqual(IDeviceKind.unknown.fallbackName, "Device")
    }
    /// The relay is a private, undocumented interface whose keys drift between
    /// iOS versions. The Mac reader gets a plausibility gate for free on the way
    /// through `centiCelsius(fromDeciKelvin:)`; this path had none, so an
    /// out-of-band value reached the display and, worse, became the cross-check
    /// that resolves the lifetime temperature scale.
    func testImplausibleRelayTemperatureIsRejected() throws {
        var fixture = iPhone15Fixture()
        fixture["Temperature"] = 65535
        fixture["VirtualTemperature"] = 65535
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: fixture))
        XCTAssertEqual(battery.temperature, 0, "the sentinel is absent, not 655.35°C")
        XCTAssertEqual(battery.virtualTemperature, 0)

        let snapshot = BatterySnapshotBuilder.build(
            battery: battery, deviceModel: "iPhone15,4", smcDischargeWatts: nil,
            now: Date(timeIntervalSince1970: 1_786_000_000)
        )
        XCTAssertNil(snapshot.temperatureCelsius)
    }

    /// What the gate buys on the lifetime path: a garbage thermometer reading
    /// fits no candidate range, so the cross-check suppresses a range it could
    /// otherwise have resolved. Rejecting the reading up front turns it into
    /// "absent", where the magnitude rule stands alone and still gets it right.
    func testGarbageReadingWouldSuppressAResolvableRange() throws {
        XCTAssertNil(BatteryLifetime.temperatureRange(minRaw: 87, maxRaw: 454, currentC: 200))

        let resolved = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 87, maxRaw: 454, currentC: nil))
        XCTAssertEqual(resolved.max, 45.4, accuracy: 0.001)
    }

    // MARK: - The adapter that is not there

    /// An iDevice publishes AdapterDetails whether or not anything is attached.
    /// With nothing attached it is all zeroes, and passing that through made an
    /// iPhone on 6% battery read "Power  -0.1 W (0W)". There is no 0 W charger.
    func testNothingPluggedInIsNotAnAdapter() {
        var d = Self.minimalBattery
        d["AdapterDetails"] = [
            "Watts": 0, "AdapterVoltage": 0, "Current": 0,
            "Description": "", "Name": "", "Manufacturer": "", "Model": "",
        ] as [String: Any]
        XCTAssertNil(AppleSmartBatteryMapper.from(dictionary: d)?.adapter)
    }

    /// An empty dictionary is the same thing: nothing is attached.
    func testAnEmptyAdapterDictionaryIsNotAnAdapter() {
        var d = Self.minimalBattery
        d["AdapterDetails"] = [String: Any]()
        XCTAssertNil(AppleSmartBatteryMapper.from(dictionary: d)?.adapter)
    }

    /// A real charger still comes through, wattage and all.
    func testARealChargerIsStillReported() {
        var d = Self.minimalBattery
        d["AdapterDetails"] = ["Watts": 20, "Name": "USB-C Power Adapter"] as [String: Any]
        let adapter = AppleSmartBatteryMapper.from(dictionary: d)?.adapter
        XCTAssertEqual(adapter?.watts, 20)
        XCTAssertEqual(adapter?.label, "20W USB-C Power Adapter")
    }

    /// A named charger reporting no wattage is still a charger: the name is
    /// evidence something is attached, so it must not be discarded.
    func testANamedChargerWithoutWattageIsKept() {
        var d = Self.minimalBattery
        d["AdapterDetails"] = ["Watts": 0, "Description": "usb host"] as [String: Any]
        XCTAssertEqual(AppleSmartBatteryMapper.from(dictionary: d)?.adapter?.description, "usb host")
    }

    /// The fixture every adapter case builds on: enough to be a battery.
    private static let minimalBattery: [String: Any] = [
        "DesignCapacity": 3092, "AppleRawMaxCapacity": 2573,
        "NominalChargeCapacity": 2573, "CycleCount": 820,
    ]

    /// A wireless charger can report no wattage and no name strings at all. It
    /// is still a charger, and dropping it loses even the fact that the device
    /// is on a pad.
    func testAWirelessChargerWithNoWattageOrNameIsKept() {
        var d = Self.minimalBattery
        d["AdapterDetails"] = ["Watts": 0, "IsWireless": true] as [String: Any]
        XCTAssertEqual(AppleSmartBatteryMapper.from(dictionary: d)?.adapter?.isWireless, true)
    }

    /// A charger still negotiating can show a voltage before it reports watts.
    func testAnAdapterReportingOnlyVoltageIsKept() {
        var d = Self.minimalBattery
        d["AdapterDetails"] = ["Watts": 0, "AdapterVoltage": 5000] as [String: Any]
        XCTAssertEqual(AppleSmartBatteryMapper.from(dictionary: d)?.adapter?.voltageMV, 5000)
    }

    /// Pre-A11 iDevices (e.g. the A10X iPad Pro 10,5", last supported by
    /// iPadOS 17) have no AppleSmartBattery node: the battery lives under
    /// AppleARMPMUCharger, with mostly the same keys but PMU spellings for the
    /// serial (BatterySerialNumber) and voltage (AppleRawBatteryVoltage only).
    ///
    /// SYNTHETIC fixture, modelled on the AppleARMPMUCharger key set, not
    /// captured from a real device: the probe corpus holds no iDevice dumps at
    /// all, and no A10X device was on hand when this was written. If a real
    /// dump ever disagrees with these spellings, trust the dump.
    func testARMPMUChargerShapedDictionaryMaps() throws {
        let d: [String: Any] = [
            "DesignCapacity": 8134,
            "AppleRawMaxCapacity": 6480,
            "AppleRawCurrentCapacity": 5122,
            "CurrentCapacity": 79,
            "CycleCount": 412,
            "Temperature": 2450,
            "AppleRawBatteryVoltage": 3812,
            "BatterySerialNumber": "F8Y12345ABCD",
            "ExternalConnected": true,
        ]
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: d))
        XCTAssertEqual(battery.designCapacity, 8134)
        XCTAssertEqual(battery.rawMaxCapacity, 6480)
        XCTAssertEqual(battery.cycleCount, 412)
        XCTAssertEqual(battery.serial, "F8Y12345ABCD", "PMU spelling of the pack serial")
        XCTAssertEqual(battery.voltage, 3812, "no Voltage key; falls back to AppleRawBatteryVoltage")
        XCTAssertTrue(battery.isPlausible, "must pass the reader's plausibility gate, not just map")
    }

    /// The user's iPad Pro 10,5" (A10X, iPadOS 17.7.11) that motivated the PMU
    /// capacity fix. The PMU dictionary carried NominalChargeCapacity=6516
    /// (static across days: a rated value) and AppleRawMaxCapacity=5336
    /// (moved 5487 to 5336 across two days, matching coconutBattery each day:
    /// a measured value). Design capacity 7966 was correct on both apps.
    /// `isPMUSourced: true` must flip the preference to the measured field;
    /// the exact same dictionary treated as AppleSmartBattery-sourced (the
    /// default) must keep the old nominal-first preference, since that
    /// preference is still correct on a Mac and on A11+ devices.
    func testPMUFallbackPrefersMeasuredOverRatedCapacity() throws {
        let d: [String: Any] = [
            "DesignCapacity": 7966,
            "NominalChargeCapacity": 6516,
            "AppleRawMaxCapacity": 5336,
            "AppleRawCurrentCapacity": 4000,
            "CurrentCapacity": 60,
            "CycleCount": 200,
        ]

        let pmuBattery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: d, isPMUSourced: true))
        XCTAssertTrue(pmuBattery.isPMUSourced)
        XCTAssertEqual(pmuBattery.fullChargeCapacitymAh, 5336, "measured AppleRawMaxCapacity must win on the PMU path")
        let pmuHealth = Double(pmuBattery.fullChargeCapacitymAh) / Double(pmuBattery.designCapacity) * 100
        XCTAssertEqual(pmuHealth, 67.0, accuracy: 0.5)

        let smartBattery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: d))
        XCTAssertFalse(smartBattery.isPMUSourced, "default must stay AppleSmartBattery-sourced")
        XCTAssertEqual(smartBattery.fullChargeCapacitymAh, 6516, "rated NominalChargeCapacity still wins off the PMU path")
    }

    /// The relay bridge's class-fallback loop stops on the first response this
    /// predicate accepts, so it must agree with `from(dictionary:)` exactly: a
    /// capacity KEY that is present but zero is not a usable battery, and
    /// accepting it would end the fallback on a response the mapper then
    /// rejects anyway.
    func testZeroCapacityIsNotUsable() {
        XCTAssertFalse(AppleSmartBatteryMapper.hasUsableCapacity(["DesignCapacity": 0]))
        XCTAssertFalse(AppleSmartBatteryMapper.hasUsableCapacity([:]))
        XCTAssertNil(AppleSmartBatteryMapper.from(dictionary: ["DesignCapacity": 0, "CycleCount": 12]))
        XCTAssertTrue(AppleSmartBatteryMapper.hasUsableCapacity(["DesignCapacity": 0, "NominalChargeCapacity": 2564]))
        XCTAssertTrue(AppleSmartBatteryMapper.hasUsableCapacity(Self.minimalBattery))
    }

    /// The AppleSmartBattery spelling must still win when both are present, so
    /// the fallback cannot change any reading that worked before it existed.
    func testSerialPrefersTheSmartBatterySpelling() {
        var d = Self.minimalBattery
        d["Serial"] = "SMART"
        d["BatterySerialNumber"] = "PMU"
        XCTAssertEqual(AppleSmartBatteryMapper.from(dictionary: d)?.serial, "SMART")
    }

    /// Under `BatterySnapshotBuilder.chargingState`'s cable-first ordering, a
    /// dictionary that never mentions ExternalConnected or
    /// AppleRawExternalConnected at all (the pre-A11 PMU fallback path's real
    /// key shape is unknown) must not silently read as unplugged. IsCharging
    /// is the fallback cable signal because a battery cannot charge without
    /// one; a non-charging read with the same key gap falls back to
    /// discharging, which is the only honest answer without a real signal.
    func testMissingExternalConnectedKeysInferFromIsCharging() throws {
        var charging = Self.minimalBattery
        charging["IsCharging"] = true
        let chargingBattery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: charging))
        XCTAssertTrue(chargingBattery.externalConnected, "charging implies a power source")
        let chargingSnapshot = BatterySnapshotBuilder.build(
            battery: chargingBattery, deviceModel: "x", smcDischargeWatts: nil, now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(chargingSnapshot.chargingState, .charging)

        var notCharging = Self.minimalBattery
        notCharging["IsCharging"] = false
        let notChargingBattery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: notCharging))
        XCTAssertFalse(notChargingBattery.externalConnected)
        let notChargingSnapshot = BatterySnapshotBuilder.build(
            battery: notChargingBattery, deviceModel: "x", smcDischargeWatts: nil, now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(notChargingSnapshot.chargingState, .discharging)
    }

    /// An explicit ExternalConnected: false must win over the IsCharging
    /// inference, not be overridden by it. Gauges do contradict themselves
    /// (the corpus has 9 of 257 charging machines reporting a negative
    /// amperage), so the mapper must pass a real answer through unchanged
    /// rather than "fixing" it.
    func testExplicitExternalConnectedFalseWinsOverIsChargingInference() throws {
        var d = Self.minimalBattery
        d["IsCharging"] = true
        d["ExternalConnected"] = false
        let battery = try XCTUnwrap(AppleSmartBatteryMapper.from(dictionary: d))
        XCTAssertFalse(battery.externalConnected, "an explicit false must not be inferred away")
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery, deviceModel: "x", smcDischargeWatts: nil, now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(snapshot.chargingState, .discharging)
    }
}
