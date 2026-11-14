// SteppedLFOTests.swift — MOD-008-T03, T05, T06, T08: square and sample-and-hold oscillators with seeded steps
// (MOD-008-R1 to R8; specs/212-mod-008-stepped-lfo, research MOD-008-D1 to D6, contract S1 to S7).
//
// The acceptance ("Same seed and timebase yield identical step values"): two banks with the same settings, seed and
// origin, driven with 60 Hz, 120 Hz and jittery frame times, hold exactly the same level (==) at every step, and that
// level is the counter-based `SteppedRandom.level(seed:step:)`; a different seed differs. Frame times are integer
// nanoseconds passed in; no clock, no sleep.
import Foundation
import ParameterGraph
import XCTest

final class SteppedLFOTests: XCTestCase {
    private static let second: UInt64 = 1_000_000_000
    private static let origin: UInt64 = 3 * second

    /// Frame times from the origin to `origin + duration` with gaps from `gap(index)`.
    private static func frames(duration: UInt64, gap: (Int) -> UInt64) -> [UInt64] {
        var times: [UInt64] = []
        var t: UInt64 = origin
        var index = 0
        while t <= origin + duration {
            times.append(t)
            t += gap(index)
            index += 1
        }
        return times
    }

    /// Deterministic irregular gaps of 1…40 ms (a fixed linear congruential sequence).
    private static func jitteryGaps() -> (Int) -> UInt64 {
        var state: UInt64 = 0x1234_5678
        return { (_: Int) -> UInt64 in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return 1_000_000 + (state >> 33) % 39_000_000
        }
    }

    /// Slot 0 of a fresh bank holding `lfos`, sampled at every frame time.
    private static func run(_ lfos: [LFO?], times: [UInt64], slot: Int = 0, tempo: (UInt64) -> Double? = { _ in nil },
                            cap: Double = .infinity) throws -> [Double] {
        let bank = LFOBank()
        try bank.set(lfos)
        var out: [Double] = Array(repeating: -1, count: LFOBank.maximumOscillators)
        var values: [Double] = []
        for t in times {
            out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Double>) -> Void in
                bank.values(atNanoseconds: t, tempoBPM: tempo(t), maximumRateHz: cap, into: buffer)
            }
            values.append(out[slot])
        }
        return values
    }

    /// The level each step held, keyed by step number; fails if a step shows two different values (it must hold).
    private func stepLevels(_ lfo: LFO, times: [UInt64], values: [Double], file: StaticString = #filePath,
                            line: UInt = #line) -> [Int64: Double] {
        var levels: [Int64: Double] = [:]
        for (t, v) in zip(times, values) {
            let step: Int64 = lfo.cycle(elapsedNanoseconds: t - Self.origin, rateHz: lfo.rateHz).step
            if let held = levels[step] {
                XCTAssertEqual(held, v, "step \(step) holds one level", file: file, line: line)
            } else {
                levels[step] = v
            }
        }
        return levels
    }

    // MARK: Acceptance (MOD-008-S1)

    func testSameSeedAndTimebaseYieldIdenticalStepValues() throws {
        let lfo = try LFO(shape: .sampleHold, rateHz: 7.3, phaseOffset: 0.3, seed: 424_242)
        let duration: UInt64 = 20 * Self.second   // 146 steps
        let at60 = Self.frames(duration: duration) { (_: Int) -> UInt64 in 16_666_667 }
        let at120 = Self.frames(duration: duration) { (_: Int) -> UInt64 in 8_333_333 }
        let jittery = Self.frames(duration: duration, gap: Self.jitteryGaps())
        let a = stepLevels(lfo, times: at60, values: try Self.run([lfo], times: at60))
        let b = stepLevels(lfo, times: at120, values: try Self.run([lfo], times: at120))
        let c = stepLevels(lfo, times: jittery, values: try Self.run([lfo], times: jittery))
        XCTAssertGreaterThanOrEqual(a.count, 140, "60 Hz sees every step")
        XCTAssertEqual(a, b, "60 Hz and 120 Hz hold identical levels at every step")
        var compared = 0
        for (step, level) in c {
            XCTAssertEqual(level, a[step], "jittery frames hold the identical level at step \(step)")
            compared += 1
        }
        XCTAssertGreaterThanOrEqual(compared, 100)
        for (step, level) in a {
            XCTAssertEqual(level, 0.5 + (SteppedRandom.level(seed: 424_242, step: step) - 0.5),
                           "the level depends only on (seed, step)")
        }
        XCTAssertGreaterThan(Set(a.values).count, 130, "the levels vary")

        let other = try LFO(shape: .sampleHold, rateHz: 7.3, phaseOffset: 0.3, seed: 424_243)
        let d = stepLevels(other, times: at60, values: try Self.run([other], times: at60))
        let differing: Int = a.keys.filter { (step: Int64) -> Bool in a[step] != d[step] }.count
        XCTAssertGreaterThan(differing, 130, "a different seed gives a different sequence")
    }

    func testUnseededSlotsDifferAndRepeat() throws {
        let lfo = try LFO(shape: .sampleHold, rateHz: 4)
        XCTAssertNil(lfo.seed)
        let times = Self.frames(duration: 5 * Self.second) { (_: Int) -> UInt64 in 16_666_667 }
        let slot0 = try Self.run([lfo, lfo], times: times, slot: 0)
        let slot1 = try Self.run([lfo, lfo], times: times, slot: 1)
        XCTAssertNotEqual(slot0, slot1, "unseeded oscillators at different positions do not move in lockstep")
        XCTAssertEqual(slot0, try Self.run([lfo, lfo], times: times, slot: 0), "and every run repeats")
        XCTAssertEqual(lfo.effectiveSeed(slot: 1), SteppedRandom.defaultSeed(slot: 1))
        XCTAssertGreaterThan(SteppedRandom.defaultSeed(slot: 0), UInt64(UInt32.max), "never equal to a stored seed")
        let seeded = try LFO(shape: .sampleHold, rateHz: 4, seed: 9)
        XCTAssertEqual(seeded.effectiveSeed(slot: 5), 9)
    }

    func testStepNumberIsExactAfterHours() throws {
        let lfo = try LFO(shape: .sampleHold, rateHz: 2, phaseOffset: 0.25, seed: 1)
        let tenHours: UInt64 = 36_000 * Self.second
        let before = lfo.cycle(elapsedNanoseconds: tenHours + 375_000_000 - 1, rateHz: 2)
        XCTAssertEqual(before.step, 72_000)
        let at = lfo.cycle(elapsedNanoseconds: tenHours + 375_000_000, rateHz: 2)
        XCTAssertEqual(at.step, 72_001, "0.25 + 2 × 36000.375 = 72001 cycles exactly: the boundary is the new step")
        XCTAssertEqual(at.phase, 0)
        XCTAssertEqual(lfo.cycle(elapsedNanoseconds: 0, rateHz: 2), LFOCycle(step: 0, phase: 0.25))
        XCTAssertEqual(lfo.value(elapsedNanoseconds: tenHours + 375_000_000),
                       SteppedRandom.level(seed: 1, step: 72_001))
    }

    func testLevelsAreUnitIntervalAndAmplitudeScaled() throws {
        for step: Int64 in [-1, 0, 1, 1_000_000, .max] {
            let l = SteppedRandom.level(seed: 7, step: step)
            XCTAssertTrue(l >= 0 && l < 1)
        }
        let narrow = try LFO(shape: .sampleHold, rateHz: 1, amplitude: 0.2, center: 0.9, seed: 3)
        for k: UInt64 in 0..<50 {
            let v = narrow.value(elapsedNanoseconds: k * Self.second)
            let expected: Double = min(max(0.9 + 0.2 * (SteppedRandom.level(seed: 3, step: Int64(k)) - 0.5), 0), 1)
            XCTAssertEqual(v, expected)
            XCTAssertTrue(v >= 0.8 - 1e-12 && v <= 1)
        }
    }

    // MARK: Glide (MOD-008-R6, T05)

    func testGlideRampsFromThePreviousLevel() throws {
        let lfo = try LFO(shape: .sampleHold, rateHz: 1, seed: 77, glide: 0.5)
        let previous = SteppedRandom.level(seed: 77, step: 3)
        let current = SteppedRandom.level(seed: 77, step: 4)
        XCTAssertEqual(lfo.value(elapsedNanoseconds: 4 * Self.second), previous, accuracy: 1e-12, "a step starts at the old level")
        XCTAssertEqual(lfo.value(elapsedNanoseconds: 4 * Self.second + 250_000_000), (previous + current) / 2, accuracy: 1e-12,
                       "halfway through the glide")
        XCTAssertEqual(lfo.value(elapsedNanoseconds: 4 * Self.second + 500_000_000), current, accuracy: 1e-12, "glide done")
        XCTAssertEqual(lfo.value(elapsedNanoseconds: 4 * Self.second + 900_000_000), current, "then it holds")
        for bad: Double in [-0.1, 1.1, .nan, .infinity] {
            XCTAssertThrowsError(try LFO(shape: .sampleHold, rateHz: 1, glide: bad), "glide \(bad)")
        }
        XCTAssertNoThrow(try LFO(shape: .sampleHold, rateHz: 1, glide: 1))
    }

    // MARK: Square (MOD-008-S2, T06)

    func testSquareTransitionsLandExactlyAtDutyBoundaries() throws {
        for duty: Double in [0.25, 0.5, 0.8] {
            let square = try LFO(shape: .square, rateHz: 1, dutyCycle: duty)
            let boundary = UInt64((duty * 1e9).rounded())
            for cycle: UInt64 in [0, 7, 3_600] {
                let start: UInt64 = cycle * Self.second
                XCTAssertEqual(square.value(elapsedNanoseconds: start), 1, "duty \(duty): high at the cycle start")
                XCTAssertEqual(square.value(elapsedNanoseconds: start + boundary - 1), 1, "duty \(duty): high just before")
                XCTAssertEqual(square.value(elapsedNanoseconds: start + boundary), 0, "duty \(duty): low at the boundary")
                XCTAssertEqual(square.value(elapsedNanoseconds: start + Self.second - 1), 0, "duty \(duty): low at the end")
            }
        }
        let half = try LFO(shape: .square, rateHz: 2)
        XCTAssertEqual(half.dutyCycle, 0.5)
        var high = 0
        for ms: UInt64 in 0..<1_000 where half.value(elapsedNanoseconds: ms * 1_000_000) == 1 { high += 1 }
        XCTAssertEqual(high, 500, "the default duty is high for exactly half of each cycle")
        let soft = try LFO(shape: .square, rateHz: 1, amplitude: 0.4, center: 0.5)
        XCTAssertEqual(soft.value(elapsedNanoseconds: 0), 0.7, accuracy: 1e-12)
        XCTAssertEqual(soft.value(elapsedNanoseconds: 600_000_000), 0.3, accuracy: 1e-12)
        for bad: Double in [0.04, 0.96, 0, 1, .nan] {
            XCTAssertThrowsError(try LFO(shape: .square, rateHz: 1, dutyCycle: bad), "duty \(bad)")
        }
        XCTAssertEqual(LFOShape(rawValue: "square"), .square)
        XCTAssertEqual(LFOShape(rawValue: "sampleHold"), .sampleHold)
    }

    // MARK: Tempo sync and Reduce flashing (MOD-008-R7, R8, T08)

    func testSyncedStepsContinueAcrossATempoChange() throws {
        let lfo = try LFO(shape: .sampleHold, rateHz: 0.5, sync: LFOSync(beatsPerCycle: 1), seed: 31)
        let times = Self.frames(duration: 6 * Self.second) { (_: Int) -> UInt64 in 16_666_667 }
        let change: UInt64 = Self.origin + 3 * Self.second + 100_000_000   // mid-step at 120 BPM
        let values = try Self.run([lfo], times: times) { (t: UInt64) -> Double? in t < change ? 120 : 90 }
        var held: [Double] = []
        for v in values where held.last != v { held.append(v) }
        let expected: [Double] = (0..<Int64(held.count)).map { (n: Int64) -> Double in SteppedRandom.level(seed: 31, step: n) }
        XCTAssertEqual(held, expected, "consecutive steps, no restart and no repeated level across 120 → 90 BPM")
        XCTAssertEqual(held.count, 11, "6 steps at 2 Hz (to 3.1 s), then 1.5 Hz: 3.1 s × 2 + 2.9 s × 1.5 = 10.55 → steps 0…10")
    }

    func testReduceFlashingCapsSteppedShapes() throws {
        let times = Self.frames(duration: Self.second - 1) { (_: Int) -> UInt64 in 1_000_000 }
        let hold = try LFO(shape: .sampleHold, rateHz: 20, seed: 5)
        let square = try LFO(shape: .square, rateHz: 20)
        func changes(_ values: [Double]) -> Int {
            zip(values, values.dropFirst()).filter { (pair: (Double, Double)) -> Bool in pair.0 != pair.1 }.count
        }
        XCTAssertGreaterThanOrEqual(changes(try Self.run([hold], times: times)), 18, "uncapped: about 20 steps in 1 s")
        XCTAssertLessThanOrEqual(changes(try Self.run([hold], times: times, cap: LFOBank.reduceFlashingMaximumRateHz)), 3,
                                 "capped: at most 3 steps per second")
        XCTAssertLessThanOrEqual(changes(try Self.run([square], times: times, cap: LFOBank.reduceFlashingMaximumRateHz)), 6,
                                 "capped: at most 3 square cycles (6 edges) per second")
    }
}
