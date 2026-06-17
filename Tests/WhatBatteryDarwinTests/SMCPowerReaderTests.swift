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
