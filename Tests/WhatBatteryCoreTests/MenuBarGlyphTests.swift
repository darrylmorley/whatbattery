import XCTest
@testable import WhatBatteryCore

final class MenuBarGlyphTests: XCTestCase {
    private func snapshot(charge: Int, state: ChargingState) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            designCapacitymAh: 6249,
            fullChargeCapacitymAh: 6220,
            healthPercent: 99.5,
            cycleCount: 42,
            designCycleCount: 1000,
            currentChargePercent: charge,
            currentChargemAh: 6220,
            chargingState: state,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: nil,
            voltageMillivolts: 13222,
            amperageMilliamps: 0,
            powerWatts: 0,
            temperatureCelsius: 30,
            adapter: nil,
            deviceModel: "Mac17,2",
            batterySerial: nil,
            manufactureDate: nil
        )
    }

    /// Any on-power state shows the bolt regardless of fill: it is the only
    /// bolt variant SF Symbols ships, and the bolt is the signal.
    func testOnPowerShowsBolt() {
        for state in [ChargingState.charging, .full, .acNoCharge] {
            XCTAssertEqual(MenuBarGlyph.symbolName(for: snapshot(charge: 42, state: state)),
                           "battery.100percent.bolt")
        }
    }

    func testDischargingMapsToNearestQuartile() {
        let cases: [(Int, String)] = [
            (0, "battery.0percent"), (12, "battery.0percent"),
            (13, "battery.25percent"), (37, "battery.25percent"),
            (38, "battery.50percent"), (62, "battery.50percent"),
            (63, "battery.75percent"), (87, "battery.75percent"),
            (88, "battery.100percent"), (100, "battery.100percent"),
        ]
        for (percent, expected) in cases {
            XCTAssertEqual(MenuBarGlyph.symbolName(for: snapshot(charge: percent, state: .discharging)),
                           expected, "at \(percent)%")
        }
    }

    func testDesktopShowsPowerPlug() {
        XCTAssertEqual(MenuBarGlyph.symbolName(for: nil), "powerplug")
    }

    func testAccessibilityDescribesState() {
        XCTAssertEqual(MenuBarGlyph.accessibilityDescription(for: snapshot(charge: 42, state: .charging)),
                       "WhatBattery: 42 percent, charging")
        XCTAssertEqual(MenuBarGlyph.accessibilityDescription(for: nil), "WhatBattery")
    }
}
