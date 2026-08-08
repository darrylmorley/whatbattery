import XCTest
@testable import WhatBatteryCore

/// The vectors here are real values from the whatcable probe corpus, not
/// invented ones: the encoding was reverse engineered from 810 machines and
/// these are the anchors that pinned it.
final class BatteryManufactureMonthTests: XCTestCase {
    /// Six ASCII digits packed into an integer, the way the gauge stores them.
    private func raw(_ digits: String) -> Int {
        digits.utf8.reduce(0) { $0 << 8 | Int($1) }
    }

    private func at(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    private let now = Date(timeIntervalSince1970: 1_786_000_000)  // 2026-08-06

    func testDecodesRealCorpusValues() {
        // This Mac: an M5, read live. Its raw value is 55186860028979.
        let mine = BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "bq40z651", now: now)
        XCTAssertEqual(mine?.year, 2026)
        XCTAssertEqual(mine?.month, 1)
        XCTAssertEqual(mine?.label, "January 2026")

        // m5_macos26.3: a pack made in the M5's launch month.
        let m5 = BatteryManufactureMonth.decode(raw: raw("120133"), gaugeName: "bq40z651", now: now)
        XCTAssertEqual(m5?.label, "October 2025")

        // m1_macos14.8.3, on the older gauge: December 2020, a month after the
        // M1 shipped.
        let m1 = BatteryManufactureMonth.decode(raw: raw("102182"), gaugeName: "bq20z451", now: now)
        XCTAssertEqual(m1?.label, "December 2020")
    }

    func testRawValueMatchesTheGaugesInteger() {
        // Guards the packing the other tests rely on: both of these were read
        // off real hardware, the first from this Mac and the second from the
        // corpus iPhone.
        XCTAssertEqual(raw("211043"), 55_186_860_028_979)
        XCTAssertEqual(raw("816009"), 61_784_013_680_697)
    }

    /// Read forwards the same digits are a different (and usually impossible)
    /// date, so a regression that drops the reversal fails loudly.
    func testDigitsAreReadBackwards() {
        // "340112" forwards would be year 2026+34, month 01, day 12.
        let forwards = BatteryManufactureMonth.decode(raw: raw("340112"), gaugeName: "bq40z651", now: now)
        XCTAssertNil(forwards, "211043 and 340112 must not both decode")
    }

    func testRejectsGaugesTheEncodingIsNotProvenOn() {
        // The corpus iPhone's gauge. This value decodes to 2082 under the Mac
        // scheme, which is exactly why an unknown gauge gets nothing.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("816009"), gaugeName: "SN7038", now: now))
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "SN7038", now: now))
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "", now: now))
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "something-new", now: now))
    }

    func testAcceptsTheApplePartGauges() {
        XCTAssertEqual(
            BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "A1964", now: now)?.label,
            "January 2026"
        )
    }

    /// The day is never displayed, but an impossible one means we have misread
    /// the field, so the whole reading is dropped.
    func testRejectsAnImpossibleDay() {
        // reversed "330230" -> 30 February 2025.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("032033"), gaugeName: "bq40z651", now: now))
        // reversed "330001" -> day 01, month 00.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("100033"), gaugeName: "bq40z651", now: now))
    }

    func testRejectsAPackMadeInTheFuture() {
        // reversed "350612" -> June 2027, read in August 2026.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("216053"), gaugeName: "bq40z651", now: now))
    }

    /// A pack assembled days ago still reads, because the comparison is by
    /// month. There is no slack past that.
    func testAcceptsThePresentMonth() {
        // reversed "340801" -> August 2026, the month of `now`.
        XCTAssertEqual(
            BatteryManufactureMonth.decode(raw: raw("108043"), gaugeName: "bq40z651", now: now)?.label,
            "August 2026"
        )
    }

    func testRejectsNextMonth() {
        // reversed "340901" -> September 2026, one month past `now`.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("109043"), gaugeName: "bq40z651", now: now))
    }

    /// The future test does arithmetic on year and month together, so the turn
    /// of the year is where an off-by-one would hide.
    func testTheYearBoundaryIsNotAWayIntoTheFuture() {
        let december = Date(timeIntervalSince1970: 1_797_000_000)  // 2026-12-10
        // reversed "341201" -> December 2026, the month of `now`: allowed.
        XCTAssertEqual(
            BatteryManufactureMonth.decode(raw: raw("102143"), gaugeName: "bq40z651", now: december)?.label,
            "December 2026"
        )
        // reversed "350101" -> January 2027, the next month across the year
        // boundary: refused, exactly as September 2026 is in August.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("101053"), gaugeName: "bq40z651", now: december))
    }

    func testRejectsAGaugeNameTheCorpusNeverShowedUs() {
        // A bare prefix would have admitted both of these.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "bq", now: now))
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "bq-unknown", now: now))
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "bqz", now: now))
        // The real part names still decode, in any case.
        XCTAssertNotNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "bq40z651", now: now))
        XCTAssertNotNil(BatteryManufactureMonth.decode(raw: raw("211043"), gaugeName: "BQ20Z451", now: now))
    }

    /// `YY` is two digits from 1992, so the encoding cannot express a year
    /// outside 1992...2091, and no Mac pack predates the Intel-era gauges.
    func testYearMustBeInsideTheEncodingsDomain() {
        XCTAssertNil(BatteryManufactureMonth(year: 2004, month: 6))
        XCTAssertNil(BatteryManufactureMonth(year: 2092, month: 1))
        XCTAssertNil(BatteryManufactureMonth(year: -1, month: 1))
        XCTAssertNotNil(BatteryManufactureMonth(year: 2005, month: 1))
        XCTAssertNotNil(BatteryManufactureMonth(year: 2091, month: 12))
    }

    /// Both ways in have to enforce the same rules, or a payload can build a
    /// value the initialiser would have refused.
    func testDecodingEnforcesTheSameDomainAsTheInitialiser() {
        for bad in [#"{"year":-1,"month":1}"#, #"{"year":9999,"month":1}"#, #"{"year":2004,"month":6}"#] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(BatteryManufactureMonth.self, from: Data(bad.utf8)),
                "should have refused \(bad)"
            )
        }
    }

    func testRejectsSomethingFarTooOldToBeAMacPack() {
        // reversed "120610" -> June 2004.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("016021"), gaugeName: "bq40z651", now: now))
    }

    func testRejectsMalformedFields() {
        XCTAssertNil(BatteryManufactureMonth.decode(raw: nil, gaugeName: "bq40z651", now: now))
        XCTAssertNil(BatteryManufactureMonth.decode(raw: 0, gaugeName: "bq40z651", now: now))
        // Five digits, not six.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("21104"), gaugeName: "bq40z651", now: now))
        // Six bytes, but not all digits.
        XCTAssertNil(BatteryManufactureMonth.decode(raw: raw("21A043"), gaugeName: "bq40z651", now: now))
    }

    func testMonthMustBeARealMonth() {
        XCTAssertNil(BatteryManufactureMonth(year: 2026, month: 0))
        XCTAssertNil(BatteryManufactureMonth(year: 2026, month: 13))
        XCTAssertNotNil(BatteryManufactureMonth(year: 2026, month: 12))
    }

    /// The synthesized decoder would walk past the failable init and build a
    /// month the type says cannot exist.
    func testDecodingRejectsAnImpossibleMonth() {
        let bad = Data(#"{"year":2026,"month":99}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(BatteryManufactureMonth.self, from: bad))
        let good = Data(#"{"year":2026,"month":1}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BatteryManufactureMonth.self, from: good).label, "January 2026")
    }

    /// A corrupt month must not take the whole snapshot read down with it
    /// either: the widget decodes this file on every refresh.
    func testASnapshotCarryingACorruptMonthFailsToDecodeRatherThanCrash() {
        let json = """
        {"timestamp":"2026-08-06T00:00:00Z","designCapacitymAh":6249,"fullChargeCapacitymAh":5949,
         "healthPercent":95.2,"cycleCount":64,"designCycleCount":1000,"currentChargePercent":69,
         "currentChargemAh":4100,"chargingState":"discharging","voltageMillivolts":11940,
         "amperageMilliamps":-780,"powerWatts":-9.3,"temperatureCelsius":30.5,"deviceModel":"Mac17,2",
         "manufactureMonth":{"year":2026,"month":99}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(BatterySnapshot.self, from: Data(json.utf8)))
    }

    func testLabelsEveryMonth() {
        XCTAssertEqual(BatteryManufactureMonth(year: 2020, month: 9)?.label, "September 2020")
        XCTAssertEqual(BatteryManufactureMonth(year: 2018, month: 6)?.label, "June 2018")
    }

    /// The builder is where the raw field and the gauge name meet, and it is the
    /// only place that should be decoding.
    func testSnapshotBuilderDecodesThroughThePackDetail() {
        let battery = AppleSmartBattery(
            batteryInstalled: true,
            deviceName: "bq40z651",
            designCapacity: 6249,
            nominalChargeCapacity: 5973,
            packDetail: BatteryPackDetail(manufactureRaw: raw("211043"))
        )
        let snapshot = BatterySnapshotBuilder.build(
            battery: battery, deviceModel: "Mac17,2", smcDischargeWatts: nil, now: now
        )
        XCTAssertEqual(snapshot.manufactureMonth?.label, "January 2026")

        // Same pack, gauge we cannot read: no date rather than a wrong one.
        let unknown = AppleSmartBattery(
            batteryInstalled: true,
            deviceName: "SN7038",
            designCapacity: 6249,
            nominalChargeCapacity: 5973,
            packDetail: BatteryPackDetail(manufactureRaw: raw("211043"))
        )
        XCTAssertNil(
            BatterySnapshotBuilder.build(
                battery: unknown, deviceModel: "Mac17,2", smcDischargeWatts: nil, now: now
            ).manufactureMonth
        )
    }
}
