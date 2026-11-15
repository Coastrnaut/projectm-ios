// MIDI-010-T05, T08 (MIDI-010-R1 to R5, S1 to S4): the clock tracker's acceptance with injected timestamps, the lane and
// the ring's hook, decoding of the UMP system real-time words, and the tempo source's priority. Pure Swift; runs on Linux.
import PerformanceControl
import XCTest

final class MIDIClockTests: XCTestCase {
    private static let origin: UInt64 = 10_000_000_000

    /// Nanoseconds per pulse at `bpm` (24 PPQN).
    private func period(_ bpm: Double) -> Double { 60e9 / (24 * bpm) }

    private func clock(_ time: UInt64) -> MIDIEvent { MIDIEvent(kind: .clock, timestamp: time) }

    /// Feeds `count` pulses at `bpm` starting at `start`; returns the time of the next pulse on the grid.
    @discardableResult
    private func feed(_ tracker: inout MIDIClockTracker, bpm: Double, count: Int, from start: UInt64,
                      jitter: ((Int) -> Double)? = nil) -> UInt64 {
        let p: Double = period(bpm)
        for i in 0..<count {
            let offset: Double = Double(i) * p + (jitter?(i) ?? 0)
            tracker.receive(clock(UInt64((Double(start) + offset).rounded())))
        }
        return start + UInt64((Double(count) * p).rounded())
    }

    private func lockedBPM(_ tracker: MIDIClockTracker, file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard case .locked(let bpm) = tracker.status else {
            XCTFail("not locked: \(tracker.status)", file: file, line: line)
            return 0
        }
        return bpm
    }

    // MARK: S1 — the row's acceptance

    func testExactPulsesReadTheirTempoWithinATenthOfABPM() {
        for bpm: Double in [60, 90, 120, 174.5, 300] {
            var tracker = MIDIClockTracker()
            feed(&tracker, bpm: bpm, count: 48, from: Self.origin)
            XCTAssertEqual(lockedBPM(tracker), bpm, accuracy: 0.1, "\(bpm) BPM")
            XCTAssertEqual(tracker.tempo?.bpm ?? 0, bpm, accuracy: 0.1)
        }
    }

    func testLocksAfterOneBeatOfPulses() {
        var tracker = MIDIClockTracker()
        XCTAssertEqual(tracker.status, .noClock)
        feed(&tracker, bpm: 120, count: 24, from: Self.origin)
        XCTAssertEqual(tracker.status, .acquiring, "24 pulses are 23 intervals")
        tracker.receive(clock(Self.origin + UInt64((24 * period(120)).rounded())))
        XCTAssertEqual(lockedBPM(tracker), 120, accuracy: 0.1)
    }

    // MARK: S2 — jitter

    func testSeededOneMillisecondJitterStaysWithinHalfABPM() {
        var rng = ClockJitterRandom(seed: 0x4D49_4449_3130)
        var tracker = MIDIClockTracker()
        let jitter: (Int) -> Double = { (_: Int) -> Double in (rng.unit() * 2 - 1) * 1_000_000 }
        feed(&tracker, bpm: 120, count: 200, from: Self.origin, jitter: jitter)
        XCTAssertEqual(lockedBPM(tracker), 120, accuracy: 0.5)
        XCTAssertEqual(tracker.rejectedPulses, 0, "jitter is never an outlier")
    }

    // MARK: S3 — tempo change, dropped and early pulses

    func testAStepFrom120To140ConvergesWithinFourBeats() {
        var tracker = MIDIClockTracker()
        let next: UInt64 = feed(&tracker, bpm: 120, count: 96, from: Self.origin)
        XCTAssertEqual(lockedBPM(tracker), 120, accuracy: 0.1)
        feed(&tracker, bpm: 140, count: 96, from: next)
        XCTAssertEqual(lockedBPM(tracker), 140, accuracy: 0.5)
    }

    func testADroppedPulseIsCountedAndAnEarlyPulseIsRejected() {
        var tracker = MIDIClockTracker()
        tracker.receive(MIDIEvent(kind: .start, timestamp: Self.origin - 1_000))
        let p: Double = period(120)
        for i in 0..<72 where i != 40 {   // pulse 40 is lost
            let time: UInt64 = Self.origin + UInt64((Double(i) * p).rounded())
            tracker.receive(clock(time))
            if i == 50 { tracker.receive(clock(time + 3_000_000)) }   // a spurious pulse 3 ms later
        }
        XCTAssertEqual(lockedBPM(tracker), 120, accuracy: 0.1)
        XCTAssertEqual(tracker.rejectedPulses, 1)
        XCTAssertEqual(tracker.position, 71, "the lost pulse is counted, the spurious one is not")
    }

    func testATempoOutsideTheRangeIsIgnored() {
        var slow = MIDIClockTracker()
        feed(&slow, bpm: 15, count: 30, from: Self.origin)
        guard case .outOfRange = slow.status else { return XCTFail("15 BPM: \(slow.status)") }
        XCTAssertNil(slow.tempo)
        var fast = MIDIClockTracker()
        feed(&fast, bpm: 320, count: 48, from: Self.origin)
        guard case .outOfRange = fast.status else { return XCTFail("320 BPM: \(fast.status)") }
        XCTAssertNil(fast.tempo)
    }

    // MARK: S4 — loss and transport

    func testStopAndATimeoutUnlock() {
        var tracker = MIDIClockTracker()
        let next: UInt64 = feed(&tracker, bpm: 120, count: 48, from: Self.origin)
        tracker.tick(now: next + 400_000_000)
        XCTAssertNotNil(tracker.tempo, "0.4 s without a pulse keeps the lock")
        tracker.tick(now: next + 600_000_000)
        XCTAssertEqual(tracker.status, .noClock)
        XCTAssertNil(tracker.tempo)

        var stopped = MIDIClockTracker()
        let after: UInt64 = feed(&stopped, bpm: 120, count: 48, from: Self.origin)
        stopped.receive(MIDIEvent(kind: .stop, timestamp: after))
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertNil(stopped.tempo)
        let resume: UInt64 = feed(&stopped, bpm: 120, count: 12, from: after)   // a master that keeps clocking
        XCTAssertNil(stopped.tempo, "pulses after Stop do not set the tempo")
        stopped.receive(MIDIEvent(kind: .start, timestamp: resume))
        feed(&stopped, bpm: 120, count: 1, from: resume)
        XCTAssertEqual(stopped.tempo?.bpm ?? 0, 120, accuracy: 0.1, "the warm measurement returns at once")
    }

    func testStartResetsThePositionAndTheAnchorFollowsEveryTwentyFourthPulse() {
        var tracker = MIDIClockTracker()
        let p: Double = period(120)
        feed(&tracker, bpm: 120, count: 30, from: Self.origin)
        XCTAssertNil(tracker.position, "a free-running clock has no position")
        XCTAssertNil(tracker.tempo?.anchorNanoseconds, "and no anchor")
        let start: UInt64 = Self.origin + UInt64((30 * p).rounded())
        tracker.receive(MIDIEvent(kind: .start, timestamp: start - 1_000))
        for count in [1, 24, 25, 49] {
            var tr: MIDIClockTracker = tracker
            feed(&tr, bpm: 120, count: count, from: start)
            XCTAssertEqual(tr.position, count - 1)
            let beat: Int = (count - 1) / 24 * 24
            let expected: Double = Double(start) + Double(beat) * p
            XCTAssertEqual(Double(tr.tempo?.anchorNanoseconds ?? 0), expected, accuracy: 1_000, "after \(count) pulses")
        }
    }

    func testSongPositionAndContinueResume() {
        var tracker = MIDIClockTracker()
        tracker.receive(MIDIEvent(kind: .start, timestamp: Self.origin - 1))
        let next: UInt64 = feed(&tracker, bpm: 120, count: 30, from: Self.origin)
        XCTAssertEqual(tracker.position, 29)
        tracker.receive(MIDIEvent(kind: .stop, timestamp: next))
        tracker.receive(MIDIEvent(kind: .continue, timestamp: next))
        let after: UInt64 = feed(&tracker, bpm: 120, count: 1, from: next)
        XCTAssertEqual(tracker.position, 30, "Continue alone resumes counting")
        tracker.receive(MIDIEvent(kind: .stop, timestamp: after))
        tracker.receive(MIDIEvent(kind: .songPosition, value: 16, timestamp: after))   // bar 2 in 4/4: 16 sixteenths
        tracker.receive(MIDIEvent(kind: .continue, timestamp: after))
        feed(&tracker, bpm: 120, count: 1, from: after)
        XCTAssertEqual(tracker.position, 96)
        XCTAssertEqual(Double(tracker.tempo?.anchorNanoseconds ?? 0), Double(after), accuracy: 1_000, "position 96 is a beat")
    }

    // MARK: R1 — lane, hook and decoding

    func testTheRingCopiesClockEventsToTheLaneInOrderOnlyWhileEnabled() {
        let ring = MIDIEventRing(capacity: 8)
        ring.push(clock(1))
        var drained: [MIDIEvent] = []
        ring.clockLane.drain(into: &drained)
        XCTAssertEqual(drained, [], "disabled: nothing is copied")
        ring.clockLane.isEnabled = true
        let sent: [MIDIEvent] = [MIDIEvent(kind: .start, timestamp: 2), clock(3), MIDIEvent(kind: .noteOn, number: 60, value: 9, timestamp: 4),
                                 clock(5), MIDIEvent(kind: .songPosition, value: 4, timestamp: 6), MIDIEvent(kind: .stop, timestamp: 7)]
        for event in sent { ring.push(event) }
        ring.clockLane.drain(into: &drained)
        XCTAssertEqual(drained.map(\.timestamp), [2, 3, 5, 6, 7], "clock-relevant kinds, in order")
        XCTAssertEqual(ring.clockCount, 3, "the ring still counts clocks")
        var main: [MIDIEvent] = []
        ring.drain(into: &main, maxCount: 8)
        XCTAssertEqual(main.map(\.kind), [.start, .noteOn, .songPosition, .stop], "the ring's own queue is unchanged")
        ring.push(clock(8))
        ring.discardAll()
        drained.removeAll()
        XCTAssertEqual(ring.clockLane.drain(into: &drained), 0, "discardAll empties the lane too")
    }

    func testTheLaneDropsTheNewestWhenFull() {
        let lane = MIDIClockLane(capacity: 2)
        lane.isEnabled = true
        for t: UInt64 in 1...3 { lane.push(clock(t)) }
        var drained: [MIDIEvent] = []
        lane.drain(into: &drained)
        XCTAssertEqual(drained.map(\.timestamp), [1, 2])
        XCTAssertEqual(lane.dropped, 1)
    }

    func testUMPSystemRealTimeWordsDecodeToClockEvents() {
        var decoder = MIDIUMPDecoder()
        var sink = MIDIEventCollector()
        let input: [UInt32] = [0x10F8_0000, 0x10FA_0000, 0x10FB_0000, 0x10FC_0000, 0x10F2_1002]
        input.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt32>) -> Void in
            decoder.decode(buffer, timestamp: 42, into: &sink)
        }
        XCTAssertEqual(sink.events.map(\.kind), [.clock, .start, .continue, .stop, .songPosition])
        XCTAssertEqual(sink.events.last?.value, 0x02 << 7 | 0x10, "song position LSB then MSB")
        XCTAssertTrue(sink.events.allSatisfy { (event: MIDIEvent) -> Bool in event.timestamp == 42 })
    }

    // MARK: R5 — tempo source priority

    func testALockedClockOutranksTapAndFallsBackToIt() {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 100, confidence: 0.9, beatNanoseconds: nil))
        for i in 0..<4 { source.tap(at: Self.origin + UInt64(i) * 500_000_000) }   // 120 BPM by tap
        source.updateMIDIClock(MIDIClockTempo(bpm: 133.3, anchorNanoseconds: 77))
        XCTAssertEqual(source.snapshot.origin, .midiClock)
        XCTAssertEqual(source.snapshot.bpm, 133.3)
        XCTAssertEqual(source.snapshot.anchorNanoseconds, 77)
        XCTAssertEqual(source.snapshot.confidence, 1)
        XCTAssertEqual(TempoReadout(snapshot: source.snapshot, indicator: TempoConfidenceIndicator()), .midiClock(bpm: 133.3))
        source.updateMIDIClock(nil)
        XCTAssertEqual(source.snapshot.origin, .manual)
        XCTAssertEqual(source.snapshot.bpm ?? 0, 120, accuracy: 0.01)
        source.resetManual()
        XCTAssertEqual(source.snapshot.origin, .estimated)
    }
}

/// A small seeded generator (deterministic jitter).
private struct ClockJitterRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}
