import XCTest
@testable import WhatBatteryCore

final class BatteryFieldResolverTests: XCTestCase {
    /// A positive-integer field, the shape most battery counts take.
    private func field(
        _ locations: [FieldLocation],
        searchAnywhere: Bool = false
    ) -> BatteryField<Int> {
        BatteryField(key: "K", locations: locations, searchAnywhere: searchAnywhere) { raw, _ in
            guard let n = (raw as? NSNumber)?.intValue, n > 0 else { return nil }
            return n
        }
    }

    private let nodeLifetime = FieldLocation(.battery, ["BatteryData", "LifetimeData", "K"])
    private let packLifetime = FieldLocation(.pack, ["BatteryData", "LifetimeData", "K"])

    func testReadsAKnownLocation() {
        let tree = BatteryTree(battery: ["BatteryData": ["LifetimeData": ["K": 45]]])
        let result = BatteryFieldResolver.resolve(field([nodeLifetime, packLifetime]), in: tree)
        XCTAssertEqual(result.value, 45)
        XCTAssertEqual(result.location, nodeLifetime)
        XCTAssertFalse(result.foundBySearch)
    }

    func testFallsThroughToTheNextKnownLocation() {
        let tree = BatteryTree(battery: [:], pack: ["BatteryData": ["LifetimeData": ["K": 82]]])
        let result = BatteryFieldResolver.resolve(field([nodeLifetime, packLifetime]), in: tree)
        XCTAssertEqual(result.value, 82)
        XCTAssertEqual(result.location?.description, "pack:BatteryData.LifetimeData.K")
    }

    func testFirstKnownLocationWinsWhenBothHaveIt() {
        let tree = BatteryTree(
            battery: ["BatteryData": ["LifetimeData": ["K": 45]]],
            pack: ["BatteryData": ["LifetimeData": ["K": 82]]]
        )
        XCTAssertEqual(BatteryFieldResolver.resolve(field([nodeLifetime, packLifetime]), in: tree).value, 45)
    }

    /// A present-but-empty value must not hide the real one (a WhatCable bug).
    func testAZeroValueDoesNotStopTheLookup() {
        let tree = BatteryTree(
            battery: ["BatteryData": ["LifetimeData": ["K": 0]]],
            pack: ["BatteryData": ["LifetimeData": ["K": 82]]]
        )
        XCTAssertEqual(BatteryFieldResolver.resolve(field([nodeLifetime, packLifetime]), in: tree).value, 82)
    }

    func testBanksCountOnlyWhenTheyAgree() {
        let bankKey = FieldLocation(.bank, ["BatteryData", "K"])
        let agree = BatteryTree(battery: [:], banks: [["BatteryData": ["K": 7]], ["BatteryData": ["K": 7]]])
        XCTAssertEqual(BatteryFieldResolver.resolve(field([bankKey]), in: agree).value, 7)
        let disagree = BatteryTree(battery: [:], banks: [["BatteryData": ["K": 7]], ["BatteryData": ["K": 8]]])
        XCTAssertNil(BatteryFieldResolver.resolve(field([bankKey]), in: disagree).value)
    }

    func testNoSearchUnlessTheFieldAllowsIt() {
        let tree = BatteryTree(battery: ["Elsewhere": ["K": 9]])
        let result = BatteryFieldResolver.resolve(field([nodeLifetime]), in: tree)
        XCTAssertNil(result.value)
        XCTAssertNil(result.location)
        XCTAssertFalse(result.foundBySearch)
    }

    func testSearchFindsTheKeyInAnUnknownPlace() {
        let tree = BatteryTree(battery: [:], pack: ["BatteryData": ["Moved": ["K": 12]]])
        let result = BatteryFieldResolver.resolve(field([nodeLifetime], searchAnywhere: true), in: tree)
        XCTAssertEqual(result.value, 12)
        XCTAssertEqual(result.location?.description, "pack:BatteryData.Moved.K")
        XCTAssertTrue(result.foundBySearch)
    }

    func testSearchPrefersTheHitNearestTheBatteryNode() {
        // battery:BatteryData.K is depth 0 + 2; pack:BatteryData.Deeper.K is 1 + 3.
        let tree = BatteryTree(
            battery: ["BatteryData": ["K": 5]],
            pack: ["BatteryData": ["Deeper": ["K": 6]]]
        )
        let result = BatteryFieldResolver.resolve(field([nodeLifetime], searchAnywhere: true), in: tree)
        XCTAssertEqual(result.value, 5)
        XCTAssertEqual(result.location?.description, "battery:BatteryData.K")
    }

    func testSearchGivesNothingWhenTheNearestHitsDisagree() {
        // battery:BatteryData.K and pack:K are both depth 2.
        let tree = BatteryTree(battery: ["BatteryData": ["K": 5]], pack: ["K": 6])
        XCTAssertNil(BatteryFieldResolver.resolve(field([nodeLifetime], searchAnywhere: true), in: tree).value)
    }

    func testSearchAcceptsNearestHitsThatAgree() {
        let tree = BatteryTree(battery: [:], banks: [["BatteryData": ["K": 3]], ["BatteryData": ["K": 3]]])
        let result = BatteryFieldResolver.resolve(field([nodeLifetime], searchAnywhere: true), in: tree)
        XCTAssertEqual(result.value, 3)
        XCTAssertEqual(result.location?.description, "bank:BatteryData.K")
    }

    func testSearchSkipsValuesTheFieldRejects() {
        let tree = BatteryTree(battery: ["K": 0], pack: ["BatteryData": ["K": 4]])
        XCTAssertEqual(BatteryFieldResolver.resolve(field([nodeLifetime], searchAnywhere: true), in: tree).value, 4)
    }

    func testKnownLocationBeatsANearerSearchHit() {
        let tree = BatteryTree(
            battery: ["K": 1],
            pack: ["BatteryData": ["LifetimeData": ["K": 82]]]
        )
        let result = BatteryFieldResolver.resolve(field([packLifetime], searchAnywhere: true), in: tree)
        XCTAssertEqual(result.value, 82)
        XCTAssertFalse(result.foundBySearch)
    }
}
