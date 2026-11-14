// EnvelopeStepResponseTests.swift — MOD-005-T02, T04, T05: the attack/release envelope's step
// response (roadmap acceptance "Step input follows selected time constants within tolerance"),
// its edge cases and live changes of its times (MOD-005-R1 to R8, R11; contract E1 to E6).
// Deterministic: frame times are generated (fixed rates or a seeded SplitMix64); no clock, no sleep.
import Foundation
import ParameterGraph
import XCTest

final class EnvelopeStepResponseTests: XCTestCase {
    static let opacity: ParameterID = "test.layer.opacity"
    static let group = ParameterGroup(id: "test.layer", displayName: "Layer")
    /// The acceptance tolerance (absolute, signal units 0…1) and the analytic agreement (contract E3).
    static let tolerance = 0.01
    static let analyticTolerance = 1e-9

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: opacity, displayName: "Opacity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.25), modulation: .continuousDefault),
        ])
    }

    // MARK: Frame patterns

    /// SplitMix64: a tiny seeded generator, identical on every platform.
    struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z: UInt64 = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    enum FramePattern: CustomStringConvertible {
        case fixed(nanoseconds: UInt64, name: String)
        case jitter(seed: UInt64)

        static let fps60 = FramePattern.fixed(nanoseconds: 16_666_667, name: "60 fps")
        static let fps120 = FramePattern.fixed(nanoseconds: 8_333_333, name: "120 fps")
        static let jittery = FramePattern.jitter(seed: 0x4D4F_442D_3030_35)
        static let all: [FramePattern] = [fps60, fps120, jittery]

        var description: String {
            switch self {
            case let .fixed(_, name): name
            case let .jitter(seed): "jitter seed \(seed)"
            }
        }

        /// Frame durations covering at least `seconds`, each 4…40 ms for jitter.
        func durations(covering seconds: Double, generator: inout SplitMix64) -> [UInt64] {
            var result: [UInt64] = []
            var total: UInt64 = 0
            let needed = UInt64(seconds * 1e9)
            while total < needed {
                let d: UInt64
                switch self {
                case let .fixed(ns, _): d = ns
                case .jitter: d = 4_000_000 + generator.next() % 36_000_001
                }
                result.append(d)
                total += d
            }
            return result
        }

        var seed: UInt64 {
            if case let .jitter(seed) = self { return seed }
            return 1
        }
    }

    // MARK: Simulation

    /// One sample after an advance: seconds since the step began, the signal, and the frame's Δt.
    struct Sample { let elapsed: Double; let signal: Double; let frame: Double }

    struct StepRun {
        var rise: [Sample] = []
        var fall: [Sample] = []
        /// The signal when the fall began.
        var fallStart = 0.0
    }

    private static func advance(_ modulator: AudioFeatureModulator, feature: Float, at time: UInt64) {
        let bands: [Float] = [feature]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            modulator.advance(frame: AudioFeatureFrame(bands: buffer), timeNanoseconds: time)
        }
    }

    /// Binds band 0 → opacity with `envelope`, holds 0, steps to 1 for `riseSeconds`, then to 0 for
    /// `fallSeconds`, sampling the signal after every advance.
    static func stepRun(_ envelope: AudioFeatureEnvelope, pattern: FramePattern,
                        riseSeconds: Double, fallSeconds: Double) throws -> StepRun {
        let modulator = AudioFeatureModulator(registry: try registry())
        try modulator.bind(AudioFeatureBinding(source: .band(0), target: opacity, outputStart: 0, outputEnd: 1,
                                               envelope: envelope))
        var generator = SplitMix64(state: pattern.seed)
        var time: UInt64 = 3_000_000_000
        advance(modulator, feature: 0, at: time)   // first advance: starts the clock at signal 0
        var run = StepRun()
        var since: UInt64 = 0
        for d in pattern.durations(covering: riseSeconds, generator: &generator) {
            time += d
            since += d
            advance(modulator, feature: 1, at: time)
            run.rise.append(Sample(elapsed: Double(since) / 1e9, signal: modulator.signal(for: opacity) ?? .nan,
                                   frame: Double(d) / 1e9))
        }
        run.fallStart = modulator.signal(for: opacity) ?? .nan
        since = 0
        for d in pattern.durations(covering: fallSeconds, generator: &generator) {
            time += d
            since += d
            advance(modulator, feature: 0, at: time)
            run.fall.append(Sample(elapsed: Double(since) / 1e9, signal: modulator.signal(for: opacity) ?? .nan,
                                   frame: Double(d) / 1e9))
        }
        return run
    }

    /// The first sample whose signal satisfies `crossed`.
    private static func firstCrossing(_ samples: [Sample], _ crossed: (Double) -> Bool) -> Sample? {
        samples.first { (sample: Sample) -> Bool in crossed(sample.signal) }
    }

    // MARK: (a) Roadmap acceptance (MOD-005-S1)

    func testStepInputFollowsSelectedTimeConstantsWithinTolerance() throws {
        let settings: [(attack: Double, release: Double)] = [(0.05, 0.5), (0.25, 0.1), (1, 2)]
        for setting in settings {
            for pattern in FramePattern.all {
                let label = "attack \(setting.attack) s, release \(setting.release) s, \(pattern)"
                let envelope = AudioFeatureEnvelope(attackSeconds: setting.attack, releaseSeconds: setting.release)
                let run = try Self.stepRun(envelope, pattern: pattern, riseSeconds: 5 * setting.attack,
                                           fallSeconds: 5 * setting.release)
                for sample in run.rise {
                    let expected: Double = 1 - exp(-sample.elapsed / setting.attack)
                    XCTAssertEqual(sample.signal, expected, accuracy: Self.tolerance, "rise, \(label), t \(sample.elapsed)")
                    XCTAssertEqual(sample.signal, expected, accuracy: Self.analyticTolerance, "rise matches E1, \(label)")
                }
                for sample in run.fall {
                    let expected: Double = run.fallStart * exp(-sample.elapsed / setting.release)
                    XCTAssertEqual(sample.signal, expected, accuracy: Self.tolerance, "fall, \(label), t \(sample.elapsed)")
                    XCTAssertEqual(sample.signal, expected, accuracy: Self.analyticTolerance, "fall matches E1, \(label)")
                }
                let riseLevel: Double = 1 - exp(-1.0)   // 63.2 %
                let rise = try XCTUnwrap(Self.firstCrossing(run.rise) { (s: Double) -> Bool in s >= riseLevel - 1e-12 }, label)
                XCTAssertLessThanOrEqual(abs(rise.elapsed - setting.attack), rise.frame, "63.2 % within one frame of attack, \(label)")
                let fallLevel: Double = run.fallStart * exp(-1.0)   // 36.8 % of the start
                let fall = try XCTUnwrap(Self.firstCrossing(run.fall) { (s: Double) -> Bool in s <= fallLevel + 1e-12 }, label)
                XCTAssertLessThanOrEqual(abs(fall.elapsed - setting.release), fall.frame, "36.8 % within one frame of release, \(label)")
            }
        }
    }

    // (b) Rise uses only the attack time, fall only the release time (MOD-005-R1).
    func testRiseUsesAttackAndFallUsesReleaseIndependently() throws {
        let base = try Self.stepRun(AudioFeatureEnvelope(attackSeconds: 0.25, releaseSeconds: 0.1), pattern: .fps60,
                                    riseSeconds: 0.5, fallSeconds: 0.5)
        let otherRelease = try Self.stepRun(AudioFeatureEnvelope(attackSeconds: 0.25, releaseSeconds: 1), pattern: .fps60,
                                            riseSeconds: 0.5, fallSeconds: 0.5)
        XCTAssertEqual(base.rise.map(\.signal), otherRelease.rise.map(\.signal), "the release time never shapes a rise")
        let otherAttack = try Self.stepRun(AudioFeatureEnvelope(attackSeconds: 0.05, releaseSeconds: 0.1), pattern: .fps60,
                                           riseSeconds: 0.5, fallSeconds: 0.5)
        XCTAssertNotEqual(base.fallStart, otherAttack.fallStart)
        for (a, b) in zip(base.fall, otherAttack.fall) {
            XCTAssertEqual(a.signal / base.fallStart, b.signal / otherAttack.fallStart, accuracy: 1e-12,
                           "the attack time never shapes a fall")
        }
    }

    // (c) The 10–90 % rise time is τ·ln 9 (MOD-005-R2, contract E1).
    func testTenToNinetyRiseTimeConversions() {
        XCTAssertEqual(AudioFeatureEnvelope.tenToNinetyFactor, log(9.0))
        XCTAssertEqual(AudioFeatureEnvelope.riseTime10To90(timeConstant: 1), log(9.0))
        XCTAssertEqual(AudioFeatureEnvelope.riseTime10To90(timeConstant: 0), 0)
        for tau in [0.01, 0.25, 3.0, 60.0] {
            let rise = AudioFeatureEnvelope.riseTime10To90(timeConstant: tau)
            XCTAssertEqual(AudioFeatureEnvelope.timeConstant(riseTime10To90: rise), tau, accuracy: 1e-12 * tau)
            // The analytic curve really covers 10 % → 90 % in that time.
            let t10: Double = -tau * log(0.9)
            let t90: Double = -tau * log(0.1)
            XCTAssertEqual(t90 - t10, rise, accuracy: 1e-12 * tau)
        }
    }

    // (d) The pure step, without a registry or modulator (contract E2, MOD-005-R11).
    func testPureStepFollowsContract() {
        let envelope = AudioFeatureEnvelope(attackSeconds: 0.5, releaseSeconds: 0.25)
        XCTAssertEqual(envelope.step(from: 0, toward: 1, elapsedSeconds: 0.5), 0 + (1 - 0) * (1 - exp(-0.5 / 0.5)))
        XCTAssertEqual(envelope.step(from: 1, toward: 0, elapsedSeconds: 0.25), 1 + (0 - 1) * (1 - exp(-0.25 / 0.25)))
        XCTAssertEqual(envelope.step(from: 0.4, toward: 0.4, elapsedSeconds: 1), 0.4, "no distance, no movement")
        XCTAssertEqual(envelope.step(from: 0.3, toward: 0.9, elapsedSeconds: 0), 0.3, "no elapsed time")
        XCTAssertEqual(AudioFeatureEnvelope.none.step(from: 0.3, toward: 0.9, elapsedSeconds: 0), 0.9, "instant")
        // Splitting the elapsed time does not change the result (E3).
        var split = 0.0
        for _ in 0..<10 { split = envelope.step(from: split, toward: 1, elapsedSeconds: 0.05) }
        XCTAssertEqual(split, envelope.step(from: 0, toward: 1, elapsedSeconds: 0.5), accuracy: 1e-12)
    }

    // MARK: MOD-005-T04: edges (MOD-005-R4 to R7, S2)

    func testEdgeInputsStayFiniteBoundedAndDeterministic() throws {
        // τ = 0 in either direction is instant, also with no elapsed time.
        let attackOnly = AudioFeatureEnvelope(attackSeconds: 0, releaseSeconds: 1)
        XCTAssertEqual(attackOnly.step(from: 0.2, toward: 0.7, elapsedSeconds: 0), 0.7)
        XCTAssertEqual(attackOnly.step(from: 0.7, toward: 0.2, elapsedSeconds: 0), 0.7, "release is not instant")
        let releaseOnly = AudioFeatureEnvelope(attackSeconds: 1, releaseSeconds: 0)
        XCTAssertEqual(releaseOnly.step(from: 0.7, toward: 0.2, elapsedSeconds: 0), 0.2)

        // Non-finite and out-of-range inputs to the pure step.
        let envelope = AudioFeatureEnvelope(attackSeconds: 0.1, releaseSeconds: 0.1)
        let odd: [Double] = [.nan, .infinity, -.infinity, -1, 2, 0.5]
        for current in odd {
            for target in odd {
                for elapsed in [Double.nan, .infinity, -.infinity, -1, 0, 0.016, 1e9] {
                    let s = envelope.step(from: current, toward: target, elapsedSeconds: elapsed)
                    XCTAssertTrue(s.isFinite && s >= 0 && s <= 1, "step(\(current), \(target), \(elapsed)) = \(s)")
                }
            }
        }
        XCTAssertEqual(envelope.step(from: .nan, toward: 0.6, elapsedSeconds: 0.01), 0.6, "a non-finite signal snaps")
        XCTAssertEqual(envelope.step(from: 0.5, toward: .nan, elapsedSeconds: 1e9), 0, accuracy: 1e-12, "a non-finite target reads 0")
        XCTAssertEqual(envelope.step(from: 0.5, toward: 0.9, elapsedSeconds: .nan), 0.5, "a non-finite Δt is ignored")

        // Through the modulator: repeated and backwards times, long gaps, non-finite features.
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(AudioFeatureBinding(source: .band(0), target: Self.opacity, outputStart: 0, outputEnd: 1,
                                               envelope: AudioFeatureEnvelope(attackSeconds: 0.5, releaseSeconds: 0.5)))
        Self.advance(modulator, feature: 1, at: 10_000_000_000)
        Self.advance(modulator, feature: 1, at: 10_100_000_000)
        let moved = try XCTUnwrap(modulator.signal(for: Self.opacity))
        Self.advance(modulator, feature: 1, at: 10_100_000_000)
        Self.advance(modulator, feature: 1, at: 10_050_000_000)
        XCTAssertEqual(modulator.signal(for: Self.opacity), moved, "Δt ≤ 0 is ignored")
        Self.advance(modulator, feature: 0, at: 19_100_000_000)   // 9 s later counts as 0.25 s
        XCTAssertEqual(modulator.signal(for: Self.opacity) ?? -1, moved * exp(-0.25 / 0.5), accuracy: 1e-12)
        var time: UInt64 = 19_100_000_000
        for feature: Float in [.nan, .infinity, -.infinity, 1, .nan] {
            time += 16_666_667
            Self.advance(modulator, feature: feature, at: time)
            let s = try XCTUnwrap(modulator.signal(for: Self.opacity))
            XCTAssertTrue(s.isFinite && s >= 0 && s <= 1, "feature \(feature) → \(s)")
        }

        // Limits (E5).
        for valid in [0.0, 60.0] {
            XCTAssertNoThrow(try modulator.bind(AudioFeatureBinding(source: .band(0), target: Self.opacity, outputStart: 0, outputEnd: 1,
                                                                    envelope: AudioFeatureEnvelope(attackSeconds: valid, releaseSeconds: valid))))
        }
        for invalid in [60.000001, -0.001, Double.nan, Double.infinity] {
            let binding = AudioFeatureBinding(source: .band(0), target: Self.opacity, outputStart: 0, outputEnd: 1,
                                              envelope: AudioFeatureEnvelope(attackSeconds: 0.1, releaseSeconds: invalid))
            XCTAssertThrowsError(try modulator.bind(binding), "release \(invalid)") { (error: Error) -> Void in
                XCTAssertEqual(error as? AudioFeatureBindingError, .invalidEnvelope(Self.opacity))
            }
        }

        // Determinism (R7): the jittery run twice, bit-identical.
        let envelopeJ = AudioFeatureEnvelope(attackSeconds: 0.25, releaseSeconds: 0.1)
        let first = try Self.stepRun(envelopeJ, pattern: .jittery, riseSeconds: 1, fallSeconds: 1)
        let second = try Self.stepRun(envelopeJ, pattern: .jittery, riseSeconds: 1, fallSeconds: 1)
        XCTAssertEqual(first.rise.map(\.signal), second.rise.map(\.signal))
        XCTAssertEqual(first.fall.map(\.signal), second.fall.map(\.signal))
    }

    // MARK: MOD-005-T05: live change (MOD-005-R8, contract E6)

    func testSetEnvelopeContinuesFromTheCurrentSignal() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        let slow = AudioFeatureEnvelope(attackSeconds: 1, releaseSeconds: 1)
        try modulator.bind(AudioFeatureBinding(source: .band(0), target: Self.opacity, outputStart: 0, outputEnd: 1, envelope: slow))
        var time: UInt64 = 1_000_000_000
        Self.advance(modulator, feature: 1, at: time)
        for _ in 0..<30 { time += 16_666_667; Self.advance(modulator, feature: 1, at: time) }
        let midRise = try XCTUnwrap(modulator.signal(for: Self.opacity))
        XCTAssertGreaterThan(midRise, 0.3)
        XCTAssertLessThan(midRise, 0.5)

        let fast = AudioFeatureEnvelope(attackSeconds: 0.05, releaseSeconds: 0.2)
        try modulator.setEnvelope(fast, for: Self.opacity)
        XCTAssertEqual(modulator.signal(for: Self.opacity), midRise, "the signal does not restart")
        XCTAssertEqual(modulator.bindings.first?.envelope, fast)
        time += 16_666_667
        Self.advance(modulator, feature: 1, at: time)
        XCTAssertEqual(modulator.signal(for: Self.opacity) ?? -1, fast.step(from: midRise, toward: 1, elapsedSeconds: 0.016666667),
                       accuracy: 1e-12, "the next frame continues with the new time constant")

        let before = modulator.signal(for: Self.opacity)
        XCTAssertThrowsError(try modulator.setEnvelope(AudioFeatureEnvelope(attackSeconds: -1, releaseSeconds: 0.1), for: Self.opacity)) {
            (error: Error) -> Void in
            XCTAssertEqual(error as? AudioFeatureBindingError, .invalidEnvelope(Self.opacity))
        }
        XCTAssertEqual(modulator.bindings.first?.envelope, fast, "a refused change leaves the binding unchanged")
        XCTAssertEqual(modulator.signal(for: Self.opacity), before)
        let unbound: ParameterID = "test.layer.unbound"
        XCTAssertThrowsError(try modulator.setEnvelope(fast, for: unbound)) { (error: Error) -> Void in
            XCTAssertEqual(error as? AudioFeatureBindingError, .unknownTarget(unbound))
        }
    }
}
