import Foundation

/// Serializes logged history samples to the two export formats: CSV (one row per
/// sample, columns matching the SQLite `samples` schema) and JSON (an array of
/// `BatterySample`). Pure and locale-independent so a comma-decimal locale can
/// never corrupt a CSV; the Pro export UI and CLI both call into here.
public enum HistoryExport {
    /// CSV column order, matching the history store's schema. Kept as a constant
    /// so the header and the per-row writer can never drift apart.
    static let csvHeader = "timestamp,charge_pct,temp_c,voltage_mv,power_w,cycle_count,health_pct"

    /// A fixed, locale-independent ISO 8601 formatter (the JSON encoder uses the
    /// same `.iso8601` strategy), so both formats stamp timestamps identically.
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// CSV text: a header line followed by one line per sample, oldest first.
    /// An empty sample set returns the header alone (a valid, if empty, file).
    public static func csv(_ samples: [BatterySample]) -> String {
        var lines = [csvHeader]
        for sample in samples {
            lines.append(csvRow(sample))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvRow(_ sample: BatterySample) -> String {
        // Doubles are forced to a `.` decimal regardless of locale so the commas
        // stay column separators. Health is blank when not reported.
        let fields: [String] = [
            isoFormatter.string(from: sample.timestamp),
            String(sample.chargePercent),
            decimal(sample.temperatureCelsius),
            String(sample.voltageMillivolts),
            decimal(sample.powerWatts),
            String(sample.cycleCount),
            sample.healthPercent.map(decimal) ?? "",
        ]
        return fields.joined(separator: ",")
    }

    /// A fixed-point string with a `.` decimal, independent of the current locale.
    /// The POSIX locale is passed explicitly so the decimal separator stays a `.`
    /// even on a system whose locale uses a comma.
    private static let posix = Locale(identifier: "en_US_POSIX")
    private static func decimal(_ value: Double) -> String {
        String(format: "%.3f", locale: posix, value)
    }

    /// JSON: a pretty-printed array of `BatterySample` with ISO 8601 dates and
    /// sorted keys, matching the CLI's `--json` snapshot output. Throws on an
    /// encode failure (rather than masking it as an empty file) so the caller can
    /// report it instead of writing a silently-empty export.
    public static func json(_ samples: [BatterySample]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(samples)
    }
}
