import XCTest
@testable import WhatBatteryCore

/// Values are from a real MacBook Pro (Mac17,2) on macOS 27, read with ioreg on
/// 2026-09-23. The capture did not include the battery node's own BatteryData,
/// so `node27` is built from keys whose values match the pack's.
final class BatteryChildNodesTests: XCTestCase {
    private func pack27() -> [String: Any] {
        [
            "DesignCapacity": 6249,
            "NominalChargeCapacity": 6090,
            "AppleRawMaxCapacity": 5938,
            "AppleRawCurrentCapacity": 5938,
            "Temperature": 2700,
            "VirtualTemperature": 2700,
            "ManufactureDate": 55_186_860_028_979 as Int64,
            "CycleCount": 82,
            "MaxCapacity": 100,
            "LifetimeData": [
                "MinimumTemperature": 11,
                "MaximumTemperature": 43,
                "AverageTemperature": 222,
                "MaximumChargeCurrent": 6825,
                "MinimumPackVoltage": 10144,
                "MaximumPackVoltage": 13304,
                "TotalOperatingTime": 5992,
            ] as [String: Any],
        ]
    }

    private func node27() -> [String: Any] {
        ["DesignCapacity": 6249, "NominalChargeCapacity": 6090, "MaxCapacity": 100, "CurrentCapacity": 100]
    }

    private func banks27() -> [BatteryBankData] {
        // Deliberately out of BankID order: the merge must sort.
        [
            BatteryBankData(bankID: 2, batteryData: ["CellVoltage": 4405, "Qmax": 6371, "WeightedRa": 41]),
            BatteryBankData(bankID: 0, batteryData: ["CellVoltage": 4405, "Qmax": 6388, "WeightedRa": 52]),
            BatteryBankData(bankID: 1, batteryData: ["CellVoltage": 4406, "Qmax": 6392, "WeightedRa": 42]),
        ]
    }

    func testMacOS27MergeRestoresPackAndCellDetail() throws {
        let merged = try XCTUnwrap(
            BatteryChildNodes.mergedBatteryData(node: node27(), pack: pack27(), banks: banks27())
        )
        XCTAssertEqual(AppleSmartBatteryMapper.capacity(topLevel: nil, batteryData: merged, key: "AppleRawMaxCapacity"), 5938)
        XCTAssertEqual(AppleSmartBatteryMapper.capacity(topLevel: nil, batteryData: merged, key: "AppleRawCurrentCapacity"), 5938)
        XCTAssertEqual(AppleSmartBatteryMapper.capacity(topLevel: nil, batteryData: merged, key: "DesignCapacity"), 6249)
        XCTAssertEqual(AppleSmartBatteryMapper.capacity(topLevel: nil, batteryData: merged, key: "NominalChargeCapacity"), 6090)

        let detail = try XCTUnwrap(BatteryPackDetail.from(batteryData: merged, currentTemperatureCentiC: 2700))
        XCTAssertEqual(detail.cellVoltagesMV, [4405, 4406, 4405])
        XCTAssertEqual(detail.cellQmax, [6388, 6392, 6371])
        XCTAssertEqual(detail.cellResistance, [52, 42, 41])
        XCTAssertEqual(detail.manufactureRaw, 55_186_860_028_979)
        XCTAssertNotNil(detail.lifetime)
    }

    func testNodeValuesWinOverPackAndBanks() throws {
        let node: [String: Any] = [
            "DesignCapacity": 8694,
            "CellVoltage": [4409, 4408, 4411],
        ]
        let merged = try XCTUnwrap(
            BatteryChildNodes.mergedBatteryData(node: node, pack: ["DesignCapacity": 1], banks: banks27())
        )
        XCTAssertEqual(merged["DesignCapacity"] as? Int, 8694)
        XCTAssertEqual(BatteryPackDetail.intArray(merged["CellVoltage"]), [4409, 4408, 4411])
        // Qmax was not on the node, so it still comes from the banks.
        XCTAssertEqual(BatteryPackDetail.intArray(merged["Qmax"]), [6388, 6392, 6371])
    }

    func testOldShapeWithoutChildrenIsUnchanged() throws {
        let node: [String: Any] = ["CellVoltage": [4409, 4408, 4411], "Qmax": [6288, 6280, 6311], "DailyMinSoc": 99]
        let merged = try XCTUnwrap(BatteryChildNodes.mergedBatteryData(node: node, pack: nil, banks: []))
        XCTAssertEqual(Set(merged.keys), Set(node.keys))
        XCTAssertEqual(BatteryPackDetail.intArray(merged["Qmax"]), [6288, 6280, 6311])
        XCTAssertNil(BatteryChildNodes.mergedBatteryData(node: nil, pack: nil, banks: []))
    }

    func testBankMissingAValueLeavesThatArrayEmpty() throws {
        var banks = banks27()
        banks[0] = BatteryBankData(bankID: 2, batteryData: ["CellVoltage": 4405, "WeightedRa": 41]) // no Qmax
        let merged = try XCTUnwrap(BatteryChildNodes.mergedBatteryData(node: nil, pack: pack27(), banks: banks))
        XCTAssertNil(merged["Qmax"])
        XCTAssertEqual(BatteryPackDetail.intArray(merged["CellVoltage"]), [4405, 4406, 4405])
    }

    func testUnreadableOrDuplicateBankIDsProduceNoArrays() throws {
        let missingID = [
            BatteryBankData(bankID: 0, batteryData: ["CellVoltage": 4405]),
            BatteryBankData(bankID: -1, batteryData: ["CellVoltage": 4406]),
        ]
        let duplicate = [
            BatteryBankData(bankID: 0, batteryData: ["CellVoltage": 4405]),
            BatteryBankData(bankID: 0, batteryData: ["CellVoltage": 4406]),
        ]
        let gapped = [
            BatteryBankData(bankID: 0, batteryData: ["CellVoltage": 4405]),
            BatteryBankData(bankID: 2, batteryData: ["CellVoltage": 4406]),
        ]
        for banks in [missingID, duplicate, gapped] {
            let merged = try XCTUnwrap(BatteryChildNodes.mergedBatteryData(node: nil, pack: pack27(), banks: banks))
            XCTAssertNil(merged["CellVoltage"])
        }
    }

    func testMacOS27TemperatureComesFromPackInCentiCelsius() {
        let t = BatteryChildNodes.temperatures(nodeTemperatureRaw: nil, nodeVirtualRaw: nil, pack: pack27())
        XCTAssertEqual(t.temperatureCentiC, 2700)
        XCTAssertEqual(t.virtualCentiC, 2700)
    }

    func testOldNodeTemperatureKeepsDeciKelvinConversion() {
        // 3000 deci-Kelvin = 26.85 C. The pack must not override the node.
        let t = BatteryChildNodes.temperatures(nodeTemperatureRaw: 3000, nodeVirtualRaw: 2690, pack: pack27())
        XCTAssertEqual(t.temperatureCentiC, 2685)
        XCTAssertEqual(t.virtualCentiC, 2690)
    }

    func testPackTemperatureIsOnlyAFallbackAndMustBePlausible() {
        let onlyTemperature = BatteryChildNodes.temperatures(
            nodeTemperatureRaw: nil, nodeVirtualRaw: nil, pack: ["Temperature": 2700, "VirtualTemperature": 65535]
        )
        XCTAssertEqual(onlyTemperature.temperatureCentiC, 2700)
        XCTAssertNil(onlyTemperature.virtualCentiC)

        let nonsense = BatteryChildNodes.temperatures(
            nodeTemperatureRaw: nil, nodeVirtualRaw: nil, pack: ["Temperature": 65535]
        )
        XCTAssertNil(nonsense.temperatureCentiC)

        let nothing = BatteryChildNodes.temperatures(nodeTemperatureRaw: nil, nodeVirtualRaw: nil, pack: nil)
        XCTAssertNil(nothing.temperatureCentiC)
        XCTAssertNil(nothing.virtualCentiC)
    }

    func testTrailingMissingBankIsCaughtByPackBankCount() throws {
        let twoOfThree = Array(banks27().filter { $0.bankID < 2 })
        let short = try XCTUnwrap(
            BatteryChildNodes.mergedBatteryData(node: nil, pack: pack27(), banks: twoOfThree, expectedBankCount: 3)
        )
        XCTAssertNil(short["CellVoltage"])

        let full = try XCTUnwrap(
            BatteryChildNodes.mergedBatteryData(node: nil, pack: pack27(), banks: banks27(), expectedBankCount: 3)
        )
        XCTAssertEqual(BatteryPackDetail.intArray(full["CellVoltage"]), [4405, 4406, 4405])
    }
}
