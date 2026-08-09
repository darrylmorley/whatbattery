import XCTest
import WhatBatteryCore
@testable import WhatBatteryDarwinBackend

/// A real read against this machine. Lenient on purpose: a desktop Mac (or CI
/// with no battery) returns nil, which is a valid result, not a failure. When a
/// battery is present, the derived values must be sane.
final class SnapshotProviderSmokeTests: XCTestCase {
    func testCurrentSnapshotIsSaneOrAbsent() {
        let provider = DarwinSnapshotProvider()
        guard let snapshot = provider.currentSnapshot() else {
            // No battery on this machine. Acceptable.
            return
        }

        XCTAssertFalse(snapshot.deviceModel.isEmpty, "expected a hw.model on a Mac with a battery")
        XCTAssert((0...100).contains(snapshot.currentChargePercent), "charge % out of range: \(snapshot.currentChargePercent)")
        XCTAssertGreaterThan(snapshot.designCapacitymAh, 0)
        XCTAssertGreaterThan(snapshot.fullChargeCapacitymAh, 0)

        if let health = snapshot.healthPercent {
            // A real battery should not read absurdly low or above ~110%.
            XCTAssert((1.0...110.0).contains(health), "implausible health: \(health)")
        }

        // Temperature on a live battery sits well within these bounds. Absent is
        // allowed (a machine whose pack reports nothing usable), a wrong number
        // is not: that distinction is the whole point of the optional.
        if let temperature = snapshot.temperatureCelsius {
            XCTAssert((0.0...80.0).contains(temperature), "implausible temperature: \(temperature)")
        }
    }
}
