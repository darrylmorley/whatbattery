import XCTest
@testable import WhatBatteryDarwinBackend
@testable import WhatBatteryCore

/// Every connected-but-unreadable device used to arrive with the same message,
/// which is why a user with a missing iPad had to ask whether his iPadOS version
/// was supported: the app could not tell him, because it had not kept the reason.
final class IDeviceUnreadableReasonTests: XCTestCase {
    private func realBattery() -> [String: Any] {
        [
            "DesignCapacity": 3329,
            "NominalChargeCapacity": 3331,
            "AppleRawCurrentCapacity": 2045,
            "CurrentCapacity": 61,
            "MaxCapacity": 100,
            "CycleCount": 90,
            "Temperature": 2809,
            "Voltage": 4205,
        ]
    }

    private func reason(reached: Bool, battery: [String: Any]?) -> IDeviceBatteryReader.UnreadableReason? {
        switch IDeviceBatteryReader.classify(reached: reached, batteryDictionary: battery) {
        case .success: return nil
        case .failure(let reason): return reason
        }
    }

    /// Connect or the lockdown session failed, so the bridge never learned what
    /// the device even is. This is the one that means "locked, or not trusted",
    /// and it is the likeliest cause of a device Finder lists and we do not.
    /// A locked device can still answer some lockdown values while refusing a
    /// session. The reason used to be inferred from an empty product type, so
    /// that device was told it "reported no battery" when it had never let us
    /// ask. `classify` cannot make that mistake now: the product type is not one
    /// of its inputs, which is why there is no separate test for it.
    func testNoSessionMeansNotReached() {
        XCTAssertEqual(reason(reached: false, battery: nil), .notReached)
    }

    /// Identified, so we got there. The relay simply gave nothing back, which is
    /// a different problem with different advice.
    func testReachedButNoBatteryMeansRelaySilent() {
        XCTAssertEqual(reason(reached: true, battery: nil), .relaySilent)
    }

    func testUnmappableDictionaryMeansUnrecognisedShape() {
        XCTAssertEqual(reason(reached: true, battery: ["Unexpected": "shape"]), .unrecognisedShape)
    }

    /// Mapped, but the numbers are not a battery. Kept distinct from an
    /// unrecognised shape because it means the keys were right and the values
    /// were not, which points somewhere else entirely.
    func testMappableButImplausibleValuesAreCalledThat() {
        // A full charge well above design is a misread key, not a battery.
        var battery = realBattery()
        battery["NominalChargeCapacity"] = 9000   // 270% of a 3329 mAh design
        XCTAssertEqual(reason(reached: true, battery: battery), .implausibleValues)
    }

    func testARealBatteryClassifiesAsReadable() {
        XCTAssertNil(reason(reached: true, battery: realBattery()))
    }

    /// `classify` must pass the bridge's PMU flag straight through to the
    /// mapped model rather than drop it, since that flag is what makes
    /// `fullChargeCapacitymAh` pick the right key on a pre-A11 device.
    func testClassifyThreadsThePMUFlagThrough() throws {
        let dict = realBattery()
        let smart = try XCTUnwrap(
            IDeviceBatteryReader.classify(reached: true, batteryDictionary: dict).get()
        )
        XCTAssertFalse(smart.isPMUSourced)

        let pmu = try XCTUnwrap(
            IDeviceBatteryReader.classify(reached: true, batteryDictionary: dict, isPMUSourced: true).get()
        )
        XCTAssertTrue(pmu.isPMUSourced)
    }

    /// Each reason has to say something different, or splitting them bought
    /// nothing. Also guards against a copy-paste leaving two cases identical.
    func testEveryReasonReadsDifferently() {
        let all: [IDeviceBatteryReader.UnreadableReason] =
            [.notReached, .relaySilent, .unrecognisedShape, .implausibleValues]
        let descriptions = all.map(\.description)
        XCTAssertEqual(Set(descriptions).count, all.count)
        for text in descriptions {
            XCTAssertFalse(text.isEmpty)
            // These are dropped into "<device> <reason>.", so a leading capital
            // or a trailing stop would read wrong in the sentence.
            XCTAssertFalse(text.hasSuffix("."), "'\(text)' should not end the sentence itself")
            XCTAssertEqual(text.first, text.first?.lowercased().first)
        }
    }
}
