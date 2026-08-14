import XCTest
@testable import WhatBatteryCore

/// The fixture mirrors the real `BatteryData` blob from a MacBook Pro (M5) on
/// 2026-07-31, including the quirks: the average temperature on a different
/// scale from the min/max pair, and a discharge current stored as a wrapped
/// unsigned value.
final class BatteryPackDetailTests: XCTestCase {
    private func realBatteryData() -> [String: Any] {
        [
            "CellVoltage": [4409, 4408, 4411],
            "Qmax": [6288, 6280, 6311],
            "WeightedRa": [37, 27, 31],
            "DailyMinSoc": 99,
            "DailyMaxSoc": 100,
            "CycleCountLastQmax": 55,
            "LifetimeData": [
                "MinimumTemperature": 11,
                "MaximumTemperature": 41,
                "AverageTemperature": 211,
                "MaximumChargeCurrent": 6825,
                "MaximumDischargeCurrent": 18_446_744_073_709_546_764 as UInt64,
                "MinimumPackVoltage": 10144,
                "MaximumPackVoltage": 13304,
                "TotalOperatingTime": 4712,
            ] as [String: Any],
        ]
    }

    func testParsesRealPackData() throws {
        let detail = try XCTUnwrap(BatteryPackDetail.from(batteryData: realBatteryData()))
        XCTAssertEqual(detail.cellVoltagesMV, [4409, 4408, 4411])
        XCTAssertEqual(detail.cellQmax, [6288, 6280, 6311])
        XCTAssertEqual(detail.cellResistance, [37, 27, 31])
        XCTAssertEqual(detail.dailyMinSoc, 99)
        XCTAssertEqual(detail.dailyMaxSoc, 100)
        XCTAssertEqual(detail.cycleCountAtLastQmax, 55)
    }

    func testCellSpreadIsTheDiagnostic() throws {
        let detail = try XCTUnwrap(BatteryPackDetail.from(batteryData: realBatteryData()))
        XCTAssertEqual(detail.cellVoltageSpreadMV, 3)      // 4411 - 4408, a healthy pack
        XCTAssertEqual(detail.cellQmaxSpreadmAh, 31)       // 6311 - 6280
    }

    func testSpreadNeedsMoreThanOneCell() {
        let detail = BatteryPackDetail(cellVoltagesMV: [4409])
        XCTAssertNil(detail.cellVoltageSpreadMV)
    }

    func testAverageTemperatureIsResolvedAgainstTheExtremes() throws {
        // Reported as 211 alongside a min of 11 and a max of 41: only 21.1
        // fits between them, so the scale is inferred rather than assumed.
        let detail = try XCTUnwrap(BatteryPackDetail.from(batteryData: realBatteryData()))
        let lifetime = try XCTUnwrap(detail.lifetime)
        XCTAssertEqual(try XCTUnwrap(lifetime.averageTemperatureC), 21.1, accuracy: 0.001)
        XCTAssertEqual(lifetime.minimumTemperatureC, 11)
        XCTAssertEqual(lifetime.maximumTemperatureC, 41)
    }

    // MARK: - Lifetime temperature scale

    /// The customer report that opened the lifetime-scale bug: a MacBook Air M1 shown as
    /// "87°C to 454°C, averaging 245.0°C". The gauge means tenths.
    func testDeciDegreeGaugeIsNotPresentedAsHundredsOfDegrees() throws {
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": 87,
            "MaximumTemperature": 454,
            "AverageTemperature": 245,
        ] as [String: Any]
        let lifetime = try XCTUnwrap(
            BatteryPackDetail.from(batteryData: data, currentTemperatureCentiC: 3030)?.lifetime
        )
        XCTAssertEqual(lifetime.minimumTemperatureC, 9)      // 8.7
        XCTAssertEqual(lifetime.maximumTemperatureC, 45)     // 45.4
        XCTAssertEqual(try XCTUnwrap(lifetime.averageTemperatureC), 24.5, accuracy: 0.001)
    }

    /// The whole-degree machines must be untouched by the rescaling.
    func testWholeDegreeGaugeIsUnchanged() throws {
        let lifetime = try XCTUnwrap(
            BatteryPackDetail.from(batteryData: realBatteryData(), currentTemperatureCentiC: 3050)?.lifetime
        )
        XCTAssertEqual(lifetime.minimumTemperatureC, 11)
        XCTAssertEqual(lifetime.maximumTemperatureC, 41)
        XCTAssertEqual(try XCTUnwrap(lifetime.averageTemperatureC), 21.1, accuracy: 0.001)
    }

    /// A below-freezing minimum is real (a laptop left in a cold car) and is
    /// only believable once the pair is scaled, which is why the minimum cannot
    /// be the thing that decides the scale.
    func testSubZeroMinimumSurvivesTheRescale() throws {
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": -123,
            "MaximumTemperature": 454,
            "AverageTemperature": 240,
        ] as [String: Any]
        let lifetime = try XCTUnwrap(
            BatteryPackDetail.from(batteryData: data, currentTemperatureCentiC: 3070)?.lifetime
        )
        XCTAssertEqual(lifetime.minimumTemperatureC, -12)    // -12.3
        XCTAssertEqual(lifetime.maximumTemperatureC, 45)
    }

    /// The corpus machine that proves a gauge-model allowlist would have been
    /// wrong: a bq40z651 reporting deci where its siblings report whole.
    func testTheGaugeModelDoesNotDecideTheScale() throws {
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": 106,
            "MaximumTemperature": 430,
            "AverageTemperature": 260,
        ] as [String: Any]
        let lifetime = try XCTUnwrap(
            BatteryPackDetail.from(batteryData: data, currentTemperatureCentiC: 3020)?.lifetime
        )
        XCTAssertEqual(lifetime.minimumTemperatureC, 11)     // 10.6
        XCTAssertEqual(lifetime.maximumTemperatureC, 43)
        XCTAssertEqual(try XCTUnwrap(lifetime.averageTemperatureC), 26.0, accuracy: 0.001)
    }

    /// When the magnitude rule and the pack's own thermometer disagree, we say
    /// nothing rather than pick one.
    func testContradictoryScaleSignalsShowNothing() throws {
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": 11,
            "MaximumTemperature": 41,        // reads as whole degrees...
            "AverageTemperature": 211,
            "MaximumChargeCurrent": 6825,    // an unrelated figure, still good
        ] as [String: Any]
        // ...but the pack says it is 68°C right now, outside that range entirely.
        let lifetime = try XCTUnwrap(
            BatteryPackDetail.from(batteryData: data, currentTemperatureCentiC: 6800)?.lifetime
        )
        XCTAssertNil(lifetime.minimumTemperatureC)
        XCTAssertNil(lifetime.maximumTemperatureC)
        XCTAssertNil(lifetime.averageTemperatureC)
        // Only the temperatures are in doubt, so only they are withheld.
        XCTAssertEqual(lifetime.maximumChargeCurrentMA, 6825)
    }

    /// A pack whose only lifetime figures are temperatures we cannot trust has
    /// nothing left to show, so the section disappears rather than rendering
    /// an empty heading.
    func testLifetimeVanishesWhenTemperaturesWereAllItHad() {
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": 11,
            "MaximumTemperature": 41,
            "AverageTemperature": 211,
        ] as [String: Any]
        XCTAssertNil(BatteryPackDetail.from(batteryData: data, currentTemperatureCentiC: 6800)?.lifetime)
    }

    /// Without a current reading to check against, the magnitude rule stands on
    /// its own: it classifies every machine in the corpus correctly.
    func testScaleStillResolvesWithoutTheCrossCheck() {
        let deci = BatteryLifetime.temperatureRange(minRaw: 87, maxRaw: 454, currentC: nil)
        XCTAssertEqual(deci?.max ?? 0, 45.4, accuracy: 0.001)
        let whole = BatteryLifetime.temperatureRange(minRaw: 11, maxRaw: 41, currentC: nil)
        XCTAssertEqual(whole?.max ?? 0, 41, accuracy: 0.001)
    }

    func testImplausibleRangesAreRefused() {
        XCTAssertNil(BatteryLifetime.temperatureRange(minRaw: 0, maxRaw: 0, currentC: nil))
        XCTAssertNil(BatteryLifetime.temperatureRange(minRaw: 41, maxRaw: 11, currentC: nil))   // inverted
        XCTAssertNil(BatteryLifetime.temperatureRange(minRaw: nil, maxRaw: 454, currentC: nil))
    }

    /// A pack whose extremes have not diverged yet is legitimate, and used to be
    /// thrown away by a strict max-greater-than-min test.
    func testAPackThatHasOnlySeenOneTemperatureIsKept() throws {
        let whole = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 25, maxRaw: 25, currentC: 25))
        XCTAssertEqual(whole.min, 25, accuracy: 0.001)
        XCTAssertEqual(whole.max, 25, accuracy: 0.001)

        let deci = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 250, maxRaw: 250, currentC: 25))
        XCTAssertEqual(deci.max, 25, accuracy: 0.001)
    }

    /// The magnitude rule's exact edge. 80 is a plausible whole-degree maximum;
    /// 81 can only be tenths.
    func testTheScaleThresholdBoundaries() throws {
        let eighty = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 20, maxRaw: 80, currentC: nil))
        XCTAssertEqual(eighty.max, 80, accuracy: 0.001)

        let eightyOne = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 200, maxRaw: 810, currentC: nil))
        XCTAssertEqual(eightyOne.max, 81, accuracy: 0.001)
    }

    /// Where magnitude alone would guess wrong, the pack's own thermometer
    /// overrules it: a max of 80 reads as whole degrees by magnitude, but a
    /// machine sitting at 30°C cannot have a lifetime maximum of 8°C.
    func testTheThermometerOverrulesTheMagnitudeRule() throws {
        let resolved = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 5, maxRaw: 80, currentC: 30))
        XCTAssertEqual(resolved.max, 80, accuracy: 0.001, "30°C fits 5...80, not 0.5...8")

        // And the mirror: a range that only makes sense as tenths.
        let tenths = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 87, maxRaw: 454, currentC: 30))
        XCTAssertEqual(tenths.max, 45.4, accuracy: 0.001)
    }

    /// When both readings are plausible AND both contain the current
    /// temperature, the scale is genuinely unresolved and nothing is shown.
    ///
    /// This fixture really does reach that branch, which matters: the case it
    /// replaced (-80 to 450) does not, because the whole-degree reading fails
    /// the plausibility net long before containment is consulted.
    func testGenuinelyAmbiguousScaleShowsNothing() {
        XCTAssertNil(BatteryLifetime.temperatureRange(minRaw: 0, maxRaw: 90, currentC: 9.2))
    }

    /// The wide sub-zero ranges the M1s report resolve on containment alone: the
    /// whole-degree reading is refused as implausible, so only one candidate is
    /// left and the row survives.
    func testWideSubZeroRangeResolvesWithoutAmbiguity() throws {
        let resolved = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: -80, maxRaw: 450, currentC: 30.8))
        XCTAssertEqual(resolved.min, -8, accuracy: 0.001)
        XCTAssertEqual(resolved.max, 45, accuracy: 0.001)
    }

    /// The temperature correction moves every Mac reading, by 2-3°C
    /// near 30°C and by much more further out (it is a scale change, not an
    /// offset), and this cross-check consumes it, so a range whose edge sits
    /// within that shift can flip. No corpus machine does, but the behaviour should change
    /// only on purpose: these pin both directions.
    func testTheTemperatureCorrectionCanFlipABoundaryCase() {
        // Raw 3050 meant 30.50°C under the old conversion and means 31.85°C now.
        // A lifetime range of 10 to 30, with a degree of slack, contained the old
        // reading and does not contain the new one.
        let old = BatteryHealth.celsius(fromCentiCelsius: 3050)                          // 30.50
        let corrected = BatteryHealth.celsius(
            fromCentiCelsius: BatteryHealth.centiCelsius(fromDeciKelvin: 3050) ?? 0       // 31.85
        )
        XCTAssertNotNil(BatteryLifetime.temperatureRange(minRaw: 10, maxRaw: 30, currentC: old))
        XCTAssertNil(
            BatteryLifetime.temperatureRange(minRaw: 10, maxRaw: 30, currentC: corrected),
            "a reading outside the range is a contradiction, and withholding is the point"
        )

        // The other direction: a range that only agrees once the reading is
        // corrected. 30.50 sits below 32 even with slack; 31.85 is inside it.
        XCTAssertNil(BatteryLifetime.temperatureRange(minRaw: 32, maxRaw: 40, currentC: old))
        XCTAssertNotNil(BatteryLifetime.temperatureRange(minRaw: 32, maxRaw: 40, currentC: corrected))
    }

    /// A missing thermometer must mean "unknown", not "0°C". Read as 0°C it
    /// would contradict every real range and silently delete the row, on the
    /// devices most likely to be missing the key.
    func testAnAbsentCurrentTemperatureDoesNotSuppressTheRange() throws {
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": 87,
            "MaximumTemperature": 454,
            "AverageTemperature": 245,
        ] as [String: Any]
        let lifetime = try XCTUnwrap(
            BatteryPackDetail.from(batteryData: data, currentTemperatureCentiC: nil)?.lifetime
        )
        XCTAssertEqual(lifetime.minimumTemperatureC, 9)
        XCTAssertEqual(lifetime.maximumTemperatureC, 45)
    }

    func testAverageTemperatureDroppedWhenNeitherScaleFits() throws {
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": 11,
            "MaximumTemperature": 41,
            "AverageTemperature": 9000,     // neither 9000 nor 900 sits in 11...41
        ] as [String: Any]
        let lifetime = try XCTUnwrap(BatteryPackDetail.from(batteryData: data)?.lifetime)
        XCTAssertNil(lifetime.averageTemperatureC)
    }

    func testWrappedDischargeCurrentDecodesToItsMagnitude() throws {
        // 18446744073709546764 is -4852 read as signed: a 4.85 A peak draw,
        // which is real data rather than the garbage it looks like.
        let lifetime = try XCTUnwrap(BatteryPackDetail.from(batteryData: realBatteryData())?.lifetime)
        XCTAssertEqual(lifetime.maximumDischargeCurrentMA, 4852)
        XCTAssertEqual(lifetime.maximumChargeCurrentMA, 6825)
    }

    func testGenuinelyImplausibleCurrentIsStillDropped() throws {
        var data = realBatteryData()
        data["LifetimeData"] = ["MaximumDischargeCurrent": 900_000, "MaximumChargeCurrent": 6825] as [String: Any]
        let lifetime = try XCTUnwrap(BatteryPackDetail.from(batteryData: data)?.lifetime)
        XCTAssertNil(lifetime.maximumDischargeCurrentMA)
    }

    func testLifetimeExtremesParsed() throws {
        let lifetime = try XCTUnwrap(BatteryPackDetail.from(batteryData: realBatteryData())?.lifetime)
        XCTAssertEqual(lifetime.minimumPackVoltageMV, 10144)
        XCTAssertEqual(lifetime.maximumPackVoltageMV, 13304)
        XCTAssertEqual(lifetime.totalOperatingTimeHours, 4712)
    }

    func testNilForAbsentOrEmptyData() {
        XCTAssertNil(BatteryPackDetail.from(batteryData: nil))
        XCTAssertNil(BatteryPackDetail.from(batteryData: [:]))
        XCTAssertNil(BatteryPackDetail.from(batteryData: ["SomethingElse": 1]))
    }

    func testOutOfRangeSocIsRejected() throws {
        var data = realBatteryData()
        data["DailyMinSoc"] = 250
        let detail = try XCTUnwrap(BatteryPackDetail.from(batteryData: data))
        XCTAssertNil(detail.dailyMinSoc)
        XCTAssertEqual(detail.dailyMaxSoc, 100)
    }

    func testMalformedArrayIsRejectedWholesale() {
        // Dropping the bad element would shift cell 3's voltage into cell 2's
        // row, mislabelling the data rather than admitting it is unreadable.
        let detail = BatteryPackDetail.from(batteryData: ["CellVoltage": [4409, "bad", 4411]])
        XCTAssertNil(detail)
    }

    func testImplausibleArrayValuesAreRejected() {
        // Also keeps the spread arithmetic from overflowing.
        let detail = BatteryPackDetail.from(batteryData: ["CellVoltage": [4409, Int.max, 4411]])
        XCTAssertNil(detail)
    }

    /// Containment settles what magnitude cannot, but it does not get to
    /// overrule it. A max of 90 can only be tenths; a current reading of 85°C
    /// nonetheless fits the whole-degree range and nothing else, so the old code
    /// confidently reported 20°C to 90°C off one signal while the other said the
    /// opposite.
    func testContainmentDoesNotOverruleMagnitude() {
        XCTAssertNil(BatteryLifetime.temperatureRange(minRaw: 20, maxRaw: 90, currentC: 85))
    }

    /// The two signals agreeing is the ordinary case and must still resolve.
    func testContainmentConfirmingMagnitudeStillResolves() throws {
        let range = try XCTUnwrap(BatteryLifetime.temperatureRange(minRaw: 87, maxRaw: 454, currentC: 30))
        XCTAssertEqual(range.min, 8.7, accuracy: 0.001)
        XCTAssertEqual(range.max, 45.4, accuracy: 0.001)
    }

    func testAmbiguousTemperatureScaleReportsNothing() throws {
        // 20 and 2.0 both sit inside 0...50, so the scale cannot be inferred.
        // A figure that might be out by ten times is worse than a blank row.
        var data = realBatteryData()
        data["LifetimeData"] = [
            "MinimumTemperature": 0,
            "MaximumTemperature": 50,
            "AverageTemperature": 20,
        ] as [String: Any]
        let lifetime = try XCTUnwrap(BatteryPackDetail.from(batteryData: data)?.lifetime)
        XCTAssertNil(lifetime.averageTemperatureC)
    }
}
