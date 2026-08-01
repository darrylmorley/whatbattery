import XCTest
@testable import WhatBatteryCore

final class GitHubReleaseHostTests: XCTestCase {
    /// The URL the releases API hands us. Always on github.com.
    func testAcceptsTheReleaseAssetURL() {
        let url = URL(string: "https://github.com/darrylmorley/whatbattery/releases/download/v1.4.0/WhatBattery.zip")!
        XCTAssertTrue(GitHubReleaseHost.isTrusted(url))
    }

    /// The host that URL actually redirects to. This is the regression: GitHub
    /// moved release downloads here, the allowlist still had the older
    /// `releases.githubusercontent.com`, and every in-app update failed with
    /// "Download redirected to an untrusted host".
    func testAcceptsTheHostReleaseDownloadsRedirectTo() {
        let url = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/1272176363/02b05360?sp=r")!
        XCTAssertTrue(GitHubReleaseHost.isTrusted(url))
    }

    /// Hosts GitHub has served assets from previously. Kept so a cleanup doesn't
    /// quietly drop a path that is still live for older releases.
    func testAcceptsPreviousAssetHosts() {
        for host in ["objects.githubusercontent.com", "releases.githubusercontent.com"] {
            XCTAssertTrue(
                GitHubReleaseHost.isTrusted(URL(string: "https://\(host)/asset.zip")!),
                "expected \(host) to stay trusted"
            )
        }
    }

    /// Exact match, not suffix. Anyone can register the first two.
    func testRejectsLookalikeHosts() {
        for host in [
            "release-assets.githubusercontent.com.example.com",
            "githubusercontent.com",
            "raw.githubusercontent.com.attacker.test",
            "example.com",
        ] {
            XCTAssertFalse(
                GitHubReleaseHost.isTrusted(URL(string: "https://\(host)/WhatBattery.zip")!),
                "expected \(host) to be rejected"
            )
        }
    }

    /// HTTPS only, even on a host that is otherwise fine.
    func testRejectsPlainHTTP() {
        let url = URL(string: "http://github.com/darrylmorley/whatbattery/releases/download/v1.4.0/WhatBattery.zip")!
        XCTAssertFalse(GitHubReleaseHost.isTrusted(url))
    }

    /// A URL with no host at all must not slip through the guard.
    func testRejectsHostlessURL() {
        XCTAssertFalse(GitHubReleaseHost.isTrusted(URL(string: "https:///WhatBattery.zip")!))
        XCTAssertFalse(GitHubReleaseHost.isTrusted(URL(fileURLWithPath: "/tmp/WhatBattery.zip")))
    }
}
