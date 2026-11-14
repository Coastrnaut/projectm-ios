// QuantizedChangeQueueTests.swift — MOD-017 acceptance: "Change requested between beats applies exactly once at
// next boundary" (specs/206-mod-017-quantized-changes; S1 to S3; contract Q1). Synthetic tempo grids and injected
// times only; no clock is read.
import PerformanceControl
import XCTest

final class QuantizedChangeQueueTests: XCTestCase {
    typealias Queue = QuantizedChangeQueue<String, Int>

    /// 120 BPM (500 ms beats) with a beat at 10 s.
    static let anchor: UInt64 = 10_000_000_000
    static let beat: UInt64 = 500_000_000

    static func tempo(bpm: Double = 120, anchor: UInt64? = QuantizedChangeQueueTests.anchor) -> TempoSnapshot {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: bpm, confidence: 1, beatNanoseconds: anchor))
        return source.snapshot
    }

    /// Steps an injected clock from `start` to `end` in `step` increments and records each application per tick.
    private func run(_ queue: inout Queue, from start: UInt64, to end: UInt64, step: UInt64) -> [(time: UInt64, value: Int)] {
        var applied: [(time: UInt64, value: Int)] = []
        var t: UInt64 = start
        while t <= end {
            for change in queue.takeDue(at: t) { applied.append((t, change.value)) }
            t += step
        }
        return applied
    }

    // MARK: - S1 acceptance per boundary kind

    func testBeatChangeMidBeatAppliesExactlyOnceAtNextBeat() {
        var queue = Queue(mode: .beat)
        let request: UInt64 = Self.anchor + 2 * Self.beat + 180_000_000   // mid-beat
        let result: QuantizeRequestResult = queue.request("glow", value: 1, current: 0, at: request,
                                                          tempo: Self.tempo(), hasCues: false)
        let boundary: UInt64 = Self.anchor + 3 * Self.beat
        XCTAssertEqual(result, .queued(.time(boundary)))
        // Not before: every 10 ms tick up to 1 ns before the boundary applies nothing.
        XCTAssertTrue(run(&queue, from: request, to: boundary - 1, step: 10_000_000).isEmpty)
        XCTAssertTrue(queue.takeDue(at: boundary - 1).isEmpty)
        // Exactly once at the boundary.
        let at: [QueuedChange<String, Int>] = queue.takeDue(at: boundary)
        XCTAssertEqual(at.map(\.value), [1])
        // Never again over three further beats.
        XCTAssertTrue(run(&queue, from: boundary, to: boundary + 3 * Self.beat, step: 10_000_000).isEmpty)
        XCTAssertTrue(queue.isEmpty)
    }

    func testBarChangeIgnoresTheBeatsInBetween() {
        var queue = Queue(mode: .bar)
        let request: UInt64 = Self.anchor + Self.beat + 250_000_000   // beat 1.5 of bar 0
        let result: QuantizeRequestResult = queue.request("bars", value: 64, current: 32, at: request,
                                                          tempo: Self.tempo(), hasCues: false)
        let bar: UInt64 = Self.anchor + 4 * Self.beat
        XCTAssertEqual(result, .queued(.time(bar)))
        for beatIndex in UInt64(2)...3 {   // beats 2 and 3 pass without applying
            XCTAssertTrue(queue.takeDue(at: Self.anchor + beatIndex * Self.beat).isEmpty)
        }
        XCTAssertEqual(queue.takeDue(at: bar).map(\.value), [64])
        XCTAssertTrue(run(&queue, from: bar, to: bar + 12 * Self.beat, step: Self.beat).isEmpty)   // three more bars
    }

    func testCueChangeAppliesOnceAtTheNextCueStep() {
        var queue = Queue(mode: .cue)
        let result: QuantizeRequestResult = queue.request("orientation", value: 2, current: 1, at: 5, tempo: .none, hasCues: true)
        XCTAssertEqual(result, .queued(.nextCue))
        XCTAssertNil(queue.nextDeadline)
        XCTAssertTrue(queue.takeDue(at: UInt64.max).isEmpty, "time alone never applies a cue change")
        let first = queue.cueStepped()
        XCTAssertEqual(first.apply.map(\.value), [2])
        XCTAssertEqual(first.dropped, 0)
        for _ in 0..<3 {
            let next = queue.cueStepped()
            XCTAssertTrue(next.apply.isEmpty)
            XCTAssertEqual(next.dropped, 0)
        }
    }

    // MARK: - Latest wins, cancel, strictness (S2, R4)

    func testLatestOfFiveRequestsAppliesOnce() {
        var queue = Queue(mode: .beat)
        for (i, value) in [3, 4, 5, 6, 7].enumerated() {
            _ = queue.request("bars", value: value, current: 0, at: Self.anchor + 50_000_000 * UInt64(i + 1),
                              tempo: Self.tempo(), hasCues: false)
        }
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertEqual(queue.pendingValue(for: "bars"), 7)
        XCTAssertEqual(queue.takeDue(at: Self.anchor + Self.beat).map(\.value), [7])
        XCTAssertTrue(queue.isEmpty)
    }

    func testRequestEqualToCurrentCancels() {
        var queue = Queue(mode: .beat)
        _ = queue.request("glow", value: 1, current: 0, at: Self.anchor + 1, tempo: Self.tempo(), hasCues: false)
        XCTAssertEqual(queue.request("glow", value: 0, current: 0, at: Self.anchor + 2, tempo: Self.tempo(), hasCues: false), .cancelled)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.request("glow", value: 0, current: 0, at: Self.anchor + 3, tempo: Self.tempo(), hasCues: false), .unchanged)
    }

    func testRequestExactlyOnABeatWaitsForTheNextOne() {
        var queue = Queue(mode: .beat)
        let onBeat: UInt64 = Self.anchor + 5 * Self.beat
        XCTAssertEqual(queue.request("glow", value: 1, current: 0, at: onBeat, tempo: Self.tempo(), hasCues: false),
                       .queued(.time(onBeat + Self.beat)))
        XCTAssertTrue(queue.takeDue(at: onBeat).isEmpty)
    }

    func testClockJumpOverSeveralBoundariesAppliesOnceInRequestOrder() {
        var queue = Queue(mode: .beat)
        _ = queue.request("b", value: 2, current: 0, at: Self.anchor + 300_000_000, tempo: Self.tempo(), hasCues: false)
        _ = queue.request("a", value: 1, current: 0, at: Self.anchor + 2 * Self.beat + 1, tempo: Self.tempo(), hasCues: false)
        XCTAssertEqual(queue.nextDeadline, Self.anchor + Self.beat)
        let due: [QueuedChange<String, Int>] = queue.takeDue(at: Self.anchor + 40 * Self.beat)   // suspended for 20 s
        XCTAssertEqual(due.map(\.key), ["b", "a"])
        XCTAssertTrue(queue.takeDue(at: Self.anchor + 41 * Self.beat).isEmpty)
    }

    // MARK: - Fallback (S3, R6) and clearing (R8)

    func testNoTempoOrNoPhaseOrNoCueAppliesNow() {
        var beat = Queue(mode: .beat)
        XCTAssertEqual(beat.request("glow", value: 1, current: 0, at: 7, tempo: .none, hasCues: true), .applyNow(.noTempo))
        XCTAssertEqual(beat.request("glow", value: 1, current: 0, at: 7, tempo: Self.tempo(anchor: nil), hasCues: true),
                       .applyNow(.noTempo), "an estimate without a beat time has no phase")
        var bar = Queue(mode: .bar)
        XCTAssertEqual(bar.request("glow", value: 1, current: 0, at: 7, tempo: .none, hasCues: true), .applyNow(.noTempo))
        var cue = Queue(mode: .cue)
        XCTAssertEqual(cue.request("glow", value: 1, current: 0, at: 7, tempo: Self.tempo(), hasCues: false), .applyNow(.noCue))
        var off = Queue()
        XCTAssertEqual(off.request("glow", value: 1, current: 0, at: 7, tempo: Self.tempo(), hasCues: true), .applyNow(.off))
        XCTAssertTrue(beat.isEmpty && bar.isEmpty && cue.isEmpty && off.isEmpty)
    }

    func testCueStepInBeatModeAndModeChangeClearTheQueue() {
        var queue = Queue(mode: .beat)
        _ = queue.request("a", value: 1, current: 0, at: Self.anchor + 1, tempo: Self.tempo(), hasCues: true)
        _ = queue.request("b", value: 1, current: 0, at: Self.anchor + 2, tempo: Self.tempo(), hasCues: true)
        let step = queue.cueStepped()
        XCTAssertTrue(step.apply.isEmpty)
        XCTAssertEqual(step.dropped, 2)
        _ = queue.request("a", value: 1, current: 0, at: Self.anchor + 3, tempo: Self.tempo(), hasCues: true)
        XCTAssertEqual(queue.setMode(.beat), 0, "the same mode keeps the queue")
        XCTAssertEqual(queue.setMode(.bar), 1)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertTrue(queue.takeDue(at: UInt64.max).isEmpty)
    }

    // MARK: - Boundary helper (D1)

    func testNextBoundaryIsStrictlyAfterOnBothSidesOfTheAnchor() {
        let tempo: TempoSnapshot = Self.tempo()
        XCTAssertEqual(tempo.nextBoundary(after: Self.anchor - 1, beats: 1), Self.anchor)
        XCTAssertEqual(tempo.nextBoundary(after: Self.anchor, beats: 1), Self.anchor + Self.beat)
        XCTAssertEqual(tempo.nextBoundary(after: Self.anchor - Self.beat, beats: 1), Self.anchor)
        XCTAssertEqual(tempo.nextBoundary(after: Self.anchor - Self.beat - 1, beats: 1), Self.anchor - Self.beat)
        XCTAssertEqual(tempo.nextBoundary(after: Self.anchor - 1, beats: 4), Self.anchor)
        XCTAssertEqual(tempo.nextBoundary(after: Self.anchor - 4 * Self.beat - 1, beats: 4), Self.anchor - 4 * Self.beat)
        XCTAssertEqual(tempo.nextBoundary(after: Self.anchor + 1, beats: 4), Self.anchor + 4 * Self.beat)
        XCTAssertNil(tempo.nextBoundary(after: 0, beats: 0))
        XCTAssertNil(TempoSnapshot.none.nextBoundary(after: 0, beats: 1))
    }
}
