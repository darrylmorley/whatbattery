import Foundation

/// Every battery field read through the resolver, and where each one is known
/// to live. When Apple moves a key, the fix is a line here.
public enum BatteryFieldMap {
    /// The cycle count when the gauge last relearned its capacity. macOS 14 to
    /// 26 keep it in the node's `BatteryData.LifetimeData` (all 944 probe-32
    /// dumps carrying it, none at `BatteryData`'s top level, measured
    /// 2026-09-24); macOS 27 moved `LifetimeData` onto the pack (one MacBook,
    /// 2026-09-23). A count means the same wherever it sits, so the resolver
    /// may search for it. Corpus values run 0 to 1746; 0 means never relearned.
    public static let cycleCountAtLastQmax = BatteryField<Int>(
        key: "CycleCountLastQmax",
        locations: [
            FieldLocation(.battery, ["BatteryData", "LifetimeData", "CycleCountLastQmax"]),
            FieldLocation(.pack, ["BatteryData", "LifetimeData", "CycleCountLastQmax"]),
        ],
        searchAnywhere: true
    ) { raw, _ in
        BatteryFieldMap.plausibleCount(raw, upTo: 10_000)
    }

    /// The keys of every mapped field. The Mac reader cannot list a node's
    /// properties (the bulk read can crash, WhatCable #181), so it reads each of
    /// these by name at the node's top level, where a search could find them.
    public static var topLevelKeys: [String] {
        [cycleCountAtLastQmax.key]
    }

    static func plausibleCount(_ raw: Any, upTo limit: Int) -> Int? {
        guard let n = (raw as? NSNumber)?.intValue, n > 0, n <= limit else { return nil }
        return n
    }
}

/// One line of the `--fields` diagnostic.
public struct FieldReportRow: Equatable, Sendable {
    public let key: String
    public let value: String?
    public let location: String?
    public let foundBySearch: Bool

    public init(key: String, value: String?, location: String?, foundBySearch: Bool) {
        self.key = key
        self.value = value
        self.location = location
        self.foundBySearch = foundBySearch
    }
}

extension BatteryFieldMap {
    /// Every mapped field, resolved against one tree. A field added to the map
    /// must be added here too, or `--fields` will not show it.
    public static func report(_ tree: BatteryTree) -> [FieldReportRow] {
        [row(cycleCountAtLastQmax, in: tree)]
    }

    public static func render(_ rows: [FieldReportRow]) -> String {
        rows.map { row in
            guard let value = row.value, let location = row.location else {
                return "\(row.key)  not found"
            }
            let line = "\(row.key)  \(value)  \(location)"
            return row.foundBySearch ? line + "  (found by search, not a known location)" : line
        }
        .joined(separator: "\n")
    }

    private static func row<Value>(_ field: BatteryField<Value>, in tree: BatteryTree) -> FieldReportRow {
        let resolution = BatteryFieldResolver.resolve(field, in: tree)
        return FieldReportRow(
            key: field.key,
            value: resolution.value.map { "\($0)" },
            location: resolution.location?.description,
            foundBySearch: resolution.foundBySearch
        )
    }
}
