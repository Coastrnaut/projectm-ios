// TapTempoTests.swift — taps establish, refine and reject tempos (SHOW-011-R2 to R7, S1 to S3;
// task SHOW-011-T03). Every time is an argument; nothing reads a clock.
import PerformanceControl
import XCTest

/// Milliseconds as monotonic nanoseconds, offset so negative jitter stays positive.
func ms(_ value: Double) -> UInt64 { UInt64((10_000 + value) * 1_000_000) }

final class TapTempoTests: XCTestCase {
    func testFourTapsAt500MillisecondsEstablish120BPM() {
        var source = TempoSource()
        XCTAssertEqual(source.tap(at: ms(0)), .counting(taps: 1, of: 4))
        XCTAssertEqual(source.tap(at: ms(500)), .counting(taps: 2, of: 4))
        XCTAssertEqual(source.tap(at: ms(1_000)), .counting(taps: 3, of: 4))
        XCTAssertEqual(source.snapshot, .none, "three taps never set a tempo (SHOW-011-S2)")
        XCTAssertFalse(source.hasManualTempo)
        XCTAssertEqual(source.tap(at: ms(1_500)), .established(bpm: 120))
        let snapshot = source.snapshot
        XCTAssertEqual(snapshot.origin, .manual)
        XCTAssertEqual(snapshot.bpm, 120)
        XCTAssertEqual(snapshot.confidence, 1)
        XCTAssertEqual(snapshot.periodNanoseconds, 500_000_000)
        XCTAssertEqual(snapshot.anchorNanoseconds, ms(1_500), "beats fall on the last tap (SHOW-011-R7)")
        XCTAssertEqual(source.tapsInSequence, 4)
    }

    func testAlternatingTwentyMillisecondErrorsStayWithinBounds() throws {
        // ±20 ms on every tap: at most ±4 BPM at tap 4, within ±1 BPM at tap 8 (SHOW-011-S1).
        var source = TempoSource()
        var bpm: Double?
        for i in 0..<8 {
            let error: Double = i.isMultiple(of: 2) ? 20 : -20
            let outcome = source.tap(at: ms(Double(i) * 500 + error))
            if i == 3 {
                guard case .established(let value) = outcome else { return XCTFail("tap 4: \(outcome)") }
                XCTAssertEqual(value, 120, accuracy: 4)
            }
            if i > 3 {
                guard case .refined(let value) = outcome else { return XCTFail("tap \(i + 1): \(outcome)") }
                bpm = value
            }
        }
        XCTAssertEqual(try XCTUnwrap(bpm), 120, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(source.snapshot.bpm), 120, accuracy: 1)
    }

    func testFurtherTapsRefineAndMoveThePhase() {
        var source = TempoSource()
        for i in 0..<4 { source.tap(at: ms(Double(i) * 500)) }
        // Speed up to 400 ms intervals: the fit moves toward it and the anchor follows the newest tap.
        let outcome = source.tap(at: ms(1_900))
        guard case .refined(let bpm) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertGreaterThan(bpm, 120)
        XCTAssertEqual(source.snapshot.anchorNanoseconds, ms(1_900))
        // Eight taps later only the new tempo is in the window.
        for i in 1...8 { source.tap(at: ms(1_900 + Double(i) * 400)) }
        XCTAssertEqual(source.snapshot.bpm ?? 0, 150, accuracy: 1e-9)
    }

    func testTooFastTapIsIgnored() {
        var source = TempoSource()
        source.tap(at: ms(0))
        source.tap(at: ms(500))
        XCTAssertEqual(source.tap(at: ms(750)), .tooFast, "250 ms is 240 BPM (SHOW-011-R5)")
        XCTAssertEqual(source.tap(at: ms(750)), .tooFast, "a bounce at the same instant")
        XCTAssertEqual(source.tapsInSequence, 2)
        XCTAssertEqual(source.tap(at: ms(1_000)), .counting(taps: 3, of: 4))
        XCTAssertEqual(source.tap(at: ms(1_500)), .established(bpm: 120))
    }

    func testTooSlowTapRestartsTheSequence() {
        var source = TempoSource()
        source.tap(at: ms(0))
        source.tap(at: ms(500))
        XCTAssertEqual(source.tap(at: ms(2_000)), .tooSlow, "1.5 s is 40 BPM (SHOW-011-R5)")
        XCTAssertEqual(source.tapsInSequence, 1)
        XCTAssertEqual(source.snapshot, .none)
    }

    func testLongPauseStartsANewSequenceSilently() {
        var source = TempoSource()
        source.tap(at: ms(0))
        source.tap(at: ms(500))
        XCTAssertEqual(source.tap(at: ms(3_500)), .counting(taps: 1, of: 4), "over 2 s (SHOW-011-R6)")
        XCTAssertEqual(source.tap(at: ms(4_000)), .counting(taps: 2, of: 4))
        XCTAssertEqual(source.tap(at: ms(4_500)), .counting(taps: 3, of: 4))
        XCTAssertEqual(source.tap(at: ms(5_000)), .established(bpm: 120))
    }

    func testManualTempoSurvivesARestartUntilReplaced() {
        var source = TempoSource()
        for i in 0..<4 { source.tap(at: ms(Double(i) * 500)) }
        let base = 5_000.0
        XCTAssertEqual(source.tap(at: ms(base)), .counting(taps: 1, of: 4))
        source.tap(at: ms(base + 600))
        source.tap(at: ms(base + 1_200))
        XCTAssertEqual(source.snapshot.bpm, 120, "the old manual tempo stays (SHOW-011 US3 scenario 4)")
        XCTAssertEqual(source.tap(at: ms(base + 1_800)), .refined(bpm: 100))
        XCTAssertEqual(source.snapshot.origin, .manual)
    }

    func testManualTempoStaysInsideTheRange() {
        // Intervals at the limits: 300 ms (200 BPM) and 1 s (60 BPM) are accepted (SHOW-011-S3).
        var fast = TempoSource()
        for i in 0..<4 { fast.tap(at: ms(Double(i) * 300)) }
        XCTAssertEqual(fast.snapshot.bpm ?? 0, 200, accuracy: 1e-9)
        var slow = TempoSource()
        for i in 0..<4 { slow.tap(at: ms(Double(i) * 1_000)) }
        XCTAssertEqual(slow.snapshot.bpm ?? 0, 60, accuracy: 1e-9)
        // Accepted intervals near both limits mixed: the fit stays within 60-200.
        var mixed = TempoSource()
        let times: [Double] = [0, 300, 1_300, 1_600, 2_600, 2_900]
        for t in times { mixed.tap(at: ms(t)) }
        let bpm = mixed.snapshot.bpm ?? 0
        XCTAssertGreaterThanOrEqual(bpm, 60)
        XCTAssertLessThanOrEqual(bpm, 200)
    }
}
