// SpectralRolloffTests.swift — ANL-011: the spectral rolloff (contracts/spectral-rolloff.md C1-C3).
// The acceptance feeds deterministic reference spectra with analytically known rolloff straight to
// the estimator (single tone, two tones, flat to a cutoff, linear power ramp), each within half a bin;
// then fractions, silence, NaN, backends, determinism and one short pipeline run. A few representative
// cases (owner rule 7). No Accelerate import, no C stdio globals, no clock.
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

final class SpectralRolloffTests: XCTestCase {
    private static let size: FFTSize = .n2048
    private static let rate: Double = 44_100
    /// Δf = R/N ≈ 21.53 Hz.
    private static let binWidth: Double = rate / Double(size.rawValue)
    private static let frame = SpectrumFrame(index: 0, size: size, sampleRate: rate, timestampNanoseconds: 0)

    // MARK: Fixtures

    /// A reference magnitude spectrum: `powers[k]` = P_k (m_k = √P_k), every other bin 0.
    private static func spectrum(_ powers: [Int: Double]) -> [Float] {
        var magnitudes = [Float](repeating: 0, count: size.binCount)
        for (bin, power) in powers { magnitudes[bin] = Float(power.squareRoot()) }
        return magnitudes
    }

    /// Bins 1…`count` with P_k = `power(k)`.
    private static func spectrum(bins count: Int, power: (Int) -> Double) -> [Float] {
        var powers: [Int: Double] = [:]
        for k in 1...count { powers[k] = power(k) }
        return spectrum(powers)
    }

    /// One frame through a fresh estimator at `fraction`.
    private static func reading(_ magnitudes: [Float], fraction: Double = 0.85,
                                backend: SpectrumBackend = .automatic) throws -> SpectralRolloffReading {
        var estimator = SpectralRolloffEstimator(configuration: try SpectralRolloffConfiguration(fraction: fraction), backend: backend)
        return magnitudes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> SpectralRolloffReading in
            estimator.process(frame, magnitudes: buffer)
        }
    }

    /// The rolloff in bins (Hz / Δf).
    private static func bins(_ magnitudes: [Float], fraction: Double = 0.85) throws -> Double {
        let r = try reading(magnitudes, fraction: fraction)
        XCTAssertTrue(r.hasSignal)
        return Double(r.hz) / binWidth
    }

    /// |measured − expected| ≤ half a bin (both in bins).
    private static func assertWithinHalfBin(_ measured: Double, _ expected: Double, _ message: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(measured - expected), 0.5 + 1e-6,
                                 "\(message): \(measured) bins vs \(expected) bins", file: file, line: line)
    }

    // MARK: Acceptance: reference spectra at p = 0.85 (T04)

    func testSingleToneReadsItsBin() throws {
        for k in [10, 93, 500] {
            let measured = try Self.bins(Self.spectrum([k: 0.25]))
            Self.assertWithinHalfBin(measured, Double(k), "tone at bin \(k)")
            XCTAssertEqual(measured, Double(k) - 0.5 + 0.85, accuracy: 1e-3, "in-bin interpolation (k − ½ + p)")
        }
    }

    func testTwoTonesFallOnTheComputedSide() throws {
        let lower = 50
        let higher = 200
        // 9 : 1 → the lower tone holds 90 % ≥ 85 %: the rolloff is the lower tone.
        let onLower = try Self.bins(Self.spectrum([lower: 9, higher: 1]))
        Self.assertWithinHalfBin(onLower, Double(lower), "9:1 falls on the lower tone")
        XCTAssertEqual(onLower, Double(lower) - 0.5 + 8.5 / 9, accuracy: 1e-3)
        // 4 : 1 → the lower tone holds 80 % < 85 %: the rolloff is the higher tone.
        let onHigher = try Self.bins(Self.spectrum([lower: 4, higher: 1]))
        Self.assertWithinHalfBin(onHigher, Double(higher), "4:1 falls on the higher tone")
        XCTAssertEqual(onHigher, Double(higher) - 0.25, accuracy: 1e-3)
        print("ANL-011 two tones: 9:1 → \(onLower) bins, 4:1 → \(onHigher) bins")
    }

    func testFlatPowerToACutoffReadsEightyFivePercentOfIt() throws {
        let count = 400
        let cutoff: Double = Double(count) + 0.5   // C: the last flat bin's upper edge, in bins
        let measured = try Self.bins(Self.spectrum(bins: count) { (_: Int) -> Double in 0.01 })
        Self.assertWithinHalfBin(measured, 0.85 * cutoff, "flat to C")
        XCTAssertEqual(measured, 0.5 + 0.85 * Double(count), accuracy: 1e-3, "exact for a flat spectrum")
        print("ANL-011 flat to \(cutoff * Self.binWidth) Hz: \(measured * Self.binWidth) Hz (0.85·C = \(0.85 * cutoff * Self.binWidth) Hz)")
    }

    func testLinearPowerRampReadsTheSquareRootPoint() throws {
        let count = 400
        let cutoff: Double = Double(count) + 0.5
        let measured = try Self.bins(Self.spectrum(bins: count) { (k: Int) -> Double in Double(k) * 1e-4 })
        let expected: Double = cutoff * 0.85.squareRoot()   // density ∝ f on [0, C]: F(f) = (f/C)²
        Self.assertWithinHalfBin(measured, expected, "linear power ramp")
        print("ANL-011 power ramp: \(measured) bins vs C·√0.85 = \(expected) bins")
    }

    // MARK: Fractions (T05)

    func testFractionsHalfAndNinetyNine() throws {
        let count = 400
        let cutoff: Double = Double(count) + 0.5
        let tone = Self.spectrum([93: 0.25])
        let pair = Self.spectrum([50: 9, 200: 1])
        let flat = Self.spectrum(bins: count) { (_: Int) -> Double in 0.01 }
        let ramp = Self.spectrum(bins: count) { (k: Int) -> Double in Double(k) * 1e-4 }
        for p in [0.5, 0.99] {
            Self.assertWithinHalfBin(try Self.bins(tone, fraction: p), 93, "tone, p = \(p)")
            XCTAssertEqual(try Self.bins(tone, fraction: p), 93 - 0.5 + p, accuracy: 1e-3)
            // 9:1 → the lower tone holds 90 %: p = 0.5 falls on it, p = 0.99 on the higher one.
            let pairExpected: Double = p <= 0.9 ? 50 : 200
            Self.assertWithinHalfBin(try Self.bins(pair, fraction: p), pairExpected, "two tones, p = \(p)")
            Self.assertWithinHalfBin(try Self.bins(flat, fraction: p), p * cutoff, "flat, p = \(p)")
            Self.assertWithinHalfBin(try Self.bins(ramp, fraction: p), cutoff * p.squareRoot(), "ramp, p = \(p)")
        }
        XCTAssertGreaterThan(try Self.bins(flat, fraction: 0.99), try Self.bins(flat, fraction: 0.85))
        XCTAssertGreaterThan(try Self.bins(flat, fraction: 0.85), try Self.bins(flat, fraction: 0.5))
    }

    func testConfigurationDefaultsNormalizationAndRefusals() throws {
        let standard = SpectralRolloffConfiguration.standard
        XCTAssertEqual(standard.fraction, 0.85)
        XCTAssertEqual(standard.sampleRate, 44_100)
        XCTAssertEqual(standard.lowerFrequency, 20)
        XCTAssertNil(standard.upperFrequency)
        XCTAssertEqual(standard.normalized(hz: 50), 0)
        XCTAssertEqual(standard.normalized(hz: 20_000), 1)
        XCTAssertEqual(standard.normalized(hz: 1_000), log2(20) / log2(400), accuracy: 1e-12)
        XCTAssertEqual(standard.normalized(hz: 30_000), 1, "clamped")
        XCTAssertEqual(standard.normalized(hz: .nan), 0)
        XCTAssertNoThrow(try SpectralRolloffConfiguration(fraction: 0.5))
        XCTAssertNoThrow(try SpectralRolloffConfiguration(fraction: 0.99))
        for bad in [0.49, 1.0, Double.nan] {
            XCTAssertThrowsError(try SpectralRolloffConfiguration(fraction: bad)) { (error: Error) -> Void in
                guard case .invalidFraction = error as? SpectralRolloffConfigurationError else {
                    return XCTFail("expected invalidFraction for \(bad), got \(error)")
                }
            }
        }
        XCTAssertThrowsError(try SpectralRolloffConfiguration(sampleRate: 0))
        XCTAssertThrowsError(try SpectralRolloffConfiguration(lowerFrequency: 30_000))
        XCTAssertThrowsError(try SpectralRolloffConfiguration(floorDecibels: 0))
        XCTAssertThrowsError(try SpectralRolloffConfiguration(normalizationLower: 100, normalizationUpper: 50))
    }

    // MARK: Silence and bad input (T06)

    func testSilenceDitherNaNAndMismatchedFrames() throws {
        let silence = [Float](repeating: 0, count: 2_048)
        let dither = TestSupport.noise(count: 2_048, seed: 7, amplitude: 1.0 / 32_768.0)
        let analyzer = SpectrumAnalyzer(backend: .automatic)
        XCTAssertEqual(try Self.reading(analyzer.magnitudes(of: silence, size: Self.size)), .none)
        XCTAssertEqual(try Self.reading(analyzer.magnitudes(of: dither, size: Self.size)), .none, "dither is below −70 dB")

        var estimator = SpectralRolloffEstimator()
        let tone = Self.spectrum([93: 0.25])
        let loud = tone.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> SpectralRolloffReading in
            estimator.process(Self.frame, magnitudes: b)
        }
        XCTAssertTrue(loud.hasSignal)
        let quiet = analyzer.magnitudes(of: silence, size: Self.size).withUnsafeBufferPointer {
            (b: UnsafeBufferPointer<Float>) -> SpectralRolloffReading in estimator.process(Self.frame, magnitudes: b)
        }
        XCTAssertEqual(quiet, .none, "silence after a tone reads 0, not the held tone")

        // Mismatched frames leave the reading unchanged.
        _ = tone.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> SpectralRolloffReading in
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

        // Non-finite magnitudes count as 0, on every backend.
        var poisoned = Self.spectrum([93: 0.25])
        poisoned[10] = .nan
        poisoned[20] = .infinity
        poisoned[30] = -.infinity
        for backend: SpectrumBackend in [.automatic, .portable] {
            let r = try Self.reading(poisoned, backend: backend)
            XCTAssertTrue(r.hz.isFinite && r.normalized.isFinite)
            XCTAssertEqual(Double(r.hz) / Self.binWidth, 93.35, accuracy: 1e-3, "\(backend)")
        }
        var allBad = [Float](repeating: .nan, count: Self.size.binCount)
        allBad[0] = .infinity
        XCTAssertEqual(try Self.reading(allBad), .none, "nothing finite reads 0")

        estimator.reset()
        XCTAssertEqual(estimator.reading, .none)
    }

    // MARK: Determinism and backends (T07)

    func testDeterministicAndBackendsAgree() throws {
        let noise = TestSupport.noise(count: 2_048, seed: 0x5EED, amplitude: 0.5)
        let magnitudes = SpectrumAnalyzer(backend: .portable).magnitudes(of: noise, size: Self.size)
        let range = try XCTUnwrap(SpectralRolloffConfiguration.standard.binRange(size: Self.size))
        func measure(_ backend: SpectrumBackend, _ p: Double) -> (hz: Double, power: Double) {
            magnitudes.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> (hz: Double, power: Double) in
                SpectralRolloffEstimator.measure(magnitudes: b, range: range, fraction: p, binWidth: Self.binWidth,
                                                 nyquist: Self.rate / 2, backend: backend)
            }
        }
        for p in [0.5, 0.85, 0.99] {
            let first = measure(.automatic, p)
            let again = measure(.automatic, p)
            XCTAssertEqual(first.hz.bitPattern, again.hz.bitPattern, "bit-equal repeat at p = \(p)")
            let portable = measure(.portable, p)
            let accelerated = measure(.accelerated, p)
            XCTAssertEqual(accelerated.hz / Self.binWidth, portable.hz / Self.binWidth, accuracy: 1e-3, "backends at p = \(p)")
            XCTAssertEqual(accelerated.power, portable.power, accuracy: portable.power * 1e-5)
            if !SpectrumBackend.isAcceleratedAvailable {
                XCTAssertEqual(accelerated.hz.bitPattern, portable.hz.bitPattern, "the Linux shape resolves to portable")
            }
        }
        let white = measure(.automatic, 0.85).hz
        print("ANL-011 white noise rolloff: \(white) Hz (0.85·Nyquist ≈ \(0.85 * Self.rate / 2) Hz), accelerated available: \(SpectrumBackend.isAcceleratedAvailable)")
        XCTAssertEqual(white, 0.85 * Self.rate / 2, accuracy: 0.05 * Self.rate / 2, "white noise rolls off near 0.85·Nyquist")
    }

    // MARK: Bus (T08)

    func testThePipelineCarriesTheRolloff() throws {
        let lead = 2_205                       // 0.05 s of silence
        let segment = 8_820                    // 0.2 s each
        var mono = [Float](repeating: 0, count: lead)
        mono += (0..<segment).map { (n: Int) -> Float in
            let phase: Double = 2 * Double.pi * 300 * Double(n) / Self.rate + 0.3
            return 0.5 * Float(sin(phase))
        }
        mono += TestSupport.noise(count: segment, seed: 0xA11, amplitude: 0.5)
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
        let low = frames.filter { (f: AnalysisFrame) -> Bool in inside(f, from: lead, to: lead + segment) }
        let bright = frames.filter { (f: AnalysisFrame) -> Bool in inside(f, from: lead + segment, to: lead + 2 * segment) }
        XCTAssertFalse(silent.isEmpty)
        XCTAssertGreaterThanOrEqual(low.count, 8)
        XCTAssertGreaterThanOrEqual(bright.count, 8)
        for f in silent { XCTAssertEqual(f.rolloffHz, 0); XCTAssertEqual(f.rolloff, 0) }
        // A Hann-windowed 300 Hz sine: the 85 % point lies in its main lobe (within two bins).
        for f in low { XCTAssertEqual(Double(f.rolloffHz), 300, accuracy: 2 * Self.binWidth, "300 Hz frame \(f.id)") }
        let lowest: Float = try XCTUnwrap(bright.map(\.rolloff).min())
        let highestLow: Float = try XCTUnwrap(low.map(\.rolloff).max())
        XCTAssertGreaterThan(lowest, highestLow, "noise reads brighter than the low tone in every frame")
        XCTAssertTrue(frames.allSatisfy { (f: AnalysisFrame) -> Bool in
            f.rolloffHz.isFinite && f.rolloff.isFinite && (0...1).contains(f.rolloff)
        })
        print("ANL-011 bus: \(frames.count) frames; 300 Hz rolloff \(low.first?.rolloffHz ?? 0) Hz, noise \(bright.first?.rolloffHz ?? 0) Hz")

        XCTAssertThrowsError(try AnalysisPipelineConfiguration(rolloff: try SpectralRolloffConfiguration(sampleRate: 48_000))) {
            (error: Error) -> Void in XCTAssertEqual(error as? AnalysisBusError, .sampleRateMismatch)
        }
    }
}
