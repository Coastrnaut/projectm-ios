// BandEnvelopeBankTests.swift — MOD-015-T03, T07: the envelope follower bank's step response (roadmap acceptance
// "Step tests verify independent smoothing profiles"), its independence, chunking, edge cases, and the band
// envelope sources (MOD-015-R1 to R9; S1 to S4; contract band-envelopes B1 to B8).
// Deterministic: frame times are generated (fixed rates or a seeded SplitMix64); no clock, no sleep.
import Foundation
import ParameterGraph
import XCTest

final class BandEnvelopeBankTests: XCTestCase {
    /// Four bands: 0, 1 and 3 steady, band 2 steps silence (1 s) → full (2 s) → silence (3 s).
    static let steady: [Float] = [0.3, 0.7, 0, 0.5]
    static let stepBand = 2
    static let origin: UInt64 = 1_000_000_000

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

    /// One frame: its time and band 2's input (applied over the interval ending at `time`).
    struct Frame { let time: UInt64; let input: Float }

    /// Frames from `origin` (input 0, the first advance) through 6 s; `step` gives each frame's duration.
    static func frames(_ step: (inout SplitMix64) -> UInt64, seed: UInt64 = 1) -> [Frame] {
        var generator = SplitMix64(state: seed)
        var result: [Frame] = [Frame(time: origin, input: 0)]
        var elapsed: UInt64 = 0
        while elapsed < 6_000_000_000 {
            elapsed += step(&generator)
            let input: Float = elapsed > 1_000_000_000 && elapsed <= 3_000_000_000 ? 1 : 0
            result.append(Frame(time: origin + elapsed, input: input))
        }
        return result
    }

    static let fps60: [Frame] = frames { (_: inout SplitMix64) -> UInt64 in 16_666_667 }
    static let fps120: [Frame] = frames { (_: inout SplitMix64) -> UInt64 in 8_333_333 }
    static let jittery: [Frame] = frames({ (g: inout SplitMix64) -> UInt64 in 4_000_000 + g.next() % 36_000_001 },
                                         seed: 0x4D4F_442D_3031_35)

    /// Runs `frames` through `bank`; returns every frame's 4 × 3 values (band-major).
    static func run(_ frames: [Frame], bank: BandEnvelopeBank = BandEnvelopeBank(), step: Bool = true) -> [[Double]] {
        var bands: [Float] = steady
        var out: [[Double]] = []
        out.reserveCapacity(frames.count)
        for frame in frames {
            bands[stepBand] = step ? frame.input : 0
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                bank.advance(bands: buffer, timeNanoseconds: frame.time)
            }
            out.append(Array(bank.values))
        }
        return out
    }

    /// Band 2's closed form for `profile` at every frame: within each constant-input segment
    /// s(t) = x + (s₀ − x)·e^(−(t − t₀)/τ), t₀ the time of the last frame before the input changed.
    static func closedForm(_ frames: [Frame], profile: AudioFeatureEnvelope) -> [Double] {
        var result: [Double] = [0]
        var segmentStart: UInt64 = frames[0].time
        var segmentValue = 0.0
        var input: Float = frames[0].input
        for k in 1..<frames.count {
            if frames[k].input != input {
                segmentStart = frames[k - 1].time
                segmentValue = result[k - 1]
                input = frames[k].input
            }
            let x = Double(input)
            let tau: Double = x > segmentValue ? profile.attackSeconds : profile.releaseSeconds
            let t = Double(frames[k].time - segmentStart) / 1e9
            result.append(x + (segmentValue - x) * exp(-t / tau))
        }
        return result
    }

    // MARK: Acceptance (MOD-015-S1, S2)

    /// The roadmap acceptance: a step into band 2 rises and falls at each profile's own documented rate.
    func testStepRiseAndFallFollowEachProfileAtEveryFrameRate() {
        for (name, frames) in [("60 fps", Self.fps60), ("120 fps", Self.fps120), ("jitter", Self.jittery)] {
            let values = Self.run(frames)
            let longestFrame: Double = zip(frames.dropFirst(), frames).map { (pair: (Frame, Frame)) -> Double in
                Double(pair.0.time - pair.1.time) / 1e9
            }.max() ?? 0
            var riseCrossing: [Double] = []
            var fallCrossing: [Double] = []
            for profile in BandEnvelopeProfile.allCases {
                let expected = Self.closedForm(frames, profile: profile.envelope)
                let column = Self.stepBand * 3 + profile.index
                for k in frames.indices {
                    XCTAssertEqual(values[k][column], expected[k], accuracy: 1e-9, "\(name) \(profile) frame \(k)")
                }
                // 90 % of the rise is reached τ·ln 10 after the step began (within one frame).
                let riseStart = Double(Self.origin) / 1e9 + 1
                let rise = Self.crossing(frames, values, column: column, after: 1) { (v: Double) -> Bool in v >= 0.9 } - riseStart
                let riseTarget = profile.envelope.attackSeconds * log(10.0)
                XCTAssertGreaterThanOrEqual(rise, riseTarget - longestFrame, "\(name) \(profile) rise")
                XCTAssertLessThanOrEqual(rise, riseTarget + longestFrame, "\(name) \(profile) rise")
                // Half of the peak is lost τ·ln 2 after the drop (within one frame); the slow profile's 10 % point
                // (5.9 s) lies beyond the 3 s of silence, so the half-life is the documented fall check.
                let k3 = frames.firstIndex { (f: Frame) -> Bool in f.time - Self.origin > 3_000_000_000 }!
                let peak = values[k3 - 1][column]
                let fallStart = Double(frames[k3 - 1].time) / 1e9
                let fall = Self.crossing(frames, values, column: column, after: 3) { (v: Double) -> Bool in v <= peak / 2 } - fallStart
                let fallTarget = profile.envelope.releaseSeconds * log(2.0)
                XCTAssertGreaterThanOrEqual(fall, fallTarget - longestFrame, "\(name) \(profile) fall")
                XCTAssertLessThanOrEqual(fall, fallTarget + longestFrame, "\(name) \(profile) fall")
                riseCrossing.append(rise)
                fallCrossing.append(fall)
            }
            XCTAssertLessThan(riseCrossing[0], riseCrossing[1], "\(name): fast rises before medium")
            XCTAssertLessThan(riseCrossing[1], riseCrossing[2], "\(name): medium rises before slow")
            XCTAssertLessThan(fallCrossing[0], fallCrossing[1], "\(name): fast falls before medium")
            XCTAssertLessThan(fallCrossing[1], fallCrossing[2], "\(name): medium falls before slow")
        }
    }

    /// The first frame time (seconds) after `after` s past the origin where band column `column` satisfies `test`.
    static func crossing(_ frames: [Frame], _ values: [[Double]], column: Int, after: Double,
                         _ test: (Double) -> Bool) -> Double {
        for k in frames.indices where Double(frames[k].time - origin) / 1e9 > after && test(values[k][column]) {
            return Double(frames[k].time) / 1e9
        }
        return .infinity
    }

    /// Independence across bands: the steady bands' envelopes are bit-identical with and without the step.
    func testOtherBandsAreUnaffectedByTheStep() {
        let with = Self.run(Self.jittery)
        let without = Self.run(Self.jittery, step: false)
        for k in with.indices {
            for band in [0, 1, 3] {
                for p in 0..<3 { XCTAssertEqual(with[k][band * 3 + p], without[k][band * 3 + p], "frame \(k) band \(band)") }
            }
        }
        XCTAssertEqual(with.last?[1 * 3 + 2] ?? 0, 0.7, accuracy: 0.01, "a steady band's slow envelope settles on its level")
    }

    /// Independence across profiles: changing the medium constants leaves fast and slow bit-identical.
    func testChangingOneProfileLeavesTheOthersBitIdentical() throws {
        let variant = try XCTUnwrap(BandEnvelopeBank(profiles: [
            BandEnvelopeProfile.fast.envelope,
            AudioFeatureEnvelope(attackSeconds: 0.2, releaseSeconds: 0.9),
            BandEnvelopeProfile.slow.envelope,
        ]))
        let base = Self.run(Self.fps60)
        let changed = Self.run(Self.fps60, bank: variant)
        var mediumDiffers = false
        for k in base.indices {
            for band in 0..<4 {
                XCTAssertEqual(base[k][band * 3 + 0], changed[k][band * 3 + 0], "fast, frame \(k)")
                XCTAssertEqual(base[k][band * 3 + 2], changed[k][band * 3 + 2], "slow, frame \(k)")
                if base[k][band * 3 + 1] != changed[k][band * 3 + 1] { mediumDiffers = true }
            }
        }
        XCTAssertTrue(mediumDiffers)
        XCTAssertNil(BandEnvelopeBank(profiles: [.none, .none]), "exactly three profiles")
        XCTAssertNil(BandEnvelopeBank(profiles: [.none, .none, AudioFeatureEnvelope(attackSeconds: -1, releaseSeconds: 0)]))
    }

    // MARK: Definition, chunking, robustness (MOD-015-S3)

    /// Each envelope equals MOD-005's `AudioFeatureEnvelope.step` iterated over the same frames, exactly.
    func testEachEnvelopeEqualsTheMOD005Step() {
        let frames = Self.jittery
        let values = Self.run(frames)
        for profile in BandEnvelopeProfile.allCases {
            var s = 0.0
            for k in frames.indices {
                let dt: Double = k == 0 ? 0 : Double(frames[k].time - frames[k - 1].time) / 1e9
                s = profile.envelope.step(from: s, toward: Double(frames[k].input), elapsedSeconds: dt)
                XCTAssertEqual(values[k][Self.stepBand * 3 + profile.index], s, "\(profile) frame \(k)")
            }
        }
    }

    /// Splitting each 60 fps frame into three advances with the same input changes nothing beyond 1e-12.
    func testChunkingInvariance() {
        let frames = Self.fps60
        let whole = Self.run(frames)
        let bank = BandEnvelopeBank()
        var bands: [Float] = Self.steady
        for k in frames.indices {
            bands[Self.stepBand] = frames[k].input
            let start: UInt64 = k == 0 ? frames[0].time : frames[k - 1].time
            let span = frames[k].time - start
            for time in [start + span / 3, start + 2 * span / 3, frames[k].time] where k > 0 || time == frames[0].time {
                bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in bank.advance(bands: b, timeNanoseconds: time) }
            }
            for i in 0..<12 { XCTAssertEqual(bank.values[i], whole[k][i], accuracy: 1e-12, "frame \(k) value \(i)") }
        }
    }

    func testNonFiniteAndOutOfRangeInputsStayFiniteInRange() {
        let bank = BandEnvelopeBank()
        let bands: [Float] = [.nan, .infinity, -.infinity, 2, -1, 0.5]
        var time = Self.origin
        for _ in 0..<30 {
            bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in bank.advance(bands: b, timeNanoseconds: time) }
            time += 16_666_667
            for v in bank.values { XCTAssertTrue(v.isFinite && v >= 0 && v <= 1, "\(v)") }
        }
        for p in BandEnvelopeProfile.allCases {
            XCTAssertEqual(bank.value(band: 0, profile: p), 0, "NaN reads 0")
            XCTAssertEqual(bank.value(band: 1, profile: p), 0, "+∞ reads 0")
            XCTAssertGreaterThan(bank.value(band: 3, profile: p), bank.value(band: 5, profile: p), "2 reads 1, above 0.5")
            XCTAssertEqual(bank.value(band: 4, profile: p), 0, "−1 reads 0")
        }
        XCTAssertEqual(bank.value(band: 3, profile: .fast), 1, accuracy: 1e-9)
    }

    func testClockRulesResetAndCapacity() {
        let bank = BandEnvelopeBank()
        let ones: [Float] = [1, 1, 1]
        func advance(_ bands: [Float], _ time: UInt64) {
            bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in bank.advance(bands: b, timeNanoseconds: time) }
        }
        advance(ones, Self.origin)
        XCTAssertEqual(bank.value(band: 0, profile: .slow), 0, "the first advance has Δt 0")
        advance(ones, Self.origin + 100_000_000)
        let afterStep = bank.value(band: 0, profile: .slow)
        XCTAssertEqual(afterStep, 1 - exp(-0.1 / 0.4), accuracy: 1e-12)
        advance(ones, Self.origin)
        XCTAssertEqual(bank.value(band: 0, profile: .slow), afterStep, "time going back moves nothing")
        advance(ones, Self.origin + 10_100_000_000)   // a 10 s gap counts as 0.25 s
        XCTAssertEqual(bank.value(band: 0, profile: .slow), 1 - exp(-0.35 / 0.4), accuracy: 1e-12)
        advance([1, 1, 1, 1], Self.origin + 10_100_000_000)
        XCTAssertEqual(bank.bandCount, 4)
        XCTAssertEqual(Array(bank.values), Array(repeating: 0, count: 12), "a new band count restarts at 0")
        XCTAssertEqual(bank.value(band: 9, profile: .fast), 0, "beyond the band count reads 0")
        advance(Array(repeating: 1, count: 200), Self.origin + 10_200_000_000)
        XCTAssertEqual(bank.bandCount, BandEnvelopeBank.maximumBands)
        XCTAssertEqual(bank.values.count, 128 * 3)
        bank.reset()
        XCTAssertEqual(bank.bandCount, 0)
        XCTAssertEqual(bank.values.count, 0)
    }

    // MARK: Sources (MOD-015-T07, S4)

    func testSourceIDsRoundTripAndRefuseMalformedIDs() {
        for profile in BandEnvelopeProfile.allCases {
            for band in [0, 7, 127] {
                let source = AudioFeatureSource.bandEnvelope(band, profile)
                XCTAssertEqual(source.id, "audio.bandEnvelope.\(profile.rawValue).\(band)")
                XCTAssertEqual(AudioFeatureSource(id: source.id), source)
                XCTAssertEqual(source.bandIndex, band)
            }
        }
        for bad in ["audio.bandEnvelope.fast.128", "audio.bandEnvelope.fast.01", "audio.bandEnvelope.loud.1",
                    "audio.bandEnvelope.fast.", "audio.bandEnvelope.fast.-1", "audio.bandEnvelope.1", "audio.bandEnvelope.Fast.1"] {
            XCTAssertNil(AudioFeatureSource(id: bad), bad)
        }
        XCTAssertEqual(AudioFeatureSource(id: "audio.band.3"), .band(3), "plain bands unchanged")
        XCTAssertNil(AudioFeatureSource.kick.bandIndex)
    }

    func testFrameValueReadsTheBorrowedEnvelopes() {
        let values: [Double] = [0.1, 0.2, 0.3, 0.4, .nan, 1.5]
        let bands: [Float] = [0, 0]
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            values.withUnsafeBufferPointer { (e: UnsafeBufferPointer<Double>) -> Void in
                let frame = AudioFeatureFrame(bands: b, bandEnvelopes: e)
                XCTAssertEqual(AudioFeatureSource.bandEnvelope(0, .medium).value(in: frame), 0.2)
                XCTAssertEqual(AudioFeatureSource.bandEnvelope(1, .fast).value(in: frame), 0.4)
                XCTAssertEqual(AudioFeatureSource.bandEnvelope(1, .medium).value(in: frame), 0, "NaN reads 0")
                XCTAssertEqual(AudioFeatureSource.bandEnvelope(1, .slow).value(in: frame), 1, "clamped to 1")
                XCTAssertEqual(AudioFeatureSource.bandEnvelope(2, .fast).value(in: frame), 0, "beyond the buffer reads 0")
            }
        }
        XCTAssertEqual(AudioFeatureSource.bandEnvelope(0, .slow).value(in: .silent), 0)
    }

    static let opacity: ParameterID = "test.layer.opacity"

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: opacity, displayName: "Opacity", group: ParameterGroup(id: "test.layer", displayName: "Layer"),
                                unit: .normalized, kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.25),
                                modulation: .continuousDefault),
        ])
    }

    /// A binding from band 2's slow envelope drives the parameter along that envelope (MOD-015-S4).
    func testBindingFollowsTheSlowEnvelope() throws {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(AudioFeatureBinding(source: .bandEnvelope(2, .slow), target: Self.opacity, outputStart: 0, outputEnd: 1))
        let bank = BandEnvelopeBank()
        var bands: [Float] = Self.steady
        for frame in Self.fps60 {
            bands[Self.stepBand] = frame.input
            bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                bank.advance(bands: b, timeNanoseconds: frame.time)
                modulator.advance(frame: AudioFeatureFrame(bands: b, bandEnvelopes: bank.values), timeNanoseconds: frame.time)
            }
            XCTAssertEqual(modulator.value(for: Self.opacity, manual: 0.25), bank.value(band: 2, profile: .slow), accuracy: 1e-12)
        }
        XCTAssertThrowsError(try modulator.bind(AudioFeatureBinding(source: .bandEnvelope(128, .fast), target: Self.opacity,
                                                                    outputStart: 0, outputEnd: 1))) { (error: Error) in
            XCTAssertEqual(error as? AudioFeatureBindingError, .bandIndexOutOfRange(Self.opacity, 128))
        }
    }

    func testTriggersAcceptBandEnvelopesInRange() throws {
        let bank = ThresholdTriggerBank()
        let settings = ThresholdTriggerSettings(high: 0.6, low: 0.4)
        try bank.set([ThresholdTriggerBinding(source: .bandEnvelope(3, .medium), action: .cueNext, settings: settings)])
        XCTAssertEqual(bank.bindings.map(\.source), [.bandEnvelope(3, .medium)])
        XCTAssertThrowsError(try bank.set([ThresholdTriggerBinding(source: .bandEnvelope(200, .slow), action: .cueNext,
                                                                   settings: settings)])) { (error: Error) in
            XCTAssertEqual(error as? ThresholdTriggerError, .bandIndexOutOfRange(200))
        }
    }
}
