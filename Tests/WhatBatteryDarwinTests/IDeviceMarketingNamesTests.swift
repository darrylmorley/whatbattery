import XCTest
@testable import WhatBatteryDarwinBackend
@testable import WhatBatteryCore

final class IDeviceMarketingNamesTests: XCTestCase {
    /// A trimmed copy of the real shape, including the parts that make naive
    /// parsing wrong: board ids and a bare family name in the same list as the
    /// product types, and a description with the regulatory numbers appended.
    private func fixture() -> [String: Any] {
        [
            "UTExportedTypeDeclarations": [
                [
                    "UTTypeDescription": "iPhone X (Model A1865, A1901, A1902, A1903)",
                    "UTTypeTagSpecification": [
                        "com.apple.device-model-code": ["D22AP", "D221AP", "iPhone10,3", "iPhone10,6", "iPhone"],
                    ],
                ],
                [
                    "UTTypeDescription": "iPad Pro (11-inch)",
                    "UTTypeTagSpecification": [
                        "com.apple.device-model-code": ["iPad8,1", "iPad8,2", "iPad"],
                    ],
                ],
            ],
        ]
    }

    func testProductTypesAreNamedAndBoardIdsIgnored() {
        let table = IDeviceMarketingNames.parse(fixture())
        XCTAssertEqual(table["iPhone10,6"], "iPhone X")
        XCTAssertEqual(table["iPhone10,3"], "iPhone X")
        XCTAssertEqual(table["iPad8,1"], "iPad Pro (11-inch)")
        XCTAssertNil(table["D22AP"])
    }

    /// The bare family appears in every declaration's code list. Keyed on, the
    /// last one parsed would win and "iPhone" would name some arbitrary model.
    func testBareFamilyNameIsNotAKey() {
        let table = IDeviceMarketingNames.parse(fixture())
        XCTAssertNil(table["iPhone"])
        XCTAssertNil(table["iPad"])
    }

    /// Anchored at the end, so the screen size in "iPad Pro (11-inch)" survives.
    func testOnlyTheTrailingModelNumbersAreStripped() {
        XCTAssertEqual(IDeviceMarketingNames.strippingModelNumbers("iPhone 5 (Model A1428)"), "iPhone 5")
        XCTAssertEqual(IDeviceMarketingNames.strippingModelNumbers("iPad Pro (11-inch)"), "iPad Pro (11-inch)")
        XCTAssertEqual(
            IDeviceMarketingNames.strippingModelNumbers("iPad Pro (12.9-inch) (5th generation)"),
            "iPad Pro (12.9-inch) (5th generation)"
        )
    }

    /// One bad element must not take the other 238 names with it. Casting the
    /// whole array to `[[String: Any]]` is all-or-nothing, which would have made
    /// a single reshaped entry silently disable the feature.
    func testOneBadDeclarationDoesNotDiscardTheRest() {
        var root = fixture()
        var declarations = root["UTExportedTypeDeclarations"] as! [Any]
        declarations.insert("not a dictionary", at: 0)
        root["UTExportedTypeDeclarations"] = declarations

        let table = IDeviceMarketingNames.parse(root)
        XCTAssertEqual(table["iPhone10,6"], "iPhone X")
        XCTAssertEqual(table["iPad8,1"], "iPad Pro (11-inch)")
    }

    /// Two declarations naming one product type differently: parse order would
    /// otherwise pick the winner. Dropping it lets the built-in table answer.
    func testConflictingDuplicatesAreDroppedRatherThanGuessed() {
        var root = fixture()
        var declarations = root["UTExportedTypeDeclarations"] as! [Any]
        declarations.append([
            "UTTypeDescription": "iPhone 11",
            "UTTypeTagSpecification": ["com.apple.device-model-code": ["iPhone10,6"]],
        ] as [String: Any])
        root["UTExportedTypeDeclarations"] = declarations

        let table = IDeviceMarketingNames.parse(root)
        XCTAssertNil(table["iPhone10,6"])
        // The unaffected entries survive.
        XCTAssertEqual(table["iPhone10,3"], "iPhone X")
    }

    /// A repeated declaration that agrees is the normal case in the real file
    /// (222 product types appear more than once) and must not be treated as a
    /// conflict.
    func testAgreeingDuplicatesAreKept() {
        var root = fixture()
        var declarations = root["UTExportedTypeDeclarations"] as! [Any]
        declarations.append([
            "UTTypeDescription": "iPhone X (Model A1901)",
            "UTTypeTagSpecification": ["com.apple.device-model-code": ["iPhone10,6"]],
        ] as [String: Any])
        root["UTExportedTypeDeclarations"] = declarations

        XCTAssertEqual(IDeviceMarketingNames.parse(root)["iPhone10,6"], "iPhone X")
    }

    func testMalformedInputYieldsAnEmptyTableRatherThanCrashing() {
        XCTAssertTrue(IDeviceMarketingNames.parse([:]).isEmpty)
        XCTAssertTrue(IDeviceMarketingNames.parse(["UTExportedTypeDeclarations": "not an array"]).isEmpty)
        XCTAssertTrue(IDeviceMarketingNames.parse(["UTExportedTypeDeclarations": [["UTTypeDescription": 42]]]).isEmpty)
    }

    /// Against the real file on this machine. Skipped rather than failed if Apple
    /// has moved it, which is exactly the case the fallback exists for.
    func testRealSystemTableNamesAKnownDevice() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: IDeviceMarketingNames.bundlePath),
            "system device table not present on this machine"
        )
        XCTAssertEqual(IDeviceMarketingNames.name(for: "iPhone10,6"), "iPhone X")
        // The reported bug: the built-in table had no entry, so this printed raw.
        XCTAssertNotEqual(IDeviceMarketingNames.name(for: "iPhone10,6"), "iPhone10,6")
    }

    /// Every product type in both tables must agree on which model it is.
    ///
    /// The first version of this compared only the leading two words, and passed
    /// while the iPhone SE generations were silently collapsing into one name. It
    /// now normalises the wording (Apple writes "5th generation" where this table
    /// wrote "5th gen") and requires one name to be a prefix of the other, so a
    /// difference in screen size or generation fails where a difference in
    /// phrasing does not.
    func testBuiltInTableDoesNotContradictTheSystemTable() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: IDeviceMarketingNames.bundlePath),
            "system device table not present on this machine"
        )
        var compared = 0
        for (identifier, ours) in IDeviceModelName.tableForTesting {
            // Only the intersection. A macOS older than one of our entries is not
            // a contradiction, and asserting otherwise would fail this build on a
            // machine that simply predates the device.
            guard let theirs = IDeviceMarketingNames.name(for: identifier) else { continue }
            compared += 1
            let mine = Self.normalised(ours)
            let apple = Self.normalised(theirs)
            XCTAssertTrue(
                mine.hasPrefix(apple) || apple.hasPrefix(mine),
                "\(identifier): we say '\(ours)', macOS says '\(theirs)'"
            )
        }
        // Guards against the loop above quietly comparing nothing: it only sees
        // identifiers present in BOTH tables, and without a floor an empty
        // intersection would pass as loudly as a clean one.
        //
        // Expect this to fail one day for a boring reason. Apple eventually drops
        // very old devices from its table, and ours starts at the iPhone 6s, so
        // the intersection shrinks over time (104 of our 104 today). When it
        // crosses this floor nothing is broken: the right response is to check
        // WHY the count fell, and if it is just macOS ageing out old models,
        // lower the number. Do not delete the assertion, it is what stops this
        // test rotting into a no-op.
        XCTAssertGreaterThan(compared, 80, "the system table stopped covering our entries")
    }

    /// The normaliser has to keep the differences that matter. If it flattened
    /// these it would pass anything.
    func testNormalisationKeepsRealDifferences() {
        let pro11 = Self.normalised("iPad Pro 11-inch (1st gen)")
        let pro129 = Self.normalised("iPad Pro (12.9-inch) (1st generation)")
        XCTAssertFalse(pro11.hasPrefix(pro129) || pro129.hasPrefix(pro11), "screen size must not be flattened")

        let third = Self.normalised("iPad Pro 11-inch (3rd gen)")
        let fifth = Self.normalised("iPad Pro (11-inch) (5th generation)")
        XCTAssertFalse(third.hasPrefix(fifth) || fifth.hasPrefix(third), "generation must not be flattened")

        // And the difference that does not matter still matches.
        XCTAssertEqual(Self.normalised("iPad (10th gen)"), Self.normalised("iPad (10th generation)"))
    }

    /// Wording only: case, punctuation, spacing, and "gen" for "generation".
    private static func normalised(_ name: String) -> String {
        var text = name.lowercased().replacingOccurrences(of: "generation", with: "gen")
        for noise in ["(", ")", "-", ",", " "] {
            text = text.replacingOccurrences(of: noise, with: "")
        }
        return text
    }
}
