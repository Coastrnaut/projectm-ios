// LFOSyncTests.swift — MOD-009-T02, T04: tempo-synced oscillators (MOD-009-R1 to R6; specs/165-mod-009-tempo-lfo,
// research MOD-009-D2, D3, contract T1 to T3).
//
// The acceptance ("At 120 BPM a quarter-note cycle lasts 0.5 seconds"): a 1-beat oscillator at a constant 120 BPM
// repeats every 0.5 s and a 4-beat one every 2.0 s, within 1e-9. Tempo changes are continuous (piecewise phase
// segments). Times and tempos are passed in; no clock, no sleep.
import Foundation
import ParameterGraph
import XCTest

final class LFOSyncTests: XCTestCase {
    private static let tolerance = 1e-9
    private static let second: UInt64 = 1_000_000_000
    private static let frame: UInt64 = 16_666_667   // 60 fps
    private static let origin: UInt64 = 5 * second

    private static func wave(_ shape: LFOShape, _ phi: Double) -> Double {
        switch shape {
        case .sine:
            return sin(2 * Double.pi * phi)
        case .triangle:
            if phi < 0.25 { return 4 * phi }
            if phi < 0.75 { return 2 - 4 * phi }
            return 4 * phi - 4
        case .square, .sampleHold:   // MOD-008: stepped shapes have their own tests (SteppedLFOTests)
            return shape.wave(phi)
        }
    }

    /// The independent closed form at phase `cycles` (any real number of cycles).
    private static func closedForm(_ lfo: LFO, cycles: Double) -> Double {
        let phi: Double = cycles - cycles.rounded(.down)
        let raw: Double = lfo.center + lfo.amplitude / 2 * wave(lfo.shape, phi)
        return min(max(raw, 0), 1)
    }

    private static func seconds(_ ns: UInt64) -> Double { Double(ns) / 1e9 }

    /// One sample of slot 0 of `bank` at `time`.
    private static func sample(_ bank: LFOBank, at time: UInt64, bpm: Double?, cap: Double = .infinity) -> Double {
        var out: [Double] = Array(repeating: -1, count: LFOBank.maximumOscillators)
        out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Double>) -> Void in
            bank.values(atNanoseconds: time, tempoBPM: bpm, maximumRateHz: cap, into: buffer)
        }
        return out[0]
    }

    private static func bank(_ lfo: LFO) throws -> LFOBank {
        let bank = LFOBank()
        try bank.set([lfo])
        return bank
    }

    // MARK: Acceptance (MOD-009-S1)

    func testQuarterNoteCycleAt120BPMLastsHalfASecond() throws {
        let quarter = try LFO(shape: .sine, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 1))
        XCTAssertEqual(quarter.effectiveRateHz(tempoBPM: 120), 2, "120 BPM / 60 / 1 beat = 2 cycles per second")
        let bank = try Self.bank(quarter)
        XCTAssertEqual(Self.sample(bank, at: Self.origin, bpm: 120), 0.5, accuracy: Self.tolerance, "origin: phase 0, centre")
        let starts: [UInt64] = [0, 123_456_789, 2 * Self.second + 7, 3_600 * Self.second + 333_333_333]   // incl. after 1 h
        for start in starts {
            let t = Self.origin + start
            let a = Self.sample(bank, at: t, bpm: 120)
            let b = Self.sample(bank, at: t + Self.second / 2, bpm: 120)
            XCTAssertEqual(a, b, accuracy: Self.tolerance, "one beat at 120 BPM repeats after 0.5 s (start \(start) ns)")
            XCTAssertEqual(a, Self.closedForm(quarter, cycles: 2 * Self.seconds(start)), accuracy: Self.tolerance)
            XCTAssertEqual(Self.sample(bank, at: t + Self.second / 4, bpm: 120) - 0.5, -(a - 0.5), accuracy: Self.tolerance,
                           "0.25 s is half a cycle on")
        }
        XCTAssertEqual(Self.sample(bank, at: Self.origin + Self.second / 8, bpm: 120), 1, accuracy: Self.tolerance,
                       "a quarter of the 0.5 s cycle (0.125 s) is the peak")
        XCTAssertEqual(Self.sample(bank, at: Self.origin + 3 * Self.second / 8, bpm: 120), 0, accuracy: Self.tolerance,
                       "three quarters (0.375 s) is the trough: the cycle is 0.5 s, not shorter")

        let bar = try LFO(shape: .triangle, rateHz: 0.25, phaseOffset: 0.1, sync: LFOSync(beatsPerCycle: 4))
        let barBank = try Self.bank(bar)
        _ = Self.sample(barBank, at: Self.origin, bpm: 120)
        for start: UInt64 in [0, 300_000_001, 7 * Self.second + 1] {
            let t = Self.origin + start
            let a = Self.sample(barBank, at: t, bpm: 120)
            XCTAssertEqual(a, Self.sample(barBank, at: t + 2 * Self.second, bpm: 120), accuracy: Self.tolerance,
                           "four beats at 120 BPM repeat after 2.0 s")
            XCTAssertEqual(a, Self.closedForm(bar, cycles: 0.1 + 0.5 * Self.seconds(start)), accuracy: Self.tolerance)
            let half = Self.sample(barBank, at: t + Self.second, bpm: 120)
            XCTAssertEqual(half - 0.5, -(a - 0.5), accuracy: Self.tolerance, "1.0 s is half a cycle on")
        }
        XCTAssertEqual(bar.value(elapsedNanoseconds: 2 * Self.second, tempoBPM: 120),
                       bar.value(elapsedNanoseconds: 0, tempoBPM: 120), accuracy: Self.tolerance, "pure constant-tempo value")
    }

    func testLengthsAndTempoBounds() throws {
        for beats in [0.25, 0.5, 1, 2, 4, 8] {
            XCTAssertNoThrow(try LFOSync(beatsPerCycle: beats), "\(beats)")
        }
        XCTAssertEqual(LFOSync.allowedBeatsPerCycle, [0.25, 0.5, 1, 2, 4, 8])
        for beats in [0, 0.3, 3, 16, -1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try LFOSync(beatsPerCycle: beats), "\(beats)")
        }
        XCTAssertEqual(LFOSync.usableBPM(300), 240)
        XCTAssertEqual(LFOSync.usableBPM(20), 40)
        XCTAssertEqual(LFOSync.usableBPM(97.5), 97.5)
        for bad: Double? in [nil, 0, -1, .nan, .infinity] { XCTAssertNil(LFOSync.usableBPM(bad), "\(String(describing: bad))") }
        let fastest = try LFOSync(beatsPerCycle: 0.25)
        let slowest = try LFOSync(beatsPerCycle: 8)
        XCTAssertEqual(fastest.rateHz(bpm: 240), 16, accuracy: 1e-12)
        XCTAssertEqual(slowest.rateHz(bpm: 40), 40.0 / 480, accuracy: 1e-12)
        XCTAssertEqual(fastest.rateHz(bpm: 1000), 16, accuracy: 1e-12, "clamped to 240 BPM")
        let lfo = try LFO(shape: .sine, rateHz: 0.7, sync: fastest)
        XCTAssertEqual(lfo.effectiveRateHz(tempoBPM: nil), 0.7, "no tempo: the stored rate")
        XCTAssertEqual(lfo.effectiveRateHz(tempoBPM: .nan), 0.7)
        XCTAssertEqual(lfo.effectiveRateHz(tempoBPM: 240, maximumRateHz: 3), 3, "capped")
        let free = try LFO(shape: .sine, rateHz: 0.7)
        XCTAssertEqual(free.effectiveRateHz(tempoBPM: 120), 0.7, "an unsynced oscillator ignores the tempo")
        XCTAssertEqual(LFO.phase(from: 0.25, elapsedNanoseconds: Self.second, rateHz: 0.5), 0.75, accuracy: 1e-15)
        XCTAssertEqual(free.phase(elapsedNanoseconds: 3 * Self.second + 1, rateHz: 0.7),
                       LFO.phase(from: 0, elapsedNanoseconds: 3 * Self.second + 1, rateHz: 0.7), "the MOD-007 phase delegates")
    }

    // MARK: Continuity (MOD-009-S3)

    func testTempoChangeKeepsPhaseContinuous() throws {
        let lfo = try LFO(shape: .triangle, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 1))
        let bank = try Self.bank(lfo)
        let changeFrame = 75   // 1.25 s: 120 BPM phase 0.5; a pure 90 BPM phase would be 0.875 (a 0.25 jump)
        let maximumStep: Double = 4 * 0.5 * 2 * (Double(Self.frame) / 1e9) + Self.tolerance   // slope 2/cycle × 2 Hz × frame
        var previous: Double?
        var changeTime: UInt64 = 0
        var changePhase = 0.0
        for index in 0...300 {
            let t = Self.origin + UInt64(index) * Self.frame
            let bpm: Double = index < changeFrame ? 120 : 90
            let value = Self.sample(bank, at: t, bpm: bpm)
            if index == changeFrame {
                changeTime = t
                changePhase = 2 * Self.seconds(t - Self.origin)
                XCTAssertEqual(value, Self.closedForm(lfo, cycles: changePhase), accuracy: Self.tolerance,
                               "the change frame keeps the 120 BPM phase")
            }
            if index > changeFrame {
                let expected = Self.closedForm(lfo, cycles: changePhase + 1.5 * Self.seconds(t - changeTime))
                XCTAssertEqual(value, expected, accuracy: Self.tolerance, "frame \(index) runs at 90 BPM from the change")
            }
            if let previous { XCTAssertLessThanOrEqual(abs(value - previous), maximumStep, "frame \(index): no jump") }
            previous = value
        }
        let after = changeTime + 10 * Self.frame
        XCTAssertEqual(Self.sample(bank, at: after, bpm: 90), Self.sample(bank, at: after + 2 * Self.second, bpm: 90),
                       accuracy: Self.tolerance, "90 BPM: three 2/3 s cycles in 2 s")
    }

    func testTempoLostFallsBackWithoutJumpAndRunsAreDeterministic() throws {
        let lfo = try LFO(shape: .sine, rateHz: 0.25, phaseOffset: 0.3, sync: LFOSync(beatsPerCycle: 2))
        func run() throws -> [Double] {
            let bank = try Self.bank(lfo)
            var values: [Double] = []
            for index in 0...240 {
                let bpm: Double? = index < 100 ? 128 : (index < 180 ? nil : 0.2)   // lost, then an unusable tempo
                values.append(Self.sample(bank, at: Self.origin + UInt64(index) * Self.frame, bpm: bpm))
            }
            return values
        }
        let first = try run()
        XCTAssertEqual(first, try run(), "identical inputs give bit-identical outputs")
        let maximumStep: Double = 2 * Double.pi * 0.5 * (128.0 / 120) * (Double(Self.frame) / 1e9) + Self.tolerance
        for index in 1..<first.count {
            XCTAssertLessThanOrEqual(abs(first[index] - first[index - 1]), maximumStep, "frame \(index)")
        }
        let lostPhase: Double = 0.3 + (128.0 / 120) * Self.seconds(100 * Self.frame)
        let late = 150 * Self.frame
        XCTAssertEqual(first[150], Self.closedForm(lfo, cycles: lostPhase + 0.25 * Self.seconds(late - 100 * Self.frame)),
                       accuracy: Self.tolerance, "no tempo: the stored 0.25 Hz from the reached phase")
    }

    // MARK: Safety (MOD-009-S4)

    func testReduceFlashingCapsSyncedRateContinuously() throws {
        let lfo = try LFO(shape: .triangle, rateHz: 0.25, phaseOffset: 0.1, sync: LFOSync(beatsPerCycle: 0.25))
        let three = try LFO(shape: .triangle, rateHz: 3, phaseOffset: 0.1)
        let bank = try Self.bank(lfo)
        var crossings = 0
        var previous: Double?
        for index in 0...120 {
            let elapsed = UInt64(index) * Self.frame
            let value = Self.sample(bank, at: Self.origin + elapsed, bpm: 240, cap: LFOBank.reduceFlashingMaximumRateHz)
            XCTAssertEqual(value, three.value(elapsedNanoseconds: elapsed), accuracy: Self.tolerance, "16 Hz capped at 3 Hz")
            if let previous, previous < 0.5, value >= 0.5 { crossings += 1 }
            previous = value
        }
        XCTAssertEqual(crossings, 6, "3 cycles per second for 2 s, not 32")

        let slow = try LFO(shape: .triangle, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 1))   // 2 Hz at 120, then capped at 1 Hz
        let toggled = try Self.bank(slow)
        var last: Double?
        for index in 0...120 {
            let cap: Double = index < 40 ? .infinity : 1
            let value = Self.sample(toggled, at: Self.origin + UInt64(index) * Self.frame, bpm: 120, cap: cap)
            if let last { XCTAssertLessThanOrEqual(abs(value - last), 4 * 0.5 * 2 * (Double(Self.frame) / 1e9) + Self.tolerance) }
            last = value
        }
    }

    func testFreeOscillatorsIgnoreTempoChanges() throws {
        let free = try LFO(shape: .sine, rateHz: 0.7, phaseOffset: 0.2)
        let synced = try LFO(shape: .sine, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 1))
        let bank = LFOBank()
        try bank.set([synced, free, nil])
        XCTAssertTrue(bank.hasSyncedOscillators)
        var out: [Double] = Array(repeating: -1, count: LFOBank.maximumOscillators)
        for index in 0...120 {
            let elapsed = UInt64(index) * Self.frame
            let bpm: Double = index % 30 < 15 ? 100 : 140
            out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Double>) -> Void in
                bank.values(atNanoseconds: Self.origin + elapsed, tempoBPM: bpm, into: buffer)
            }
            XCTAssertEqual(out[1], free.value(elapsedNanoseconds: elapsed), "free slot is MOD-007's pure function")
            XCTAssertEqual(out[2], 0)
        }
        XCTAssertEqual(Self.sample(bank, at: Self.origin, bpm: 100), Self.sample(bank, at: Self.origin - 1, bpm: 100),
                       "time before the segment start reads the start phase")
        try bank.set([free])
        XCTAssertFalse(bank.hasSyncedOscillators)
        XCTAssertThrowsError(try LFO(shape: .sine, rateHz: 0, sync: LFOSync(beatsPerCycle: 1)), "the fallback rate is still validated")
    }
}
