import Foundation

/// App identity and version helpers. The single source of truth for the running
/// version, the GitHub repo, and the version-comparison used by the in-app
/// updater. Pure (no IOKit / SwiftUI), so the free build, the CLI, and the
/// updater all share it.
public enum AppInfo {
    public static let name = "WhatBattery"
    /// owner/repo on GitHub. Public mirror that hosts the releases the updater
    /// downloads.
    public static let repo = "darrylmorley/whatbattery"

    public static let version: String = {
        // Single source of truth lives in the .app's Info.plist (written by
        // scripts/smoke-test.sh). Falls back to a dev string when run via
        // `swift run`, which has no bundled Info.plist.
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return v
        }
        // The CLI binary at Contents/Helpers/whatbattery lives one extra level
        // deep, so Bundle.main doesn't auto-resolve to the .app. Walk up from the
        // executable until we find a Contents/Info.plist sibling. Resolve
        // symlinks first: when invoked via a Homebrew symlink, the executable
        // path points outside the .app and walking up would never find it.
        let exe = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        var dir = URL(fileURLWithPath: exe)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<4 {
            let plist = dir.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: plist),
               let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let v = parsed["CFBundleShortVersionString"] as? String {
                return v
            }
            dir = dir.deletingLastPathComponent()
        }
        return "0.1.0-dev"
    }()

    /// A build with no matching GitHub tag: a dev / pre-release version (run via
    /// `swift run`, or any version carrying a "-" suffix).
    public static var isDevBuild: Bool { version.contains("-") }

    /// The app's GitHub page.
    public static var githubURL: URL {
        URL(string: "https://github.com/\(repo)")!
    }

    /// The GitHub release page for this version. A dev / pre-release build has no
    /// tag, so link to the releases list instead.
    public static var releaseURL: URL {
        if isDevBuild {
            return URL(string: "https://github.com/\(repo)/releases")!
        }
        return URL(string: "https://github.com/\(repo)/releases/tag/v\(version)")!
    }

    /// The GitHub API endpoint the updater polls for the latest release.
    public static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    /// Compare dot-separated numeric versions. Non-numeric segments compare as 0,
    /// so "0.1.0-dev" reads as older than any real "1.x" release.
    public static func isNewer(remote: String, current: String) -> Bool {
        let r = parts(remote)
        let c = parts(current)
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv != cv { return rv > cv }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
