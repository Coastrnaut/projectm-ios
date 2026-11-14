// QuantizedCueStepTests.swift — SHOW-003 acceptance: "Synthetic beats trigger once and missing tempo uses explicit
// fallback" (specs/214-show-003-beat-quantized-cues; S1 to S4; contract Q1). Synthetic tempo grids and injected times
// only; no clock is read.
import Foundation
import PerformanceControl
import XCTest

final class QuantizedCueStepTests: XCTestCase {
    /// 120 BPM (500 ms beats) with a beat at 10 s.
    static let anchor: UInt64 = 10_000_000_000
    static let beat: UInt64 = 500_000_000

    static func tempo(bpm: Double = 120, anchor: UInt64? = QuantizedCueStepTests.anchor) -> TempoSnapshot {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: bpm, confidence: 1, beatNanoseconds: anchor))
        return source.snapshot
    }

    /// Ticks every 10 ms from `start` through `end`; returns the times at which a step was taken.
    private func run(_ step: inout QuantizedCueStep, from start: UInt64, through end: UInt64) -> [UInt64] {
        var fired: [UInt64] = []
        var t: UInt64 = start
        while t <= end {
            if step.takeDue(at: t) != nil { fired.append(t) }
            t += 10_000_000
        }
        return fired
    }

    // MARK: - S1: synthetic beats trigger once

    func testNextMidBeatTriggersExactlyOnceAtTheNextBeat() {
        var step = QuantizedCueStep(mode: .beat)
        let request: UInt64 = Self.anchor + 2 * Self.beat + 180_000_000
        let boundary: UInt64 = Self.anchor + 3 * Self.beat
        XCTAssertEqual(step.request(.next, at: request, tempo: Self.tempo()), .queued(deadline: boundary))
        XCTAssertEqual(run(&step, from: request, through: boundary - 1), [], "none before the beat")
        XCTAssertEqual(step.takeDue(at: boundary), .next, "once at the beat")
        XCTAssertEqual(run(&step, from: boundary, through: boundary + 3 * Self.beat), [], "never again over 3 beats")
        XCTAssertNil(step.pending)
    }

    func testBarWaitsForTheBarNotTheBeatsInside() {
        var step = QuantizedCueStep(mode: .bar)
        let request: UInt64 = Self.anchor + Self.beat + 250_000_000
        let bar: UInt64 = Self.anchor + 4 * Self.beat
        XCTAssertEqual(step.request(.next, at: request, tempo: Self.tempo()), .queued(deadline: bar))
        XCTAssertEqual(run(&step, from: request, through: bar + 8 * Self.beat), [bar], "once, at the bar only")
    }

    func testRequestExactlyOnABeatWaitsForTheNextOne() {
        var step = QuantizedCueStep(mode: .beat)
        let onBeat: UInt64 = Self.anchor + 5 * Self.beat
        XCTAssertEqual(step.request(.previous, at: onBeat, tempo: Self.tempo()), .queued(deadline: onBeat + Self.beat))
        XCTAssertNil(step.takeDue(at: onBeat))
    }

    func testClockJumpOverSeveralBeatsFiresOnce() {
        var step = QuantizedCueStep(mode: .beat)
        _ = step.request(.next, at: Self.anchor + 10, tempo: Self.tempo())
        XCTAssertEqual(step.takeDue(at: Self.anchor + 9 * Self.beat), .next)
        XCTAssertNil(step.takeDue(at: Self.anchor + 10 * Self.beat))
    }

    func testALaterTempoDoesNotMoveTheDeadline() {
        var step = QuantizedCueStep(mode: .beat)
        _ = step.request(.next, at: Self.anchor + 100, tempo: Self.tempo())
        // A new, slower tempo arrives; the deadline computed at request time stands (bounded wait).
        XCTAssertEqual(step.deadline, Self.anchor + Self.beat)
        _ = Self.tempo(bpm: 60)
        XCTAssertEqual(step.takeDue(at: Self.anchor + Self.beat), .next)
    }

    // MARK: - S3: replace, cancel, timed

    func testDifferentRequestReplacesAndSameRequestCancels() {
        var step = QuantizedCueStep(mode: .beat)
        let tempo: TempoSnapshot = Self.tempo()
        _ = step.request(.next, at: Self.anchor + 100, tempo: tempo)
        XCTAssertEqual(step.request(.previous, at: Self.anchor + Self.beat + 1, tempo: tempo),
                       .replaced(deadline: Self.anchor + 2 * Self.beat), "latest wins, deadline from its own time")
        XCTAssertEqual(step.takeDue(at: Self.anchor + 2 * Self.beat), .previous)

        let cue = UUID()
        _ = step.request(.go(cue), at: Self.anchor + 100, tempo: tempo)
        XCTAssertEqual(step.request(.go(cue), at: Self.anchor + 200, tempo: tempo), .cancelled, "tap again cancels")
        XCTAssertEqual(run(&step, from: Self.anchor, through: Self.anchor + 4 * Self.beat), [], "nothing at the beat")
    }

    func testTimedRequestNeverCancelsOrReplacesAWaitingStep() {
        var step = QuantizedCueStep(mode: .beat)
        let tempo: TempoSnapshot = Self.tempo()
        _ = step.request(.previous, at: Self.anchor + 100, tempo: tempo)
        XCTAssertEqual(step.request(.next, at: Self.anchor + 200, tempo: tempo, timed: true), .kept)
        XCTAssertEqual(step.pendingRequest, .previous)
        step.cancel()
        XCTAssertEqual(step.request(.next, at: Self.anchor + 200, tempo: tempo, timed: true),
                       .queued(deadline: Self.anchor + Self.beat))
        XCTAssertEqual(step.pending?.timed, true)
    }

    func testModeChangeDropsAndCueModeIsOff() {
        var step = QuantizedCueStep(mode: .beat)
        _ = step.request(.next, at: Self.anchor + 100, tempo: Self.tempo())
        XCTAssertTrue(step.setMode(.bar), "a waiting step is dropped")
        XCTAssertNil(step.pending)
        XCTAssertFalse(step.setMode(.bar))
        XCTAssertEqual(QuantizedCueStep(mode: .cue).mode, .off)
        XCTAssertEqual(step.request(.next, at: 0, tempo: Self.tempo()), .queued(deadline: 2_000_000_000), "bars extend before the anchor")
        XCTAssertTrue(step.setMode(.off))
        XCTAssertEqual(step.request(.next, at: 0, tempo: Self.tempo()), .applyNow(.off))
    }

    // MARK: - S2: missing tempo uses the explicit fallback

    func testNoTempoOrNoPhaseAppliesNow() {
        var step = QuantizedCueStep(mode: .beat)
        XCTAssertEqual(step.request(.next, at: Self.anchor, tempo: .none), .applyNow(.noTempo))
        XCTAssertEqual(step.request(.next, at: Self.anchor, tempo: Self.tempo(anchor: nil)), .applyNow(.noTempo),
                       "a tempo without phase is no tempo")
        _ = step.request(.next, at: Self.anchor, tempo: Self.tempo())
        XCTAssertEqual(step.request(.previous, at: Self.anchor, tempo: .none), .applyNow(.noTempo))
        XCTAssertNil(step.pending, "the fallback drops a waiting step: the new request applies now instead")
    }
}
