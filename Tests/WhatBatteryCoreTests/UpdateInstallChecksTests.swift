import XCTest
@testable import WhatBatteryCore

/// The checks that stand between a downloaded zip and the user's installed
/// application. Every one of these was unreachable from a test until the pure
/// part was moved out of the app target.
///
/// The threat model is not "GitHub is hostile". It is that the signature check
/// runs AFTER extraction, so anything an archive can do while being unpacked
/// happens before the real gate.
final class UpdateInstallChecksTests: XCTestCase {
    /// What a real release zip's listings look like, near enough.
    private let goodNames = """
    WhatBattery.app/
    WhatBattery.app/Contents/Info.plist
    WhatBattery.app/Contents/MacOS/whatbattery
    """
    private let goodModes = """
    Archive:  update.zip
    drwxr-xr-x  3.0 unx        0 bx stor 26-Aug-11 00:00 WhatBattery.app/
    -rw-r--r--  3.0 unx     1234 tx defN 26-Aug-11 00:00 WhatBattery.app/Contents/Info.plist
    -rwxr-xr-x  3.0 unx  9000000 bx defN 26-Aug-11 00:00 WhatBattery.app/Contents/MacOS/whatbattery
    3 files, 9001234 bytes uncompressed, 4000000 bytes compressed:  55.6%
    """

    func testARealisticArchiveIsAccepted() {
        XCTAssertNil(UpdateInstallChecks.rejectArchive(names: goodNames, modes: goodModes))
    }

    // MARK: - Path traversal

    func testAnAbsolutePathIsRejected() {
        let names = goodNames + "\n/etc/paths.d/evil"
        XCTAssertEqual(
            UpdateInstallChecks.rejectArchive(names: names, modes: goodModes),
            .unsafePath("/etc/paths.d/evil")
        )
    }

    func testTraversalIsRejectedInBothSpellings() {
        for path in ["../../Library/LaunchAgents/evil.plist", "WhatBattery.app/../../evil"] {
            XCTAssertEqual(
                UpdateInstallChecks.rejectArchive(names: goodNames + "\n" + path, modes: goodModes),
                .unsafePath(path),
                "should reject \(path)"
            )
        }
    }

    /// A name that merely CONTAINS two dots is not traversal, and rejecting it
    /// would refuse legitimate releases.
    func testAnInnocentDoubleDotInAFilenameIsAllowed() {
        let names = goodNames + "\nWhatBattery.app/Contents/Resources/readme..txt"
        XCTAssertNil(UpdateInstallChecks.rejectArchive(names: names, modes: goodModes))
    }

    // MARK: - Symlinks

    /// The whole reason the expensive second listing is taken. `unzip` follows
    /// a symlink during extraction to write outside the work directory, and
    /// that happens before the signature is ever checked.
    func testASymlinkIsRejected() {
        let modes = goodModes + "\nlrwxr-xr-x  3.0 unx  11 bx stor 26-Aug-11 00:00 WhatBattery.app/evil -> /etc/hosts"
        XCTAssertEqual(UpdateInstallChecks.rejectArchive(names: goodNames, modes: modes), .symlink)
    }

    /// Matched on the type character, never on "lrwx". The permission bits are
    /// the archive author's to choose, so a symlink stored without
    /// owner-execute would slip past a check that expected "lrwx" and still be
    /// followed on extraction.
    func testASymlinkWithoutExecuteBitsIsStillRejected() {
        let modes = goodModes + "\nlrw-------  3.0 unx  11 bx stor 26-Aug-11 00:00 WhatBattery.app/evil -> /etc/hosts"
        XCTAssertEqual(UpdateInstallChecks.rejectArchive(names: goodNames, modes: modes), .symlink)
    }

    // MARK: - Zip bombs

    func testTooManyEntriesIsRejected() {
        let names = (1...20).map { "WhatBattery.app/f\($0)" }.joined(separator: "\n")
        XCTAssertEqual(
            UpdateInstallChecks.rejectArchive(names: names, modes: goodModes, maxEntries: 19),
            .tooManyEntries(20)
        )
    }

    func testADeclaredUncompressedSizeOverTheCeilingIsRejected() {
        let modes = "1 files, 900000000 bytes uncompressed, 1000 bytes compressed:  99.9%"
        XCTAssertEqual(
            UpdateInstallChecks.rejectArchive(names: "WhatBattery.app/f", modes: modes),
            .uncompressedTooLarge
        )
    }

    func testTheDeclaredSizeIsReadFromTheSummaryLine() {
        XCTAssertEqual(UpdateInstallChecks.declaredUncompressedBytes(inZipInfo: goodModes), 9_001_234)
    }

    /// An unparseable summary must not reject the update: the entry count and
    /// the download size ceiling already bound the damage, and failing closed
    /// on a zipinfo format change would break every update for a cosmetic
    /// reason.
    func testAMissingSummaryDoesNotRejectTheArchive() {
        let modes = "drwxr-xr-x  3.0 unx  0 bx stor 26-Aug-11 00:00 WhatBattery.app/"
        XCTAssertNil(UpdateInstallChecks.declaredUncompressedBytes(inZipInfo: modes))
        XCTAssertNil(UpdateInstallChecks.rejectArchive(names: goodNames, modes: modes))
    }

    // MARK: - Version

    func testAnUpgradeIsAccepted() {
        XCTAssertNil(UpdateInstallChecks.rejectBundleVersion(
            embedded: "1.6.1", advertised: "1.6.1", current: "1.6.0"
        ))
    }

    /// The tag says one thing and the bundle another: refuse, rather than
    /// install something that is not what the release claimed.
    func testABundleThatDisagreesWithTheReleaseTagIsRejected() {
        XCTAssertEqual(
            UpdateInstallChecks.rejectBundleVersion(embedded: "1.5.0", advertised: "1.6.1", current: "1.6.0"),
            .versionMismatch(advertised: "1.6.1", embedded: "1.5.0")
        )
    }

    func testADowngradeIsRejected() {
        XCTAssertEqual(
            UpdateInstallChecks.rejectBundleVersion(embedded: "1.5.0", advertised: "1.5.0", current: "1.6.0"),
            .notAnUpgrade(embedded: "1.5.0", current: "1.6.0")
        )
    }

    func testReinstallingTheSameVersionIsRejected() {
        XCTAssertEqual(
            UpdateInstallChecks.rejectBundleVersion(embedded: "1.6.0", advertised: "1.6.0", current: "1.6.0"),
            .notAnUpgrade(embedded: "1.6.0", current: "1.6.0")
        )
    }

    /// A bundle with no version string reads as "unknown" rather than as an
    /// empty gap in the sentence.
    func testAMissingBundleVersionSaysUnknown() {
        let rejection = UpdateInstallChecks.rejectBundleVersion(
            embedded: "", advertised: "1.6.1", current: "1.6.0"
        )
        XCTAssertEqual(rejection?.errorDescription,
                       "Version mismatch: release claims 1.6.1 but the bundle is unknown")
    }

    // MARK: - Team identifier

    /// codesign writes its report to stderr, and the caller joins both streams,
    /// so the parse has to cope with the line sitting anywhere.
    func testTheTeamIdentifierIsReadFromCodesignOutput() {
        let output = """
        Executable=/Applications/WhatBattery.app/Contents/MacOS/whatbattery
        Identifier=app.whatbattery.whatbattery
        TeamIdentifier=M4RUJ7W6MP
        Sealed Resources version=2 rules=13 files=42
        """
        XCTAssertEqual(UpdateInstallChecks.teamIdentifier(inCodesignOutput: output), "M4RUJ7W6MP")
    }

    /// An unsigned bundle prints "not set". Returning that verbatim would let
    /// two unsigned bundles compare equal and pass the "same developer" check,
    /// which is the one thing this comparison exists to prevent.
    func testAnUnsignedBundleHasNoTeamIdentifier() {
        XCTAssertNil(UpdateInstallChecks.teamIdentifier(inCodesignOutput: "TeamIdentifier=not set"))
        XCTAssertNil(UpdateInstallChecks.teamIdentifier(inCodesignOutput: "TeamIdentifier="))
    }

    func testNoTeamIdentifierLineAtAll() {
        XCTAssertNil(UpdateInstallChecks.teamIdentifier(inCodesignOutput: "Identifier=app.whatbattery\nformat=app bundle"))
    }

    /// A line that merely mentions the key must not be mistaken for it.
    func testALineThatOnlyMentionsTheKeyIsNotParsed() {
        XCTAssertNil(UpdateInstallChecks.teamIdentifier(
            inCodesignOutput: "warning: could not read TeamIdentifier=X from bundle"
        ))
    }

    // MARK: - The swap script

    private func script(
        newPath: String = "/tmp/whatbattery-update-1/WhatBattery.app",
        oldPath: String = "/Applications/WhatBattery.app",
        workDirPath: String = "/tmp/whatbattery-update-1"
    ) -> String {
        UpdateInstallChecks.swapScript(
            pid: 4242, newPath: newPath, oldPath: oldPath,
            workDirPath: workDirPath, backupSuffix: "FIXED-SUFFIX"
        )
    }

    /// The single most destructive line in the app. It must remove the
    /// per-update folder and never widen to its parent, which is the shared
    /// temp root every other process is also using.
    func testTheOnlyThingDeletedIsThePerUpdateFolder() {
        let deletions = script().split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("rm -rf") }

        XCTAssertFalse(deletions.isEmpty)
        for line in deletions {
            let target = line.dropFirst("rm -rf ".count)
            XCTAssertTrue(
                target == "'/tmp/whatbattery-update-1'" || target == "\"$BACKUP\"" || target == "\"$OLD\"",
                "unexpected deletion target: \(target)"
            )
        }
        XCTAssertFalse(script().contains("rm -rf /tmp\n"), "must never remove the shared temp root")
        XCTAssertFalse(script().contains("rm -rf '/tmp'"))
    }

    /// A path with a quote in it must not be able to end the quoting and run
    /// its own commands. This is the injection the quoting exists to stop.
    ///
    /// Asserted by asking bash, not by looking for a substring: quoting
    /// PRESERVES the dangerous characters, it just stops them being syntax, so
    /// the injected text is still there in the script and a substring check
    /// proves nothing. The property that matters is that bash parses the whole
    /// thing back as one literal argument, which is what this measures.
    /// The payload is deliberately inert (`echo`, not anything that touches the
    /// filesystem). This test exists to be run against a DELIBERATELY BROKEN
    /// `shellQuote`, whether by a mutation-testing pass or by a change that
    /// regresses it, and at that moment bash really does execute whatever the
    /// payload says. A destructive payload here would make the test suite
    /// itself the thing that does the damage. Escaping is proven by comparing
    /// the output, not by the payload being frightening.
    func testAHostilePathIsOneLiteralArgumentToBash() throws {
        let hostile = "/tmp/eviluser'; echo INJECTED; echo 'x"
        let quoted = UpdateInstallChecks.shellQuote(hostile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // printf %s with a single conversion prints its FIRST argument only, so
        // a string that broke into several words would come back truncated.
        process.arguments = ["-c", "printf %s \(quoted)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(String(data: data, encoding: .utf8), hostile,
                       "bash did not read the path back as a single literal")
        XCTAssertTrue(script(workDirPath: hostile).contains(quoted))
    }

    func testShellQuotingClosesAndReopensAroundAQuote() {
        XCTAssertEqual(UpdateInstallChecks.shellQuote("a'b"), #"'a'\''b'"#)
        XCTAssertEqual(UpdateInstallChecks.shellQuote("/Applications/WhatBattery.app"),
                       "'/Applications/WhatBattery.app'")
    }

    /// Moving a bundle out from under a running process can corrupt it, so the
    /// script must refuse rather than swap.
    func testTheScriptRefusesToSwapWhileTheAppIsStillRunning() {
        let generated = script()
        XCTAssertTrue(generated.contains("PID=4242"))
        // The guard that bails out, and the move it must come before.
        guard let guardIndex = generated.range(of: "if kill -0 \"$PID\" 2>/dev/null; then"),
              let moveIndex = generated.range(of: "mv \"$OLD\" \"$BACKUP\"") else {
            return XCTFail("script no longer has the running-app guard and the move")
        }
        XCTAssertTrue(guardIndex.upperBound < moveIndex.lowerBound,
                      "the swap must be guarded by the still-running check, not the other way round")
    }

    /// A failed swap must put the user's application back rather than leave
    /// them with nothing.
    func testAFailedSwapRestoresTheBackup() {
        let generated = script()
        XCTAssertTrue(generated.contains("mv \"$BACKUP\" \"$OLD\""))
        XCTAssertTrue(generated.contains("open \"$OLD\""))
    }

    /// The backup path carries a fresh suffix per invocation, and an existing
    /// one is treated as a reason to bail rather than something to overwrite.
    func testAnExistingBackupPathMakesTheScriptBailIntact() {
        let generated = script()
        XCTAssertTrue(generated.contains("BACKUP=\"${OLD}.backup-FIXED-SUFFIX\""))
        XCTAssertTrue(generated.contains("if [ -e \"$BACKUP\" ]; then"))
    }
}
