import Foundation

/// One device's health for a single calendar month, rolled up from its records:
/// average health and the latest cycle count / capacity, the same columns
/// coconutBattery's History tab shows ("2026-06 | ø 97% | 42 cycles").
public struct MonthlyHealthSummary: Equatable, Sendable, Identifiable {
    public let year: Int
    public let month: Int             // 1...12

    /// Mean of the non-nil health readings in the month; nil if none reported.
    public let avgHealthPercent: Double?
    /// Cycle count is monotonic, so the latest record's value is the month's.
    public let latestCycleCount: Int
    /// Full-charge capacity from the latest record in the month.
    public let latestFullChargemAh: Int
    public let recordCount: Int

    /// "YYYY-MM", zero-padded and locale-independent.
    public var label: String { String(format: "%04d-%02d", year, month) }
    public var id: String { label }

    public init(
        year: Int,
        month: Int,
        avgHealthPercent: Double?,
        latestCycleCount: Int,
        latestFullChargemAh: Int,
        recordCount: Int
    ) {
        self.year = year
        self.month = month
        self.avgHealthPercent = avgHealthPercent
        self.latestCycleCount = latestCycleCount
        self.latestFullChargemAh = latestFullChargemAh
        self.recordCount = recordCount
    }

    /// Roll a single device's records up into one summary per calendar month,
    /// newest month first. The calendar is injectable so grouping is deterministic
    /// in tests (the default groups in the user's local time, as coconutBattery
    /// does). Records from multiple devices should be grouped with
    /// `DeviceHealthHistory.group(_:)` first.
    public static func compute(from records: [HealthRecord], calendar: Calendar = .autoupdatingCurrent) -> [MonthlyHealthSummary] {
        guard !records.isEmpty else { return [] }

        var buckets: [String: [HealthRecord]] = [:]
        for record in records {
            let parts = calendar.dateComponents([.year, .month], from: record.date)
            guard let year = parts.year, let month = parts.month else { continue }
            buckets[String(format: "%04d-%02d", year, month), default: []].append(record)
        }

        return buckets.values.map { monthRecords in
            let sorted = monthRecords.sorted { $0.date < $1.date }
            let latest = sorted.last!
            let parts = calendar.dateComponents([.year, .month], from: latest.date)
            let healths = monthRecords.compactMap(\.healthPercent)
            let avg = healths.isEmpty ? nil : healths.reduce(0, +) / Double(healths.count)
            return MonthlyHealthSummary(
                year: parts.year ?? 0,
                month: parts.month ?? 0,
                avgHealthPercent: avg,
                latestCycleCount: latest.cycleCount,
                latestFullChargemAh: latest.fullChargeCapacitymAh,
                recordCount: monthRecords.count
            )
        }
        .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }
}

/// All of one physical device's health history: its identity (taken from the most
/// recent record, so a renamed device or OS upgrade shows current values) and its
/// monthly summaries. The History view renders one of these per device.
public struct DeviceHealthHistory: Equatable, Sendable, Identifiable {
    public let deviceID: String
    public let kind: DeviceKind
    public let model: String
    public let name: String
    public let osVersion: String
    public let serial: String
    public let latest: HealthRecord
    public let months: [MonthlyHealthSummary]

    public var id: String { deviceID }

    public init(
        deviceID: String,
        kind: DeviceKind,
        model: String,
        name: String,
        osVersion: String,
        serial: String = "",
        latest: HealthRecord,
        months: [MonthlyHealthSummary]
    ) {
        self.deviceID = deviceID
        self.kind = kind
        self.model = model
        self.name = name
        self.osVersion = osVersion
        self.serial = serial
        self.latest = latest
        self.months = months
    }

    /// Split a mixed set of records by device, newest-active device first within
    /// each kind (Macs before iDevices). Each device's identity comes from its
    /// most recent record.
    public static func group(_ records: [HealthRecord], calendar: Calendar = .autoupdatingCurrent) -> [DeviceHealthHistory] {
        guard !records.isEmpty else { return [] }

        var byDevice: [String: [HealthRecord]] = [:]
        for record in records {
            byDevice[record.deviceID, default: []].append(record)
        }

        return byDevice.values.map { deviceRecords -> DeviceHealthHistory in
            let latest = deviceRecords.max { $0.date < $1.date }!
            return DeviceHealthHistory(
                deviceID: latest.deviceID,
                kind: latest.kind,
                model: latest.model,
                name: latest.name,
                osVersion: latest.osVersion,
                serial: latest.serial,
                latest: latest,
                months: MonthlyHealthSummary.compute(from: deviceRecords, calendar: calendar)
            )
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                // Macs first, then iDevices.
                return lhs.kind == .mac
            }
            if lhs.latest.date != rhs.latest.date {
                return lhs.latest.date > rhs.latest.date   // most recently seen first
            }
            return lhs.name < rhs.name
        }
    }
}
