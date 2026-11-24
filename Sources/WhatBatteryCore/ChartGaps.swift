import Foundation

/// A series split into the runs that were measured and the silences between
/// them, ready to draw: each run solid, each bridge (the two readings either
/// side of a silence) faded and dashed.
public struct ChartSegments<Point> {
    public let runs: [[Point]]
    public let bridges: [[Point]]

    public static var empty: ChartSegments { ChartSegments(runs: [], bridges: []) }

    public var isEmpty: Bool { runs.isEmpty }

    /// Whether enough of the data sits in one unbroken run for a filled area to
    /// describe a measured band, rather than a row of columns each filled down
    /// to the axis floor, which reads as a bar chart where the value dropped to
    /// zero in between.
    ///
    /// Judged on the longest run's share, not on whether any gap exists: "no
    /// gaps" was too brittle, and a cabled iPad that missed two polls in ten
    /// minutes lost its fill entirely (found on the iPhone/iPad chart, where
    /// this rule started).
    public var isMostlyContinuous: Bool {
        let total = runs.reduce(0) { $0 + $1.count }
        guard let longest = runs.map(\.count).max(), total > 1 else { return true }
        return Double(longest) >= 0.8 * Double(total)
    }
}

extension ChartSegments: Sendable where Point: Sendable {}

/// Where a chart's line may join two readings.
///
/// Swift Charts joins consecutive points with a straight line, so two readings
/// either side of three weeks with the app closed were drawn as a steady climb
/// that never happened. Every history chart goes through here so they all break
/// in the same places and draw the break the same way, the way the iPhone/iPad
/// live chart already did.
public enum ChartGaps {
    /// The longest gap still drawn as a joined line.
    ///
    /// Two limits, the larger wins. Three sampling intervals, so one or two
    /// missed samples do not break the line. And one percent of the span being
    /// drawn, so a gap too narrow to see does not either: in a Year view an
    /// overnight sleep is a fraction of a pixel, and breaking there would shatter
    /// the line into hundreds of pieces that all look like one.
    public static func breakThreshold(cadence: TimeInterval, span: TimeInterval) -> TimeInterval {
        max(3 * cadence, span / 100)
    }

    /// Splits `points` (oldest first) at every gap longer than `maxGap`, then
    /// thins it to roughly `maxPoints` if it is larger.
    ///
    /// Split first, thin second. Thinning first picked every nth point across
    /// the whole series, which moved where a run appeared to end, and could
    /// swallow a short run outright. Each run keeps its first and last reading,
    /// so the bridges sit exactly on the real edges of the silence.
    public static func segments<Point>(
        _ points: [Point],
        maxGap: TimeInterval,
        maxPoints: Int? = nil,
        timestamp: (Point) -> Date
    ) -> ChartSegments<Point> {
        var runs = contiguousRuns(points, maxGap: maxGap, timestamp: timestamp)
        if let maxPoints, maxPoints > 0, points.count > maxPoints {
            // Every run keeps both ends, so a step sized from the total alone
            // overshoots with many runs. Size it from the interior points left
            // once the ends are paid for, then widen as a safety net. A soft
            // cap: more runs than half the budget can only ever come down to
            // their ends. The span-based threshold keeps real charts near a
            // hundred runs, well inside it.
            let ends = runs.reduce(0) { $0 + min($1.count, 2) }
            let interior = points.count - ends
            let room = max(maxPoints - ends, 1)
            var step = max(1, Int((Double(interior) / Double(room)).rounded(.up)))
            var thinned = runs.map { thin($0, step: step) }
            while thinned.reduce(0, { $0 + $1.count }) > maxPoints,
                  thinned.contains(where: { $0.count > 2 }) {
                step += max(1, step / 4)
                thinned = runs.map { thin($0, step: step) }
            }
            runs = thinned
        }
        let bridges: [[Point]] = zip(runs, runs.dropFirst()).compactMap { earlier, later in
            guard let last = earlier.last, let first = later.first else { return nil }
            return [last, first]
        }
        return ChartSegments(runs: runs, bridges: bridges)
    }

    /// Splits a series (oldest first) into runs of consecutive points, breaking
    /// wherever the gap between two points exceeds `maxGap`.
    ///
    /// Swift Charts joins consecutive points with a straight line, so two real
    /// readings either side of a silence are drawn as a smooth climb that never
    /// happened. Keeping the data honest is not enough: the drawing has to
    /// break too.
    public static func contiguousRuns<Point>(
        _ points: [Point],
        maxGap: TimeInterval,
        timestamp: (Point) -> Date
    ) -> [[Point]] {
        var runs: [[Point]] = []
        var current: [Point] = []
        for point in points {
            if let last = current.last, timestamp(point).timeIntervalSince(timestamp(last)) > maxGap {
                runs.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    private static func thin<Point>(_ run: [Point], step: Int) -> [Point] {
        guard step > 1, run.count > 2 else { return run }
        var kept = run.enumerated().compactMap { index, point in index % step == 0 ? point : nil }
        if (run.count - 1) % step != 0, let last = run.last { kept.append(last) }
        return kept
    }
}
