import XCTest
@testable import WhatBatteryCore

final class MonthlyHealthSummaryTests: XCTestCase {
    /// A fixed UTC calendar so month grouping is deterministic regardless of the
    /// machine's time zone.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = 12
        return utc.date(from: components)!
    }

    private func record(
        id: String = "MAC-1",
        kind: DeviceKind = .mac,
        date: Date,
        name: String = "MacBook Pro",
        model: String = "Mac17,2",
        os: String = "26.4.0",
        cycles: Int = 42,
        health: Double? = 97,
        full: Int = 6069
    ) -> HealthRecord {
        HealthRecord(
            deviceID: id, kind: kind, date: date, model: model, name: name, osVersion: os,
            cycleCount: cycles, healthPercent: health, designCapacitymAh: 6249, fullChargeCapacitymAh: full
        )
    }

    // MARK: - MonthlyHealthSummary.compute

    func testEmptyRecordsYieldNoSummaries() {
        XCTAssertEqual(MonthlyHealthSummary.compute(from: [], calendar: utc), [])
    }

    func testSingleRecordOneMonth() {
        let summaries = MonthlyHealthSummary.compute(from: [record(date: date(2026, 6, 16))], calendar: utc)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].label, "2026-06")
        XCTAssertEqual(summaries[0].avgHealthPercent, 97)
        XCTAssertEqual(summaries[0].latestCycleCount, 42)
        XCTAssertEqual(summaries[0].recordCount, 1)
    }

    func testAveragesHealthAndTakesLatestCyclesWithinMonth() {
        let records = [
            record(date: date(2026, 6, 2), cycles: 40, health: 98),
            record(date: date(2026, 6, 20), cycles: 44, health: 96, full: 6000),
        ]
        let summaries = MonthlyHealthSummary.compute(from: records, calendar: utc)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].avgHealthPercent, 97)             // (98 + 96) / 2
        XCTAssertEqual(summaries[0].latestCycleCount, 44)            // latest by date
        XCTAssertEqual(summaries[0].latestFullChargemAh, 6000)
        XCTAssertEqual(summaries[0].recordCount, 2)
    }

    func testMultipleMonthsSortedNewestFirst() {
        let records = [
            record(date: date(2026, 4, 10)),
            record(date: date(2026, 6, 10)),
            record(date: date(2026, 5, 10)),
        ]
        let labels = MonthlyHealthSummary.compute(from: records, calendar: utc).map(\.label)
        XCTAssertEqual(labels, ["2026-06", "2026-05", "2026-04"])
    }

    func testYearBoundarySortsByYearThenMonth() {
        let records = [
            record(date: date(2025, 12, 31)),
            record(date: date(2026, 1, 1)),
        ]
        let labels = MonthlyHealthSummary.compute(from: records, calendar: utc).map(\.label)
        XCTAssertEqual(labels, ["2026-01", "2025-12"])
    }

    func testAvgHealthNilWhenAllHealthMissing() {
        let records = [
            record(date: date(2026, 6, 2), health: nil),
            record(date: date(2026, 6, 3), health: nil),
        ]
        XCTAssertNil(MonthlyHealthSummary.compute(from: records, calendar: utc)[0].avgHealthPercent)
    }

    func testAvgHealthIgnoresNilReadings() {
        let records = [
            record(date: date(2026, 6, 2), health: nil),
            record(date: date(2026, 6, 3), health: 90),
            record(date: date(2026, 6, 4), health: 80),
        ]
        // Average over the two non-nil readings only.
        XCTAssertEqual(MonthlyHealthSummary.compute(from: records, calendar: utc)[0].avgHealthPercent, 85)
    }

    func testLabelIsZeroPadded() {
        let summaries = MonthlyHealthSummary.compute(from: [record(date: date(2026, 1, 5))], calendar: utc)
        XCTAssertEqual(summaries[0].label, "2026-01")
    }

    // MARK: - DeviceHealthHistory.group

    func testGroupEmpty() {
        XCTAssertEqual(DeviceHealthHistory.group([], calendar: utc), [])
    }

    func testGroupSplitsByDevice() {
        let records = [
            record(id: "MAC-1", kind: .mac, date: date(2026, 6, 1)),
            record(id: "UDID-9", kind: .iDevice, date: date(2026, 6, 2), name: "Darryl's iPhone", model: "iPhone 11", cycles: 768, health: 85),
        ]
        let groups = DeviceHealthHistory.group(records, calendar: utc)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.deviceID)), ["MAC-1", "UDID-9"])
    }

    func testGroupSortsMacsBeforeIDevices() {
        let records = [
            record(id: "UDID-9", kind: .iDevice, date: date(2026, 6, 5)),   // more recent
            record(id: "MAC-1", kind: .mac, date: date(2026, 6, 1)),
        ]
        let kinds = DeviceHealthHistory.group(records, calendar: utc).map(\.kind)
        XCTAssertEqual(kinds, [.mac, .iDevice])
    }

    func testGroupIdentityComesFromLatestRecord() {
        let records = [
            record(id: "MAC-1", date: date(2026, 4, 1), name: "Old Name", os: "26.0.0"),
            record(id: "MAC-1", date: date(2026, 6, 1), name: "New Name", os: "26.4.0"),
        ]
        let group = DeviceHealthHistory.group(records, calendar: utc)[0]
        XCTAssertEqual(group.name, "New Name")
        XCTAssertEqual(group.osVersion, "26.4.0")
        XCTAssertEqual(group.months.count, 2)
    }

    func testGroupComputesMonthsPerDevice() {
        let records = [
            record(id: "MAC-1", date: date(2026, 5, 1)),
            record(id: "MAC-1", date: date(2026, 6, 1)),
            record(id: "UDID-9", kind: .iDevice, date: date(2026, 6, 1)),
        ]
        let groups = DeviceHealthHistory.group(records, calendar: utc)
        let mac = groups.first { $0.deviceID == "MAC-1" }!
        let phone = groups.first { $0.deviceID == "UDID-9" }!
        XCTAssertEqual(mac.months.count, 2)
        XCTAssertEqual(phone.months.count, 1)
    }
}
