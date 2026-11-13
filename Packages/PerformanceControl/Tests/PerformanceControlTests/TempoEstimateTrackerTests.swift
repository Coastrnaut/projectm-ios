// TempoEstimateTrackerTests.swift — ANL-016 frames and beat events become tempo estimates
// (SHOW-011-R9, R14; research SHOW-011-D4; task SHOW-011-T05). Items are built by hand.
import AnalysisFeatures
import AudioCore
import PerformanceControl
import PerformanceControlAnalysis
import XCTest

final class TempoEstimateTrackerTests: XCTestCase {
    private let rate = 44_100.0

    private func time(_ sessionSample: Int64, host: UInt64) -> AnalysisTimestamp {
        AnalysisTimestamp(session: 1, sessionSample: sessionSample, timelineSample: sessionSample, hostNanoseconds: host)
    }

    private func frame(bpm: Double?, confidence: Double, id: UInt64 = 1) -> AnalysisFrame {
        AnalysisFrame(id: id, time: time(44_100, host: 2_000_000_000), bandCount: 16, onsetFlux: 0, bpm: bpm,
                      beatConfidence: confidence)
    }

    func testFramesGiveTempoWithoutPhase() throws {
        var tracker = TempoEstimateTracker(sampleRate: rate)
        XCTAssertNil(tracker.estimate)
        tracker.observe(frame(bpm: 120, confidence: 0.8))
        let estimate = try XCTUnwrap(tracker.estimate)
        XCTAssertEqual(estimate, TempoEstimate(bpm: 120, confidence: 0.8, beatNanoseconds: nil))
    }

    func testBeatEventSetsTheBeatHostTime() throws {
        var tracker = TempoEstimateTracker(sampleRate: rate)
        tracker.observe(frame(bpm: 120, confidence: 0.9))
        // Known at session sample 88,200 (host 3 s); the beat itself was at 66,150: 0.5 s earlier.
        tracker.observe(AnalysisEvent(id: 2, time: time(88_200, host: 3_000_000_000), eventSample: 66_150,
                                      kind: .beat(bpm: 120, periodSamples: 22_050, confidence: 0.9)))
        XCTAssertEqual(try XCTUnwrap(tracker.estimate).beatNanoseconds, 2_500_000_000)
    }

    func testNoTempoFrameClearsTheEstimate() {
        var tracker = TempoEstimateTracker(sampleRate: rate)
        tracker.observe(frame(bpm: 120, confidence: 0.9))
        tracker.observe(frame(bpm: nil, confidence: 0, id: 2))
        XCTAssertNil(tracker.estimate)
    }

    func testSessionMarkersAndClearResetTheEstimate() {
        for kind in [AnalysisEventKind.sessionStarted(.sourceRestarted), .sessionEnded(.detached)] {
            var tracker = TempoEstimateTracker(sampleRate: rate)
            tracker.observe(frame(bpm: 120, confidence: 0.9))
            tracker.observe(AnalysisEvent(id: 3, time: time(0, host: 1), eventSample: 0, kind: kind))
            XCTAssertNil(tracker.estimate, "\(kind)")
        }
        var tracker = TempoEstimateTracker(sampleRate: rate)
        tracker.observe(frame(bpm: 120, confidence: 0.9))
        tracker.clear()
        XCTAssertNil(tracker.estimate)
    }

    func testOnsetEventsChangeNothing() {
        var tracker = TempoEstimateTracker(sampleRate: rate)
        tracker.observe(frame(bpm: 120, confidence: 0.9))
        let before = tracker.estimate
        tracker.observe(AnalysisEvent(id: 4, time: time(100, host: 5), eventSample: 90, kind: .onset(strength: 1, threshold: 0.5)))
        XCTAssertEqual(tracker.estimate, before)
    }

    func testAnalyzerStartsAndStopsIdempotently() throws {
        // The analyzer's own pipeline (projectM case): stop clears the estimate (SHOW-011-R14).
        let analyzer = try TempoAnalyzer()
        XCTAssertFalse(analyzer.isRunning)
        analyzer.stop()
        XCTAssertNil(analyzer.reader.poll())
        let ring = try XCTUnwrap(NormalizedPCMRing(analysisTapCapacityFrames: 4_096).analysisTap)   // empty tap
        analyzer.start(reader: ring)
        analyzer.start(reader: ring)
        XCTAssertTrue(analyzer.isRunning)
        analyzer.stop()
        analyzer.stop()
        XCTAssertFalse(analyzer.isRunning)
        XCTAssertNil(analyzer.reader.poll())
    }
}
