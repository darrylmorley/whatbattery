import Foundation
import WhatBatteryCore

/// Reads the battery's service condition from `system_profiler SPPowerDataType`,
/// the authoritative source that matches macOS System Information / Settings.
///
/// We use this rather than the IOPowerSources `BatteryHealth` key, which proved
/// unreliable in testing (it reported "Check Battery" on a battery that Settings
/// and system_profiler both call "Normal"). `system_profiler` is a first-party
/// tool present on every Mac. Read-only. The call blocks (a fraction of a
/// second), so callers run it off the main actor.
public enum BatteryConditionReader {
    public static func read() -> BatteryCondition {
        readHealth().condition
    }

    /// Both of macOS's own figures: the service condition and the "Maximum
    /// Capacity" percentage System Settings shows.
    ///
    /// Cached briefly. Spawning `system_profiler` costs a noticeable fraction of
    /// a second, and this is hit on every overview appearance and every report
    /// build; neither value moves faster than the gauge updates, so a short TTL
    /// costs nothing in freshness.
    public static func readHealth() -> SystemProfilerBatteryHealth {
        if let cached = cache.value() { return cached }
        guard let output = systemProfilerPower() else { return .unknown }
        let parsed = SystemProfilerBatteryHealth.from(systemProfilerOutput: output)
        cache.store(parsed)
        return parsed
    }

    private static let cache = TimedCache(ttl: 60)

    private static func systemProfilerPower() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType"]
        // Force English so the "Condition" line and its labels parse on a
        // localized macOS install.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        // Read on a background queue so a stalled system_profiler can't hang the
        // caller forever; give up after a few seconds and terminate it.
        let handle = pipe.fileHandleForReading
        let box = DataBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = handle.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return String(data: box.data, encoding: .utf8)
    }
}

/// A minimal box so the background read can hand the data back across the
/// semaphore (which provides the happens-before ordering).
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// A last-value-wins cache with a time to live. Locked rather than actor-based
/// because callers read it from a detached task and expect a synchronous answer.
private final class TimedCache: @unchecked Sendable {
    private let ttl: TimeInterval
    private let lock = NSLock()
    private var stored: (value: SystemProfilerBatteryHealth, at: Date)?

    init(ttl: TimeInterval) { self.ttl = ttl }

    func value() -> SystemProfilerBatteryHealth? {
        lock.lock()
        defer { lock.unlock() }
        guard let stored, Date().timeIntervalSince(stored.at) < ttl else { return nil }
        return stored.value
    }

    func store(_ value: SystemProfilerBatteryHealth) {
        lock.lock()
        defer { lock.unlock() }
        stored = (value, Date())
    }
}
