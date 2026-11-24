import XCTest
@testable import WhatBatteryCore

/// The shared display rules every surface goes through, so one kind of value
/// reads the same everywhere ("55 W", never "55W" on one tab and "55.0 W" on
/// the next).
final class DisplayFormatTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")
    private let gb = Locale(identifier: "en_GB")
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testWholeWattsHasASpaceBeforeTheUnit() {
        XCTAssertEqual(BatteryFormatter.wholeWatts(55.4, locale: posix), "55 W")
        XCTAssertEqual(BatteryFormatter.wholeWatts(73.6, locale: posix), "74 W")
        XCTAssertEqual(BatteryFormatter.wholeWatts(0, locale: posix), "0 W")
        // A tiny negative must not round to a signed zero.
        XCTAssertEqual(BatteryFormatter.wholeWatts(-0.4, locale: posix), "0 W")
    }

    func testChargerNameDropsTheRawPDDescription() {
        XCTAssertEqual(BatteryFormatter.chargerName("96W pd charger"), "96W charger")
        XCTAssertEqual(BatteryFormatter.chargerName("100W PD Charger"), "100W charger")
        XCTAssertEqual(BatteryFormatter.chargerName("pd charger"), "Charger")
    }

    func testChargerNameLeavesRealNamesAlone() {
        XCTAssertEqual(BatteryFormatter.chargerName("96W USB-C Power Adapter"), "96W USB-C Power Adapter")
        XCTAssertEqual(BatteryFormatter.chargerName("Unknown charger"), "Unknown charger")
        // Only the whole word "pd" goes, never the tail of another word.
        XCTAssertEqual(BatteryFormatter.chargerName("Upd charger"), "Upd charger")
        // Stray whitespace from the firmware must not leave a nameless " charger".
        XCTAssertEqual(BatteryFormatter.chargerName(" PD Charger"), "Charger")
        XCTAssertEqual(BatteryFormatter.chargerName("96W pd charger "), "96W charger")
        XCTAssertEqual(BatteryFormatter.chargerName("96W pd charger\n"), "96W charger")
        XCTAssertEqual(BatteryFormatter.chargerName(" Unknown charger "), "Unknown charger")
        XCTAssertEqual(BatteryFormatter.chargerName("96W\n pd charger"), "96W charger")
        XCTAssertEqual(BatteryFormatter.chargerName("96W\tpd charger"), "96W charger")
        XCTAssertEqual(BatteryFormatter.chargerName("İstanbul PD Charger"), "İstanbul charger")
        XCTAssertEqual(BatteryFormatter.chargerName(" \n"), "Charger")
    }

    func testRangeReadsLowToHigh() {
        XCTAssertEqual(BatteryFormatter.range(10.64, 32.81, unit: "°C", decimals: 1, locale: posix), "10.6 to 32.8°C")
        XCTAssertEqual(BatteryFormatter.range(10.99, 13.22, unit: " V", decimals: 2, locale: posix), "10.99 to 13.22 V")
    }

    func testTemperatureRangeFollowsTheChosenUnit() {
        XCTAssertEqual(BatteryFormatter.temperatureRange(10.6, 32.8, unit: .celsius, locale: posix), "10.6 to 32.8°C")
        XCTAssertEqual(BatteryFormatter.temperatureRange(10, 30, unit: .fahrenheit, locale: posix), "50.0 to 86.0°F")
        // The gauge's lifetime extremes are whole degrees; no invented decimal.
        XCTAssertEqual(BatteryFormatter.temperatureRange(9, 43, unit: .celsius, decimals: 0, locale: posix), "9 to 43°C")
    }

    func testUnitConvertsACelsiusValueForPlotting() {
        XCTAssertEqual(BatteryFormatter.TemperatureUnit.celsius.value(fromCelsius: 30), 30)
        XCTAssertEqual(BatteryFormatter.TemperatureUnit.fahrenheit.value(fromCelsius: 30), 86, accuracy: 0.0001)
        XCTAssertEqual(BatteryFormatter.TemperatureUnit.fahrenheit.symbol, "°F")
    }

    func testDayIsWrittenOutNotISO() {
        let date = utc.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
        XCTAssertEqual(BatteryFormatter.day(date, locale: gb, calendar: utc), "24 Nov 2026")
    }

    func testMonthIsWrittenOutNotISO() {
        XCTAssertEqual(BatteryFormatter.month(year: 2026, month: 7, locale: gb, calendar: utc), "Jul 2026")
    }
}
