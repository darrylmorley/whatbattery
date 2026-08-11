import XCTest
@testable import WhatBatteryDarwinBackend

/// The folding of raw attach/detach events into "is this device present", which
/// is the part with logic in it. The subscription itself needs the framework and
/// a real device, so it is exercised by hand rather than here.
final class DevicePresenceMonitorTests: XCTestCase {
    private let usb: Int32 = 1
    private let network: Int32 = 2

    func testAttachAndDetachOfASingleInterface() {
        let monitor = DevicePresenceMonitor()
        XCTAssertEqual(monitor.record(attached: true, udid: "A", interface: usb),
                       .attached(udid: "A", interface: usb))
        XCTAssertEqual(monitor.attachedUDIDs, ["A"])
        XCTAssertEqual(monitor.record(attached: false, udid: "A", interface: usb),
                       .detached(udid: "A", interface: usb))
        XCTAssertTrue(monitor.attachedUDIDs.isEmpty)
    }

    /// A device cabled and WiFi-paired attaches twice. The second attach is not
    /// news, and reporting it would have the caller acting on an arrival that
    /// already happened.
    func testTheSecondInterfaceIsNotAnArrival() {
        let monitor = DevicePresenceMonitor()
        _ = monitor.record(attached: true, udid: "A", interface: usb)
        XCTAssertNil(monitor.record(attached: true, udid: "A", interface: network))
        XCTAssertEqual(monitor.attachedUDIDs, ["A"])
    }

    /// And it is only gone when the last interface goes. Unplugging the cable
    /// from a device that is also on WiFi is not a disconnection, and treating
    /// it as one would drop a device that is still perfectly readable.
    func testLosingOneOfTwoInterfacesIsNotADeparture() {
        let monitor = DevicePresenceMonitor()
        _ = monitor.record(attached: true, udid: "A", interface: usb)
        _ = monitor.record(attached: true, udid: "A", interface: network)

        XCTAssertNil(monitor.record(attached: false, udid: "A", interface: usb))
        XCTAssertEqual(monitor.attachedUDIDs, ["A"], "still there over WiFi")

        XCTAssertEqual(monitor.record(attached: false, udid: "A", interface: network),
                       .detached(udid: "A", interface: network))
        XCTAssertTrue(monitor.attachedUDIDs.isEmpty)
    }

    func testDevicesAreTrackedSeparately() {
        let monitor = DevicePresenceMonitor()
        _ = monitor.record(attached: true, udid: "A", interface: usb)
        _ = monitor.record(attached: true, udid: "B", interface: network)
        XCTAssertEqual(monitor.attachedUDIDs, ["A", "B"])

        _ = monitor.record(attached: false, udid: "A", interface: usb)
        XCTAssertEqual(monitor.attachedUDIDs, ["B"])
    }

    /// A detach for something never seen is noise, not a departure.
    func testAnUnknownDetachReportsNothing() {
        let monitor = DevicePresenceMonitor()
        XCTAssertNil(monitor.record(attached: false, udid: "GHOST", interface: usb))
    }

    /// A repeated attach on the same interface must not make the device look
    /// present twice, or the matching detach would leave it stuck.
    func testARepeatedAttachOnOneInterfaceIsIdempotent() {
        let monitor = DevicePresenceMonitor()
        _ = monitor.record(attached: true, udid: "A", interface: usb)
        XCTAssertNil(monitor.record(attached: true, udid: "A", interface: usb))
        XCTAssertEqual(monitor.record(attached: false, udid: "A", interface: usb),
                       .detached(udid: "A", interface: usb))
        XCTAssertTrue(monitor.attachedUDIDs.isEmpty)
    }

    /// The framework can hand back a device it cannot identify. Tracking it
    /// under an empty key would merge every such device into one.
    func testAnEmptyUDIDIsIgnored() {
        let monitor = DevicePresenceMonitor()
        XCTAssertNil(monitor.record(attached: true, udid: "", interface: usb))
        XCTAssertTrue(monitor.attachedUDIDs.isEmpty)
    }

    /// The session decides whether to act on a detach from this, so it has to
    /// be the interface that went rather than anything inferred later. An
    /// unrecognised transport is deliberately not a cable: the value comes from
    /// a private framework, and guessing wrong here evicts a live device.
    func testOnlyUSBCountsAsACable() {
        XCTAssertTrue(DevicePresenceMonitor.Change.detached(udid: "A", interface: usb).isCable)
        XCTAssertFalse(DevicePresenceMonitor.Change.detached(udid: "A", interface: network).isCable)
        XCTAssertFalse(DevicePresenceMonitor.Change.detached(udid: "A", interface: 7).isCable)
        XCTAssertTrue(DevicePresenceMonitor.Change.attached(udid: "A", interface: usb).isCable)
    }

    /// The interface that made the device absent is not always the one it was
    /// attached on first. A device on both loses the cable (suppressed, still
    /// present), then loses WiFi, and the departure that finally comes out is
    /// the WiFi one, which is the whole reason the caller must not classify it
    /// from the device's last reading.
    func testTheReportedInterfaceIsTheOneThatMadeItAbsent() {
        let monitor = DevicePresenceMonitor()
        _ = monitor.record(attached: true, udid: "A", interface: usb)
        _ = monitor.record(attached: true, udid: "A", interface: network)

        XCTAssertNil(monitor.record(attached: false, udid: "A", interface: usb))
        let departure = monitor.record(attached: false, udid: "A", interface: network)
        XCTAssertEqual(departure, .detached(udid: "A", interface: network))
        XCTAssertEqual(departure?.isCable, false, "the cable went first, but WiFi is what made it absent")
    }

    func testStopForgetsEverything() {
        let monitor = DevicePresenceMonitor()
        _ = monitor.record(attached: true, udid: "A", interface: usb)
        monitor.stop()
        XCTAssertTrue(monitor.attachedUDIDs.isEmpty)
    }
}
