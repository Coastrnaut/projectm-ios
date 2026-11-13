// BeatTrackerTests.swift — ANL-005-T05, T12: the beat tracker on exact onset lists (no audio), for
// every backend in this build. Covers ANL-005-R1 to R11, R15 and S4 (random onsets).
import XCTest
@testable import AnalysisFeatures

final class BeatTrackerTests: XCTestCase {
    private let rate = 44_100
    private func train(period: Double, count: Int, skipping: Set<Int> = []) -> [Int64] {
        (0..<count).filter { !skipping.contains($0) }.map { Int64((Double($0) * period).rounded()) }
    }

    func testSteadyTrainsLockToTheirTempoAndPredictTheNextBeat() throws {
        for backend in TestSupport.backends {
            let tracker = AdaptiveBeatTracker(backend: backend)
            let run = BeatTestSupport.track(onsets: train(period: 22_050, count: 20), end: 441_000, tracker: tracker)
            // No estimate before the 4th onset (66,150) has been added.
            for step in run.steps where step.position <= 66_150 { XCTAssertNil(step.estimate, "\(backend) \(step.position)") }
            let last = try XCTUnwrap(run.steps.last?.estimate)
            XCTAssertEqual(last.bpm, 120, accuracy: 0.01, "\(backend)")
            XCTAssertEqual(last.periodSamples, 22_050, accuracy: 0.1)
            XCTAssertEqual(last.confidence, 1, accuracy: 1e-12)
            XCTAssertEqual(last.matchedBeats, 13)                   // onsets 7…19: the 6 s window, inclusive
            XCTAssertEqual(last.nextBeatSample, 441_000)
            XCTAssertGreaterThanOrEqual(last.nextBeatSample, last.position)
            XCTAssertEqual(last.anchorSample, 418_950, accuracy: 0.5)
            // Confidence reaches 1 once 8 beats are matched.
            let full = try XCTUnwrap(run.steps.first { ($0.estimate?.confidence ?? 0) >= 1 - 1e-12 })
            XCTAssertGreaterThan(full.position, 7 * 22_050)
            XCTAssertLessThanOrEqual(full.position, 7 * 22_050 + 512)

            // 132 BPM: a period that is not a whole number of samples.
            let fractional = BeatTestSupport.track(onsets: train(period: 44_100 * 60 / 132.0, count: 22), end: 441_000,
                                                   tracker: AdaptiveBeatTracker(backend: backend))
            XCTAssertEqual(try XCTUnwrap(fractional.steps.last?.estimate).bpm, 132, accuracy: 0.01, "\(backend)")
        }
    }

    func testTempoRangeEdgesAndOctaveFolding() throws {
        // 60 BPM is the range's lower edge and is kept, not doubled.
        let slow = BeatTestSupport.track(onsets: train(period: 44_100, count: 12), end: 12 * 44_100)
        XCTAssertEqual(try XCTUnwrap(slow.steps.last?.estimate).bpm, 60, accuracy: 0.01)
        // 240 BPM is above the range: reported one octave down.
        let fast = BeatTestSupport.track(onsets: train(period: 11_025, count: 40), end: 441_000)
        XCTAssertEqual(try XCTUnwrap(fast.steps.last?.estimate).bpm, 120, accuracy: 0.01)
        // A missing onset keeps the tempo and a high confidence (coverage 11/12 in the window).
        let gappy = BeatTestSupport.track(onsets: train(period: 22_050, count: 20, skipping: [14]), end: 441_000)
        let estimate = try XCTUnwrap(gappy.steps.last?.estimate)
        XCTAssertEqual(estimate.bpm, 120, accuracy: 0.01)
        XCTAssertGreaterThan(estimate.confidence, 0.8)
        XCTAssertLessThan(estimate.confidence, 1)
    }

    func testInvalidOnsetsAndPositionsAreIgnoredAndCounted() {
        let tracker = AdaptiveBeatTracker()
        tracker.add(onsetAt: 1_000)
        tracker.add(onsetAt: 1_000)        // not after the previous onset
        tracker.add(onsetAt: 500)          // earlier
        tracker.add(OnsetEvent(sequence: 1, sampleIndex: 2_000, frameIndex: 0, strength: 0.5, threshold: 0.1,
                               sampleRate: 48_000, timestampNanoseconds: 0))   // other rate
        XCTAssertEqual(tracker.acceptedOnsets, 1)
        XCTAssertEqual(tracker.ignoredOnsets, 3)
        XCTAssertNil(tracker.advance(to: 100))
        XCTAssertNil(tracker.advance(to: 50))
        XCTAssertEqual(tracker.ignoredPositions, 1)
        XCTAssertNil(tracker.estimate)
        XCTAssertEqual(tracker.confidence, 0)
    }

    func testEachBeatIsReportedOnceAndJumpsCountSkippedBeats() throws {
        let tracker = AdaptiveBeatTracker()
        let run = BeatTestSupport.track(onsets: train(period: 22_050, count: 20), end: 441_000, tracker: tracker)
        XCTAssertFalse(run.beats.isEmpty)
        XCTAssertEqual(run.beats.map(\.sequence), Array(1...UInt64(run.beats.count)))
        for (a, b) in zip(run.beats, run.beats.dropFirst()) { XCTAssertEqual(b.sampleIndex - a.sampleIndex, 22_050) }
        for beat in run.beats {
            XCTAssertEqual(beat.sampleIndex % 22_050, 0)
            XCTAssertEqual(beat.bpm, 120, accuracy: 0.01)
        }
        XCTAssertEqual(run.beats.last?.sampleIndex, 418_950)
        XCTAssertEqual(tracker.skippedBeats, 0)
        // Jump over 441,000, 463,050 and 485,100: one event for the latest, two skipped.
        let jump = try XCTUnwrap(tracker.advance(to: 485_200))
        XCTAssertEqual(jump.sampleIndex, 485_100)
        XCTAssertEqual(jump.sequence, UInt64(run.beats.count + 1))
        XCTAssertEqual(tracker.skippedBeats, 2)
        XCTAssertEqual(tracker.beatCount, UInt64(run.beats.count + 1))
    }

    func testSilenceDecaysToNoTempoAndResetKeepsTheSequence() throws {
        let tracker = AdaptiveBeatTracker()
        let lastOnset: Int64 = 418_950
        let run = BeatTestSupport.track(onsets: train(period: 22_050, count: 20), end: lastOnset + 6 * 44_100, tracker: tracker)
        let silent = run.steps.filter { $0.position > lastOnset }
        var previous = Double.infinity
        for step in silent {
            let confidence = step.estimate?.confidence ?? 0
            XCTAssertLessThanOrEqual(confidence, previous, "\(step.position)")
            previous = confidence
            if step.position >= lastOnset + 4 * 44_100 { XCTAssertNil(step.estimate, "\(step.position)") }
            if step.position < lastOnset + 4 * 44_100 { XCTAssertNotNil(step.estimate, "\(step.position)") }
        }
        let gone = lastOnset + 4 * 44_100
        XCTAssertTrue(run.beats.allSatisfy { $0.sampleIndex < gone })

        let count = tracker.beatCount
        tracker.reset()
        XCTAssertNil(tracker.estimate)
        XCTAssertEqual(tracker.beatCount, count)
        // After a reset the position starts over and the sequence continues.
        let again = BeatTestSupport.track(onsets: train(period: 22_050, count: 10), end: 220_500, tracker: tracker)
        XCTAssertEqual(again.beats.first?.sequence, count + 1)
    }

    func testProcessFrameEqualsAddThenAdvance() {
        let a = AdaptiveBeatTracker()
        let b = AdaptiveBeatTracker()
        var beatsA: [BeatEvent] = []
        var beatsB: [BeatEvent] = []
        let onsets = Set(train(period: 22_050, count: 20).map { $0 / 512 })      // the hop each onset falls in
        for k in 0..<870 {
            let index = Int64(k * 512 - 1_536)
            let frame = SpectrumFrame(index: index, size: .n2048, sampleRate: 44_100, timestampNanoseconds: 0, hop: 512)
            let sample = index + 1_536
            let onset = onsets.contains(sample / 512)
                ? OnsetEvent(sequence: UInt64(k), sampleIndex: sample, frameIndex: index, strength: 0.5, threshold: 0.1,
                             sampleRate: 44_100, timestampNanoseconds: 0)
                : nil
            if let beat = a.process(frame, onset: onset) { beatsA.append(beat) }
            if let onset { b.add(onset) }
            if let beat = b.advance(to: index + 2_048) { beatsB.append(beat) }
            XCTAssertEqual(a.estimate, b.estimate)
        }
        XCTAssertEqual(beatsA, beatsB)
        XCTAssertFalse(beatsA.isEmpty)
    }

    /// ANL-005-T12 (S4): random onsets never reach "high" confidence.
    func testRandomOnsetsNeverReachHighConfidence() {
        var maxima: [String] = []
        for (perSecond, seed) in [(1.0, UInt64(11)), (4.0, 12), (16.0, 13)] {
            let onsets = BeatTestSupport.randomOnsets(perSecond: perSecond, seconds: 30, rate: rate, seed: seed)
            let run = BeatTestSupport.track(onsets: onsets, end: Int64(30 * rate))
            let top = run.steps.max { ($0.estimate?.confidence ?? 0) < ($1.estimate?.confidence ?? 0) }
            let highest = top?.estimate?.confidence ?? 0
            if let e = top?.estimate {
                print("ANL-005 random onsets \(perSecond)/s highest at \(e.position): \(e.bpm) BPM, precision \(e.precision), coverage \(e.coverage), support \(e.support), freshness \(e.freshness), matched \(e.matchedBeats) of \(e.onsetsInWindow)")
            }
            XCTAssertLessThan(highest, AdaptiveBeatTracker.highConfidence, "\(perSecond)/s")
            maxima.append("\(perSecond)/s: \(onsets.count) onsets, max confidence \(highest)")
        }
        print("ANL-005 random onsets: \(maxima.joined(separator: "; "))")
    }
}
