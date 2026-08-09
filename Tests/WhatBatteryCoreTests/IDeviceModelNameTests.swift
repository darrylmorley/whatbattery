import XCTest
@testable import WhatBatteryCore

final class IDeviceModelNameTests: XCTestCase {
    /// The reported case: an iPhone X showed as "iPhone10,6" in the CLI, beside a
    /// correctly named iPhone 15 Pro Max, because the table started at the XS.
    func testIPhoneXIsNamed() {
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone10,6"), "iPhone X")
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone10,3"), "iPhone X")
    }

    /// Apple ships one model under two identifiers (usually a radio variant), and
    /// the table carries both. Missing the second is how the gap above happened:
    /// half the owners of a model see a name and half see a number.
    func testBothIdentifiersForASplitModelResolve() {
        for pair in [("iPhone10,1", "iPhone10,4"), ("iPhone9,1", "iPhone9,3"), ("iPad14,3", "iPad14,4")] {
            let first = IDeviceModelName.marketingName(for: pair.0)
            let second = IDeviceModelName.marketingName(for: pair.1)
            XCTAssertEqual(first, second, "\(pair.0) and \(pair.1) are the same model")
            XCTAssertNotEqual(first, pair.0, "\(pair.0) fell through to its identifier")
        }
    }

    func testIPadsOldEnoughToStillRunIPadOS17AreNamed() {
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPad7,5"), "iPad (6th gen)")
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPad7,3"), "iPad Pro 10.5-inch")
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPad11,3"), "iPad Air (3rd gen)")
    }

    /// The fallback is the point: a device we cannot name prints its identifier
    /// rather than a guess. Ugly beats confidently wrong.
    func testUnknownIdentifierFallsBackToItself() {
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone99,1"), "iPhone99,1")
    }

    func testEmptyIdentifierIsNeverBlank() {
        XCTAssertEqual(IDeviceModelName.marketingName(for: ""), "Device")
    }

    /// The family comes from the prefix, so an unrecognised model still gets the
    /// right icon and label.
    func testKindFromPrefixSurvivesAnUnknownModel() {
        XCTAssertEqual(IDeviceModelName.kind(for: "iPhone99,1"), .iPhone)
        XCTAssertEqual(IDeviceModelName.kind(for: "iPad99,1"), .iPad)
        XCTAssertEqual(IDeviceModelName.kind(for: "iPod9,1"), .iPod)
        XCTAssertEqual(IDeviceModelName.kind(for: "Watch7,1"), .unknown)
    }

    /// A name in the table that is just the identifier back again would be a typo
    /// that reads as working, since the fallback returns exactly that.
    func testNoEntryMapsToItsOwnIdentifier() {
        for (identifier, name) in IDeviceModelName.tableForTesting {
            XCTAssertNotEqual(identifier, name, "\(identifier) maps to itself")
            XCTAssertFalse(name.isEmpty, "\(identifier) maps to an empty name")
        }
    }

    /// macOS names both iPhone SE generations plain "iPhone SE". Taking the
    /// system name unconditionally made two different phones render the same
    /// string, so the more specific name wins when one strictly extends the
    /// other.
    func testTheMoreSpecificNameWins() {
        XCTAssertEqual(
            IDeviceModelName.marketingName(for: "iPhone8,4", systemName: "iPhone SE"),
            "iPhone SE (1st gen)"
        )
        XCTAssertEqual(
            IDeviceModelName.marketingName(for: "iPhone12,8", systemName: "iPhone SE"),
            "iPhone SE (2nd gen)"
        )
    }

    /// A disagreement is not a refinement. Where the two tables name different
    /// models, the system is authoritative: it is the one Apple maintains.
    func testSystemWinsWhenTheTablesDisagree() {
        XCTAssertEqual(
            IDeviceModelName.marketingName(for: "iPhone10,6", systemName: "iPhone X Special Edition"),
            "iPhone X Special Edition"
        )
    }

    /// Apple's own wording is preferred where it says the same thing at more
    /// length, so the app matches Finder rather than inventing a house style.
    func testSystemWinsOnWordingAlone() {
        XCTAssertEqual(
            IDeviceModelName.marketingName(for: "iPad13,18", systemName: "iPad (10th generation)"),
            "iPad (10th generation)"
        )
    }

    func testFallsBackWhenTheSystemHasNothing() {
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone10,6", systemName: nil), "iPhone X")
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone10,6", systemName: ""), "iPhone X")
        XCTAssertEqual(IDeviceModelName.marketingName(for: "iPhone99,1", systemName: nil), "iPhone99,1")
    }
}
