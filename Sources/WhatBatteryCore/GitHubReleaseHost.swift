import Foundation

/// Host allowlist for release downloads.
///
/// This is a second layer, not the gate. The real check is in the installer:
/// bundle identifier match, `codesign --verify --strict`, and `spctl --assess`
/// on the downloaded app before anything is swapped in. This just keeps the
/// download itself pointed at GitHub.
///
/// It lives in Core so it can be unit tested. The app target is an executable
/// with no test target of its own, and an allowlist nobody tests is exactly how
/// this went stale: GitHub moved release downloads to
/// `release-assets.githubusercontent.com`, the list still said
/// `releases.githubusercontent.com`, and the updater started refusing its own
/// download.
public enum GitHubReleaseHost {
    /// Hosts GitHub serves release assets from, including the ones it redirects
    /// to. Add rather than replace: old hosts stay live for a long time, and a
    /// wrong removal breaks the updater exactly as silently as a wrong addition.
    public static let trusted: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "releases.githubusercontent.com",
    ]

    /// True when `url` is an HTTPS URL on an allowlisted GitHub host.
    ///
    /// Matches the host exactly. A suffix match would accept
    /// `githubusercontent.com.example.com`, which is a domain anyone can
    /// register.
    public static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return trusted.contains(host)
    }
}
