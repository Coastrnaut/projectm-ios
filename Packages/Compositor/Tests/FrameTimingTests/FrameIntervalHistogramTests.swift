// FrameIntervalHistogramTests.swift — PERF-012-T04 (specs/209-perf-012-performance-report): percentile maths of the
// frame interval histogram against exact nearest-rank values, and the feed from FrameDropCounter.submit (injected
// display-link times; no wall clock).
import FrameTiming
import XCTest

final class FrameIntervalHistogramTests: XCTestCase {
    /// Exact nearest-rank percentile of `values` (ms).
    private func nearestRank(_ values: [Double], _ p: Double) -> Double {
        let sorted: [Double] = values.sorted()
        let rank: Int = max(1, Int((p * Double(sorted.count)).rounded(.up)))
        return sorted[rank - 1]
    }

    private func histogram(_ ms: [Double]) -> FrameIntervalHistogram {
        var h = FrameIntervalHistogram()
        for value in ms { h.record(seconds: value / 1_000) }
        return h
    }

    func testEmptyHasNoPercentiles() {
        let h = FrameIntervalHistogram()
        XCTAssertEqual(h.count, 0)
        XCTAssertNil(h.percentile(0.5))
        XCTAssertNil(h.percentile(0.99))
        XCTAssertEqual(h.maxMs, 0)
    }

    /// 100 known intervals: 90 at 16.67 ms, 8 at 33.3 ms, 1 at 50.2 ms, 1 at 120.04 ms.
    func testKnownSetWithinOneResolutionStepAndExactMax() throws {
        var values: [Double] = [Double](repeating: 16.67, count: 90)
        values += [Double](repeating: 33.3, count: 8)
        values += [50.2, 120.04]
        let h = histogram(values.shuffled())
        XCTAssertEqual(h.count, 100)
        for p in [0.5, 0.9, 0.95, 0.99] {
            let exact: Double = nearestRank(values, p)
            let reported: Double = try XCTUnwrap(h.percentile(p))
            XCTAssertGreaterThanOrEqual(reported, exact - 1e-9, "p\(p) never optimistic")
            XCTAssertLessThanOrEqual(reported - exact, FrameIntervalHistogram.resolutionMs + 1e-9, "p\(p) within one step")
        }
        XCTAssertEqual(h.percentile(1.0), 120.04)
        XCTAssertEqual(h.maxMs, 120.04, accuracy: 1e-9)
        XCTAssertEqual(h.longFrames, [10, 2, 1])   // ≥ 25, ≥ 50, ≥ 100 ms
        XCTAssertEqual(h.measuredSeconds, values.reduce(0, +) / 1_000, accuracy: 1e-9)
    }

    /// A single interval: every percentile is that interval (capped by the exact max, not the bucket edge).
    func testSingleSampleIsExact() {
        let h = histogram([8.33])
        XCTAssertEqual(h.percentile(0.5), 8.33)
        XCTAssertEqual(h.percentile(0.99), 8.33)
    }

    /// Intervals past 250 ms land in the last bucket and report the exact maximum.
    func testOverflowBucketReportsExactMax() {
        let h = histogram([10, 400, 900.5])
        XCTAssertEqual(h.percentile(0.99), 900.5)
        XCTAssertEqual(h.percentile(0.6), 900.5)
        XCTAssertEqual(h.buckets.last, 2)
    }

    func testNonFiniteAndNonPositiveAreIgnored() {
        var h = FrameIntervalHistogram()
        h.record(seconds: .nan)
        h.record(seconds: .infinity)
        h.record(seconds: 0)
        h.record(seconds: -0.016)
        XCTAssertEqual(h.count, 0)
    }

    /// The counter feeds the recorder with the interval since the previous accepted submit: not the first frame of a
    /// session, not a duplicate timestamp; a new session does not reset the recorder.
    func testCounterFeedsTheRecorder() throws {
        let recorder = FrameIntervalRecorder()
        let counter = FrameDropCounter(intervals: recorder)
        let session: FrameDropSession = counter.beginSession(measuresPresentation: false)
        let period: Double = 1.0 / 60
        _ = counter.submit(session, timestamp: 100, targetTimestamp: 100 + period)
        _ = counter.submit(session, timestamp: 100 + period, targetTimestamp: 100 + 2 * period)
        _ = counter.submit(session, timestamp: 100 + period, targetTimestamp: 100 + 2 * period)   // duplicate
        _ = counter.submit(session, timestamp: 100 + 3 * period, targetTimestamp: 100 + 4 * period)   // one slot missed
        var h: FrameIntervalHistogram = recorder.snapshot()
        XCTAssertEqual(h.count, 2)
        XCTAssertEqual(h.maxMs, 2 * period * 1_000, accuracy: 1e-6)
        let next: FrameDropSession = counter.beginSession(measuresPresentation: false)
        _ = counter.submit(next, timestamp: 200, targetTimestamp: 200 + period)   // first of the new session
        _ = counter.submit(next, timestamp: 200 + period, targetTimestamp: 200 + 2 * period)
        h = recorder.snapshot()
        XCTAssertEqual(h.count, 3, "kept across counting sessions")
        XCTAssertEqual(try XCTUnwrap(h.percentile(0.5)), period * 1_000, accuracy: FrameIntervalHistogram.resolutionMs)
    }

    /// Without a recorder the counter behaves exactly as before.
    func testCounterWithoutRecorder() {
        let counter = FrameDropCounter()
        let session: FrameDropSession = counter.beginSession(measuresPresentation: false)
        _ = counter.submit(session, timestamp: 1, targetTimestamp: 1.016)
        _ = counter.submit(session, timestamp: 1.016, targetTimestamp: 1.032)
        XCTAssertEqual(counter.counts().submitted, 2)
    }
}
