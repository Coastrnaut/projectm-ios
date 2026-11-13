// TempoSourceTests.swift — estimate, reset and the consumers' read API (SHOW-011-R1, R8 to R11,
// S4, S5; task SHOW-011-T04).
import Foundation
import PerformanceControl
import XCTest

final class TempoSourceTests: XCTestCase {
    private func manual120(_ source: inout TempoSource) {
        for i in 0..<4 { source.tap(at: ms(Double(i) * 500)) }
    }

    func testNoInputIsNone() {
        let snapshot = TempoSource().snapshot
        XCTAssertEqual(snapshot, .none)
        XCTAssertEqual(snapshot.origin, .none)
        XCTAssertNil(snapshot.bpm)
        XCTAssertEqual(snapshot.confidence, 0)
        XCTAssertNil(snapshot.nextBeat(atOrAfter: ms(0)))
        XCTAssertNil(snapshot.beatPhase(at: ms(0)))
    }

    func testConfidentEstimateIsEstimated() {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 126, confidence: 0.8, beatNanoseconds: ms(100)))
        let snapshot = source.snapshot
        XCTAssertEqual(snapshot.origin, .estimated)
        XCTAssertEqual(snapshot.bpm, 126)
        XCTAssertEqual(snapshot.confidence, 0.8)
        XCTAssertEqual(snapshot.periodNanoseconds, UInt64((60e9 / 126).rounded()))
        XCTAssertEqual(snapshot.anchorNanoseconds, ms(100))
    }

    func testLowConfidenceOrOutOfRangeEstimateIsNone() {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 126, confidence: 0.49, beatNanoseconds: nil))
        XCTAssertEqual(source.snapshot, .none, "below ANL-005's 0.5 (SHOW-011-R9)")
        source.updateEstimate(TempoEstimate(bpm: 240, confidence: 0.9, beatNanoseconds: nil))
        XCTAssertEqual(source.snapshot, .none)
        source.updateEstimate(TempoEstimate(bpm: 126, confidence: 0.5, beatNanoseconds: nil))
        XCTAssertEqual(source.snapshot.origin, .estimated)
        XCTAssertNil(source.snapshot.anchorNanoseconds, "a tempo without a beat yet has no phase")
        XCTAssertNil(source.snapshot.nextBeat(atOrAfter: ms(0)))
    }

    func testEstimateNeverOverridesManual() {
        var source = TempoSource()
        manual120(&source)
        source.updateEstimate(TempoEstimate(bpm: 90, confidence: 1, beatNanoseconds: ms(0)))
        XCTAssertEqual(source.snapshot.origin, .manual)
        XCTAssertEqual(source.snapshot.bpm, 120)
    }

    func testResetReturnsToTheEstimate() {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 126, confidence: 0.9, beatNanoseconds: ms(40)))
        let estimated = source.snapshot
        manual120(&source)
        XCTAssertEqual(source.snapshot.origin, .manual)
        source.resetManual()
        XCTAssertEqual(source.snapshot, estimated, "reset returns to the estimated state (SHOW-011-S4)")
        XCTAssertFalse(source.hasManualTempo)
    }

    func testResetWithoutEstimateIsNoneAndClearsTheSequence() {
        var source = TempoSource()
        manual120(&source)
        source.resetManual()
        XCTAssertEqual(source.snapshot, .none)
        XCTAssertEqual(source.tapsInSequence, 0)
        XCTAssertEqual(source.tap(at: ms(1_700)), .counting(taps: 1, of: 4), "old taps do not count")
    }

    func testNextBeatFollowsTheTappedGrid() throws {
        var source = TempoSource()
        manual120(&source)   // anchor at 1,500 ms, period 500 ms
        let snapshot = source.snapshot
        XCTAssertEqual(snapshot.nextBeat(atOrAfter: ms(1_500)), ms(1_500))
        XCTAssertEqual(snapshot.nextBeat(atOrAfter: ms(1_501)), ms(2_000))
        XCTAssertEqual(snapshot.nextBeat(atOrAfter: ms(3_250)), ms(3_500))
        XCTAssertEqual(snapshot.nextBeat(atOrAfter: ms(700)), ms(1_000), "before the anchor too")
        XCTAssertEqual(try XCTUnwrap(snapshot.beatPhase(at: ms(1_750))), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(snapshot.beatPhase(at: ms(1_500))), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(snapshot.beatPhase(at: ms(1_250))), 0.5, accuracy: 1e-9)
    }

    func testEstimatedBeatsFollowTheAnalysis() {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: ms(30)))
        XCTAssertEqual(source.snapshot.nextBeat(atOrAfter: ms(100)), ms(530))
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        var source = TempoSource()
        manual120(&source)
        for snapshot in [source.snapshot, TempoSnapshot.none] {
            let data = try JSONEncoder().encode(snapshot)
            XCTAssertEqual(try JSONDecoder().decode(TempoSnapshot.self, from: data), snapshot)
        }
        let rules = try JSONDecoder().decode(TapTempoRules.self, from: JSONEncoder().encode(TapTempoRules.standard))
        XCTAssertEqual(rules, .standard)
    }
}
