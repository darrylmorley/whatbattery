import SwiftUI
import Charts

/// The house style for every chart in the app.
///
/// Swift Charts' defaults draw a dashed vertical rule at every x label, which
/// on a dense time series turns into a picket fence competing with the data.
/// Horizontal rules are what a reader actually uses (to judge a level against
/// the axis), so those stay and the vertical ones go. Everything else here is
/// about letting the line be the darkest thing in the frame.
public struct AppChartStyle: ViewModifier {
    private let yValues: [Double]?

    public init(yValues: [Double]? = nil) {
        self.yValues = yValues
    }

    public func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks { _ in
                    AxisTick().foregroundStyle(Color(nsColor: .separatorColor))
                    AxisValueLabel().foregroundStyle(Self.axisLabel)
                }
            }
            .chartYAxis {
                if let yValues {
                    AxisMarks(position: .trailing, values: yValues) { _ in
                        AxisGridLine().foregroundStyle(Self.gridLine)
                        AxisValueLabel().foregroundStyle(Self.axisLabel)
                    }
                } else {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(Self.gridLine)
                        AxisValueLabel().foregroundStyle(Self.axisLabel)
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.background(Color.clear)
            }
    }

    private static let gridLine = Color(nsColor: .separatorColor).opacity(0.5)

    /// Explicitly grey, not `.secondary`. Inside a chart the semantic styles
    /// resolve against the plot's own foreground, so `.secondary` came out
    /// tinted and the axis started reading as another data series.
    private static let axisLabel = Color(nsColor: .secondaryLabelColor)
}

public extension View {
    /// Apply the shared chart axis treatment. Pass `yValues` to pin the
    /// horizontal rules to meaningful levels rather than whatever Charts picks.
    func appChartStyle(yValues: [Double]? = nil) -> some View {
        modifier(AppChartStyle(yValues: yValues))
    }
}

public extension Theme {
    /// The wash under a chart line: the series colour at the top, fading out
    /// before it reaches the axis. Gives the line something to sit on so a
    /// mostly-flat series still reads as a quantity rather than a rule, without
    /// the block of colour a solid fill would put behind the gridlines.
    /// Matches the treatment WhatPort uses, so the family looks related.
    ///
    /// **Any chart using this must guarantee its y-domain contains the area's
    /// baseline.** An `AreaMark` without an explicit `yStart` is drawn down to
    /// zero, and Charts does not clip that to the plot area: if the domain
    /// excludes zero (a temperature series sitting at 30, a power series that
    /// is entirely negative while discharging) the fill escapes the chart and
    /// paints over the rest of the view. Either include zero in the domain, or
    /// pass `yStart` pinned to the domain's lower bound.
    static func chartFill(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.28), color.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
