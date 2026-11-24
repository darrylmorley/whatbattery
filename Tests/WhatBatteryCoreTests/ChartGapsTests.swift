import XCTest
@testable import WhatBatteryCore

/// Where a chart's line may join two readings, and where it has to admit that
/// nothing was measured in between.
final class ChartGapsTests: XCTestCase {
    private struct Point: Equatable {
        let t: Double
        var date: Date { Date(timeIntervalSince1970: t) }
    }

    private func points(_ times: [Double]) -> [Point] { times.map(Point.init) }

    func testThresholdIsThreeSamplingIntervalsOnAShortSpan() {
        XCTAssertEqual(ChartGaps.breakThreshold(cadence: 300, span: 3600), 900)
    }

    func testThresholdGrowsWithTheSpanSoInvisibleGapsDoNotBreakTheLine() {
        // A week: one percent of the width is 6048 s, longer than 3 x 300 s.
        XCTAssertEqual(ChartGaps.breakThreshold(cadence: 300, span: 7 * 86_400), 6_048, accuracy: 0.001)
        // A year: an overnight sleep is far under one percent and stays joined.
        XCTAssertGreaterThan(ChartGaps.breakThreshold(cadence: 300, span: 365 * 86_400), 8 * 3600)
    }

    func testUnbrokenSeriesIsOneRunWithNoBridges() {
        let segments = ChartGaps.segments(points([0, 300, 600, 900]), maxGap: 900, timestamp: \.date)
        XCTAssertEqual(segments.runs, [points([0, 300, 600, 900])])
        XCTAssertTrue(segments.bridges.isEmpty)
    }

    func testAGapLongerThanTheThresholdSplitsAndIsBridgedByItsTwoEnds() {
        let segments = ChartGaps.segments(points([0, 300, 5000, 5300]), maxGap: 900, timestamp: \.date)
        XCTAssertEqual(segments.runs, [points([0, 300]), points([5000, 5300])])
        XCTAssertEqual(segments.bridges, [points([300, 5000])])
    }

    func testAGapExactlyAtTheThresholdStaysJoined() {
        let segments = ChartGaps.segments(points([0, 900]), maxGap: 900, timestamp: \.date)
        XCTAssertEqual(segments.runs.count, 1)
    }

    func testEmptyInputHasNothingToDraw() {
        let segments = ChartGaps.segments([Point](), maxGap: 900, timestamp: \.date)
        XCTAssertTrue(segments.runs.isEmpty)
        XCTAssertTrue(segments.bridges.isEmpty)
    }

    func testThinningKeepsEveryRunsEndsSoTheGapsStayWhereTheyWere() {
        // Two dense runs of 100 points either side of a long silence.
        let first = (0..<100).map { Double($0) * 300 }
        let second = (0..<100).map { 200_000 + Double($0) * 300 }
        let segments = ChartGaps.segments(points(first + second), maxGap: 900, maxPoints: 20, timestamp: \.date)

        XCTAssertEqual(segments.runs.count, 2)
        XCTAssertEqual(segments.runs[0].first?.t, first.first)
        XCTAssertEqual(segments.runs[0].last?.t, first.last)
        XCTAssertEqual(segments.runs[1].first?.t, second.first)
        XCTAssertEqual(segments.runs[1].last?.t, second.last)
        XCTAssertEqual(segments.bridges, [points([first.last!, second.first!])])
        // Near the budget: thinned to the cap, plus at most one kept end per run.
        XCTAssertLessThanOrEqual(segments.runs.joined().count, 20 + 2)
    }

    func testMostlyContinuousWhenOneRunHoldsMostOfTheReadings() {
        // Nine of ten in one run: a missed sample or two keeps the fill.
        let mostly = ChartGaps.segments(points([0, 300, 600, 900, 1200, 1500, 1800, 2100, 2400, 90_000]), maxGap: 900, timestamp: \.date)
        XCTAssertTrue(mostly.isMostlyContinuous)
    }

    func testNotMostlyContinuousWhenTheReadingsAreScatteredAcrossRuns() {
        // Short runs each filled to the floor read as a bar chart.
        let scattered = ChartGaps.segments(points([0, 300, 10_000, 10_300, 20_000, 20_300]), maxGap: 900, timestamp: \.date)
        XCTAssertFalse(scattered.isMostlyContinuous)
    }

    func testThinningHonoursTheBudgetAcrossManyRuns() {
        // 80 runs of 30 readings: every run keeps both ends, so a step sized
        // from the total alone overshoots the cap. 2,400 points, cap 400.
        let times = (0..<80).flatMap { run in (0..<30).map { Double(run) * 100_000 + Double($0) * 300 } }
        let segments = ChartGaps.segments(points(times), maxGap: 900, maxPoints: 400, timestamp: \.date)
        XCTAssertEqual(segments.runs.count, 80)
        XCTAssertLessThanOrEqual(segments.runs.joined().count, 400)
        for (index, run) in segments.runs.enumerated() {
            XCTAssertEqual(run.first?.t, Double(index) * 100_000)
            XCTAssertEqual(run.last?.t, Double(index) * 100_000 + 29 * 300)
        }
    }

    func testMoreRunsThanTheBudgetCanHoldKeepsOnlyEachRunsEnds() {
        // 250 runs cannot fit 400 points at two ends each. The cap is soft:
        // it must stop, at exactly the ends, rather than drop a run's edge.
        let times = (0..<250).flatMap { run in (0..<10).map { Double(run) * 100_000 + Double($0) * 300 } }
        let segments = ChartGaps.segments(points(times), maxGap: 900, maxPoints: 400, timestamp: \.date)
        XCTAssertEqual(segments.runs.count, 250)
        XCTAssertEqual(segments.runs.joined().count, 500)
        for (index, run) in segments.runs.enumerated() {
            XCTAssertEqual(run.map(\.t), [Double(index) * 100_000, Double(index) * 100_000 + 9 * 300])
        }
    }

    func testThinningLeavesASmallSeriesAlone() {
        let segments = ChartGaps.segments(points([0, 300, 600]), maxGap: 900, maxPoints: 400, timestamp: \.date)
        XCTAssertEqual(segments.runs, [points([0, 300, 600])])
    }
}
