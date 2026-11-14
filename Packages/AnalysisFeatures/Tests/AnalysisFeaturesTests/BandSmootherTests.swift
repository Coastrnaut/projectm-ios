// BandSmootherTests.swift — ANL-003-T02: the roadmap acceptance "Step input reaches 90 percent by
// attack setting and decays by release setting" (ANL-003-R3 to R5, R7; S1 to S3; contract C1).
// Frame intervals are injected (60 fps, 120 fps and a seeded jittery 8-25 ms sequence); nothing
// reads a clock. Representative cases only (owner rule 7).
import Foundation
import XCTest
@testable import AnalysisFeatures

/// A deterministic frame-interval source.
private struct FrameClock {
    enum Kind { case fixed(Double), jitter(seed: UInt64) }
    let kind: Kind
    private var state: UInt64

    init(_ kind: Kind) {
        self.kind = kind
        if case .jitter(let seed) = kind { state = seed } else { state = 0 }
    }

    /// The next interval in seconds (jitter: uniform 8…25 ms from a 64-bit LCG).
    mutating func next() -> Double {
        switch kind {
        case .fixed(let interval):
            return interval
        case .jitter:
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let top: UInt64 = state >> 11
            let unit: Double = Double(top) / Double(UInt64(1) << 53)
            let span: Double = 0.025 - 0.008
            return 0.008 + unit * span
        }
    }

    var name: String {
        switch kind {
        case .fixed(let interval): return "\(Int((1 / interval).rounded())) fps"
        case .jitter: return "jitter 8-25 ms"
        }
    }
}

/// The first frame at which a step's output passed 90 % of the way.
private struct Crossing {
    let time: Double       // seconds since the step, at the end of the crossing frame
    let interval: Double   // that frame's interval
}

final class BandSmootherTests: XCTestCase {
    private static let clocks: [FrameClock.Kind] = [.fixed(1.0 / 60.0), .fixed(1.0 / 120.0), .jitter(seed: 0x5EED)]
    /// Float state: a crossing exactly at τ may land a hair short of 0.9.
    private static let valueTolerance: Float = 1e-5
    private static let timeTolerance = 1e-9

    /// Primes band 0 at `from`, then holds `to` until the output covers 90 % of the step.
    private func crossing(from: Float, to: Float, times: SmoothingTimes, clock kind: FrameClock.Kind) -> Crossing? {
        let smoother = BandSmoother(times: times)
        var target: Float = from
        _ = smoother.update(target: &target, count: 1, frameInterval: 1.0 / 60.0, generation: 1)
        target = to
        var clock = FrameClock(kind)
        let goal: Float = from + 0.9 * (to - from)
        var elapsed = 0.0
        for _ in 0..<2_000 {
            let interval = clock.next()
            elapsed += interval
            let output: Float = smoother.update(target: &target, count: 1, frameInterval: interval, generation: 1)[0]
            let passed: Bool = to > from ? output >= goal - Self.valueTolerance : output <= goal + Self.valueTolerance
            if passed { return Crossing(time: elapsed, interval: interval) }
        }
        return nil
    }

    private func assertCrossing(from: Float, to: Float, timeConstant: Double, times: SmoothingTimes,
                                file: StaticString = #filePath, line: UInt = #line) {
        for kind in Self.clocks {
            let name = FrameClock(kind).name
            guard let c = crossing(from: from, to: to, times: times, clock: kind) else {
                XCTFail("no 90 % crossing (\(name))", file: file, line: line)
                continue
            }
            let lower: Double = timeConstant - Self.timeTolerance
            let upper: Double = timeConstant + c.interval + Self.timeTolerance
            XCTAssertGreaterThanOrEqual(c.time, lower, "crossed before τ = \(timeConstant) s (\(name))", file: file, line: line)
            XCTAssertLessThan(c.time, upper, "crossed more than one frame after τ = \(timeConstant) s (\(name))",
                              file: file, line: line)
            let milliseconds: Double = c.time * 1_000
            print("ANL-003 crossing: \(from)→\(to), τ \(Int(timeConstant * 1_000)) ms, \(name): \(String(format: "%.2f", milliseconds)) ms")
        }
    }

    // MARK: Acceptance (ANL-003-S1)

    func testStepUpReachesNinetyPercentAtTheAttackTime() {
        for attack in [0.025, 0.1] {
            assertCrossing(from: 0, to: 1, timeConstant: attack, times: SmoothingTimes(attackSeconds: attack, releaseSeconds: 0.5))
        }
    }

    func testStepDownDecaysNinetyPercentAtTheReleaseTime() {
        for release in [0.1, 0.5] {
            assertCrossing(from: 1, to: 0, timeConstant: release, times: SmoothingTimes(attackSeconds: 0.025, releaseSeconds: release))
        }
    }

    func testPartialStepsScaleWithTheirSize() {
        // A step from 0.2 to 0.7 covers 90 % of its own distance at τ, like a full step.
        assertCrossing(from: 0.2, to: 0.7, timeConstant: 0.05, times: SmoothingTimes(attackSeconds: 0.05, releaseSeconds: 0))
        assertCrossing(from: 0.7, to: 0.2, timeConstant: 0.25, times: SmoothingTimes(attackSeconds: 0, releaseSeconds: 0.25))
    }

    // MARK: Independence, instant, resets (ANL-003-S2, S3)

    func testBandsRiseAndFallIndependently() {
        let smoother = BandSmoother(times: SmoothingTimes(attackSeconds: 0.025, releaseSeconds: 0.5))
        var values: [Float] = [0, 1, 0.5]
        _ = values.withUnsafeBufferPointer { smoother.update(target: $0.baseAddress!, count: 3, frameInterval: 0.01, generation: 7) }
        values = [1, 0, 0.5]
        var output: [Float] = []
        for _ in 0..<3 {   // 25 ms at 120 fps (3 × 8.33 ms)
            output = values.withUnsafeBufferPointer {
                Array(smoother.update(target: $0.baseAddress!, count: 3, frameInterval: 1.0 / 120.0, generation: 7))
            }
        }
        XCTAssertEqual(output[0], 0.9, accuracy: 1e-4, "band 0 follows the 25 ms attack")
        let expectedFall: Double = exp(log(0.1) * 0.025 / 0.5)   // still 89 % of the way up after 25 ms
        XCTAssertEqual(Double(output[1]), expectedFall, accuracy: 1e-4, "band 1 follows the 500 ms release")
        XCTAssertEqual(output[2], 0.5, "a steady band stays put")
    }

    func testInstantTimesCopyTheInputExactly() {
        let smoother = BandSmoother()
        XCTAssertTrue(smoother.times.isInstant, "Instant by default (today's look)")
        var rng: UInt64 = 42
        var input = [Float](repeating: 0, count: 64)
        for frame in 0..<50 {
            for i in 0..<64 {
                rng = rng &* 6_364_136_223_846_793_005 &+ 1
                let unit: Float = Float(rng >> 40) / Float(1 << 24)
                input[i] = unit
            }
            let interval: Double = frame % 2 == 0 ? 1.0 / 60.0 : 0.013
            let output: [Float] = input.withUnsafeBufferPointer {
                Array(smoother.update(target: $0.baseAddress!, count: 64, frameInterval: interval, generation: 1))
            }
            XCTAssertEqual(output, input, "frame \(frame)")
        }
        // Instant even with a zero or invalid interval.
        let zero: [Float] = input.withUnsafeBufferPointer { Array(smoother.update(target: $0.baseAddress!, count: 64, frameInterval: 0, generation: 1)) }
        XCTAssertEqual(zero, input)
    }

    func testFirstUpdateResetGenerationAndCountChangesTakeTheInputDirectly() {
        let smoother = BandSmoother(times: SmoothingTimes(attackSeconds: 0.5, releaseSeconds: 0.5))
        var one: [Float] = [0.8, 0.4]
        func run(_ count: Int, _ generation: UInt64) -> [Float] {
            one.withUnsafeBufferPointer { Array(smoother.update(target: $0.baseAddress!, count: count, frameInterval: 1.0 / 60.0, generation: generation)) }
        }
        XCTAssertEqual(run(2, 1), [0.8, 0.4], "first update: no ramp from zero")
        one = [0, 0]
        XCTAssertGreaterThan(run(2, 1)[0], 0.7, "then it smooths")
        XCTAssertEqual(run(2, 2), [0, 0], "a new capture session snaps")
        one = [1, 1]
        XCTAssertEqual(run(1, 2), [1], "a band-count change snaps")
        one = [0.3, 0.3]
        smoother.reset()
        XCTAssertEqual(run(2, 2), [0.3, 0.3], "reset snaps")
    }

    func testChangingTimesMidRunDoesNotSnap() {
        let smoother = BandSmoother(times: SmoothingTimes(attackSeconds: 0, releaseSeconds: 0.5))
        var value: Float = 1
        _ = smoother.update(target: &value, count: 1, frameInterval: 0.01, generation: 1)
        value = 0
        let before: Float = smoother.update(target: &value, count: 1, frameInterval: 0.01, generation: 1)[0]
        smoother.times = SmoothingTimes(attackSeconds: 0, releaseSeconds: 0.1)
        let after: Float = smoother.update(target: &value, count: 1, frameInterval: 0.01, generation: 1)[0]
        XCTAssertGreaterThan(before, 0.9)
        let expected: Double = Double(before) * exp(log(0.1) * 0.01 / 0.1)
        XCTAssertEqual(Double(after), expected, accuracy: 1e-5, "continues from the current value with the new time")
    }

    // MARK: Invalid input and bounds (ANL-003-R5, R7)

    func testNonFiniteInputHoldsAndInvalidIntervalsMakeNoProgress() {
        let smoother = BandSmoother(times: SmoothingTimes(attackSeconds: 0.1, releaseSeconds: 0.1))
        var values: [Float] = [.nan, 0.5, .infinity]
        let first: [Float] = values.withUnsafeBufferPointer { Array(smoother.update(target: $0.baseAddress!, count: 3, frameInterval: 0.01, generation: 1)) }
        XCTAssertEqual(first, [0, 0.5, 0], "non-finite bands start at 0")
        values = [1, -.infinity, .nan]
        let second: [Float] = values.withUnsafeBufferPointer { Array(smoother.update(target: $0.baseAddress!, count: 3, frameInterval: 0.01, generation: 1)) }
        XCTAssertGreaterThan(second[0], 0)
        XCTAssertEqual(second[1], 0.5, "a non-finite band holds")
        XCTAssertEqual(second[2], 0, "a non-finite band holds")
        values = [0, 0, 0]
        for interval in [0.0, -0.01, Double.nan, Double.infinity] {
            let held: [Float] = values.withUnsafeBufferPointer { Array(smoother.update(target: $0.baseAddress!, count: 3, frameInterval: interval, generation: 1)) }
            XCTAssertEqual(held, second, "interval \(interval): no progress")
        }
        XCTAssertEqual(BandSmoother.capacity, 128)
    }

    func testTimesAreClampedAndCoefficientsFollowTheRule() {
        XCTAssertEqual(SmoothingTimes(attackSeconds: -1, releaseSeconds: 9).attackSeconds, 0)
        XCTAssertEqual(SmoothingTimes(attackSeconds: -1, releaseSeconds: 9).releaseSeconds, 2)
        XCTAssertEqual(SmoothingTimes(attackSeconds: .nan, releaseSeconds: .infinity), SmoothingTimes(attackSeconds: 0, releaseSeconds: 2))
        XCTAssertEqual(SmoothingTimes.instant, SmoothingTimes(attackSeconds: 0, releaseSeconds: 0))
        XCTAssertEqual(SmoothingTimes.coefficient(timeConstant: 0, frameInterval: 0.01), 1)
        XCTAssertEqual(SmoothingTimes.coefficient(timeConstant: 0.1, frameInterval: 0.1), 0.9, accuracy: 1e-12)
        XCTAssertEqual(SmoothingTimes.coefficient(timeConstant: 0.1, frameInterval: -1), 0)
    }

    func testStorageNeverMovesAndCountIsClamped() {
        let smoother = BandSmoother(times: SmoothingTimes(attackSeconds: 0.05, releaseSeconds: 0.2))
        var input = [Float](repeating: 0.5, count: 200)
        let first = input.withUnsafeBufferPointer { smoother.update(target: $0.baseAddress!, count: 200, frameInterval: 0.01, generation: 1) }
        XCTAssertEqual(first.count, 128, "count clamped to capacity")
        let address = first.baseAddress
        for frame in 0..<1_000 {
            input[frame % 128] = Float(frame % 7) / 7
            let output = input.withUnsafeBufferPointer { smoother.update(target: $0.baseAddress!, count: 128, frameInterval: 0.008, generation: 1) }
            XCTAssertEqual(output.baseAddress, address)
        }
        let none = input.withUnsafeBufferPointer { smoother.update(target: $0.baseAddress!, count: -3, frameInterval: 0.01, generation: 1) }
        XCTAssertEqual(none.count, 0)
    }
}
