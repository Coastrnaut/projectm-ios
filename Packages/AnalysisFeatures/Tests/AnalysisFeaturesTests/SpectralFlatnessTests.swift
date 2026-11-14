// SpectralFlatnessTests.swift — ANL-012: spectral flatness (contracts/spectral-flatness.md C1-C3).
// The acceptance compares a deterministic sine (a single-bin spectrum and windowed PCM) with a seeded
// white-noise fixture through ANL-001's analyzer; then a flat spectrum (exactly 1), silence, NaN, a
// one-bin range, backends, scale invariance, determinism and one short pipeline run. A few
// representative cases (owner rule 7). No Accelerate import, no C stdio globals, no clock.
import XCTest
import AudioCore
@testable import AnalysisFeatures
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

final class SpectralFlatnessTests: XCTestCase {
    private static let size: FFTSize = .n2048
    private static let rate: Double = 44_100
    private static let frame = SpectrumFrame(index: 0, size: size, sampleRate: rate, timestampNanoseconds: 0)
    /// e^−γ: the flatness of exponentially distributed bin power (white noise).
    private static let noiseExpectation: Double = exp(-0.5772156649015329)

    // MARK: Fixtures

    /// A magnitude spectrum: `powers[k]` = P_k (m_k = √P_k), every other bin 0.
    private static func spectrum(_ powers: [Int: Double]) -> [Float] {
        var magnitudes = [Float](repeating: 0, count: size.binCount)
        for (bin, power) in powers { magnitudes[bin] = Float(power.squareRoot()) }
        return magnitudes
    }

    /// One frame through a fresh estimator.
    private static func reading(_ magnitudes: [Float], configuration: SpectralFlatnessConfiguration = .standard,
                                backend: SpectrumBackend = .automatic) -> SpectralFlatnessReading {
        var estimator = SpectralFlatnessEstimator(configuration: configuration, backend: backend)
        return magnitudes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> SpectralFlatnessReading in
            estimator.process(frame, magnitudes: buffer)
        }
    }

    /// A 0.5-amplitude sine of `hz` over one frame.
    private static func sine(hz: Double) -> [Float] {
        (0..<size.rawValue).map { (n: Int) -> Float in
            let phase: Double = 2 * Double.pi * hz * Double(n) / rate + 0.3
            return 0.5 * Float(sin(phase))
        }
    }

    /// `count` seeded white-noise frames (amplitude 0.5) through the portable analyzer.
    private static func noiseFlatness(frames count: Int) -> [Double] {
        let analyzer = SpectrumAnalyzer(backend: .portable)
        return (0..<count).map { (index: Int) -> Double in
            let pcm = TestSupport.noise(count: size.rawValue, seed: UInt64(0x5EED + index), amplitude: 0.5)
            let r = reading(analyzer.magnitudes(of: pcm, size: size))
            XCTAssertTrue(r.hasSignal)
            return Double(r.flatness)
        }
    }

    // MARK: Acceptance: sine < white noise (T04)

    func testSineReadsLowerFlatnessThanTheWhiteNoiseFixture() {
        // A deterministic single-bin sine spectrum: effectively 0.
        let lone = Self.reading(Self.spectrum([93: 0.25]))
        XCTAssertTrue(lone.hasSignal)
        XCTAssertLessThan(lone.flatness, 0.05)
        // PCM sines through ANL-001 (Hann): a bin-centred one (bin 93) and an off-bin 1 kHz one.
        let analyzer = SpectrumAnalyzer(backend: .portable)
        let binHz: Double = 93 * Self.rate / Double(Self.size.rawValue)
        var sines: [Double] = []
        for hz in [binHz, 1_000] {
            let r = Self.reading(analyzer.magnitudes(of: Self.sine(hz: hz), size: Self.size))
            XCTAssertTrue(r.hasSignal)
            XCTAssertLessThan(r.flatness, 0.05, "sine at \(hz) Hz")
            sines.append(Double(r.flatness))
        }
        // The seeded white-noise fixture: every frame > 0.4, mean near e^−γ ≈ 0.56.
        let noise = Self.noiseFlatness(frames: 8)
        let lowest: Double = noise.min() ?? 0
        let mean: Double = noise.reduce(0, +) / Double(noise.count)
        XCTAssertGreaterThan(lowest, 0.4)
        XCTAssertTrue((0.45...0.65).contains(mean), "noise mean \(mean)")
        let highestSine: Double = max(sines.max() ?? 1, Double(lone.flatness))
        XCTAssertGreaterThanOrEqual(lowest - highestSine, 0.3, "sine below noise by a margin")
        print("ANL-012 flatness: single bin \(lone.flatness), sines \(sines), noise mean \(mean) (e^−γ = \(Self.noiseExpectation)), lowest noise \(lowest)")
    }

    func testFlatSpectrumReadsExactlyOne() throws {
        let range = try XCTUnwrap(SpectralFlatnessConfiguration.standard.binRange(size: Self.size))
        var powers: [Int: Double] = [:]
        for k in range.first...range.last { powers[k] = 0.01 }
        for backend: SpectrumBackend in [.automatic, .portable] {
            let r = Self.reading(Self.spectrum(powers), backend: backend)
            XCTAssertTrue(r.hasSignal)
            XCTAssertEqual(Double(r.flatness), 1, accuracy: 1e-9, "\(backend)")
            let measured = Self.spectrum(powers).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Double in
                SpectralFlatnessEstimator.measure(magnitudes: b, range: range, backend: backend).flatness
            }
            XCTAssertEqual(measured, 1, accuracy: 1e-9, "\(backend), Double")
        }
    }

    func testConfigurationDefaultsAndRefusals() throws {
        let standard = SpectralFlatnessConfiguration.standard
        XCTAssertEqual(standard.sampleRate, 44_100)
        XCTAssertEqual(standard.lowerFrequency, 20)
        XCTAssertNil(standard.upperFrequency)
        XCTAssertEqual(standard.floorDecibels, -70)
        XCTAssertEqual(SpectralFlatnessConfiguration.relativeEpsilon, 1e-12)
        XCTAssertThrowsError(try SpectralFlatnessConfiguration(sampleRate: 0))
        XCTAssertThrowsError(try SpectralFlatnessConfiguration(sampleRate: .nan))
        XCTAssertThrowsError(try SpectralFlatnessConfiguration(lowerFrequency: 30_000))
        XCTAssertThrowsError(try SpectralFlatnessConfiguration(lowerFrequency: 100, upperFrequency: 50))
        XCTAssertThrowsError(try SpectralFlatnessConfiguration(floorDecibels: 0)) { (error: Error) -> Void in
            XCTAssertEqual(error as? SpectralFlatnessConfigurationError, .invalidFloor(0))
        }
    }

    // MARK: Silence and bad input (T05)

    func testSilenceDitherNaNOneBinAndMismatchedFrames() throws {
        let silence = [Float](repeating: 0, count: 2_048)
        let dither = TestSupport.noise(count: 2_048, seed: 7, amplitude: 1.0 / 32_768.0)
        let analyzer = SpectrumAnalyzer(backend: .automatic)
        XCTAssertEqual(Self.reading(analyzer.magnitudes(of: silence, size: Self.size)), .none)
        XCTAssertEqual(Self.reading(analyzer.magnitudes(of: dither, size: Self.size)), .none, "dither is below −70 dB, not noise")

        var estimator = SpectralFlatnessEstimator()
        let tone = Self.spectrum([93: 0.25])
        let loud = tone.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> SpectralFlatnessReading in
            estimator.process(Self.frame, magnitudes: b)
        }
        XCTAssertTrue(loud.hasSignal)
        let quiet = analyzer.magnitudes(of: silence, size: Self.size).withUnsafeBufferPointer {
            (b: UnsafeBufferPointer<Float>) -> SpectralFlatnessReading in estimator.process(Self.frame, magnitudes: b)
        }
        XCTAssertEqual(quiet, .none, "silence after a tone reads 0")

        // Mismatched frames leave the reading unchanged.
        _ = tone.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> SpectralFlatnessReading in
            estimator.process(Self.frame, magnitudes: b)
        }
        let before = estimator.reading
        let other = SpectrumFrame(index: 0, size: Self.size, sampleRate: 48_000, timestampNanoseconds: 0)
        silence.prefix(Self.size.binCount).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            estimator.process(other, magnitudes: b)
        }
        XCTAssertEqual(estimator.reading, before, "another sample rate is ignored")
        Array(silence.prefix(100)).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            estimator.process(Self.frame, magnitudes: b)
        }
        XCTAssertEqual(estimator.reading, before, "a wrong magnitude count is ignored")
        estimator.reset()
        XCTAssertEqual(estimator.reading, .none)

        // Non-finite magnitudes count as power 0, on every backend; the value stays finite and bounded.
        var poisoned = Self.spectrum([93: 0.25])
        poisoned[10] = .nan
        poisoned[20] = .infinity
        poisoned[30] = -.infinity
        let noise = analyzer.magnitudes(of: TestSupport.noise(count: 2_048, seed: 3, amplitude: 0.5), size: Self.size)
        var poisonedNoise = noise
        poisonedNoise[40] = .nan
        for backend: SpectrumBackend in [.automatic, .portable] {
            for input in [poisoned, poisonedNoise] {
                let r = Self.reading(input, backend: backend)
                XCTAssertTrue(r.hasSignal)
                XCTAssertTrue(r.flatness.isFinite && (0...1).contains(r.flatness), "\(backend): \(r.flatness)")
            }
            XCTAssertLessThan(Self.reading(poisoned, backend: backend).flatness, 0.05)
            XCTAssertGreaterThan(Self.reading(poisonedNoise, backend: backend).flatness, 0.4)
        }
        var allBad = [Float](repeating: .nan, count: Self.size.binCount)
        allBad[0] = .infinity
        XCTAssertEqual(Self.reading(allBad), .none, "nothing finite reads 0")

        // A range of one bin: G = A, so an audible bin reads 1 (spec Edge Cases).
        let single = try SpectralFlatnessConfiguration(lowerFrequency: 2_000, upperFrequency: 2_010)
        let oneBin = try XCTUnwrap(single.binRange(size: Self.size))
        XCTAssertEqual(oneBin.count, 1)
        let r = Self.reading(Self.spectrum([oneBin.first: 0.25]), configuration: single)
        XCTAssertTrue(r.hasSignal)
        XCTAssertEqual(Double(r.flatness), 1, accuracy: 1e-9)
    }

    // MARK: Determinism, backends, scale (T06)

    func testDeterministicBackendsAgreeAndScaleInvariant() throws {
        let analyzer = SpectrumAnalyzer(backend: .portable)
        let noise = analyzer.magnitudes(of: TestSupport.noise(count: 2_048, seed: 0x5EED, amplitude: 0.5), size: Self.size)
        let tone = analyzer.magnitudes(of: Self.sine(hz: 1_000), size: Self.size)
        let range = try XCTUnwrap(SpectralFlatnessConfiguration.standard.binRange(size: Self.size))
        func measure(_ magnitudes: [Float], _ backend: SpectrumBackend) -> (flatness: Double, power: Double) {
            magnitudes.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> (flatness: Double, power: Double) in
                SpectralFlatnessEstimator.measure(magnitudes: b, range: range, backend: backend)
            }
        }
        for input in [noise, tone] {
            let first = measure(input, .automatic)
            let again = measure(input, .automatic)
            XCTAssertEqual(first.flatness.bitPattern, again.flatness.bitPattern, "bit-equal repeat")
            let portable = measure(input, .portable)
            let accelerated = measure(input, .accelerated)
            XCTAssertEqual(accelerated.flatness, portable.flatness, accuracy: 1e-6, "backends")
            XCTAssertEqual(accelerated.power, portable.power, accuracy: portable.power * 1e-5)
            if !SpectrumBackend.isAcceleratedAvailable {
                XCTAssertEqual(accelerated.flatness.bitPattern, portable.flatness.bitPattern, "the Linux shape resolves to portable")
            }
            // Scale invariance: ×10 in magnitude (×100 in power) reads the same flatness.
            let louder = input.map { (m: Float) -> Float in m * 10 }
            XCTAssertEqual(measure(louder, .portable).flatness, portable.flatness, accuracy: 1e-6, "scale-invariant")
        }
        print("ANL-012 backends: noise \(measure(noise, .automatic).flatness), 1 kHz \(measure(tone, .automatic).flatness), accelerated available: \(SpectrumBackend.isAcceleratedAvailable)")
    }

    // MARK: Bus (T07)

    func testThePipelineCarriesTheFlatness() throws {
        let lead = 2_205                       // 0.05 s of silence
        let segment = 8_820                    // 0.2 s each
        var mono = [Float](repeating: 0, count: lead)
        mono += (0..<segment).map { (n: Int) -> Float in
            let phase: Double = 2 * Double.pi * 440 * Double(n) / Self.rate + 0.3
            return 0.5 * Float(sin(phase))
        }
        mono += TestSupport.noise(count: segment, seed: 0xA12, amplitude: 0.5)
        var stereo = [Float](repeating: 0, count: mono.count * 2)
        for (n, value) in mono.enumerated() { stereo[2 * n] = value; stereo[2 * n + 1] = value }

        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.feed(stereo, into: ring, chunkFrames: 512) {
            pipeline.step()
            recorder.poll()
        }
        let frames = recorder.recording.frames
        let size = 2_048
        func inside(_ frame: AnalysisFrame, from start: Int, to end: Int) -> Bool {
            let windowEnd = Int(frame.time.sessionSample)
            return windowEnd - size >= start && windowEnd <= end
        }
        let silent = frames.filter { (f: AnalysisFrame) -> Bool in Int(f.time.sessionSample) <= lead }
        let tonal = frames.filter { (f: AnalysisFrame) -> Bool in inside(f, from: lead, to: lead + segment) }
        let noisy = frames.filter { (f: AnalysisFrame) -> Bool in inside(f, from: lead + segment, to: lead + 2 * segment) }
        XCTAssertFalse(silent.isEmpty)
        XCTAssertGreaterThanOrEqual(tonal.count, 8)
        XCTAssertGreaterThanOrEqual(noisy.count, 8)
        for f in silent { XCTAssertEqual(f.flatness, 0) }
        for f in tonal { XCTAssertLessThan(f.flatness, 0.05, "440 Hz frame \(f.id)") }
        let lowestNoise: Float = try XCTUnwrap(noisy.map(\.flatness).min())
        let highestTone: Float = try XCTUnwrap(tonal.map(\.flatness).max())
        XCTAssertGreaterThan(lowestNoise, 0.4)
        XCTAssertGreaterThan(lowestNoise, highestTone, "noise reads flatter than the tone in every frame")
        XCTAssertTrue(frames.allSatisfy { (f: AnalysisFrame) -> Bool in f.flatness.isFinite && (0...1).contains(f.flatness) })
        print("ANL-012 bus: \(frames.count) frames; 440 Hz max \(highestTone), noise min \(lowestNoise)")

        XCTAssertThrowsError(try AnalysisPipelineConfiguration(flatness: try SpectralFlatnessConfiguration(sampleRate: 48_000))) {
            (error: Error) -> Void in XCTAssertEqual(error as? AnalysisBusError, .sampleRateMismatch)
        }
    }
}
