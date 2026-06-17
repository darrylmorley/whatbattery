import XCTest
@testable import WhatBatteryDarwinBackend

/// Real reads against this machine. Lenient: CI or a VM may not expose every
/// identity key, so a value is either empty or sane, never garbage. On a real Mac
/// these are populated.
final class SystemInfoTests: XCTestCase {
    func testHardwareModelIsEmptyOrSane() {
        let model = SystemInfo.hardwareModel()
        if !model.isEmpty {
            XCTAssertTrue(model.contains("Mac"), "unexpected hw.model: \(model)")
        }
    }

    func testChipIsEmptyOrSane() {
        let chip = SystemInfo.chip()
        // Apple Silicon reports "Apple M…"; tolerate empty on other hosts.
        if !chip.isEmpty {
            XCTAssertFalse(chip.contains("\0"))
        }
    }

    func testMarketingNameHasNoNulPadding() {
        // Device-tree strings come from a NUL-terminated data blob; the read must
        // strip the padding rather than leak it into the string.
        let name = SystemInfo.marketingName()
        XCTAssertFalse(name.contains("\0"), "marketing name kept NUL padding: \(name)")
    }

    func testRegulatoryModelNumberHasNoNulPadding() {
        let model = SystemInfo.regulatoryModelNumber()
        XCTAssertFalse(model.contains("\0"), "model number kept NUL padding: \(model)")
    }

    func testSerialIsEmptyOrTrimmed() {
        let serial = SystemInfo.hardwareSerial()
        XCTAssertEqual(serial, serial.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(serial.contains("\0"))
    }

    // MARK: - decodeProperty (the String/Data/NUL handling, with controlled input)

    func testDecodePropertyPlainString() {
        XCTAssertEqual(SystemInfo.decodeProperty("MacBook Pro"), "MacBook Pro")
    }

    func testDecodePropertyStringStripsNulPadding() {
        XCTAssertEqual(SystemInfo.decodeProperty("A3434\0\0\0"), "A3434")
    }

    func testDecodePropertyNulTerminatedData() {
        let data = Data("MacBook Pro (14-inch, M5)\0\0\0".utf8)
        XCTAssertEqual(SystemInfo.decodeProperty(data), "MacBook Pro (14-inch, M5)")
    }

    func testDecodePropertyDataWithoutNul() {
        XCTAssertEqual(SystemInfo.decodeProperty(Data("A3434".utf8)), "A3434")
    }

    func testDecodePropertyUnsupportedTypeIsEmpty() {
        XCTAssertEqual(SystemInfo.decodeProperty(42), "")
    }
}
