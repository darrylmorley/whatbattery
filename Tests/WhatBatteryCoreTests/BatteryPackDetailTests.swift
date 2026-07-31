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
