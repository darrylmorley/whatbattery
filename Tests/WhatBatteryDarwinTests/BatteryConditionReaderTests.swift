import XCTest
import WhatBatteryCore
@testable import WhatBatteryDarwinBackend

/// A real read against this machine. Lenient: a desktop or VM with no battery
/// returns `.unknown`, which is valid. When a battery is present, the condition
/// must be a real determination (anything but unknown).
final class BatteryConditionReaderTests: XCTestCase {
    func testReadIsSaneForThisMachine() {
        let condition = BatteryConditionReader.read()
        if DarwinSnapshotProvider().currentSnapshot() != nil {
            XCTAssertNotEqual(condition, .unknown, "a Mac with a battery should report a condition")
        }
        // No battery: .unknown is acceptable, and the call must not crash.
    }
}
