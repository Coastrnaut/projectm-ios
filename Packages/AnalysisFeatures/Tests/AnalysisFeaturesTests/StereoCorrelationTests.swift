// StereoCorrelationTests.swift — ANL-013 acceptance: identical and inverted stereo fixtures read
// opposite correlation signs; the phase-inversion warning's hold and hysteresis; silence, NaN, mono;
// determinism and chunking invariance; the pipeline carries both values (ANL-013-S1 to S5).
// Everything runs on the sample clock: no wall clock.
import AudioCore
import XCTest
@testable import AnalysisFeatures

final class StereoCorrelationTests: XCTestCase {
    static let rate: Double = 44_100

    // MARK: Fixtures

    static func sine(seconds: Double, frequency: Double = 440, amplitude: Float = 0.5) -> [Float] {
        let count = Int(seconds * rate)
        return (0..<count).map { (n: Int) -> Float in
            let phase: Double = 2 * Double.pi * frequency * Double(n) / rate + 0.3
            return amplitude * Float(sin(phase))
        }
    }

    /// Interleaves `left` with `right` (same length).
    static func stereo(_ left: [Float], _ right: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: left.count * 2)
        for n in 0..<left.count {
            out[2 * n] = left[n]
            out[2 * n + 1] = right[n]
        }
        return out
    }

    static func identical(_ mono: [Float]) -> [Float] { stereo(mono, mono) }
    static func inverted(_ mono: [Float]) -> [Float] { stereo(mono, mono.map { (x: Float) -> Float in -x }) }

    static func measure(_ interleaved: [Float]) -> StereoCorrelationReading {
        var meter = StereoCorrelationMeter()
        meter.append(interleaved: interleaved)
        return meter.reading
    }

    // MARK: US1 — the roadmap acceptance

    /// ANL-013-T04 (S1): identical fixtures > 0.99, inverted < −0.99 (opposite signs), independent noise |r| < 0.1.
    func testIdenticalAndInvertedFixturesProduceOppositeCorrelationSigns() {
        let sine = Self.sine(seconds: 1)
        let noise = TestSupport.noise(count: Int(Self.rate), seed: 0x5EED, amplitude: 0.5)
        for (name, mono) in [("sine", sine), ("noise", noise)] {
            let same = Self.measure(Self.identical(mono))
            let flipped = Self.measure(Self.inverted(mono))
            XCTAssertGreaterThan(same.correlation, 0.99, "identical \(name)")
            XCTAssertLessThan(flipped.correlation, -0.99, "inverted \(name)")
            XCTAssertEqual(same.correlation.sign, .plus)
            XCTAssertEqual(flipped.correlation.sign, .minus, "opposite signs (\(name))")
            XCTAssertTrue(same.hasSignal && flipped.hasSignal)
            print("ANL-013 \(name): identical \(same.correlation), inverted \(flipped.correlation)")
        }
        let left = TestSupport.noise(count: Int(Self.rate), seed: 0xA11, amplitude: 0.5)
        let right = TestSupport.noise(count: Int(Self.rate), seed: 0xB22, amplitude: 0.5)
        let independent = Self.measure(Self.stereo(left, right))
        XCTAssertLessThan(abs(independent.correlation), 0.1, "independent noise")
        XCTAssertTrue(independent.hasSignal)
        print("ANL-013 independent noise: \(independent.correlation)")
    }

    func testConfigurationDefaultsAndRefusals() {
        let standard = StereoCorrelationConfiguration.standard
        XCTAssertEqual(standard.blockFrames, 1_024)
        XCTAssertEqual(standard.holdBlocks, 44, "ceil(1 s / 23.2 ms)")
        XCTAssertEqual(standard.decay, exp(-1_024 / (0.1 * 44_100)), accuracy: 1e-12)
        XCTAssertEqual(standard.floorMeanSquare, 0.5e-7, accuracy: 1e-15)
        XCTAssertThrowsError(try StereoCorrelationConfiguration(sampleRate: 0))
        XCTAssertThrowsError(try StereoCorrelationConfiguration(blockFrames: 8))
        XCTAssertThrowsError(try StereoCorrelationConfiguration(timeConstant: .nan))
        XCTAssertThrowsError(try StereoCorrelationConfiguration(floorDecibels: 0))
        XCTAssertThrowsError(try StereoCorrelationConfiguration(raiseBelow: -0.2, clearAbove: -0.3))
        XCTAssertThrowsError(try StereoCorrelationConfiguration(holdSeconds: -1))
        XCTAssertThrowsError(try AnalysisPipelineConfiguration(correlation: try StereoCorrelationConfiguration(sampleRate: 48_000)))
    }

    // MARK: US2 — the warning

    /// ANL-013-T05 (S2): the warning waits for the hold, then clears only after the clear hold; a
    /// short return above the clear threshold does not clear it; silence clears it after the hold.
    func testWarningRaisesAfterTheHoldAndClearsWithHysteresis() {
        let config = StereoCorrelationConfiguration.standard
        let blockSeconds: Double = Double(config.blockFrames) / Self.rate
        var meter = StereoCorrelationMeter()
        meter.append(interleaved: Self.identical(Self.sine(seconds: 0.5)))
        XCTAssertFalse(meter.reading.phaseInverted)

        // Inverted: r crosses −0.5 within a few blocks; the warning waits 44 blocks below it.
        let inverted = Self.inverted(Self.sine(seconds: 2))
        var raisedAt: Int?
        inverted.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            let base = buffer.baseAddress!
            for block in 0..<(buffer.count / 2 / config.blockFrames) {
                meter.append(interleaved: base + block * config.blockFrames * 2, frames: config.blockFrames, channels: 2)
                if raisedAt == nil, meter.reading.phaseInverted { raisedAt = block + 1 }
            }
        }
        let raised = try? XCTUnwrap(raisedAt)
        XCTAssertNotNil(raised)
        let raisedSeconds: Double = Double(raised ?? 0) * blockSeconds
        XCTAssertGreaterThan(raisedSeconds, 1.0, "not before the 1 s hold")
        XCTAssertLessThan(raisedSeconds, 1.3, "soon after the hold (r drops below −0.5 within a few blocks)")
        XCTAssertTrue(meter.reading.phaseInverted)

        // A short identical burst (0.4 s) does not clear it; back to inverted keeps it.
        meter.append(interleaved: Self.identical(Self.sine(seconds: 0.4)))
        XCTAssertGreaterThan(meter.reading.correlation, 0.9)
        XCTAssertTrue(meter.reading.phaseInverted, "0.4 s above −0.3 is shorter than the clear hold")
        meter.append(interleaved: Self.inverted(Self.sine(seconds: 0.5)))
        XCTAssertTrue(meter.reading.phaseInverted)

        // Identical for 0.9 s: still raised (the hold counts from the first block above −0.3); 1.3 s: cleared.
        meter.append(interleaved: Self.identical(Self.sine(seconds: 0.9)))
        XCTAssertTrue(meter.reading.phaseInverted)
        meter.append(interleaved: Self.identical(Self.sine(seconds: 0.4)))
        XCTAssertFalse(meter.reading.phaseInverted, "cleared after the clear hold")

        // Raise again, then silence clears it after the hold (silence reads 0 > −0.3).
        meter.append(interleaved: Self.inverted(Self.sine(seconds: 1.5)))
        XCTAssertTrue(meter.reading.phaseInverted)
        meter.append(interleaved: [Float](repeating: 0, count: Int(1.5 * Self.rate) * 2))
        XCTAssertEqual(meter.reading.correlation, 0)
        XCTAssertFalse(meter.reading.phaseInverted)
    }

    // MARK: US3 — calm input

    /// ANL-013-T06 (S3): silence, dither, one silent channel, NaN/inf, mono and fewer than two channels.
    func testSilenceOneSidedNaNMonoAndChannelCount() {
        let silence = Self.measure([Float](repeating: 0, count: 44_100 * 2))
        XCTAssertEqual(silence, .none)
        let dither = TestSupport.noise(count: 44_100, seed: 0xD1, amplitude: 1 / 32_768)
        XCTAssertEqual(Self.measure(Self.inverted(dither)).correlation, 0, "±1 LSB dither is below the floor")
        let tone = Self.sine(seconds: 0.5)
        let oneSided = Self.measure(Self.stereo(tone, [Float](repeating: 0, count: tone.count)))
        XCTAssertEqual(oneSided.correlation, 0)
        XCTAssertFalse(oneSided.hasSignal)

        var poisoned = Self.inverted(tone)
        for n in stride(from: 0, to: poisoned.count, by: 97) { poisoned[n] = [Float.nan, .infinity, -.infinity][n % 3] }
        let reading = Self.measure(poisoned)
        XCTAssertTrue(reading.correlation.isFinite)
        XCTAssertLessThan(reading.correlation, -0.9, "a few non-finite samples count as 0")
        let allNaN = Self.measure([Float](repeating: .nan, count: 8_192))
        XCTAssertEqual(allNaN.correlation, 0)

        // Mono, and every AUD-009 mode other than Mix (one signal in both channels): exactly 1, never a warning.
        var meter = StereoCorrelationMeter()
        meter.append(interleaved: Self.identical(TestSupport.noise(count: 3 * 44_100, seed: 0x3, amplitude: 0.5)))
        XCTAssertEqual(meter.reading.correlation, 1)
        XCTAssertFalse(meter.reading.phaseInverted)

        var mono = StereoCorrelationMeter()
        mono.append(interleaved: tone, channels: 1)
        XCTAssertEqual(mono.reading, .none, "fewer than two channels are ignored")
    }

    // MARK: US4 — determinism

    /// ANL-013-T07 (S4): repeats and chunkings are bit-equal; reset returns to `.none`.
    func testDeterministicAndChunkingInvariant() {
        let left = TestSupport.noise(count: 30_000, seed: 0x77, amplitude: 0.5)
        let right = zip(left, TestSupport.noise(count: 30_000, seed: 0x78, amplitude: 0.5)).map { (a: Float, b: Float) -> Float in
            -0.8 * a + 0.2 * b
        }
        let input = Self.stereo(left, right)
        let whole = Self.measure(input)
        XCTAssertEqual(whole.correlation.bitPattern, Self.measure(input).correlation.bitPattern)
        for chunk in [1, 333, 2_048] {
            var meter = StereoCorrelationMeter()
            input.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                var frame = 0
                let frames = buffer.count / 2
                while frame < frames {
                    let n = min(chunk, frames - frame)
                    meter.append(interleaved: buffer.baseAddress! + frame * 2, frames: n, channels: 2)
                    frame += n
                }
            }
            XCTAssertEqual(meter.reading.correlation.bitPattern, whole.correlation.bitPattern, "chunk \(chunk)")
            XCTAssertEqual(meter.reading, whole)
            meter.reset()
            XCTAssertEqual(meter.reading, .none)
        }
        XCTAssertLessThan(whole.correlation, -0.9)
    }

    // MARK: US5 — the pipeline

    /// ANL-013-T08 (S5): identical then inverted stereo through the ANL-016 pipeline.
    func testThePipelineCarriesTheCorrelationAndTheWarning() throws {
        let segment = Int(1.5 * Self.rate)
        let first = TestSupport.noise(count: segment, seed: 0xC0, amplitude: 0.5)
        let second = TestSupport.noise(count: segment, seed: 0xC1, amplitude: 0.5)
        let stereo = Self.identical(first) + Self.inverted(second)

        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.feed(stereo, into: ring, chunkFrames: 512) {
            pipeline.step()
            recorder.poll()
        }
        let frames = recorder.recording.frames
        let settle = Int(0.6 * Self.rate)   // τ = 0.1 s: e^−6 of the previous segment is left
        let same = frames.filter { (f: AnalysisFrame) -> Bool in
            let end = Int(f.time.sessionSample)
            return end >= settle && end <= segment
        }
        let flipped = frames.filter { (f: AnalysisFrame) -> Bool in Int(f.time.sessionSample) >= segment + settle }
        XCTAssertGreaterThanOrEqual(same.count, 40)
        XCTAssertGreaterThanOrEqual(flipped.count, 40)
        for f in same {
            XCTAssertGreaterThan(f.correlation, 0.99, "identical frame \(f.id)")
            XCTAssertFalse(f.phaseInverted)
        }
        for f in flipped { XCTAssertLessThan(f.correlation, -0.99, "inverted frame \(f.id)") }
        XCTAssertTrue(try XCTUnwrap(frames.last).phaseInverted, "raised after the hold")
        XCTAssertFalse(try XCTUnwrap(flipped.first).phaseInverted, "not at once")
        XCTAssertTrue(frames.allSatisfy { (f: AnalysisFrame) -> Bool in f.correlation.isFinite && (-1...1).contains(f.correlation) })

        pipeline.restartSession()
        BusFixture.feed(Self.identical([Float](repeating: 0, count: 4_096)), into: ring, chunkFrames: 512) {
            pipeline.step()
            recorder.poll()
        }
        let after = try XCTUnwrap(recorder.recording.frames.last)
        XCTAssertEqual(after.correlation, 0, "a session start resets the meter")
        XCTAssertFalse(after.phaseInverted)
        print("ANL-013 bus: \(frames.count) frames; identical min \(same.map(\.correlation).min() ?? 0), inverted max \(flipped.map(\.correlation).max() ?? 0)")
    }
}
