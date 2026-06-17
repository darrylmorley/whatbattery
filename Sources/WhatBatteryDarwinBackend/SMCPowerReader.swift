import Foundation
import IOKit

/// The Mac's overall power input, as the SMC reports it on the DC-in rail.
///
/// Desktops (Mac mini / Studio / Pro) have no battery controller, so the laptop
/// pipeline's battery power is always 0 there. The DC-in figure still exists:
/// the internal PSU feeds the logic board on a rail the SMC meters as
/// `VD0R` / `ID0R` / `PDTR`.
public struct SMCSystemPowerInput: Sendable, Equatable {
    public let volts: Double
    public let amps: Double
    public let watts: Double

    public init(volts: Double, amps: Double, watts: Double) {
        self.volts = volts
        self.amps = amps
        self.watts = watts
    }
}

/// Reads live power figures from the SMC via the AppleSMC user client.
///
/// Lifted from WhatCable. It opens a user client (`IOServiceOpen` on `AppleSMC`)
/// and calls a struct method, the long-standing public ABI used by powermetrics,
/// smcFanControl and libsmc. The app is not sandboxed, so a hardened-runtime
/// Developer ID build is allowed to do this. If the open ever fails, every
/// method degrades to "no data" rather than crashing.
///
/// Read-only: it only ever reads keys, never writes.
public final class SMCPowerReader {
    private var connection: io_connect_t = 0

    public init() {
        // The kernel reads this struct at fixed C offsets and rejects any other
        // size. Catch a layout regression during development.
        assert(
            MemoryLayout<SMCParamStruct>.stride == 80,
            "SMCParamStruct must be 80 bytes to match the AppleSMC ABI, got \(MemoryLayout<SMCParamStruct>.stride)"
        )
    }

    deinit { close() }

    /// Opens the AppleSMC user client. Idempotent. Returns false when AppleSMC
    /// is missing or the open is refused.
    @discardableResult
    public func open() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { return false }
        connection = conn
        return true
    }

    public func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    /// Reads the Mac's DC-in power input (`VD0R` / `ID0R` / `PDTR`). Opens
    /// lazily. Returns nil when the SMC can't be opened or neither voltage nor
    /// current is present. Works on desktops including M1/M2 Mac minis.
    public func readSystemPowerInput() -> SMCSystemPowerInput? {
        guard open() else { return nil }
        let volts = readFloat("VD0R")
        let amps = readFloat("ID0R")
        guard volts != nil || amps != nil else { return nil }
        let watts = readFloat("PDTR") ?? ((volts ?? 0) * (amps ?? 0))
        return SMCSystemPowerInput(
            volts: Double(volts ?? 0),
            amps: Double(amps ?? 0),
            watts: Double(watts)
        )
    }

    /// Live battery discharge power in milliwatts, read from the SMC battery
    /// rail (`PPBR`). Opens lazily. Returns nil when the SMC can't be opened,
    /// the key is absent (a desktop has no battery rail), or the value is
    /// implausible.
    ///
    /// Why this exists: on Apple Silicon, the fuel gauge's BatteryPower does not
    /// update under load (it holds a value for tens of seconds), so a discharge
    /// figure read from there sits stale. `PPBR` is the live battery rail
    /// (updates ~1 Hz, tracks load).
    public func readBatteryPowerMW() -> Int? {
        guard open() else { return nil }
        guard let watts = readFloat("PPBR") else { return nil }
        // Real discharge is a few watts to tens of watts; 200 W is a safe
        // ceiling. Anything negative or above means the wrong key on this
        // silicon; fall back to the gauge.
        guard watts >= 0, watts < 200 else { return nil }
        return Int((Double(watts) * 1000).rounded())
    }

    // MARK: - Key reads

    private func readFloat(_ key: String) -> Float? {
        guard let bytes = readKey(key) else { return nil }
        return Self.decodeFloat(bytes)
    }

    /// Decode an SMC `flt` payload. Returns nil for short payloads and for
    /// non-finite values (infinity, NaN). Internal so the decode is unit-
    /// testable without SMC hardware.
    static func decodeFloat(_ bytes: [UInt8]) -> Float? {
        guard bytes.count >= 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Float(bitPattern: bits)
        return value.isFinite ? value : nil
    }

    // MARK: - SMC ABI

    private func readKey(_ key: String) -> [UInt8]? {
        guard let fourCC = Self.fourCC(key) else { return nil }

        var info = SMCParamStruct()
        info.key = fourCC
        info.data8 = Self.cmdGetKeyInfo
        guard let infoOut = callDriver(&info) else { return nil }
        let size = infoOut.keyInfo.dataSize
        guard size > 0 else { return nil }

        var read = SMCParamStruct()
        read.key = fourCC
        read.keyInfo.dataSize = size
        read.keyInfo.dataType = infoOut.keyInfo.dataType
        read.data8 = Self.cmdReadKey
        guard let readOut = callDriver(&read) else { return nil }

        let count = Int(min(size, 32))
        var value = readOut.bytes
        return withUnsafeBytes(of: &value) { Array($0.prefix(count)) }
    }

    private func callDriver(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        guard connection != 0 else { return nil }
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            Self.kernelIndex,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        return kr == KERN_SUCCESS ? output : nil
    }

    /// Packs a 4-character key into its FourCC `UInt32` (MSB first).
    static func fourCC(_ key: String) -> UInt32? {
        let scalars = Array(key.unicodeScalars)
        guard scalars.count == 4 else { return nil }
        var value: UInt32 = 0
        for scalar in scalars {
            guard scalar.value <= 0xFF else { return nil }
            value = (value << 8) | UInt32(scalar.value)
        }
        return value
    }

    private static let kernelIndex: UInt32 = 2
    private static let cmdReadKey: UInt8 = 5
    private static let cmdGetKeyInfo: UInt8 = 9
}

// MARK: - AppleSMC user-client ABI structs
//
// These mirror the C layout used by powermetrics / smcFanControl byte-for-byte.
// Field order and types must not change: the kernel reads this struct at fixed
// offsets. `MemoryLayout<SMCParamStruct>.stride` must be 80 bytes.

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

/// A 32-byte payload buffer as a homogeneous tuple (the C `char bytes[32]`).
private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimit = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    // C keeps `keyInfo`'s 3-byte trailing padding before `result`; this explicit
    // pad restores the C offsets so the total is 80 (asserted in `init()`).
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
