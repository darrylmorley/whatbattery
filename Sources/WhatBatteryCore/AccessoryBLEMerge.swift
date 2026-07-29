import Foundation

/// Fills accessories that report no battery through `system_profiler` with a
/// level read over the GATT Battery Service. Pure so the merge rules are
/// testable:
///
/// - Only an accessory with no available cells is filled; a level the system
///   profiler already reports is never overridden (it may be richer, e.g. the
///   per-bud AirPods breakdown).
/// - Matching is by device name, the only identity both sources share (the
///   profiler exposes a Bluetooth address, CoreBluetooth a UUID; neither maps
///   to the other without a join key).
/// - A name is only trusted when it is unambiguous on both sides: accessories
///   sharing a name are left untouched (the level could belong to either), and
///   the BLE reader likewise drops names carried by more than one peripheral.
public enum AccessoryBLEMerge {
    public static func merge(_ accessories: [Accessory], bleLevels: [String: Int]) -> [Accessory] {
        var nameCounts: [String: Int] = [:]
        for accessory in accessories {
            nameCounts[accessory.name, default: 0] += 1
        }
        return accessories.map { accessory in
            guard !accessory.isAvailable, nameCounts[accessory.name] == 1,
                  let level = bleLevels[accessory.name],
                  (0...100).contains(level) else { return accessory }
            return Accessory(
                id: accessory.id,
                name: accessory.name,
                kind: accessory.kind,
                cells: [Accessory.Cell(label: "", percent: level)],
                transport: accessory.transport
            )
        }
    }
}
