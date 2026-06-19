import XCTest
@testable import WhatBatteryCore

final class AppInfoTests: XCTestCase {
    func testRemoteNewerByMajor() {
        XCTAssertTrue(AppInfo.isNewer(remote: "2.0.0", current: "1.9.9"))
    }

    func testRemoteNewerByMinor() {
        XCTAssertTrue(AppInfo.isNewer(remote: "1.2.0", current: "1.1.5"))
    }

    func testRemoteNewerByPatch() {
        XCTAssertTrue(AppInfo.isNewer(remote: "1.0.1", current: "1.0.0"))
    }

    func testEqualIsNotNewer() {
        XCTAssertFalse(AppInfo.isNewer(remote: "1.2.3", current: "1.2.3"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(AppInfo.isNewer(remote: "1.0.0", current: "1.0.1"))
    }

    func testDifferentSegmentCounts() {
        // "1.2" reads as "1.2.0", so "1.2.1" is newer and "1.2" is not newer
        // than "1.2.0".
        XCTAssertTrue(AppInfo.isNewer(remote: "1.2.1", current: "1.2"))
        XCTAssertFalse(AppInfo.isNewer(remote: "1.2", current: "1.2.0"))
    }

    func testLongerRemoteWithTrailingZerosNotNewer() {
        XCTAssertFalse(AppInfo.isNewer(remote: "1.0.0.0", current: "1.0.0"))
    }

    func testNonNumericSegmentsCompareAsZero() {
        // A dev build ("0.1.0-dev" -> [0,1,0,0]) is older than any real release.
        XCTAssertTrue(AppInfo.isNewer(remote: "1.0.0", current: "0.1.0-dev"))
        XCTAssertFalse(AppInfo.isNewer(remote: "0.1.0-dev", current: "1.0.0"))
    }

    func testGithubURL() {
        XCTAssertEqual(AppInfo.githubURL.absoluteString, "https://github.com/darrylmorley/whatbattery")
    }

    func testLatestReleaseAPIEndpoint() {
        XCTAssertEqual(
            AppInfo.latestReleaseAPI.absoluteString,
            "https://api.github.com/repos/darrylmorley/whatbattery/releases/latest"
        )
    }
}
