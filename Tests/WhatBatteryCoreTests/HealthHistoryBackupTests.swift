import XCTest
@testable import WhatBatteryCore

final class HealthHistoryBackupTests: XCTestCase {
    private func record(id: String = "MAC-1", kind: DeviceKind = .mac, health: Double? = 97) -> HealthRecord {
        HealthRecord(
            deviceID: id, kind: kind, date: Date(timeIntervalSince1970: 1_700_000_000),
            model: "Mac17,2", name: "MacBook Pro", osVersion: "26.4.0",
            cycleCount: 42, healthPercent: health, designCapacitymAh: 6249, fullChargeCapacitymAh: 6069
        )
    }

    func testRoundTripPreservesRecords() throws {
        let original = [record(), record(id: "UDID-9", kind: .iDevice, health: 85), record(health: nil)]
        let data = try HealthHistoryBackup.encode(original)
        XCTAssertEqual(try HealthHistoryBackup.decode(data), original)
    }

    func testEmptyRoundTrips() throws {
        let data = try HealthHistoryBackup.encode([])
        XCTAssertEqual(try HealthHistoryBackup.decode(data), [])
    }

    func testBackupCarriesCurrentVersion() throws {
        let data = try HealthHistoryBackup.encode([record()])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthHistoryBackup.self, from: data)
        XCTAssertEqual(decoded.version, HealthHistoryBackup.currentVersion)
    }

    func testDecodesPreSerialBackup() throws {
        // A backup written before the `serial` field existed must still restore,
        // with serial defaulting to "".
        let json = """
        {
          "version": 1,
          "records": [
            {
              "deviceID": "MAC-1",
              "kind": "mac",
              "date": "2026-06-16T12:00:00Z",
              "model": "Mac17,2",
              "name": "MacBook Pro",
              "osVersion": "26.4.0",
              "cycleCount": 42,
              "healthPercent": 97,
              "designCapacitymAh": 6249,
              "fullChargeCapacitymAh": 6069
            }
          ]
        }
        """
        let records = try HealthHistoryBackup.decode(Data(json.utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].serial, "")
        XCTAssertEqual(records[0].deviceID, "MAC-1")
        XCTAssertEqual(records[0].cycleCount, 42)
    }

    func testDecodeRejectsNonBackupJSON() {
        let garbage = Data(#"{"something":1}"#.utf8)
        XCTAssertThrowsError(try HealthHistoryBackup.decode(garbage))
    }
}
