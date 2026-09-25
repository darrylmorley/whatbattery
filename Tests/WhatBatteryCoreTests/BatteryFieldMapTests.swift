import XCTest
@testable import WhatBatteryCore

/// Shapes measured 2026-09-24 over probe 32 (944 dumps carry the key, every
/// one inside the node's `BatteryData.LifetimeData`) and on one macOS 27
/// MacBook (the pack's `BatteryData.LifetimeData`, 82).
final class BatteryFieldMapTests: XCTestCase {
    private func resolve(_ tree: BatteryTree) -> FieldResolution<Int> {
        BatteryFieldResolver.resolve(BatteryFieldMap.cycleCountAtLastQmax, in: tree)
    }

    func testMacOS26ShapeReadsTheNodesLifetimeData() {
        let result = resolve(BatteryTree(battery: ["BatteryData": ["LifetimeData": ["CycleCountLastQmax": 45]]]))
        XCTAssertEqual(result.value, 45)
        XCTAssertEqual(result.location?.description, "battery:BatteryData.LifetimeData.CycleCountLastQmax")
        XCTAssertFalse(result.foundBySearch)
    }

    func testMacOS27ShapeReadsThePacksLifetimeData() {
        let tree = BatteryTree(
            battery: ["BatteryData": ["DesignCapacity": 6249]],
            pack: ["BatteryData": ["LifetimeData": ["CycleCountLastQmax": 82]]]
        )
        let result = resolve(tree)
        XCTAssertEqual(result.value, 82)
        XCTAssertEqual(result.location?.description, "pack:BatteryData.LifetimeData.CycleCountLastQmax")
        XCTAssertFalse(result.foundBySearch)
    }

    func testAFutureMoveIsFoundBySearch() {
        let tree = BatteryTree(battery: [:], pack: ["BatteryData": ["CycleCountLastQmax": 90]])
        let result = resolve(tree)
        XCTAssertEqual(result.value, 90)
        XCTAssertTrue(result.foundBySearch)
    }

    /// 8 of the corpus renderings carry 0: never relearned, not a real count.
    func testZeroAndImplausibleValuesAreAbsent() {
        XCTAssertNil(resolve(BatteryTree(battery: ["BatteryData": ["LifetimeData": ["CycleCountLastQmax": 0]]])).value)
        XCTAssertNil(resolve(BatteryTree(battery: ["BatteryData": ["LifetimeData": ["CycleCountLastQmax": 20_000]]])).value)
    }

    func testTopLevelKeysNameEveryMappedField() {
        XCTAssertEqual(BatteryFieldMap.topLevelKeys, ["CycleCountLastQmax"])
    }

    func testReportNamesWhereEachFieldWasFound() {
        let tree = BatteryTree(battery: [:], pack: ["BatteryData": ["LifetimeData": ["CycleCountLastQmax": 82]]])
        XCTAssertEqual(BatteryFieldMap.report(tree), [
            FieldReportRow(
                key: "CycleCountLastQmax",
                value: "82",
                location: "pack:BatteryData.LifetimeData.CycleCountLastQmax",
                foundBySearch: false
            ),
        ])
    }

    func testRenderMarksSearchHitsAndMissingFields() {
        let rows = [
            FieldReportRow(key: "A", value: "1", location: "battery:BatteryData.A", foundBySearch: false),
            FieldReportRow(key: "B", value: "2", location: "pack:Moved.B", foundBySearch: true),
            FieldReportRow(key: "C", value: nil, location: nil, foundBySearch: false),
        ]
        XCTAssertEqual(BatteryFieldMap.render(rows), """
        A  1  battery:BatteryData.A
        B  2  pack:Moved.B  (found by search, not a known location)
        C  not found
        """)
    }
}
