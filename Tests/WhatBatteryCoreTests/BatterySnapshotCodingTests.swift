import XCTest
@testable import WhatBatteryCore

/// The snapshot's coding is hand-written for one reason: `--json` and the
/// widget's shared file must be able to withhold the figures the window hides
/// behind a licence. These cover that gate and the compatibility the
/// hand-written version has to keep.
final class BatterySnapshotCodingTests: XCTestCase {
    private func makeSnapshot() -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            designCapacitymAh: 6249,
            fullChargeCapacitymAh: 6220,
            healthPercent: 99.5,
            cycleCount: 42,
            designCycleCount: 1000,
            currentChargePercent: 77,
            currentChargemAh: 4789,
            chargingState: .discharging,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: 214,
            atCriticalLevel: false,
            voltageMillivolts: 13222,
            amperageMilliamps: -1850,
            instantAmperageMilliamps: -3200,
            powerWatts: -24.5,
            temperatureCelsius: 30.4,
            adapter: nil,
            deviceModel: "Mac17,2",
            batterySerial: "F5D1234567890ABCD",
            manufactureMonth: BatteryManufactureMonth(year: 2026, month: 1)
        )
    }

    private func encoded(_ snapshot: BatterySnapshot, omitProDetail: Bool) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if omitProDetail {
            encoder.userInfo[.omitProDetail] = true
        }
        let data = try encoder.encode(snapshot)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEncodesEveryFieldByDefault() throws {
        let object = try encoded(makeSnapshot(), omitProDetail: false)
        XCTAssertEqual(object["designCapacitymAh"] as? Int, 6249)
        XCTAssertEqual(object["fullChargeCapacitymAh"] as? Int, 6220)
        XCTAssertEqual(object["currentChargemAh"] as? Int, 4789)
        XCTAssertEqual(object["instantAmperageMilliamps"] as? Int, -3200)
        XCTAssertEqual(object["atCriticalLevel"] as? Bool, false)
        XCTAssertNotNil(object["manufactureMonth"])
    }

    /// `currentChargemAh` goes with the capacities deliberately: on its own it
    /// divides by the charge percent straight back into the full-charge capacity
    /// the gate exists to withhold. `manufactureMonth` is here because the
    /// window gates it, so `--json` must too.
    func testOmitsEveryProFigureWhenAsked() throws {
        let object = try encoded(makeSnapshot(), omitProDetail: true)
        XCTAssertNil(object["designCapacitymAh"])
        XCTAssertNil(object["fullChargeCapacitymAh"])
        XCTAssertNil(object["currentChargemAh"])
        XCTAssertNil(object["manufactureMonth"])
        // The percentage figures are free in the app, so they stay here too.
        XCTAssertEqual(object["healthPercent"] as? Double, 99.5)
        XCTAssertEqual(object["currentChargePercent"] as? Int, 77)
        XCTAssertEqual(object["cycleCount"] as? Int, 42)
        // Not gated: the window hides the battery serial, but --json has always
        // published it, and narrowing shipped output is its own decision.
        XCTAssertEqual(object["batterySerial"] as? String, "F5D1234567890ABCD")
    }

    func testRedactedPayloadStillDecodes() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.userInfo[.omitProDetail] = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(BatterySnapshot.self, from: try encoder.encode(makeSnapshot()))
        XCTAssertEqual(decoded.designCapacitymAh, 0)
        XCTAssertEqual(decoded.fullChargeCapacitymAh, 0)
        XCTAssertEqual(decoded.currentChargemAh, 0)
        XCTAssertNil(decoded.manufactureMonth)
        XCTAssertEqual(decoded.currentChargePercent, 77)
    }

    func testRoundTripsUnchanged() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = makeSnapshot()
        XCTAssertEqual(try decoder.decode(BatterySnapshot.self, from: try encoder.encode(original)), original)
    }

    /// The widget reads a file the app wrote, and an upgrade can leave the two
    /// briefly out of step, so fields added since must decode as absent rather
    /// than fail the whole read.
    func testDecodesPayloadFromAnOlderVersion() throws {
        let json = """
        {
          "timestamp": "2023-11-14T22:13:20Z",
          "designCapacitymAh": 6249,
          "fullChargeCapacitymAh": 6220,
          "healthPercent": 99.5,
          "cycleCount": 42,
          "designCycleCount": 1000,
          "currentChargePercent": 77,
          "currentChargemAh": 4789,
          "chargingState": "discharging",
          "voltageMillivolts": 13222,
          "amperageMilliamps": -1850,
          "powerWatts": -24.5,
          "temperatureCelsius": 30.4,
          "deviceModel": "Mac17,2"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BatterySnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.instantAmperageMilliamps, 0)
        XCTAssertFalse(decoded.atCriticalLevel)
        XCTAssertNil(decoded.adapter)
        XCTAssertNil(decoded.batterySerial)
        XCTAssertEqual(decoded.fullChargeCapacitymAh, 6220)
    }
    /// An absent temperature is absent from the payload, not zero in it. The
    /// widget and any `--json` consumer must be able to tell "no reading" from
    /// "0.0°C", which is the whole point of the optional.
    func testAbsentTemperatureIsOmittedAndRoundTrips() throws {
        var snapshot = makeSnapshot()
        snapshot = BatterySnapshot(
            timestamp: snapshot.timestamp,
            designCapacitymAh: snapshot.designCapacitymAh,
            fullChargeCapacitymAh: snapshot.fullChargeCapacitymAh,
            healthPercent: snapshot.healthPercent,
            cycleCount: snapshot.cycleCount,
            designCycleCount: snapshot.designCycleCount,
            currentChargePercent: snapshot.currentChargePercent,
            currentChargemAh: snapshot.currentChargemAh,
            chargingState: snapshot.chargingState,
            timeToFullMinutes: snapshot.timeToFullMinutes,
            timeToEmptyMinutes: snapshot.timeToEmptyMinutes,
            atCriticalLevel: snapshot.atCriticalLevel,
            voltageMillivolts: snapshot.voltageMillivolts,
            amperageMilliamps: snapshot.amperageMilliamps,
            instantAmperageMilliamps: snapshot.instantAmperageMilliamps,
            powerWatts: snapshot.powerWatts,
            temperatureCelsius: nil,
            adapter: snapshot.adapter,
            deviceModel: snapshot.deviceModel,
            batterySerial: snapshot.batterySerial,
            manufactureMonth: snapshot.manufactureMonth
        )
        let data = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["temperatureCelsius"])

        let decoder = JSONDecoder()
        XCTAssertNil(try decoder.decode(BatterySnapshot.self, from: data).temperatureCelsius)
    }

}
