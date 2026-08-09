import XCTest
@testable import WhatBatteryDarwinBackend

/// One physical device can be enumerated twice, once per interface. Observed on
/// a Mac with a single iPhone 15 plugged in and WiFi-paired: `AMDCreateDeviceList`
/// returned it as interface type 1 and again as type 2, same UDID. Reading both
/// opened two lockdown sessions and two diagnostics relays for one device, and
/// the duplicate reached the SwiftUI picker, which keys on UDID.
final class MobileDeviceDedupeTests: XCTestCase {
    private let usb: Int32 = 1
    private let network: Int32 = 2

    /// The first interface of each device, which is the one actually read
    /// unless it fails and the fallback kicks in.
    private func pick(_ candidates: [(udid: String, interface: Int32, device: String)]) -> [String] {
        MobileDeviceBridge.interfacesPerDevice(candidates).compactMap(\.first)
    }

    private func groups(_ candidates: [(udid: String, interface: Int32, device: String)]) -> [[String]] {
        MobileDeviceBridge.interfacesPerDevice(candidates)
    }

    func testTheSameDeviceOnTwoInterfacesIsReadOnce() {
        let result = pick([
            (udid: "A", interface: usb, device: "A-usb"),
            (udid: "A", interface: network, device: "A-net"),
        ])
        XCTAssertEqual(result, ["A-usb"])
    }

    /// USB wins whichever order the framework offers them in. The relay read is
    /// blocking I/O and a cabled device answers it more reliably.
    func testUSBWinsRegardlessOfOrder() {
        XCTAssertEqual(
            pick([(udid: "A", interface: network, device: "A-net"), (udid: "A", interface: usb, device: "A-usb")]),
            ["A-usb"]
        )
    }

    /// The swap happens in place, so preferring USB does not shuffle a
    /// multi-device list under the user.
    func testOrderIsPreservedWhenTheUSBEntryComesSecond() {
        let result = pick([
            (udid: "A", interface: network, device: "A-net"),
            (udid: "B", interface: usb, device: "B"),
            (udid: "A", interface: usb, device: "A-usb"),
        ])
        XCTAssertEqual(result, ["A-usb", "B"])
    }

    func testDistinctDevicesAreAllKept() {
        let result = pick([
            (udid: "A", interface: usb, device: "A"),
            (udid: "B", interface: network, device: "B"),
            (udid: "C", interface: usb, device: "C"),
        ])
        XCTAssertEqual(result, ["A", "B", "C"])
    }

    /// Two devices that both failed to identify are not evidence of being the
    /// same device, so an empty UDID never collapses with another.
    func testUnidentifiedDevicesAreNotCollapsed() {
        let result = pick([
            (udid: "", interface: usb, device: "unknown-1"),
            (udid: "", interface: network, device: "unknown-2"),
        ])
        XCTAssertEqual(result, ["unknown-1", "unknown-2"])
    }

    /// Neither entry is USB: keep the first rather than dropping both or
    /// preferring the later one arbitrarily.
    func testTwoNonUSBEntriesKeepTheFirst() {
        let result = pick([
            (udid: "A", interface: network, device: "A-net-1"),
            (udid: "A", interface: 3, device: "A-net-2"),
        ])
        XCTAssertEqual(result, ["A-net-1"])
    }

    func testEmptyInputIsEmpty() {
        XCTAssertTrue(pick([]).isEmpty)
    }

    /// The other interfaces are kept, not discarded. Preferring USB and throwing
    /// the rest away meant a stale USB entry (cable half out, device mid
    /// reconnect) lost the network entry that would have worked, turning a
    /// readable device unreadable. Preference sets the order to try, not the
    /// only candidate.
    func testTheOtherInterfaceIsKeptAsAFallback() {
        XCTAssertEqual(
            groups([
                (udid: "A", interface: network, device: "A-net"),
                (udid: "A", interface: usb, device: "A-usb"),
            ]),
            [["A-usb", "A-net"]]
        )
    }

    /// Three interfaces for one device: USB first, the rest in the order the
    /// framework listed them.
    func testRemainingInterfacesKeepTheirOriginalOrder() {
        XCTAssertEqual(
            groups([
                (udid: "A", interface: 3, device: "A-other"),
                (udid: "A", interface: network, device: "A-net"),
                (udid: "A", interface: usb, device: "A-usb"),
            ]),
            [["A-usb", "A-other", "A-net"]]
        )
    }

    func testEachDeviceGetsItsOwnGroup() {
        XCTAssertEqual(
            groups([
                (udid: "A", interface: usb, device: "A"),
                (udid: "B", interface: network, device: "B"),
            ]),
            [["A"], ["B"]]
        )
    }
}
