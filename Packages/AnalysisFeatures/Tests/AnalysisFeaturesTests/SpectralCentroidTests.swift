// SpectralCentroidTests.swift — ANL-010: the power-weighted spectral centroid (contracts/
// spectral-centroid.md C1-C3). Synthetic PCM, one analysis window per case through the real
// SpectrumAnalyzer (every compiled backend), plus one short pipeline run; a few representative cases
// (owner rule 7). No Accelerate import, no C stdio globals, no clock.
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

final class SpectralCentroidTests: XCTestCase {
    // MARK: Fixtures

    /// `amplitude`·sin(2π·f·n/R + 0.3): deliberately not bin-centred.
    private static func sine(_ frequency: Double, amplitude: Float = 0.5, count: Int, rate: Double = 44_100) -> [Float] {
        (0..<count).map { (n: Int) -> Float in
            let phase: Double = 2 * Double.pi * frequency * Double(n) / rate + 0.3
            return amplitude * Float(sin(phase))
        }
    }

    private static func amplitude(dBFS: Double) -> Float {
        let linear: Double = pow(10, dBFS / 20)
        return Float(linear)
    }

    /// Analyses `samples[0..<size]` with `backend` and feeds the spectrum to `estimator`.
    private static func process(_ samples: [Float], size: FFTSize = .n2048, rate: Double = 44_100,
                                backend: SpectrumBackend = .automatic,
                                into estimator: inout SpectralCentroidEstimator) -> SpectralCentroidReading {
        let magnitudes = SpectrumAnalyzer(backend: backend).magnitudes(of: samples, size: size)
        let frame = SpectrumFrame(index: 0, size: size, sampleRate: rate, timestampNanoseconds: 0)
        return magnitudes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> SpectralCentroidReading in
            estimator.process(frame, magnitudes: buffer)
        }
    }

    /// One window through a fresh estimator.
    private static func reading(_ samples: [Float], size: FFTSize = .n2048, rate: Double = 44_100,
                                backend: SpectrumBackend = .automatic) throws -> SpectralCentroidReading {
        var estimator = SpectralCentroidEstimator(configuration: try SpectralCentroidConfiguration(sampleRate: rate))
        return process(samples, size: size, rate: rate, backend: backend, into: &estimator)
    }

    private static func assertWithin(_ value: Float, _ expected: Double, relative: Double, _ message: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let error: Double = abs(Double(value) - expected)
        let allowed: Double = expected * relative
        XCTAssertLessThanOrEqual(error, allowed, "\(message): \(value) Hz vs \(expected) Hz", file: file, line: line)
    }

    // MARK: Bin range and configuration (T02)

    func testBinRangeExcludesDCAndClampsToNyquist() throws {
        let standard = try XCTUnwrap(SpectralBinRange(lowerFrequency: 20, upperFrequency: 22_050, size: .n2048, sampleRate: 44_100))
        XCTAssertEqual(standard.first, 1, "⌈20·2048/44100⌉ = 1")
        XCTAssertEqual(standard.last, 1_024)
        XCTAssertEqual(standard.count, 1_024)
        let fine = try XCTUnwrap(SpectralBinRange(lowerFrequency: 20, upperFrequency: 1e9, size: .n8192, sampleRate: 44_100))
        XCTAssertEqual(fine.first, 4, "⌈3.715⌉")
        XCTAssertEqual(fine.last, 4_096, "clamped to Nyquist")
        let dc = try XCTUnwrap(SpectralBinRange(lowerFrequency: 0, upperFrequency: 100, size: .n512, sampleRate: 44_100))
        XCTAssertEqual(dc.first, 1, "DC is never included")
        XCTAssertEqual(dc.last, 1, "⌊1.16⌋")
        XCTAssertNil(SpectralBinRange(lowerFrequency: 30, upperFrequency: 40, size: .n512, sampleRate: 44_100), "no whole bin")
        XCTAssertNil(SpectralBinRange(lowerFrequency: 100, upperFrequency: 50, size: .n512, sampleRate: 44_100))
        XCTAssertNil(SpectralBinRange(lowerFrequency: .nan, upperFrequency: 50, size: .n512, sampleRate: 44_100))
        XCTAssertNil(SpectralBinRange(lowerFrequency: 20, upperFrequency: 50, size: .n512, sampleRate: 0))
    }

    func testStandardConfigurationAndNormalization() throws {
        let standard = SpectralCentroidConfiguration.standard
        XCTAssertEqual(standard.sampleRate, 44_100)
        XCTAssertEqual(standard.lowerFrequency, 20)
        XCTAssertNil(standard.upperFrequency, "Nyquist")
        XCTAssertEqual(standard.floorDecibels, -70)
        XCTAssertEqual(standard.normalizationLower, 50)
        XCTAssertEqual(standard.normalizationUpper, 10_000)
        XCTAssertEqual(try SpectralCentroidConfiguration(), standard)
        XCTAssertEqual(standard.floorPower, 1.5e-7, accuracy: 1e-12)
        XCTAssertEqual(standard.normalized(hz: 50), 0)
        XCTAssertEqual(standard.normalized(hz: 10_000), 1)
        XCTAssertEqual(standard.normalized(hz: 20), 0, "clamped below")
        XCTAssertEqual(standard.normalized(hz: 15_000), 1, "clamped above")
        XCTAssertEqual(standard.normalized(hz: 1_000), 0.5654, accuracy: 1e-4)
        XCTAssertEqual(standard.normalized(hz: 100), 0.1308, accuracy: 1e-4, "one octave = 1/7.64")
        XCTAssertEqual(standard.normalized(hz: .nan), 0)
        XCTAssertEqual(standard.normalized(hz: -5), 0)
        XCTAssertEqual(standard.normalized(hz: .infinity), 0)
    }

    func testInvalidConfigurationsThrow() {
        XCTAssertThrowsError(try SpectralCentroidConfiguration(sampleRate: 0))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(sampleRate: .nan))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(lowerFrequency: 0))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(lowerFrequency: 22_050))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(upperFrequency: 20))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(upperFrequency: .infinity))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(floorDecibels: 0))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(floorDecibels: .nan))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(normalizationLower: 0))
        XCTAssertThrowsError(try SpectralCentroidConfiguration(normalizationLower: 100, normalizationUpper: 100))
        do {
            _ = try SpectralCentroidConfiguration(upperFrequency: 10)
            XCTFail("expected a range error")
        } catch {
            XCTAssertEqual(error, .invalidFrequencyRange(lower: 20, upper: 10))
        }
    }

    // MARK: US1 — brighter reads higher (T04)

    func testRisingToneFrequencyRaisesTheCentroidMonotonically() throws {
        let tones: [Double] = [100, 200, 400, 800, 1_600, 3_200, 6_400]
        for backend in TestSupport.backends {
            var previous: SpectralCentroidReading?
            var table: [String] = []
            for tone in tones {
                let r = try Self.reading(Self.sine(tone, amplitude: Self.amplitude(dBFS: -6), count: 2_048), backend: backend)
                table.append("\(Int(tone)) Hz → \(r.hz) Hz, \(r.normalized)")
                XCTAssertTrue(r.hasSignal)
                Self.assertWithin(r.hz, tone, relative: 0.01, "tone \(tone) Hz")
                XCTAssertTrue((0...1).contains(r.normalized))
                if let previous {
                    XCTAssertGreaterThan(r.hz, previous.hz, "strictly increasing Hz")
                    XCTAssertGreaterThan(r.normalized, previous.normalized, "strictly increasing normalized")
                }
                previous = r
            }
            print("ANL-010 tone table (\(backend)): \(table.joined(separator: "; "))")
        }
    }

    func testWhiteNoiseReadsTheMeanOfTheAnalysedRange() throws {
        let noise = TestSupport.noise(count: 2_048, seed: 0x5EED, amplitude: 0.5)
        let r = try Self.reading(noise)
        let binWidth: Double = 44_100.0 / 2_048.0
        let expected: Double = Double(1 + 1_024) / 2 * binWidth        // ≈ 11,035 Hz
        print("ANL-010 white noise: \(r.hz) Hz (expected ≈ \(expected)), normalized \(r.normalized)")
        Self.assertWithin(r.hz, expected, relative: 0.05, "white noise")
        XCTAssertEqual(r.normalized, 1, "above 10 kHz reads 1")
    }

    func testTwoTonesReadTheirPowerWeightedMean() throws {
        let low = Self.sine(500, amplitude: 0.4, count: 2_048)
        let equal = zip(low, Self.sine(2_000, amplitude: 0.4, count: 2_048)).map { (a: Float, b: Float) -> Float in a + b }
        let quiet = zip(low, Self.sine(2_000, amplitude: 0.1, count: 2_048)).map { (a: Float, b: Float) -> Float in a + b }
        Self.assertWithin(try Self.reading(equal).hz, 1_250, relative: 0.01, "equal tones")
        // Amplitudes 1 : 0.25 → (1·500 + 0.0625·2000) / 1.0625 = 588.2 Hz.
        let weightLow: Double = 1
        let weightHigh: Double = 0.0625
        let expected: Double = (weightLow * 500 + weightHigh * 2_000) / (weightLow + weightHigh)
        Self.assertWithin(try Self.reading(quiet).hz, expected, relative: 0.01, "1 : 0.25 tones")
    }

    // MARK: US2 — the same reading everywhere (T05)

    func testSizesRatesAndLevelsAgree() throws {
        for rate: Double in [44_100, 48_000] {
            for size in FFTSize.allCases {
                let r = try Self.reading(Self.sine(1_000, count: size.rawValue, rate: rate), size: size, rate: rate)
                Self.assertWithin(r.hz, 1_000, relative: 0.01, "1 kHz at \(size.rawValue) points, \(rate) Hz")
            }
        }
        Self.assertWithin(try Self.reading(Self.sine(200, count: 512), size: .n512).hz, 200, relative: 0.01, "200 Hz at 512")
        Self.assertWithin(try Self.reading(Self.sine(100, count: 1_024), size: .n1024).hz, 100, relative: 0.01, "100 Hz at 1,024")
        let loud = try Self.reading(Self.sine(2_500, amplitude: Self.amplitude(dBFS: -6), count: 2_048))
        let soft = try Self.reading(Self.sine(2_500, amplitude: Self.amplitude(dBFS: -40), count: 2_048))
        Self.assertWithin(soft.hz, Double(loud.hz), relative: 0.001, "level independence")
    }

    // MARK: US3 — silence is calm (T06)

    func testSilenceDitherAndHold() throws {
        let silence = [Float](repeating: 0, count: 2_048)
        let dither = TestSupport.noise(count: 2_048, seed: 7, amplitude: 1.0 / 32_768.0)
        XCTAssertEqual(try Self.reading(silence), .none)
        XCTAssertEqual(try Self.reading(dither), .none, "dither is below the −70 dB floor")

        var estimator = SpectralCentroidEstimator()
        let tone = Self.process(Self.sine(3_000, count: 2_048), into: &estimator)
        XCTAssertTrue(tone.hasSignal)
        let held = Self.process(silence, into: &estimator)
        XCTAssertEqual(held.hz, tone.hz, "Hz held exactly")
        XCTAssertEqual(held.normalized, tone.normalized, "normalized held exactly")
        XCTAssertFalse(held.hasSignal)
        XCTAssertEqual(Self.process(dither, into: &estimator).hz, tone.hz)

        // Mismatched frames leave the reading unchanged; non-finite magnitudes give finite output.
        let other = SpectrumFrame(index: 0, size: .n2048, sampleRate: 48_000, timestampNanoseconds: 0)
        let ones = [Float](repeating: 1, count: FFTSize.n2048.binCount)
        let before = estimator.reading
        ones.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in estimator.process(other, magnitudes: b) }
        XCTAssertEqual(estimator.reading, before, "another sample rate is ignored")
        let frame = SpectrumFrame(index: 0, size: .n2048, sampleRate: 44_100, timestampNanoseconds: 0)
        Array(ones.prefix(100)).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in estimator.process(frame, magnitudes: b) }
        XCTAssertEqual(estimator.reading, before, "a wrong magnitude count is ignored")
        var poisoned = [Float](repeating: 0, count: FFTSize.n2048.binCount)
        poisoned[10] = .nan
        poisoned[20] = .infinity
        poisoned[93] = 1                                   // ≈ 2 kHz
        let r = poisoned.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> SpectralCentroidReading in
            estimator.process(frame, magnitudes: b)
        }
        XCTAssertTrue(r.hz.isFinite && r.normalized.isFinite)
        XCTAssertEqual(Double(r.hz), FFTSize.n2048.frequency(ofBin: 93, sampleRate: 44_100), accuracy: 0.01)

        estimator.reset()
        XCTAssertEqual(estimator.reading, .none)
    }

    // MARK: Bus (T07)

    func testThePipelineCarriesBothValuesInEveryFrame() throws {
        let rate = 44_100
        let lead = 2_205                       // 0.05 s of silence
        let segment = 8_820                    // 0.2 s per tone
        var mono = [Float](repeating: 0, count: lead)
        mono += Self.sine(300, count: segment)
        mono += Self.sine(3_000, count: segment)
        var stereo = [Float](repeating: 0, count: mono.count * 2)
        for (n, value) in mono.enumerated() { stereo[2 * n] = value; stereo[2 * n + 1] = value }

        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let pipeline = AnalysisPipeline(clock: StepClock().function)
        let recorder = BusRecorder(try pipeline.subscribe(eventCapacity: 256))
        pipeline.attach(try XCTUnwrap(ring.analysisTap))
        BusFixture.feed(stereo, into: ring, chunkFrames: 512) {   // one hop per chunk: every frame is seen
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
        let high = frames.filter { (f: AnalysisFrame) -> Bool in inside(f, from: lead + segment, to: lead + 2 * segment) }
        print("ANL-010 bus: \(frames.count) frames at \(rate) Hz; silent \(silent.count), 300 Hz \(low.count), 3 kHz \(high.count)")
        XCTAssertFalse(silent.isEmpty)
        XCTAssertGreaterThanOrEqual(low.count, 8)
        XCTAssertGreaterThanOrEqual(high.count, 8)
        for f in silent {
            XCTAssertEqual(f.centroidHz, 0, "before any signal after a session start")
            XCTAssertEqual(f.centroid, 0)
        }
        for f in low { Self.assertWithin(f.centroidHz, 300, relative: 0.01, "300 Hz frame \(f.id)") }
        for f in high { Self.assertWithin(f.centroidHz, 3_000, relative: 0.01, "3 kHz frame \(f.id)") }
        let lowNormalized: Float = try XCTUnwrap(low.last?.centroid)
        let highNormalized: Float = try XCTUnwrap(high.first?.centroid)
        XCTAssertGreaterThan(highNormalized, lowNormalized)
        XCTAssertTrue(frames.allSatisfy { (f: AnalysisFrame) -> Bool in
            f.centroidHz.isFinite && f.centroid.isFinite && (0...1).contains(f.centroid)
        })

        XCTAssertThrowsError(try AnalysisPipelineConfiguration(centroid: try SpectralCentroidConfiguration(sampleRate: 48_000))) {
            (error: Error) -> Void in XCTAssertEqual(error as? AnalysisBusError, .sampleRateMismatch)
        }
    }
}
