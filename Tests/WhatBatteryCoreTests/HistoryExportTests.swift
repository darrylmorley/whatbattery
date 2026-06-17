import XCTest
@testable import WhatBatteryCore

final class HistoryExportTests: XCTestCase {
    private func sample(
        ts: TimeInterval = 1_700_000_000,
        charge: Int = 80,
        temp: Double = 30.5,
        mv: Int = 12345,
        power: Double = -5.25,
        cycles: Int = 100,
        health: Double? = 91.5
    ) -> BatterySample {
        BatterySample(
            timestamp: Date(timeIntervalSince1970: ts),
            chargePercent: charge,
            temperatureCelsius: temp,
            voltageMillivolts: mv,
            powerWatts: power,
            cycleCount: cycles,
            healthPercent: health
        )
    }

    func testEmptySamplesReturnsHeaderOnly() {
        let csv = HistoryExport.csv([])
        XCTAssertEqual(csv, HistoryExport.csvHeader + "\n")
    }

    func testCsvHeaderColumnsMatchSchema() {
        XCTAssertEqual(
            HistoryExport.csvHeader,
            "timestamp,charge_pct,temp_c,voltage_mv,power_w,cycle_count,health_pct"
        )
    }

    func testCsvRowFieldsAndOrder() {
        let csv = HistoryExport.csv([sample()])
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(rows.count, 2)
        let fields = rows[1].split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, 7)
        XCTAssertEqual(fields[0], "2023-11-14T22:13:20Z")   // ISO 8601, UTC
        XCTAssertEqual(fields[1], "80")
        XCTAssertEqual(fields[2], "30.500")
        XCTAssertEqual(fields[3], "12345")
        XCTAssertEqual(fields[4], "-5.250")
        XCTAssertEqual(fields[5], "100")
        XCTAssertEqual(fields[6], "91.500")
    }

    func testNilHealthIsEmptyCell() {
        let csv = HistoryExport.csv([sample(health: nil)])
        let lastField = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false).last
        XCTAssertEqual(lastField, "")
    }

    func testDoublesUseDecimalPointWithExactOutput() {
        // The decimal separator must stay a `.` (forced POSIX locale), and the
        // value must land in its own column. Exact-match, not self-referential.
        let csv = HistoryExport.csv([sample(temp: 1234.5, power: 6.7)])
        let fields = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, 7)
        XCTAssertEqual(fields[2], "1234.500")
        XCTAssertEqual(fields[4], "6.700")
    }

    func testJsonRoundTripsToSamples() throws {
        let original = [sample(), sample(ts: 1_700_000_300, charge: 81, health: nil)]
        let data = try HistoryExport.json(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([BatterySample].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJsonEmptyArray() throws {
        let data = try HistoryExport.json([])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode([BatterySample].self, from: data), [])
    }
}
