// BeatGridTests.swift — SHOW-010-T03: the roadmap acceptance "120 BPM test renders beat ticks every half second"
// (SHOW-010-S1 to S3; contracts/beat-grid.md G1 to G4). Integer-nanosecond exact; no clock.
import Foundation
import ShowControl
import XCTest

final class BeatGridTests: XCTestCase {
    static let halfSecond: Int64 = 500_000_000

    private func tempo(bpm: Double = 120, anchor: Int64 = 0, source: BeatGridTempo.Source = .manual) -> BeatGridTempo {
        let period = Int64((60e9 / bpm).rounded())
        return BeatGridTempo(bpm: bpm, periodNanoseconds: period, anchorNanoseconds: anchor, source: source)!
    }

    // MARK: - S1

    func testAt120BPMBeatTicksAreExactlyHalfASecondApartAndBarsTwoSeconds() {
        let ticks: [BeatGridTick] = BeatGrid.ticks(tempo(), from: .zero, to: .seconds(10))
        XCTAssertEqual(ticks.count, 21, "0, 0.5 … 10 s")
        XCTAssertEqual(ticks.first?.nanoseconds, 0)
        XCTAssertEqual(ticks.last?.time, .seconds(10))
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            XCTAssertEqual(b.nanoseconds - a.nanoseconds, Self.halfSecond, "every pair exactly 500,000,000 ns apart")
        }
        XCTAssertEqual(ticks.map(\.nanoseconds), (0...20).map { (i: Int64) -> Int64 in i * Self.halfSecond })
        let bars: [Int64] = ticks.filter(\.isBar).map(\.nanoseconds)
        XCTAssertEqual(bars, [0, 2, 4, 6, 8, 10].map { (s: Int64) -> Int64 in s * 1_000_000_000 }, "bars every 2 s")
    }

    func testAnAnchorOffsetShiftsEveryTick() {
        let shifted: [BeatGridTick] = BeatGrid.ticks(tempo(anchor: 250_000_000), from: .zero, to: .seconds(10))
        XCTAssertEqual(shifted.count, 20, "0.25, 0.75 … 9.75 s")
        XCTAssertEqual(shifted.map(\.nanoseconds), (0..<20).map { (i: Int64) -> Int64 in 250_000_000 + i * Self.halfSecond })
        XCTAssertEqual(shifted.first { (t: BeatGridTick) -> Bool in t.isBar }?.nanoseconds, 250_000_000, "the first bar is on the anchor")
        XCTAssertEqual(shifted.filter(\.isBar).count, 5)
        // An anchor far away (a later beat) gives the same grid.
        let far: [BeatGridTick] = BeatGrid.ticks(tempo(anchor: 250_000_000 + 400 * Self.halfSecond), from: .zero, to: .seconds(10))
        XCTAssertEqual(far.map(\.nanoseconds), shifted.map(\.nanoseconds))
        XCTAssertEqual(far.map(\.isBar), shifted.map(\.isBar), "400 beats = 100 bars: the same bar phase")
    }

    func testAWindowBeforeTheAnchorStillHasBeats() {
        let ticks: [BeatGridTick] = BeatGrid.ticks(tempo(anchor: 5_000_000_000), from: .seconds(1), to: .seconds(3))
        XCTAssertEqual(ticks.map(\.nanoseconds), [1, 1.5, 2, 2.5, 3].map { (s: Double) -> Int64 in Int64(s * 1e9) })
        XCTAssertEqual(ticks.map(\.beat), [-8, -7, -6, -5, -4])
        XCTAssertEqual(ticks.filter(\.isBar).map(\.nanoseconds), [1_000_000_000, 3_000_000_000], "bars 4 beats from the anchor")
    }

    // MARK: - S2

    func testNoTempoGivesNoTicksAndNoMarks() {
        XCTAssertEqual(BeatGrid.ticks(nil, from: .zero, to: .seconds(10)), [])
        XCTAssertEqual(BeatGrid.marks(nil, duration: .seconds(20), width: 300, inset: 14), [])
        XCTAssertNil(BeatGrid.position(nil, at: .seconds(1)))
        XCTAssertEqual(BeatGrid.readoutText(nil, at: .seconds(1)), "No tempo")
        XCTAssertEqual(BeatGrid.accessibilityValue(nil, at: nil), "No tempo")
        XCTAssertNil(BeatGridTempo(bpm: 120, periodNanoseconds: 0, anchorNanoseconds: 0, source: .manual))
        XCTAssertNil(BeatGridTempo(bpm: .nan, periodNanoseconds: 1, anchorNanoseconds: 0, source: .manual))
    }

    func testTheCountIsBoundedAndDecimatesToBars() {
        let fast: BeatGridTempo = tempo(bpm: 300)
        let long: [BeatGridTick] = BeatGrid.ticks(fast, from: .zero, to: .seconds(3600))   // 18,001 beats
        XCTAssertLessThanOrEqual(long.count, BeatGrid.maximumTicks)
        XCTAssertTrue(long.allSatisfy(\.isBar), "decimated ticks are bars")
        XCTAssertGreaterThan(long.count, BeatGrid.maximumTicks / 2, "the smallest stride that fits")
        // A 2:30 show 300 points wide at 120 BPM: beats would be 1 point apart → bars (4 points) are drawn.
        XCTAssertEqual(BeatGrid.stride(tempo(), duration: .seconds(150), width: 300), 4)
        XCTAssertEqual(BeatGrid.stride(tempo(), duration: .seconds(20), width: 300), 1, "7.5 points apart: every beat")
        XCTAssertEqual(BeatGrid.stride(tempo(), duration: .seconds(600), width: 300), 16, "8 beats would be 2 points apart")
    }

    // MARK: - Position and texts

    func testPositionCountsBarsFromZeroAndBeatsOneToFour() {
        XCTAssertEqual(BeatGrid.position(tempo(), at: .milliseconds(4500)), BeatGridPosition(bar: 3, beat: 2))
        XCTAssertEqual(BeatGrid.position(tempo(), at: .zero), BeatGridPosition(bar: 1, beat: 1))
        XCTAssertEqual(BeatGrid.position(tempo(), at: .milliseconds(1999)), BeatGridPosition(bar: 1, beat: 4))
        // Anchor 0.25 s: 0:00 is the last beat of bar 1 (which started at -1.75 s); bar 2 starts at 0.25 s.
        let shifted: BeatGridTempo = tempo(anchor: 250_000_000)
        XCTAssertEqual(BeatGrid.position(shifted, at: .zero), BeatGridPosition(bar: 1, beat: 4))
        XCTAssertEqual(BeatGrid.position(shifted, at: .milliseconds(250)), BeatGridPosition(bar: 2, beat: 1))
        XCTAssertEqual(BeatGrid.nearestBeat(tempo(), to: .milliseconds(1240)), .seconds(1))
        XCTAssertEqual(BeatGrid.nearestBeat(tempo(), to: .milliseconds(1250)), .milliseconds(1500), "a tie goes later")
    }

    func testTexts() {
        XCTAssertEqual(BeatGrid.readoutText(tempo(), at: .milliseconds(4500)), "Bar 3 · Beat 2 · 120 BPM")
        XCTAssertEqual(BeatGrid.readoutText(tempo(), at: nil), "120 BPM")
        XCTAssertEqual(BeatGrid.accessibilityValue(tempo(), at: .milliseconds(4500)), "120 BPM, tap tempo, bar 3 beat 2")
        XCTAssertEqual(BeatGrid.accessibilityValue(tempo(bpm: 127.6, source: .estimated), at: nil), "128 BPM, detected")
    }

    // MARK: - S3 layout

    func testMarksLieAtTheirTimesFractionAcrossTheTrack() {
        let marks: [BeatGridMark] = BeatGrid.marks(tempo(), duration: .seconds(20), width: 300, inset: 14)
        XCTAssertEqual(marks.count, 41, "every beat (7.2 points apart)")
        for (i, mark) in marks.enumerated() {
            let expected: Double = 14 + Double(i) * 0.5 / 20 * 272
            XCTAssertEqual(mark.x, expected, accuracy: 0.01)
            XCTAssertEqual(mark.isBar, i % 4 == 0)
        }
        XCTAssertEqual(marks.last?.x ?? 0, 286, accuracy: 0.01, "the last beat at the end of the track")
    }
}
