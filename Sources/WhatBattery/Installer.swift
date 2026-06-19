// In-process installer for the self-update path. Free feature: downloads a
// release zip, validates its code signature matches the running app, and swaps
// the bundles via a detached shell script that waits for this process to exit.
import Foundation
import AppKit
import os.log
import WhatBatteryCore

/// Downloads a new release zip from GitHub, validates its code signature matches
/// the currently running app, and swaps the bundles via a small shell script that
/// waits for this process to exit before doing the move.
@MainActor
final class Installer: ObservableObject {
    static let shared = Installer()
    private nonisolated static let log = Logger(subsystem: "app.whatbattery.whatbattery", category: "installer")
    private static let expectedBundleID = "app.whatbattery.whatbattery"
    private static let expectedAppName = "WhatBattery.app"

    enum State: Equatable {
        case idle
        case downloading
        case verifying
        case installing
        case failed(String)
        /// The update can't be applied here (e.g. a non-admin account that can't
        /// write to /Applications). Distinct from `failed` so the UI can show the
        /// guidance verbatim, without the "Install failed:" prefix.
        case blocked(String)
    }

    @Published private(set) var state: State = .idle

    private init() {}

    func install(_ update: AvailableUpdate) {
        // A failed install leaves the button visible but the guard below would
        // block re-entry, making the click a no-op. Reset to idle so the user can
        // retry after a transient error (e.g. a network blip).
        if case .failed = state { state = .idle }
        guard case .idle = state else { return }
        guard let downloadURL = update.downloadURL else {
            state = .failed("No download asset for this release")
            return
        }

        // A standard (non-admin) account can't write to /Applications, so the
        // in-place bundle swap at the end would fail. That swap runs in a detached
        // script after we quit, with its output sent to /dev/null, so the failure
        // would otherwise be invisible. Catch the unwritable location up front and
        // tell the user how to update instead.
        let installDir = Bundle.main.bundleURL.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: installDir.path) {
            state = .blocked("This account can't update apps in this location. Download the new version from whatbattery.app, or update with Homebrew.")
            return
        }

        state = .downloading

        Task {
            var workDir: URL?
            do {
                workDir = try makeWorkDir()
                let zipURL = try await download(from: downloadURL, into: workDir!)

                state = .verifying
                let extractedApp = try await unzipAndLocate(zip: zipURL, in: workDir!)
                try verifyNotDowngrade(app: extractedApp, advertised: update.version)
                try await verifySignatureMatches(new: extractedApp, current: Bundle.main.bundleURL)

                state = .installing
                try launchSwapScript(newApp: extractedApp, currentApp: Bundle.main.bundleURL, workDir: workDir!)

                // Give the script a moment to start before we quit.
                try await Task.sleep(nanoseconds: 250_000_000)
                NSApp.terminate(nil)
            } catch {
                if let workDir {
                    try? FileManager.default.removeItem(at: workDir)
                }
                Self.log.error("Install failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Steps

    private func makeWorkDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whatbattery-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func download(from url: URL, into dir: URL) async throws -> URL {
        let (tmpURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError("Download failed with HTTP \(http.statusCode)")
        }
        let dest = dir.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    private func unzipAndLocate(zip: URL, in dir: URL) async throws -> URL {
        try await validateZipEntries(zip)
        try await run("/usr/bin/unzip", ["-q", zip.path, "-d", dir.path])

        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let apps = contents.filter { $0.pathExtension == "app" }
        guard apps.count == 1, apps[0].lastPathComponent == Self.expectedAppName else {
            throw InstallError("Expected exactly one \(Self.expectedAppName) in the downloaded zip")
        }
        return apps[0]
    }

    // Reject unsafe archives before extracting. Two listings, because the cheap
    // names-only `-Z1` listing hides symlinks (which `unzip` would follow during
    // extraction to write outside the work dir, before any signature check runs).
    private func validateZipEntries(_ zip: URL) async throws {
        let names = try await run("/usr/bin/unzip", ["-Z1", zip.path])
        for entry in names.split(separator: "\n") {
            let path = String(entry)
            if path.hasPrefix("/") || path.contains("../") || path.contains("/..") {
                throw InstallError("Zip contains unsafe path: \(path)")
            }
        }
        // The long zipinfo listing prints a leading mode string per entry; a
        // symlink shows as "lrwx...". A symlink in the archive is never something
        // a legitimate WhatBattery release contains, so reject the whole zip.
        let modes = try await run("/usr/bin/unzip", ["-Z", zip.path])
        for line in modes.split(separator: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("lrwx") {
                throw InstallError("Zip contains a symlink; refusing to install")
            }
        }
    }

    /// Guard against a downgrade or a tag/binary mismatch: the downloaded bundle's
    /// own `CFBundleShortVersionString` must match the advertised release version
    /// and be newer than what's running. A tampered Info.plist version would later
    /// be caught by `codesign --verify --strict` (the seal covers Info.plist), so
    /// this runs first purely as a cheap sanity gate.
    private func verifyNotDowngrade(app: URL, advertised: String) throws {
        let embedded = (Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        guard embedded == advertised else {
            throw InstallError("Version mismatch: release claims \(advertised) but the bundle is \(embedded.isEmpty ? "unknown" : embedded)")
        }
        guard AppInfo.isNewer(remote: embedded, current: AppInfo.version) else {
            throw InstallError("Not an upgrade: \(embedded) is not newer than \(AppInfo.version)")
        }
    }

    private func verifySignatureMatches(new: URL, current: URL) async throws {
        // Check team identifier matches.
        let newTeam = try await teamIdentifier(of: new)
        let currentTeam = try await teamIdentifier(of: current)
        if newTeam != currentTeam {
            throw InstallError("Signature mismatch: refusing to install (current \(currentTeam), new \(newTeam))")
        }
        // Check bundle ID is exactly what we expect.
        let bundleID = Bundle(url: new)?.bundleIdentifier ?? ""
        if bundleID != Self.expectedBundleID {
            throw InstallError("Unexpected bundle identifier: \(bundleID)")
        }
        // Verify signature structure is valid.
        try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", new.path])
        // Verify Gatekeeper / notarization acceptance.
        try await run("/usr/sbin/spctl", ["--assess", "--type", "execute", new.path])
        // Strip quarantine only after all checks pass.
        _ = try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", new.path])
    }

    private func teamIdentifier(of app: URL) async throws -> String {
        let result = try await runProcess("/usr/bin/codesign", ["-dvv", app.path])
        if result.exitCode != 0 {
            throw InstallError("codesign failed (\(result.exitCode)): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        // codesign writes its `-dvv` report to stderr, not stdout. Search both so
        // the parse is robust to that (and to any future change in which stream
        // it uses).
        let combined = result.stderr + "\n" + result.stdout
        for line in combined.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count))
            }
        }
        throw InstallError("Could not read TeamIdentifier from \(app.lastPathComponent)")
    }

    private func launchSwapScript(newApp: URL, currentApp: URL, workDir: URL) throws {
        let script = Self.makeSwapScript(
            pid: ProcessInfo.processInfo.processIdentifier,
            newPath: newApp.path,
            oldPath: currentApp.path,
            workDirPath: workDir.path
        )

        let scriptURL = workDir.appendingPathComponent("whatbattery-swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]
        // Detach stdio so the child survives our exit cleanly.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        try task.run()
    }

    // MARK: - Process helpers

    /// The outcome of a finished subprocess, with stdout and stderr kept apart.
    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Run a subprocess on a background queue and throw on a non-zero exit.
    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) async throws -> String {
        let result = try await runProcess(launchPath, arguments)
        if result.exitCode != 0 {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw InstallError("\(launchPath) failed (\(result.exitCode)): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result.stdout
    }

    /// Run a subprocess off the main actor (via the global queue), so the install
    /// UI never freezes while `codesign` / `spctl` / `unzip` run. stdout and
    /// stderr get their own pipes, each drained concurrently while the child is
    /// alive: a child that writes more than the ~64KB pipe buffer would otherwise
    /// stall on `write()` while we sat in `waitUntilExit()`, deadlocking.
    private func runProcess(_ launchPath: String, _ arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: launchPath)
                task.arguments = arguments

                let outPipe = Pipe()
                let errPipe = Pipe()
                task.standardOutput = outPipe
                task.standardError = errPipe
                task.standardInput = FileHandle.nullDevice

                do {
                    try task.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain stderr on its own queue while we drain stdout inline, so
                // neither pipe's buffer can fill and stall the child. Both reads
                // return at EOF (the child closing the pipe), and `group.wait()`
                // gives the happens-before that makes `errData` safe to read.
                let errQueue = DispatchQueue(label: "app.whatbattery.installer.stderr")
                let group = DispatchGroup()
                var errData = Data()
                group.enter()
                errQueue.async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                task.waitUntilExit()

                continuation.resume(returning: ProcessResult(
                    exitCode: task.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }

    private nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Builds the detached bundle-swap script. Pure (no I/O), so the deletion
    /// target can be asserted in tests without running anything destructive.
    ///
    /// The cleanup at the end removes `workDirPath` and nothing else. The download
    /// zip, the extracted bundle and this script itself all live inside that
    /// per-update folder, so one removal cleans everything we created. It must
    /// never widen to the folder's parent (the shared temp root).
    nonisolated static func makeSwapScript(pid: Int32, newPath: String, oldPath: String, workDirPath: String) -> String {
        """
        #!/bin/bash
        set -e
        PID=\(pid)
        NEW=\(shellQuote(newPath))
        OLD=\(shellQuote(oldPath))
        BACKUP="${OLD}.backup"

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

        # Move old bundle to backup instead of deleting it.
        # If the swap fails, the user can rename .backup back.
        rm -rf "$BACKUP"
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

private struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { self.errorDescription = message }
}
