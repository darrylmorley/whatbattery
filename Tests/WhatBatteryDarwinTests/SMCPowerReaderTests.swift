import XCTest
@testable import WhatBatteryDarwinBackend

/// Tests the pure decode helpers, which need no SMC hardware.
final class SMCPowerReaderTests: XCTestCase {
    func testDecodeFloatOne() {
        // IEEE 754 1.0 = 0x3F800000, little-endian bytes.
        let bytes: [UInt8] = [0x00, 0x00, 0x80, 0x3F]
        XCTAssertEqual(SMCPowerReader.decodeFloat(bytes), 1.0)
    }

    func testDecodeFloatHalf() {
        // 0.5 = 0x3F000000.
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x3F]
        XCTAssertEqual(SMCPowerReader.decodeFloat(bytes), 0.5)
    }

    func testDecodeFloatRejectsShortPayload() {
        XCTAssertNil(SMCPowerReader.decodeFloat([0x00, 0x00, 0x80]))
    }

    func testDecodeFloatRejectsInfinity() {
        // +inf = 0x7F800000.
        let bytes: [UInt8] = [0x00, 0x00, 0x80, 0x7F]
        XCTAssertNil(SMCPowerReader.decodeFloat(bytes))
    }

    func testFourCCPacking() {
        // 'P','P','B','R' -> 0x50504252.
        XCTAssertEqual(SMCPowerReader.fourCC("PPBR"), 0x5050_4252)
    }

    func testFourCCRejectsWrongLength() {
        XCTAssertNil(SMCPowerReader.fourCC("PPB"))
        XCTAssertNil(SMCPowerReader.fourCC("PPBRX"))
    }
}

/// Drives the two-step key read with canned driver replies.
extension SMCPowerReaderTests {
    private static let cmdReadKey: UInt8 = 5
    private static let cmdGetKeyInfo: UInt8 = 9

    /// Builds a fake driver: answers key-info (data8 9) and read (data8 5)
    /// with the given result bytes, data size and payload start.
    private func fakeDriver(
        infoResult: UInt8,
        readResult: UInt8,
        dataSize: UInt32,
        payload: [UInt8]
    ) -> (inout SMCParamStruct) -> SMCParamStruct? {
        { input in
            var out = SMCParamStruct()
            switch input.data8 {
            case Self.cmdGetKeyInfo:
                out.result = infoResult
                out.keyInfo.dataSize = dataSize
            case Self.cmdReadKey:
                out.result = readResult
                var bytes = out.bytes
                withUnsafeMutableBytes(of: &bytes) { raw in
                    for (i, b) in payload.enumerated() { raw[i] = b }
                }
                out.bytes = bytes
            default:
                return nil
            }
            return out
        }
    }

    func testReadKeyReturnsNilWhenReadResultIsNonZero() {
        // 0x84: the SMC refused the read but the kernel call succeeded, so the
        // payload is zeroed. That must not come back as four zero bytes.
        let call = fakeDriver(infoResult: 0, readResult: 0x84, dataSize: 4, payload: [0, 0, 0, 0])
        XCTAssertNil(SMCPowerReader.readKey("PPBR", call: call))
    }

    func testReadKeyReturnsNilWhenKeyInfoResultIsNonZero() {
        // A refused key-info that still carries a size.
        let call = fakeDriver(infoResult: 0x84, readResult: 0, dataSize: 4, payload: [0x00, 0x00, 0x80, 0x3F])
        XCTAssertNil(SMCPowerReader.readKey("PPBR", call: call))
    }

    func testReadKeyReturnsBytesWhenResultIsZero() {
        let call = fakeDriver(infoResult: 0, readResult: 0, dataSize: 4, payload: [0x00, 0x00, 0x80, 0x3F])
        XCTAssertEqual(SMCPowerReader.readKey("PPBR", call: call), [0x00, 0x00, 0x80, 0x3F])
    }
}
