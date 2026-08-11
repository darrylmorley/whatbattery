import Foundation

/// The pure decisions the self-updater makes before it replaces the running
/// app: is this archive safe to extract, is this bundle actually an upgrade,
/// who signed it, and what exactly will the swap script delete.
///
/// These live in Core, away from the `Installer` that performs them, for one
/// reason: the app is an executable target with no test target of its own, so
/// nothing in it can be tested. Every check below decides whether to overwrite
/// the user's application, and every one of them was previously unreachable
/// from a test. The precedent is `AppInfo`'s trusted-host allowlist, moved here
/// for the same reason.
///
/// Nothing here touches the filesystem or runs a subprocess. The caller runs
/// `unzip`/`codesign` and hands the output in as text.
public enum UpdateInstallChecks {
    /// Ceilings for the archive. The real app zip is about 10 MB and a few
    /// hundred entries, so these are an order of magnitude of slack rather
    /// than a limit anything legitimate will meet.
    public static let maxUncompressedBytes: Int64 = 600 * 1_024 * 1_024
    public static let maxArchiveEntries = 5_000

    /// Why an update was refused. `errorDescription` is what the user sees, so
    /// these strings are the UI.
    public enum Rejection: LocalizedError, Equatable {
        case unsafePath(String)
        case symlink
        case tooManyEntries(Int)
        case uncompressedTooLarge
        case versionMismatch(advertised: String, embedded: String)
        case notAnUpgrade(embedded: String, current: String)

        public var errorDescription: String? {
            switch self {
            case .unsafePath(let path):
                return "Zip contains unsafe path: \(path)"
            case .symlink:
                return "Zip contains a symlink; refusing to install"
            case .tooManyEntries(let count):
                return "Zip contains implausibly many entries (\(count))"
            case .uncompressedTooLarge:
                return "Zip declares an implausibly large uncompressed size"
            case .versionMismatch(let advertised, let embedded):
                return "Version mismatch: release claims \(advertised) but the bundle is \(embedded.isEmpty ? "unknown" : embedded)"
            case .notAnUpgrade(let embedded, let current):
                return "Not an upgrade: \(embedded) is not newer than \(current)"
            }
        }
    }

    /// Reject an unsafe archive from `unzip`'s own listings, before extraction.
    ///
    /// Two listings are needed. The cheap names-only `-Z1` listing hides
    /// symlinks, and `unzip` follows those during extraction to write outside
    /// the work directory, which happens BEFORE any signature check runs. So
    /// the signature is not the gate that protects this step; this is.
    ///
    /// - Parameters:
    ///   - names: output of `unzip -Z1`, one path per line.
    ///   - modes: output of `unzip -Z`, a mode string per line plus a summary.
    public static func rejectArchive(
        names: String,
        modes: String,
        maxEntries: Int = maxArchiveEntries,
        maxUncompressed: Int64 = maxUncompressedBytes
    ) -> Rejection? {
        for entry in names.split(separator: "\n") {
            let path = String(entry)
            if path.hasPrefix("/") || path.contains("../") || path.contains("/..") {
                return .unsafePath(path)
            }
        }
        // Matched on the type character alone, NOT on "lrwx". The rwx are
        // permission bits the archive author chooses freely, so a crafted
        // symlink stored without owner-execute lists as "lrw-------" and would
        // slip past an "lrwx" prefix while still being followed on extraction.
        // A symlink is never something a legitimate release contains.
        for line in modes.split(separator: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("l") { return .symlink }
        }

        let entryCount = names.split(separator: "\n").count
        if entryCount > maxEntries { return .tooManyEntries(entryCount) }

        if let declared = declaredUncompressedBytes(inZipInfo: modes), declared > maxUncompressed {
            return .uncompressedTooLarge
        }
        return nil
    }

    /// The archive's own declared uncompressed total, from zipinfo's summary
    /// line ("NNN files, XXX bytes uncompressed, YYY bytes compressed").
    ///
    /// Nil when the summary is absent or unparseable, which is not treated as a
    /// rejection: the entry count and the download size ceiling already bound
    /// the damage, and failing closed on a format change would break every
    /// update for a cosmetic reason.
    public static func declaredUncompressedBytes(inZipInfo modes: String) -> Int64? {
        guard let summary = modes.split(separator: "\n").last(where: { $0.contains("bytes uncompressed") }),
              let match = summary.range(of: #"(\d+) bytes uncompressed"#, options: .regularExpression),
              let declared = Int64(String(summary[match]).split(separator: " ").first ?? "")
        else { return nil }
        return declared
    }

    /// The downloaded bundle must be the version the release advertised, and
    /// newer than what is running.
    ///
    /// A tampered Info.plist version is caught later by `codesign --verify
    /// --strict`, whose seal covers Info.plist, so this is a cheap sanity gate
    /// rather than the security boundary.
    public static func rejectBundleVersion(
        embedded: String,
        advertised: String,
        current: String
    ) -> Rejection? {
        guard embedded == advertised else {
            return .versionMismatch(advertised: advertised, embedded: embedded)
        }
        guard AppInfo.isNewer(remote: embedded, current: current) else {
            return .notAnUpgrade(embedded: embedded, current: current)
        }
        return nil
    }

    /// Pull the team identifier out of `codesign -dvv` output.
    ///
    /// codesign writes that report to stderr, not stdout, so the caller passes
    /// both streams joined; this only has to find the line. Nil when there is
    /// no such line, which the caller must treat as a refusal: an unsigned or
    /// unreadable bundle must never compare equal to the running app.
    public static func teamIdentifier(inCodesignOutput output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("TeamIdentifier=") {
                let value = String(trimmed.dropFirst("TeamIdentifier=".count))
                // "not set" is what codesign prints for an unsigned bundle.
                // Returning it verbatim would let two unsigned bundles compare
                // equal and pass the "same developer" check.
                return value.isEmpty || value == "not set" ? nil : value
            }
        }
        return nil
    }

    /// Single-quote a string for `bash`, closing and reopening the quote around
    /// any embedded quote. Every path the swap script touches goes through this.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Build the detached bundle-swap script.
    ///
    /// The cleanup at the end removes `workDirPath` and nothing else. The
    /// download zip, the extracted bundle and this script itself all live
    /// inside that per-update folder, so one removal cleans everything we
    /// created. It must never widen to the folder's parent, which is the
    /// shared temp root.
    public static func swapScript(
        pid: Int32,
        newPath: String,
        oldPath: String,
        workDirPath: String,
        backupSuffix: String
    ) -> String {
        """
        #!/bin/bash
        set -e
        PID=\(pid)
        NEW=\(shellQuote(newPath))
        OLD=\(shellQuote(oldPath))
        BACKUP="${OLD}.backup-\(backupSuffix)"

        # Wait up to 30s for the running app to exit
        for _ in $(seq 1 60); do
            if ! kill -0 "$PID" 2>/dev/null; then break; fi
            sleep 0.5
        done

        # If the app is somehow still running, do NOT swap a live bundle (moving it
        # out from under the running process could corrupt it). Leave everything
        # intact, clean up, and bail.
        if kill -0 "$PID" 2>/dev/null; then
            rm -rf \(shellQuote(workDirPath))
            exit 0
        fi

        # Move old bundle to a backup this invocation owns. The path carries a
        # fresh UUID, so it never collides with (and never deletes) anything a
        # user or an earlier update left behind; if it exists anyway, something
        # is wrong enough that touching it would be reckless, so bail intact.
        if [ -e "$BACKUP" ]; then
            rm -rf \(shellQuote(workDirPath))
            exit 0
        fi
        mv "$OLD" "$BACKUP"

        if mv "$NEW" "$OLD"; then
            open "$OLD"
            sleep 2
            rm -rf "$BACKUP"
        else
            # Swap failed; remove any partial destination before restoring.
            rm -rf "$OLD"
            mv "$BACKUP" "$OLD"
            open "$OLD"
        fi

        # Clean up the per-update folder only. The download zip, the extracted
        # bundle and this script all live inside it, so this single removal cleans
        # everything we created without ever touching the shared temp root.
        # Deleting the folder this running script lives in is safe: bash has
        # already read the script into memory.
        rm -rf \(shellQuote(workDirPath))
        """
    }
}
