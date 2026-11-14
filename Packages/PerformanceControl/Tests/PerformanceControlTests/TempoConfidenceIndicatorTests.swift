// TempoConfidenceIndicatorTests.swift — ANL-006-T02, T05: the searching / uncertain / stable state
// machine on scripted estimates and an injected clock (contract C1; research ANL-006-D3): dwell,
// hysteresis, dips, tempo change, drift, invalid input, backwards time, no flicker, and the
// readout mapping with a manual tempo. No wall clock; every test runs in milliseconds.
import PerformanceControl
import XCTest

final class TempoConfidenceIndicatorTests: XCTestCase {
    private static let poll: UInt64 = 250_000_000          // the app's 250 ms poll
    private static let second: UInt64 = 1_000_000_000

    /// Feeds one estimate per poll for `polls` polls starting at `time`; returns the next time.
    @discardableResult
    private func feed(_ indicator: inout TempoConfidenceIndicator, bpm: Double?, confidence: Double,
                      polls: Int, from time: UInt64) -> UInt64 {
        var now: UInt64 = time
        for _ in 0..<polls {
            let estimate: TempoEstimate? = bpm.map { (value: Double) -> TempoEstimate in
                TempoEstimate(bpm: value, confidence: confidence, beatNanoseconds: nil)
            }
            indicator.update(estimate, at: now)
            now += Self.poll
        }
        return now
    }

    /// Stable at 120 BPM; returns the next time.
    private func makeStable(_ indicator: inout TempoConfidenceIndicator, bpm: Double = 120) -> UInt64 {
        let next = feed(&indicator, bpm: bpm, confidence: 0.9, polls: 9, from: Self.second)
        XCTAssertEqual(indicator.state, .stable)
        return next
    }

    func testStandardRules() {
        let rules = TempoConfidenceRules.standard
        XCTAssertEqual(rules.enterConfidence, 0.7)
        XCTAssertEqual(rules.exitConfidence, 0.5)
        XCTAssertEqual(rules.enterDwellNanoseconds, 2 * Self.second)
        XCTAssertEqual(rules.exitDwellNanoseconds, Self.second)
        XCTAssertEqual(rules.reacquireNanoseconds, 3 * Self.second)
        XCTAssertEqual(rules.bpmTolerance, 0.03)
        XCTAssertGreaterThanOrEqual(rules.exitConfidence, 0.5, "never below ANL-005's high level (ANL-006-R5)")
    }

    func testStartsSearchingAndAFirstEstimateIsUncertain() {
        var indicator = TempoConfidenceIndicator()
        XCTAssertEqual(indicator.state, .searching)
        XCTAssertNil(indicator.bpm)
        XCTAssertEqual(indicator.confidence, 0)
        indicator.update(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil), at: Self.second)
        XCTAssertEqual(indicator.state, .uncertain)
        XCTAssertEqual(indicator.bpm, 120)
        XCTAssertEqual(indicator.confidence, 0.9)
    }

    func testStableNeedsTheEnterDwell() {
        var indicator = TempoConfidenceIndicator()
        // Polls at 0, 0.25 … 1.75 s after the first: 8 polls, 1.75 s of run.
        let next = feed(&indicator, bpm: 120, confidence: 0.9, polls: 8, from: Self.second)
        XCTAssertEqual(indicator.state, .uncertain, "1.75 s is not enough")
        feed(&indicator, bpm: 120, confidence: 0.9, polls: 1, from: next)
        XCTAssertEqual(indicator.state, .stable, "2.0 s is")
        XCTAssertEqual(indicator.bpm, 120)
        XCTAssertEqual(indicator.stateChanges, 2)   // searching → uncertain → stable
    }

    func testConfidenceBetweenTheThresholdsHoldsButNeverEnters() {
        var never = TempoConfidenceIndicator()
        feed(&never, bpm: 120, confidence: 0.69, polls: 200, from: Self.second)
        XCTAssertEqual(never.state, .uncertain)

        var held = TempoConfidenceIndicator()
        let next = makeStable(&held)
        feed(&held, bpm: 120, confidence: 0.5, polls: 200, from: next)
        XCTAssertEqual(held.state, .stable, "0.5 is not below the exit threshold")
    }

    func testShortDipsStayStableAndALongDipIsUncertain() {
        var indicator = TempoConfidenceIndicator()
        var now = makeStable(&indicator)
        now = feed(&indicator, bpm: 120, confidence: 0.3, polls: 4, from: now)     // 0.75 s below exit
        XCTAssertEqual(indicator.state, .stable)
        now = feed(&indicator, bpm: 120, confidence: 0.9, polls: 1, from: now)     // recovers: timer cleared
        now = feed(&indicator, bpm: 120, confidence: 0.3, polls: 4, from: now)
        XCTAssertEqual(indicator.state, .stable)
        feed(&indicator, bpm: 120, confidence: 0.3, polls: 1, from: now)           // 1.0 s of the new dip
        XCTAssertEqual(indicator.state, .uncertain)
        XCTAssertEqual(indicator.bpm, 120, "uncertain still shows the estimate")
    }

    func testATempoChangeReacquiresThroughSearching() {
        var indicator = TempoConfidenceIndicator()
        var now = makeStable(&indicator)
        now = feed(&indicator, bpm: 90, confidence: 0.4, polls: 4, from: now)
        XCTAssertEqual(indicator.state, .stable, "within the exit dwell")
        XCTAssertEqual(indicator.bpm, 120, "the new tempo is never shown as stable before it earns it")
        now = feed(&indicator, bpm: 90, confidence: 0.4, polls: 1, from: now)
        XCTAssertEqual(indicator.state, .searching, "a departure is a tempo change")
        XCTAssertNil(indicator.bpm, "no number while searching")
        // Still weak: uncertain once the reacquire time (3 s) has passed.
        now = feed(&indicator, bpm: 90, confidence: 0.4, polls: 11, from: now)     // 2.75 s
        XCTAssertEqual(indicator.state, .searching)
        now = feed(&indicator, bpm: 90, confidence: 0.4, polls: 1, from: now)      // 3.0 s
        XCTAssertEqual(indicator.state, .uncertain)
        XCTAssertEqual(indicator.bpm, 90)
        feed(&indicator, bpm: 90, confidence: 0.9, polls: 9, from: now)
        XCTAssertEqual(indicator.state, .stable)
        XCTAssertEqual(indicator.bpm, 90)
    }

    func testAConfidentNewTempoGoesStraightFromSearchingToStable() {
        var indicator = TempoConfidenceIndicator()
        var now = makeStable(&indicator)
        now = feed(&indicator, bpm: 90, confidence: 0.9, polls: 5, from: now)
        XCTAssertEqual(indicator.state, .searching)
        // The run at 90 started with the departure's last poll: 2 s later it is stable.
        now = feed(&indicator, bpm: 90, confidence: 0.9, polls: 7, from: now)
        XCTAssertEqual(indicator.state, .searching)
        feed(&indicator, bpm: 90, confidence: 0.9, polls: 1, from: now)
        XCTAssertEqual(indicator.state, .stable)
    }

    func testSmallJitterWithinTheToleranceKeepsTheLock() {
        var indicator = TempoConfidenceIndicator()
        var now = makeStable(&indicator)
        for i in 0..<40 {
            let offset: Double = i % 2 == 0 ? 3.4 : -3.4      // ±2.8 % of 120
            now = feed(&indicator, bpm: 120 + offset, confidence: 0.9, polls: 1, from: now)
        }
        XCTAssertEqual(indicator.state, .stable)
        XCTAssertEqual(indicator.stateChanges, 2)
    }

    func testAWanderingTempoRestartsTheDwell() {
        var indicator = TempoConfidenceIndicator()
        var now: UInt64 = Self.second
        var bpm: Double = 100
        for _ in 0..<40 {                       // +2 BPM per poll: never 2 s within 3 % of the run's start
            now = feed(&indicator, bpm: bpm, confidence: 0.9, polls: 1, from: now)
            bpm += 2
        }
        XCTAssertEqual(indicator.state, .uncertain)
    }

    func testInvalidEstimatesAreNoEstimate() {
        let invalid: [TempoEstimate?] = [
            nil,
            TempoEstimate(bpm: .nan, confidence: 0.9, beatNanoseconds: nil),
            TempoEstimate(bpm: 120, confidence: .nan, beatNanoseconds: nil),
            TempoEstimate(bpm: .infinity, confidence: 0.9, beatNanoseconds: nil),
            TempoEstimate(bpm: 40, confidence: 0.9, beatNanoseconds: nil),
            TempoEstimate(bpm: 250, confidence: 0.9, beatNanoseconds: nil),
        ]
        for estimate in invalid {
            var indicator = TempoConfidenceIndicator()
            let now = makeStable(&indicator)
            indicator.update(estimate, at: now)
            XCTAssertEqual(indicator.state, .searching, "\(String(describing: estimate))")
            XCTAssertNil(indicator.bpm)
            XCTAssertEqual(indicator.confidence, 0)
        }
    }

    func testConfidenceIsClampedAndNeverRaised() {
        var indicator = TempoConfidenceIndicator()
        indicator.update(TempoEstimate(bpm: 120, confidence: 1.7, beatNanoseconds: nil), at: Self.second)
        XCTAssertEqual(indicator.confidence, 1)
        indicator.update(TempoEstimate(bpm: 120, confidence: -0.2, beatNanoseconds: nil), at: 2 * Self.second)
        XCTAssertEqual(indicator.confidence, 0)
        indicator.update(TempoEstimate(bpm: 120, confidence: 0.42, beatNanoseconds: nil), at: 3 * Self.second)
        XCTAssertEqual(indicator.confidence, 0.42)
    }

    func testTimeGoingBackwardsAddsNoElapsedTime() {
        var indicator = TempoConfidenceIndicator()
        indicator.update(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil), at: 10 * Self.second)
        for _ in 0..<20 {
            indicator.update(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil), at: Self.second)
        }
        XCTAssertEqual(indicator.state, .uncertain)
    }

    func testResetReturnsToSearching() {
        var indicator = TempoConfidenceIndicator()
        let now = makeStable(&indicator)
        indicator.reset()
        XCTAssertEqual(indicator.state, .searching)
        XCTAssertNil(indicator.bpm)
        XCTAssertEqual(indicator.stateChanges, 3)
        indicator.update(TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: nil), at: now)
        XCTAssertEqual(indicator.state, .uncertain, "the dwell starts again")
    }

    // MARK: - ANL-006-T05: no flicker

    func testBorderlineConfidenceChangesStateAtMostTwice() {
        var indicator = TempoConfidenceIndicator()
        var state: UInt64 = 0x0A6_006
        var now: UInt64 = Self.second
        for _ in 0..<240 {                       // 60 s at 4 Hz
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit: Double = Double(state >> 11) / Double(UInt64(1) << 53)
            let confidence: Double = 0.45 + 0.3 * unit
            now = feed(&indicator, bpm: 120, confidence: confidence, polls: 1, from: now)
        }
        XCTAssertLessThanOrEqual(indicator.stateChanges, 2, "\(indicator.stateChanges) changes")
    }

    func testAlternatingConfidenceAfterStableStaysStable() {
        var indicator = TempoConfidenceIndicator()
        var now = makeStable(&indicator)
        for i in 0..<240 {
            let confidence: Double = i % 2 == 0 ? 0.45 : 0.75
            now = feed(&indicator, bpm: 120, confidence: confidence, polls: 1, from: now)
        }
        XCTAssertEqual(indicator.state, .stable)
        XCTAssertEqual(indicator.stateChanges, 2)
    }

    // MARK: - Readout

    func testReadoutMapping() {
        var indicator = TempoConfidenceIndicator()
        XCTAssertEqual(TempoReadout(snapshot: .none, indicator: indicator), .searching)
        indicator.update(TempoEstimate(bpm: 124.4, confidence: 0.6, beatNanoseconds: nil), at: Self.second)
        XCTAssertEqual(TempoReadout(snapshot: .none, indicator: indicator), .uncertain(bpm: 124.4))
        _ = makeStable(&indicator)
        XCTAssertEqual(TempoReadout(snapshot: .none, indicator: indicator), .stable(bpm: 120))

        var source = TempoSource()
        for i in 0..<4 { source.tap(at: 20 * Self.second + UInt64(i) * 500_000_000) }
        XCTAssertEqual(TempoReadout(snapshot: source.snapshot, indicator: indicator), .manual(bpm: 120),
                       "a manual tempo wins over every analysis state")
        source.resetManual()
        XCTAssertEqual(TempoReadout(snapshot: source.snapshot, indicator: indicator), .stable(bpm: 120),
                       "reset shows the analysis's current state at once")
    }
}
