import SwiftUI
import Charts
import WhatBatteryCore

/// One line on a chart, drawn honestly across the gaps in its data: each
/// measured run solid (and optionally filled), each silence between runs a
/// faded dashed line between the two readings that border it, with no fill.
///
/// Every history chart draws its lines through this, so a gap looks the same
/// on every tab. Split the data with `ChartGaps.segments` first.
///
/// Each run and each bridge carries its own `series` value, because Charts
/// decides what to join from series identity, not from the loop that emitted
/// the marks. Distinct string values under one label: different labels with
/// equal values can be read as the same series and joined back together,
/// undoing the split (found on the iPhone/iPad chart).
public struct GappedSeries<Point>: ChartContent {
    public enum Style {
        /// A fixed colour.
        case colour(Color)
        /// A category for `foregroundStyle(by:)`, so the chart's own colour
        /// scale and legend apply (one line per accessory cell, say).
        case category(String)
    }

    private let segments: ChartSegments<Point>
    private let id: String
    private let style: Style
    private let fillFrom: Double?
    private let markLoneReadings: Bool
    private let yLabel: String
    private let x: (Point) -> Date
    private let y: (Point) -> Double

    /// - Parameters:
    ///   - id: Unique per line on the chart; it prefixes the series names.
    ///   - fillFrom: Fill each run down to this value (the axis floor), or nil
    ///     for no fill. Explicit because an area defaulting to zero on an axis
    ///     that starts at 94 is drawn outside the plot and not clipped.
    ///   - markLoneReadings: Dot a run of one reading, which a line cannot draw.
    ///   - yLabel: What the value is ("Charge"), which VoiceOver reads out.
    public init(
        _ segments: ChartSegments<Point>,
        id: String,
        style: Style,
        fillFrom: Double? = nil,
        markLoneReadings: Bool = true,
        yLabel: String = "Value",
        x: @escaping (Point) -> Date,
        y: @escaping (Point) -> Double
    ) {
        self.segments = segments
        self.id = id
        self.style = style
        self.fillFrom = fillFrom
        self.markLoneReadings = markLoneReadings
        self.yLabel = yLabel
        self.x = x
        self.y = y
    }

    public var body: some ChartContent {
        ForEach(Array(segments.runs.enumerated()), id: \.offset) { index, run in
            ForEach(Array(run.enumerated()), id: \.offset) { _, point in
                if let fillFrom, run.count > 1 {
                    styled(
                        AreaMark(
                            x: .value("Time", x(point)),
                            yStart: .value(yLabel, fillFrom),
                            yEnd: .value(yLabel, y(point)),
                            series: .value("Series", "\(id)-run-\(index)")
                        ),
                        fill: true
                    )
                }
                styled(
                    LineMark(
                        x: .value("Time", x(point)),
                        y: .value(yLabel, y(point)),
                        series: .value("Series", "\(id)-run-\(index)")
                    ),
                    fill: false
                )
                if markLoneReadings, run.count == 1 {
                    styled(
                        PointMark(
                            x: .value("Time", x(point)),
                            y: .value(yLabel, y(point))
                        )
                        .symbolSize(10),
                        fill: false
                    )
                }
            }
        }
        ForEach(Array(segments.bridges.enumerated()), id: \.offset) { index, pair in
            ForEach(Array(pair.enumerated()), id: \.offset) { _, point in
                styled(
                    LineMark(
                        x: .value("Time", x(point)),
                        y: .value(yLabel, y(point)),
                        series: .value("Series", "\(id)-gap-\(index)")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])),
                    fill: false
                )
                .opacity(0.35)
            }
        }
    }

    @ChartContentBuilder
    private func styled<Mark: ChartContent>(_ mark: Mark, fill: Bool) -> some ChartContent {
        switch style {
        case .colour(let colour):
            if fill {
                mark.foregroundStyle(Theme.chartFill(colour))
            } else {
                mark.foregroundStyle(colour)
            }
        case .category(let name):
            // A category colour is solid; faded so a filled run reads as a
            // band under the line rather than a block over the plot.
            mark.foregroundStyle(by: .value("Category", name))
                .opacity(fill ? 0.15 : 1)
        }
    }
}
