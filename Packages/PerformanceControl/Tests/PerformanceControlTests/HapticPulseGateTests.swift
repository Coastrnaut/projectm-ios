// HapticPulseGateTests.swift — ACC-007-T04: the haptic pulse gate (contract C1), the event mapping (C2) and
// `TempoSubscriptionReader.poll(onEvent:)` (specs/238-acc-007-haptic-beat-feedback; R3, R4; S2, S3).
// Every time is an argument: synthetic streams on a nanosecond grid, no wall clock (owner rule 7: a few
// representative cases, each well under a second).
import AnalysisFeatures
import AudioCore
import PerformanceControl
import PerformanceControlAnalysis
import XCTest

final class HapticPulseGateTests: XCTestCase {
    private static let ms: UInt64 = 1_000_000
    private static let start: UInt64 = 5_000_000_000

    /// Runs `count` cues every `periodMs`, delivered on time; returns the pulse times.
    private func run(_ gate: inout HapticPulseGate, cue: (Int) -> HapticCue, count: Int, periodMs: UInt64) -> [UInt64] {
        var times: [UInt64] = []
        for i in 0..<count {
            let t: UInt64 = Self.start + UInt64(i) * periodMs * Self.ms
            if gate.consider(cue(i), eventNanoseconds: t, now: t, playable: true) == .pulse { times.append(t) }
        }
        return times
    }

    func testKicksAt30HzAreThrottledToTheThreeLimits() {
        var gate = HapticPulseGate(choice: .kicks)
        let times: [UInt64] = run(&gate, cue: { (_: Int) -> HapticCue in .kick }, count: 30 * 60, periodMs: 33)   // ≈ 60 s at 30 Hz
        XCTAssertFalse(times.isEmpty)
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 150 * Self.ms, "minimum interval")
        }
        for (i, t) in times.enumerated() where i >= 4 {
            XCTAssertGreaterThanOrEqual(t - times[i - 4], 1_000 * Self.ms, "at most 4 in any 1 s")
        }
        XCTAssertLessThanOrEqual(times.count, 180, "at most 180 in 60 s")
        XCTAssertGreaterThan(times.count, 150, "the duty cycle still lets about 3 per second through")
        XCTAssertEqual(gate.pulses, times.count)
        XCTAssertEqual(gate.throttledCount, 30 * 60 - times.count)

        var again = HapticPulseGate(choice: .kicks)
        XCTAssertEqual(run(&again, cue: { (_: Int) -> HapticCue in .kick }, count: 30 * 60, periodMs: 33), times, "deterministic")
    }

    func testDutyCycleCapsALongDenseStream() {
        var gate = HapticPulseGate(choice: .kicks)
        // 4 per second fits the burst limit but exceeds 180 per 60 s.
        let times: [UInt64] = run(&gate, cue: { (_: Int) -> HapticCue in .kick }, count: 4 * 120, periodMs: 250)
        for (i, t) in times.enumerated() where i >= 180 {
            XCTAssertGreaterThanOrEqual(t - times[i - 180], 60_000 * Self.ms, "at most 180 in any 60 s")
        }
        XCTAssertEqual(times.count, 360)
    }

    func testChoiceFiltersAndDownbeatsCountFromTheSession() {
        let stream: [HapticCue] = [.sessionBoundary, .beat(confidence: 0.9), .kick, .beat(confidence: 0.2), .beat(confidence: 0.8),
                                   .beat(confidence: 0.8), .beat(confidence: 0.8), .beat(confidence: 0.8), .kick,
                                   .sessionBoundary, .beat(confidence: 0.8), .beat(confidence: 0.8)]
        func pulses(_ choice: HapticBeatChoice) -> [Int] {
            var gate = HapticPulseGate(choice: choice)
            var hits: [Int] = []
            for (i, cue) in stream.enumerated() {
                let t: UInt64 = Self.start + UInt64(i) * 500 * Self.ms
                if gate.consider(cue, eventNanoseconds: t, now: t, playable: true) == .pulse { hits.append(i) }
            }
            return hits
        }
        XCTAssertEqual(pulses(.beats), [1, 4, 5, 6, 7, 10, 11], "confident beats only")
        XCTAssertEqual(pulses(.downbeats), [1, 7, 10], "beats 1 and 5 of a session; a new session restarts")
        XCTAssertEqual(pulses(.kicks), [2, 8])
    }

    /// QA-011 D1 2026-11-23: the music fixture's 120 BPM chorus (eighth-note hi-hats) gives ANL-005 confidences that
    /// waver between 0.46 and 0.52 (measured on the host from scripts/make_music_fixture.py). Beats engage at 0.5 and
    /// then hold down to 0.4; nothing pulses before the first 0.5, a weak beat disengages, a marker does too.
    func testBeatsHoldThroughConfidenceWaveringBelowTheEngageLevel() {
        let confidences: [Double] = [0.46, 0.46, 0.52, 0.46, 0.46, 0.46, 0.52, 0.52, 0.46, 0.5, 0.46,
                                     0.3, 0.46, 0.46, 0.5, 0.46]
        var gate = HapticPulseGate(choice: .beats)
        let times = run(&gate, cue: { .beat(confidence: confidences[$0]) }, count: confidences.count, periodMs: 500)
        let hits = times.map { Int(($0 - Self.start) / (500 * Self.ms)) }
        XCTAssertEqual(hits, [2, 3, 4, 5, 6, 7, 8, 9, 10, 14, 15], "engage at 0.5, hold at 0.46, drop at 0.3")
        XCTAssertEqual(gate.beatCount, 11)
        XCTAssertEqual(gate.consider(.sessionBoundary, eventNanoseconds: Self.start, now: Self.start, playable: true), .filtered)
        XCTAssertFalse(gate.beatsEngaged, "a session marker disengages")
        let t: UInt64 = Self.start + 20_000 * Self.ms
        XCTAssertEqual(gate.consider(.beat(confidence: 0.46), eventNanoseconds: t, now: t, playable: true), .filtered)
    }

    func testStaleSuppressedAndOutOfOrderEventsNeverPulse() {
        var gate = HapticPulseGate(choice: .beats)
        let t: UInt64 = Self.start
        XCTAssertEqual(gate.consider(.beat(confidence: 1), eventNanoseconds: t, now: t + 201 * Self.ms, playable: true), .stale)
        XCTAssertEqual(gate.consider(.beat(confidence: 1), eventNanoseconds: t, now: t, playable: false), .suppressed)
        XCTAssertEqual(gate.consider(.beat(confidence: 1), eventNanoseconds: t, now: t + 200 * Self.ms, playable: true), .pulse)
        XCTAssertEqual(gate.consider(.beat(confidence: 1), eventNanoseconds: t - Self.ms, now: t, playable: true), .throttled)
        XCTAssertEqual(gate.beatCount, 4, "every confident beat counts, played or not")
        gate.reset()
        XCTAssertEqual(gate.pulses, 0)
        XCTAssertEqual(gate.consider(.beat(confidence: 1), eventNanoseconds: t, now: t, playable: true), .pulse)
    }

    func testAnalysisEventsMapToCues() {
        let time = AnalysisTimestamp(session: 1, sessionSample: 0, timelineSample: 0, hostNanoseconds: 0)
        func cue(_ kind: AnalysisEventKind) -> HapticCue? { HapticCue(AnalysisEvent(id: 1, time: time, eventSample: 0, kind: kind)) }
        XCTAssertEqual(cue(.beat(bpm: 120, periodSamples: 22_050, confidence: 0.7)), .beat(confidence: 0.7))
        XCTAssertEqual(cue(.transient(band: .kick, strength: 1, threshold: 1, level: -10, confidence: 0.5)), .kick)
        XCTAssertNil(cue(.transient(band: .midTransient, strength: 1, threshold: 1, level: -10, confidence: 0.5)))
        XCTAssertNil(cue(.onset(strength: 1, threshold: 0.5)))
        XCTAssertEqual(cue(.sessionStarted(.attached)), .sessionBoundary)
        XCTAssertEqual(cue(.sessionEnded(.detached)), .sessionBoundary)
    }

    func testPollHandsEveryDrainedEventToTheObserver() throws {
        let rate = 44_100
        let generator = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5)),
                                          format: try ToneFormat(sampleRate: rate, channels: 2))
        let samples = generator.interleaved(frames: rate * 4)
        let pipeline = AnalysisPipeline(configuration: try AnalysisPipelineConfiguration(bandCount: .b16), clock: { 1_000_000_000 })
        let reader = TempoSubscriptionReader(subscription: try pipeline.subscribe(eventCapacity: 1_024), sampleRate: Double(rate))
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        let frames = samples.count / 2
        var offset = 0
        var seen: [AnalysisEvent] = []
        samples.withUnsafeBufferPointer { buffer in
            while offset < frames {
                let n = min(2_048, frames - offset)
                ring.write(buffer.baseAddress! + 2 * offset, frames: n)
                offset += n
                pipeline.step()
                _ = reader.poll(onEvent: { (event: AnalysisEvent) -> Void in seen.append(event) })
            }
        }
        pipeline.detach()
        _ = reader.poll(onEvent: { (event: AnalysisEvent) -> Void in seen.append(event) })   // the session-ended marker
        XCTAssertEqual(reader.subscription.pendingEvents, 0)
        XCTAssertEqual(seen.map(\.id), seen.map(\.id).sorted(), "in ID order")
        XCTAssertTrue(seen.contains { (event: AnalysisEvent) -> Bool in HapticCue(event) == .sessionBoundary })
        XCTAssertTrue(seen.contains { (event: AnalysisEvent) -> Bool in HapticCue(event) == .kick }, "120 BPM pulses give kicks")
    }
}
