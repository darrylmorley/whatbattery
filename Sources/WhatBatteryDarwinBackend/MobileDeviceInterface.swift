import Foundation

/// How a device is attached, as `AMDeviceGetInterfaceType` reports it.
///
/// One definition, because there are now two mechanisms reading this number and
/// they must agree. `MobileDeviceBridge` uses it to prefer the cable when the
/// same device is enumerated twice; `DevicePresenceMonitor` uses it to say
/// whether a departure was a cable coming out, which decides whether the tab
/// acts on it at once or waits out a grace. Those two answering differently
/// would be very hard to see and would show up as a device that flickers.
///
/// The string form of the same question (`ReadingFreshness.isCable`) had already
/// been written out three times and consolidated for the same reason; this is
/// the integer form, which that consolidation did not reach.
///
/// Values confirmed on a Mac with one iPhone enumerated on both interfaces at
/// once. They come from a private framework, so anything unrecognised is
/// deliberately treated as "not a cable": that is the answer whose failure mode
/// is a longer wait rather than a live device evicted from the screen.
enum MobileDeviceInterface {
    static let usb: Int32 = 1
    static let network: Int32 = 2

    static func isCable(_ interface: Int32) -> Bool { interface == usb }
}
