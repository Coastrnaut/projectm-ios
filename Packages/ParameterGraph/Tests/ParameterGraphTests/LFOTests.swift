// LFOTests.swift — MOD-007-T02, T04, T05: clocked sine and triangle oscillators (MOD-007-R1 to R6, R10;
// specs/156-mod-007-lfo, research MOD-007-D1 to D5, contract L1 to L4).
//
// The acceptance ("Known time samples match mathematical waveforms") compares the oscillator with an independent
// closed form at quarter periods, irrational times and after hours/days of running, within 1e-9. Times are integer
// nanoseconds passed in; no clock, no sleep.
import Foundation
import ParameterGraph
import XCTest

final class LFOTests: XCTestCase {
    private static let tolerance = 1e-9
    private static let second: UInt64 = 1_000_000_000

    // MARK: Independent closed form (MOD-007-R2)

    /// The bipolar waveform at phase φ ∈ [0, 1).
    private static func wave(_ shape: LFOShape, _ phi: Double) -> Double {
        switch shape {
        case .sine:
            return sin(2 * Double.pi * phi)
        case .triangle:
            if phi < 0.25 { return 4 * phi }
            if phi < 0.75 { return 2 - 4 * phi }
            return 4 * phi - 4
        }
    }

    private static func closedForm(_ lfo: LFO, phase phi: Double) -> Double {
        let raw: Double = lfo.center + lfo.amplitude / 2 * wave(lfo.shape, phi)
        return min(max(raw, 0), 1)
    }

    /// frac(phaseOffset + rate·t) for short times (Double is exact enough below a minute).
    private static func shortPhase(_ lfo: LFO, nanoseconds: UInt64) -> Double {
        let cycles: Double = lfo.phaseOffset + lfo.rateHz * (Double(nanoseconds) / 1e9)
        return cycles - cycles.rounded(.down)
    }

    private static func time(seconds: Double) -> UInt64 { UInt64((seconds * 1e9).rounded()) }

    // MARK: (a) Acceptance: known time samples (MOD-007-S1)

    func testKnownTimeSamplesMatchClosedForm() throws {
        let settings: [(rate: Double, phase: Double, amplitude: Double, center: Double)] = [
            (1, 0, 1, 0.5), (0.25, 0.125, 0.4, 0.3), (2.5, 0.6, 1, 0.9), (0.3, 0, 0, 0.5), (0.3, 0.6, 0.8, 0.5),
        ]
        var checked = 0
        for shape in [LFOShape.sine, .triangle] {
            for s in settings {
                let lfo = try LFO(shape: shape, rateHz: s.rate, phaseOffset: s.phase, amplitude: s.amplitude, center: s.center)
                let period: Double = 1 / s.rate
                let quarterTimes: [Double] = [0, 0.25, 0.5, 0.75].map { (f: Double) -> Double in f * period }
                let irrational: [Double] = [Double.pi, 2.0.squareRoot(), exp(1.0) * 1.7]
                for seconds in quarterTimes + irrational {
                    let t = Self.time(seconds: seconds)
                    let expected = Self.closedForm(lfo, phase: Self.shortPhase(lfo, nanoseconds: t))
                    XCTAssertEqual(lfo.value(elapsedNanoseconds: t), expected, accuracy: Self.tolerance,
                                   "\(shape) \(s) at \(seconds) s")
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 2 * 5 * 7)

        // Full swing at 1 Hz: the textbook values at 0, ¼, ½, ¾ period for both shapes.
        for shape in [LFOShape.sine, .triangle] {
            let lfo = try LFO(shape: shape, rateHz: 1)
            let values: [Double] = [0, 250_000_000, 500_000_000, 750_000_000].map { (t: UInt64) -> Double in lfo.value(elapsedNanoseconds: t) }
            for (value, expected) in zip(values, [0.5, 1, 0.5, 0]) {
                XCTAssertEqual(value, expected, accuracy: Self.tolerance, "\(shape)")
            }
        }
        // Triangle is piecewise linear: ⅛ period is exactly halfway up.
        let triangle = try LFO(shape: .triangle, rateHz: 1)
        XCTAssertEqual(triangle.value(elapsedNanoseconds: 125_000_000), 0.75, accuracy: Self.tolerance)
    }

    // MARK: (b) Very long running times (MOD-007-R3)

    func testLongRunningTimeHasNoDrift() throws {
        // 0.25 Hz after 10 h + 1 s (¼ period): 9000.25 cycles, phase exactly 0.25.
        let sine = try LFO(shape: .sine, rateHz: 0.25)
        let tenHours: UInt64 = 36_000 * Self.second
        XCTAssertEqual(sine.phase(elapsedNanoseconds: tenHours + Self.second, rateHz: 0.25), 0.25, accuracy: Self.tolerance)
        XCTAssertEqual(sine.value(elapsedNanoseconds: tenHours + Self.second), 1, accuracy: Self.tolerance)
        XCTAssertEqual(sine.value(elapsedNanoseconds: tenHours + 3 * Self.second), 0, accuracy: Self.tolerance)

        // 0.3 Hz (not exact in binary) after 3 days + 0.125 s and 10 h + 0.8 s: the exact phase is
        // (3·N mod 10¹⁰) / 10¹⁰ for N nanoseconds, computed with integers.
        for n: UInt64 in [259_200_125_000_000, 36_000_800_000_000, 7 * 86_400 * Self.second + 333_333_333] {
            let exactPhase = Double((3 * n) % 10_000_000_000) / 1e10
            for shape in [LFOShape.sine, .triangle] {
                let lfo = try LFO(shape: shape, rateHz: 0.3, phaseOffset: 0.2, amplitude: 0.9, center: 0.5)
                let expectedPhase: Double = (exactPhase + 0.2).truncatingRemainder(dividingBy: 1)
                XCTAssertEqual(lfo.phase(elapsedNanoseconds: n, rateHz: 0.3), expectedPhase, accuracy: Self.tolerance)
                XCTAssertEqual(lfo.value(elapsedNanoseconds: n), Self.closedForm(lfo, phase: expectedPhase),
                               accuracy: Self.tolerance, "\(shape) at \(n) ns")
            }
        }
    }

    // MARK: US2: deterministic, bounded and safe

    func testDeterministicAcrossFrameRates() throws {
        let lfo = try LFO(shape: .sine, rateHz: 1.7, phaseOffset: 0.3, amplitude: 0.7, center: 0.4)
        var at60: [UInt64: Double] = [:]
        var t: UInt64 = 0
        while t <= 2 * Self.second {
            at60[t] = lfo.value(elapsedNanoseconds: t)
            t += 50_000_000   // shared grid of every 3rd 60 fps and 6th 120 fps frame
        }
        let bank = LFOBank()
        try bank.set([lfo])
        var buffer = [Double](repeating: -1, count: LFOBank.maximumOscillators)
        var matched = 0
        for step: UInt64 in [8_333_333, 16_666_667, 1_000_003] {   // 120 fps, 60 fps, jitter-like
            try bank.set([lfo])   // restart the origin
            var time: UInt64 = 5 * Self.second
            let origin = time
            while time <= origin + 2 * Self.second {
                buffer.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Double>) -> Void in
                    bank.values(atNanoseconds: time, into: b)
                }
                if let expected = at60[time - origin] {
                    XCTAssertEqual(buffer[0], expected, "bit-identical at \(time - origin) ns")
                    matched += 1
                }
                time += step
            }
        }
        XCTAssertGreaterThan(matched, 2)
        XCTAssertEqual(buffer[1], 0, "an empty slot reads 0")
    }

    func testOutputBoundedAndInvalidSettingsRefused() throws {
        for shape in [LFOShape.sine, .triangle] {
            for (amplitude, center) in [(1.0, 0.9), (1.0, 0.0), (0.6, 1.0), (0.0, 0.2)] {
                let lfo = try LFO(shape: shape, rateHz: 3.1, amplitude: amplitude, center: center)
                var t: UInt64 = 0
                var maximum = -Double.infinity
                var minimum = Double.infinity
                while t < 2 * Self.second {
                    let v = lfo.value(elapsedNanoseconds: t)
                    maximum = max(maximum, v)
                    minimum = min(minimum, v)
                    t += 7_000_001
                }
                XCTAssertLessThanOrEqual(maximum, 1)
                XCTAssertGreaterThanOrEqual(minimum, 0)
                if amplitude == 0 { XCTAssertEqual(maximum, minimum, "amplitude 0 is a constant") }
            }
        }
        let clipped = try LFO(shape: .sine, rateHz: 1, center: 0.9)
        XCTAssertEqual(clipped.value(elapsedNanoseconds: 250_000_000), 1, "centre 0.9 + 0.5 clamps to 1")

        let invalid: [(rate: Double, phase: Double, amplitude: Double, center: Double)] = [
            (0, 0, 1, 0.5), (0.005, 0, 1, 0.5), (21, 0, 1, 0.5), (.nan, 0, 1, 0.5), (.infinity, 0, 1, 0.5),
            (1, -0.1, 1, 0.5), (1, 1.5, 1, 0.5), (1, 0, 2, 0.5), (1, 0, -0.1, 0.5), (1, 0, 1, -1), (1, 0, 1, .nan),
        ]
        for s in invalid {
            XCTAssertThrowsError(try LFO(shape: .sine, rateHz: s.rate, phaseOffset: s.phase, amplitude: s.amplitude, center: s.center),
                                 "\(s)")
        }
        XCTAssertNoThrow(try LFO(shape: .sine, rateHz: 0.01))
        XCTAssertNoThrow(try LFO(shape: .triangle, rateHz: 20, phaseOffset: 1))
        let zero = try LFO(shape: .triangle, rateHz: 0.7)
        let one = try LFO(shape: .triangle, rateHz: 0.7, phaseOffset: 1)
        for t: UInt64 in [0, 123_456_789, 3 * Self.second] {
            XCTAssertEqual(zero.value(elapsedNanoseconds: t), one.value(elapsedNanoseconds: t), accuracy: 1e-15, "phase 1 ≡ 0")
        }
    }

    func testReduceFlashingCapsRate() throws {
        let cap = LFOBank.reduceFlashingMaximumRateHz
        XCTAssertEqual(cap, 3)
        let fast = try LFO(shape: .sine, rateHz: 10, phaseOffset: 0.1)
        let three = try LFO(shape: .sine, rateHz: 3, phaseOffset: 0.1)
        func upwardCrossings(_ lfo: LFO, maximumRateHz: Double) -> Int {
            var count = 0
            var previous = lfo.value(elapsedNanoseconds: 0, maximumRateHz: maximumRateHz)
            var t: UInt64 = 1_000_000
            while t <= 2 * Self.second {
                let v = lfo.value(elapsedNanoseconds: t, maximumRateHz: maximumRateHz)
                if previous < 0.5 && v >= 0.5 { count += 1 }
                previous = v
                t += 1_000_000
            }
            return count
        }
        XCTAssertEqual(upwardCrossings(fast, maximumRateHz: .infinity), 20)
        XCTAssertEqual(upwardCrossings(fast, maximumRateHz: cap), 6, "at most 3 cycles per second")
        for t: UInt64 in [0, 77_777_777, 1_500_000_000] {
            XCTAssertEqual(fast.value(elapsedNanoseconds: t, maximumRateHz: cap), three.value(elapsedNanoseconds: t))
        }
        let slow = try LFO(shape: .triangle, rateHz: 0.5)
        XCTAssertEqual(slow.value(elapsedNanoseconds: 300_000_000, maximumRateHz: cap), slow.value(elapsedNanoseconds: 300_000_000),
                       "slower oscillators are unchanged")

        let bank = LFOBank()
        try bank.set([fast])
        var capped = [Double](repeating: 0, count: 1)
        capped.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Double>) -> Void in
            bank.values(atNanoseconds: 1_000, into: b)   // origin
            bank.values(atNanoseconds: 1_000 + 77_777_777, maximumRateHz: cap, into: b)
        }
        XCTAssertEqual(capped[0], three.value(elapsedNanoseconds: 77_777_777))
    }

    func testBankOriginSlotsAndLimit() throws {
        let a = try LFO(shape: .sine, rateHz: 1)
        let b = try LFO(shape: .triangle, rateHz: 2, phaseOffset: 0.25)
        let bank = LFOBank()
        XCTAssertFalse(bank.hasOscillators)
        try bank.set([a, nil, b])
        XCTAssertTrue(bank.hasOscillators)
        XCTAssertEqual(bank.oscillators, [a, nil, b])
        var out = [Double](repeating: -1, count: 4)
        out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Double>) -> Void in
            bank.values(atNanoseconds: 10 * Self.second, into: p)   // origin
        }
        XCTAssertEqual(out, [0.5, 0, 1, 0], "origin: elapsed 0; nil and missing slots read 0")
        out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Double>) -> Void in
            bank.values(atNanoseconds: 10 * Self.second + 250_000_000, into: p)
        }
        XCTAssertEqual(out[0], 1, accuracy: Self.tolerance)
        XCTAssertEqual(out[2], 0, accuracy: Self.tolerance, "triangle at phase 0.25 + 0.5 = ¾: the trough")
        out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Double>) -> Void in
            bank.values(atNanoseconds: 3 * Self.second, into: p)   // before the origin
        }
        XCTAssertEqual(out[0], 0.5, "time before the origin reads elapsed 0")

        XCTAssertThrowsError(try bank.set([LFO?](repeating: a, count: LFOBank.maximumOscillators + 1)))
        var broken = b
        broken.rateHz = 50
        XCTAssertThrowsError(try bank.set([a, broken]))
        XCTAssertEqual(bank.oscillators, [a, nil, b], "a refused set leaves the bank unchanged")
        try bank.set([LFO?](repeating: a, count: LFOBank.maximumOscillators))
        try bank.set([])
        XCTAssertFalse(bank.hasOscillators)
    }

    // MARK: US3: the binding source (contract L4)

    func testLFOSourceIDsParseExactly() {
        for index in 0..<LFOBank.maximumOscillators {
            let source = AudioFeatureSource.lfo(index)
            XCTAssertEqual(source.id, "audio.lfo.\(index)")
            XCTAssertEqual(AudioFeatureSource(id: source.id), source)
        }
        for id in ["audio.lfo.8", "audio.lfo.01", "audio.lfo.", "audio.lfo", "audio.lfo.-1", "lfo.0", "audio.lfo.1x"] {
            XCTAssertNil(AudioFeatureSource(id: id), id)
        }
        XCTAssertEqual(AudioFeatureSource(id: "audio.kick"), .kick, "audio features unchanged")
    }

    func testLFOSourceReadsFrameValues() {
        let values: [Double] = [0.25, .nan, 1.5, -0.5]
        values.withUnsafeBufferPointer { (lfos: UnsafeBufferPointer<Double>) -> Void in
            let frame = AudioFeatureFrame(bands: UnsafeBufferPointer(start: nil, count: 0), lfos: lfos)
            XCTAssertEqual(AudioFeatureSource.lfo(0).value(in: frame), 0.25)
            XCTAssertEqual(AudioFeatureSource.lfo(1).value(in: frame), 0, "non-finite reads 0")
            XCTAssertEqual(AudioFeatureSource.lfo(2).value(in: frame), 1, "clamped to 0…1")
            XCTAssertEqual(AudioFeatureSource.lfo(3).value(in: frame), 0)
            XCTAssertEqual(AudioFeatureSource.lfo(5).value(in: frame), 0, "missing reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.lfo(0).value(in: .silent), 0)
    }

    func testLFOSourceDrivesBindingThroughModulator() throws {
        let registry = try AudioFeatureModulatorTests.registry()
        let modulator = AudioFeatureModulator(registry: registry)
        let target = AudioFeatureModulatorTests.opacity
        try modulator.bind(AudioFeatureBinding(source: .lfo(1), target: target, outputStart: 0.2, outputEnd: 0.8))
        XCTAssertEqual(modulator.modulationGraph.edges.first?.source, .audio(.lfo(1)))
        let lfo = try LFO(shape: .triangle, rateHz: 0.5, amplitude: 1, center: 0.5)
        let bank = LFOBank()
        try bank.set([nil, lfo])
        var scratch = [Double](repeating: 0, count: LFOBank.maximumOscillators)
        let origin: UInt64 = 2 * Self.second
        for elapsed: UInt64 in [0, 500_000_000, 1_000_000_000, 1_500_000_000, 1_234_567_891] {
            let time = origin + elapsed
            scratch.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Double>) -> Void in
                bank.values(atNanoseconds: time, into: p)
            }
            scratch.withUnsafeBufferPointer { (lfos: UnsafeBufferPointer<Double>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: UnsafeBufferPointer(start: nil, count: 0), lfos: lfos), timeNanoseconds: time)
            }
            let expected: Double = 0.2 + 0.6 * lfo.value(elapsedNanoseconds: elapsed)
            XCTAssertEqual(modulator.value(for: target, manual: 0.25), expected, accuracy: 1e-12, "at \(elapsed) ns")
        }
        XCTAssertThrowsError(try modulator.bind(AudioFeatureBinding(source: .lfo(8), target: target, outputStart: 0, outputEnd: 1))) {
            (error: Error) -> Void in
            XCTAssertEqual(error as? AudioFeatureBindingError, .lfoIndexOutOfRange(target, 8))
        }
    }
}
