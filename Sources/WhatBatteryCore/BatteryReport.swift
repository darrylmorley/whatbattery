import Foundation

/// A one-page device report: the current battery state plus the lifetime summary,
/// assembled from a live `BatterySnapshot` and an optional `LifetimeSummary`.
/// Pure and testable; the Pro PDF/print view renders from the same struct so the
/// on-page layout and the CLI's plain text stay in sync.
public struct BatteryReport: Equatable, Sendable {
    /// One labelled line in a report section.
    public struct Line: Equatable, Sendable {
        public let label: String
        public let value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public let title: String
    public let generatedAt: Date
    public let appVersion: String
    public let deviceModel: String
    /// The device serial shown in the header (the Mac's hardware serial). Empty
    /// when unavailable.
    public let serial: String

    /// Current state rows (health, charge, cycles, temperature, power, voltage).
    public let currentLines: [Line]
    /// Lifetime rows (ranges and peaks), empty when there is no history yet.
    public let lifetimeLines: [Line]

    public init(
        title: String,
        generatedAt: Date,
        appVersion: String,
        deviceModel: String,
        serial: String = "",
        currentLines: [Line],
        lifetimeLines: [Line]
    ) {
        self.title = title
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.serial = serial
        self.currentLines = currentLines
        self.lifetimeLines = lifetimeLines
    }

    /// Build a report from the current snapshot and (when available) the lifetime
    /// summary computed from logged history. `deviceName` (the marketing model
    /// name) and `serial` (the device serial) enrich the header when known.
    public static func make(
        snapshot: BatterySnapshot,
        summary: LifetimeSummary?,
        generatedAt: Date,
        appVersion: String,
        deviceName: String? = nil,
        serial: String = ""
    ) -> BatteryReport {
        let model = deviceName.flatMap { $0.isEmpty ? nil : $0 } ?? snapshot.deviceModel
        return BatteryReport(
            title: "Battery Report",
            generatedAt: generatedAt,
            appVersion: appVersion,
            deviceModel: model,
            serial: serial,
            currentLines: buildCurrentLines(from: snapshot),
            lifetimeLines: buildLifetimeLines(from: summary)
        )
    }

    private static func buildCurrentLines(from snapshot: BatterySnapshot) -> [Line] {
        var lines: [Line] = [
            Line(label: "Health", value: BatteryFormatter.health(snapshot)),
            Line(label: "Charge", value: BatteryFormatter.chargeLine(snapshot)),
            Line(label: "Cycles", value: cyclesValue(snapshot)),
            Line(label: "Temperature", value: BatteryFormatter.temperature(snapshot.temperatureCelsius)),
            Line(label: "Power", value: powerValue(snapshot)),
            Line(label: "Voltage", value: BatteryFormatter.voltage(snapshot.voltageMillivolts)),
        ]
        if let serial = snapshot.batterySerial {
            lines.append(Line(label: "Battery Serial", value: serial))
        }
        return lines
    }

    private static func cyclesValue(_ snapshot: BatterySnapshot) -> String {
        snapshot.designCycleCount > 0
            ? "\(snapshot.cycleCount) (design \(snapshot.designCycleCount))"
            : "\(snapshot.cycleCount)"
    }

    private static func powerValue(_ snapshot: BatterySnapshot) -> String {
        var text = BatteryFormatter.power(snapshot.powerWatts)
        if let adapter = snapshot.adapter?.label { text += " (\(adapter))" }
        return text
    }

    private static func buildLifetimeLines(from summary: LifetimeSummary?) -> [Line] {
        guard let summary, summary.sampleCount > 0 else { return [] }
        var lines: [Line] = []
        if let lo = summary.minTemperatureC, let avg = summary.avgTemperatureC, let hi = summary.maxTemperatureC {
            lines.append(Line(label: "Temperature", value: String(format: "%.1f / %.1f / %.1f C (min/avg/max)", lo, avg, hi)))
        }
        if let lo = summary.minVoltageMV, let hi = summary.maxVoltageMV {
            lines.append(Line(label: "Voltage", value: String(format: "%.2f to %.2f V", Double(lo) / 1000, Double(hi) / 1000)))
        }
        if let peak = summary.maxChargeW {
            lines.append(Line(label: "Peak charge", value: String(format: "%.1f W", peak)))
        }
        if let peak = summary.maxDischargeW {
            lines.append(Line(label: "Peak discharge", value: String(format: "%.1f W", peak)))
        }
        lines.append(Line(label: "Readings", value: "\(summary.sampleCount) over \(spanText(summary))"))
        return lines
    }

    private static func spanText(_ summary: LifetimeSummary) -> String {
        guard let span = summary.monitoredSpan, span > 0 else { return "this session" }
        let days = Int((span / 86_400).rounded())
        if days >= 1 { return "\(days) day\(days == 1 ? "" : "s")" }
        let hours = Int((span / 3_600).rounded())
        if hours >= 1 { return "\(hours) hour\(hours == 1 ? "" : "s")" }
        return "less than 1 hour"
    }

    /// A plain-text rendering for the CLI `--report`.
    public var plainText: String {
        var out: [String] = []
        out.append(title)
        out.append(String(repeating: "=", count: title.count))
        out.append("")
        out.append("Model:      \(deviceModel)")
        if !serial.isEmpty {
            out.append("Serial:     \(serial)")
        }
        out.append("Generated:  \(Self.stamp.string(from: generatedAt))")
        out.append("WhatBattery \(appVersion)")
        out.append("")
        out.append("Current")
        out.append("-------")
        for line in currentLines {
            out.append(pad(line.label) + line.value)
        }
        if !lifetimeLines.isEmpty {
            out.append("")
            out.append("Lifetime")
            out.append("--------")
            for line in lifetimeLines {
                out.append(pad(line.label) + line.value)
            }
        }
        return out.joined(separator: "\n")
    }

    private func pad(_ label: String) -> String {
        (label + ":").padding(toLength: 14, withPad: " ", startingAt: 0)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
