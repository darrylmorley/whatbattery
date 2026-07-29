import XCTest
@testable import WhatBatteryCore

final class AccessoryBLEMergeTests: XCTestCase {
    private func accessory(_ name: String, cells: [Accessory.Cell]) -> Accessory {
        Accessory(id: name, name: name, kind: .mouse, cells: cells, transport: "Bluetooth")
    }

    /// The point of the merge: a device the profiler lists with no battery gets
    /// its GATT level.
    func testFillsUnavailableAccessoryFromBLE() {
        let merged = AccessoryBLEMerge.merge(
            [accessory("MX Anywhere 2", cells: [])],
            bleLevels: ["MX Anywhere 2": 90]
        )
        XCTAssertEqual(merged[0].cells, [Accessory.Cell(label: "", percent: 90)])
        XCTAssertTrue(merged[0].isAvailable)
    }

    /// A profiler-reported level is richer (AirPods per-bud) and always wins.
    func testNeverOverridesProfilerLevels() {
        let pods = accessory("AirPods", cells: [.init(label: "Left", percent: 80), .init(label: "Right", percent: 75)])
        let merged = AccessoryBLEMerge.merge([pods], bleLevels: ["AirPods": 50])
        XCTAssertEqual(merged[0], pods)
    }

    func testNoBLEMatchLeavesAccessoryUntouched() {
        let mouse = accessory("MX Anywhere 2", cells: [])
        XCTAssertEqual(AccessoryBLEMerge.merge([mouse], bleLevels: [:]), [mouse])
        XCTAssertEqual(AccessoryBLEMerge.merge([mouse], bleLevels: ["Other Device": 50]), [mouse])
    }

    /// A GATT read that decodes outside 0-100 is a protocol violation, not a
    /// level; keep the accessory honestly unavailable.
    func testOutOfRangeLevelRejected() {
        let mouse = accessory("MX Anywhere 2", cells: [])
        XCTAssertEqual(AccessoryBLEMerge.merge([mouse], bleLevels: ["MX Anywhere 2": 101]), [mouse])
        XCTAssertEqual(AccessoryBLEMerge.merge([mouse], bleLevels: ["MX Anywhere 2": -1]), [mouse])
    }

    /// Name is the only join key, so a duplicated name is ambiguous: the level
    /// could belong to either device. Both stay untouched, even when only one
    /// of them lacks a level.
    func testDuplicateNamesAreNeverFilled() {
        let unavailable = accessory("MX Anywhere 2", cells: [])
        let populated = accessory("MX Anywhere 2", cells: [.init(label: "", percent: 40)])

        let bothEmpty = AccessoryBLEMerge.merge([unavailable, unavailable], bleLevels: ["MX Anywhere 2": 90])
        XCTAssertEqual(bothEmpty, [unavailable, unavailable])

        let mixed = AccessoryBLEMerge.merge([populated, unavailable], bleLevels: ["MX Anywhere 2": 90])
        XCTAssertEqual(mixed, [populated, unavailable])
    }

    func testIdentityAndOrderPreserved() {
        let list = [
            accessory("Keyboard", cells: [.init(label: "", percent: 100)]),
            accessory("MX Anywhere 2", cells: []),
        ]
        let merged = AccessoryBLEMerge.merge(list, bleLevels: ["MX Anywhere 2": 90])
        XCTAssertEqual(merged.map(\.id), ["Keyboard", "MX Anywhere 2"])
        XCTAssertEqual(merged[0], list[0])
    }
}
