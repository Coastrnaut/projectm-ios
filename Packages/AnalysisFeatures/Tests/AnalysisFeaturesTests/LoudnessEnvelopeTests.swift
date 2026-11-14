// LoudnessEnvelopeTests.swift — ANL-014: the K-weighted, smoothed, normalized loudness envelope
// (contracts/loudness-envelope.md C1-C3). Synthetic PCM: single analysis windows through the real
// SpectrumAnalyzer, one 2 s stream through SpectrumStream for the step lag, and one short pipeline
// run; a few representative cases (owner rule 7). No Accelerate import, no C stdio globals, no clock.
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

final class LoudnessEnvelopeTests: XCTestCase {
    // MARK: Documented lag (spec.md, "Documented lag")

    /// Whole-chain 90 % rise time of the −40 → −10 dBFS step, in samples at 44.1 kHz (2,048 points,
    /// hop 512, attack 0.1 s): measured once and recorded in the spec.
    static let documentedRiseSamples = 5_086      // 115.3 ms
    /// Whole-chain 90 % fall time of the −10 → −40 dBFS step (release 0.4 s).
    static let documentedFallSamples = 19_115     // 433.4 ms

    // MARK: Fixtures

    private static let rate: Double = 44_100

    private static func amplitude(dBFS: Double) -> Float {
        let linear: Double = pow(10, dBFS / 20)
        return Float(linear)
    }

    /// `amplitude`·sin(2π·f·n/R + 0.3) for n in `range` (phase continuous across segments).
    private static func sine(_ frequency: Double, amplitude: Float, range: Range<Int>, rate: Double = 44_100) -> [Float] {
        range.map { (n: Int) -> Float in
            let phase: Double = 2 * Double.pi * frequency * Double(n) / rate + 0.3
            return amplitude * Float(sin(phase))
        }
    }

    /// One 2,048-point window of `samples` through a fresh envelope (so the reading is the snapped
    /// first frame: envelope = normalized level).
    private static func window(_ samples: [Float], rate: Double = 44_100) throws -> LoudnessReading {
        var envelope = LoudnessEnvelope(configuration: try LoudnessConfiguration(sampleRate: rate))
        let magnitudes = SpectrumAnalyzer().magnitudes(of: samples, size: .n2048)
        let frame = SpectrumFrame(index: 0, size: .n2048, sampleRate: rate, timestampNanoseconds: 0, hop: 512)
        return magnitudes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> LoudnessReading in
            envelope.process(frame, magnitudes: buffer)
        }
    }

    /// Streams mono `samples` through a 2,048-point, hop-512 `SpectrumStream` into `envelope`;
    /// returns each frame's window end (index + size, the sample clock) and reading.
    private static func stream(_ samples: [Float], into envelope: inout LoudnessEnvelope) throws -> [(end: Int, reading: LoudnessReading)] {
        let configuration = try SpectrumConfiguration(size: .n2048, hop: 512, sampleRate: 44_100)
        let spectra = SpectrumStream(configuration: configuration, clock: { 0 })
        var out: [(end: Int, reading: LoudnessReading)] = []
        var offset = 0
        while offset < samples.count {
            let count: Int = min(512, samples.count - offset)
            samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                guard let base = buffer.baseAddress else { return }
                _ = spectra.append(mono: base + offset, count: count)
            }
            offset += count
            while let frame = spectra.nextFrame() {
                let reading = envelope.process(frame, magnitudes: spectra.magnitudes)
                let end: Int = Int(frame.index) + frame.size.rawValue
                out.append((end: end, reading: reading))
            }
        }
        return out
    }

    private static func inRange(_ reading: LoudnessReading) -> Bool {
        reading.decibels.isFinite && reading.decibels >= -120 && reading.envelope.isFinite && (0...1).contains(reading.envelope)
    }

    // MARK: K-weighting and configuration (T02)

    func testKWeightingMatchesTheStandardAt48kHzAndTheReferencePoint() {
        let shelf = KWeighting.shelf(sampleRate: 48_000)
        XCTAssertEqual(shelf.b0, 1.53512485958697, accuracy: 1e-6)
        XCTAssertEqual(shelf.b1, -2.69169618940638, accuracy: 1e-6)
        XCTAssertEqual(shelf.b2, 1.19839281085285, accuracy: 1e-6)
        XCTAssertEqual(shelf.a1, -1.69065929318241, accuracy: 1e-6)
        XCTAssertEqual(shelf.a2, 0.73248077421585, accuracy: 1e-6)
        let highPass = KWeighting.highPass(sampleRate: 48_000)
        XCTAssertEqual(highPass.b0, 1)
        XCTAssertEqual(highPass.b1, -2)
        XCTAssertEqual(highPass.b2, 1)
        XCTAssertEqual(highPass.a1, -1.99004745483398, accuracy: 1e-6)
        XCTAssertEqual(highPass.a2, 0.99007225036621, accuracy: 1e-6)
        for rate: Double in [44_100, 48_000] {
            let gain: Double = 10 * log10(KWeighting.powerGain(frequency: 997, sampleRate: rate))
            XCTAssertEqual(gain, 0.69, accuracy: 0.02, "997 Hz at \(rate) Hz")
        }
        let table = KWeighting.table(size: .n2048, sampleRate: 44_100)
        XCTAssertEqual(table.count, FFTSize.n2048.binCount)
        XCTAssertEqual(table[0], 0, "DC excluded")
        XCTAssertTrue(table.allSatisfy { (w: Float) -> Bool in w.isFinite && w >= 0 })
    }

    func testConfigurationDefaultsValidationAndNormalization() throws {
        let standard = LoudnessConfiguration.standard
        XCTAssertEqual(standard.sampleRate, 44_100)
        XCTAssertEqual(standard.floorDecibels, -60)
        XCTAssertEqual(standard.ceilingDecibels, 0)
        XCTAssertEqual(standard.times, SmoothingTimes(attackSeconds: 0.1, releaseSeconds: 0.4))
        XCTAssertThrowsError(try LoudnessConfiguration(sampleRate: .nan))
        XCTAssertThrowsError(try LoudnessConfiguration(sampleRate: 0))
        XCTAssertThrowsError(try LoudnessConfiguration(sampleRate: 3_000), "the shelf must lie below Nyquist")
        XCTAssertThrowsError(try LoudnessConfiguration(floorDecibels: 0, ceilingDecibels: 0))
        XCTAssertThrowsError(try LoudnessConfiguration(floorDecibels: -.infinity))
        XCTAssertThrowsError(try LoudnessConfiguration(ceilingDecibels: .nan))
        XCTAssertEqual(standard.normalized(decibels: -60), 0)
        XCTAssertEqual(standard.normalized(decibels: -30), 0.5, accuracy: 1e-12)
        XCTAssertEqual(standard.normalized(decibels: 0), 1)
        XCTAssertEqual(standard.normalized(decibels: 6), 1)
        XCTAssertEqual(standard.normalized(decibels: -90), 0)
        XCTAssertEqual(standard.normalized(decibels: .nan), 0)
    }

    // MARK: User story 1 (T04)

    func testFullScale997HzSineReadsTheReferenceLevel() throws {
        let r = try Self.window(Self.sine(997, amplitude: 1, range: 0..<2_048))
        print("ANL-014 calibration: full-scale 997 Hz sine \(r.decibels) dB, envelope \(r.envelope)")
        XCTAssertEqual(r.decibels, -3.01, accuracy: 0.2)
    }

    func testStepIsFollowedWithTheDocumentedLag() throws {
        let quietLength = 22_050       // 0.5 s at −40 dBFS
        let loudLength = 33_075        // 0.75 s at −10 dBFS
        let fallLength = 33_075        // 0.75 s at −40 dBFS
        let quiet: Float = Self.amplitude(dBFS: -40)
        let loud: Float = Self.amplitude(dBFS: -10)
        let riseAt: Int = quietLength
        let fallAt: Int = quietLength + loudLength
        var samples = Self.sine(1_000, amplitude: quiet, range: 0..<riseAt)
        samples += Self.sine(1_000, amplitude: loud, range: riseAt..<fallAt)
        samples += Self.sine(1_000, amplitude: quiet, range: fallAt..<(fallAt + fallLength))
        var envelope = LoudnessEnvelope()
        let frames = try Self.stream(samples, into: &envelope)
        XCTAssertTrue(frames.allSatisfy { (f: (end: Int, reading: LoudnessReading)) -> Bool in Self.inRange(f.reading) })

        let before = try XCTUnwrap(frames.last { (f: (end: Int, reading: LoudnessReading)) -> Bool in f.end <= riseAt })
        let top = try XCTUnwrap(frames.last { (f: (end: Int, reading: LoudnessReading)) -> Bool in f.end <= fallAt })
        let low: Float = before.reading.envelope
        let high: Float = top.reading.envelope
        let change: Float = high - low
        XCTAssertGreaterThan(change, 0.4, "a 30 dB step moves the envelope by about half its range")
        let riseMark: Float = low + 0.9 * change
        let fallMark: Float = high - 0.9 * change
        let risen = try XCTUnwrap(frames.first { (f: (end: Int, reading: LoudnessReading)) -> Bool in
            f.end > riseAt && f.reading.envelope >= riseMark
        })
        let fallen = try XCTUnwrap(frames.first { (f: (end: Int, reading: LoudnessReading)) -> Bool in
            f.end > fallAt && f.reading.envelope <= fallMark
        })
        let rise: Int = risen.end - riseAt
        let fall: Int = fallen.end - fallAt
        let riseMs: Double = Double(rise) / Self.rate * 1_000
        let fallMs: Double = Double(fall) / Self.rate * 1_000
        print("ANL-014 step: quiet \(low) (\(before.reading.decibels) dB), loud \(high) (\(top.reading.decibels) dB); "
              + "90 % rise \(rise) samples (\(riseMs) ms), 90 % fall \(fall) samples (\(fallMs) ms)")
        let hop = 512
        XCTAssertLessThanOrEqual(abs(rise - Self.documentedRiseSamples), hop, "rise matches the documented lag within one frame")
        XCTAssertLessThanOrEqual(abs(fall - Self.documentedFallSamples), hop, "fall matches the documented lag within one frame")
        // Tied to the model: the smoother's own 90 % time ≤ lag ≤ that + one window.
        let attack: Int = Int((0.1 * Self.rate).rounded())
        let release: Int = Int((0.4 * Self.rate).rounded())
        XCTAssertGreaterThanOrEqual(rise, attack - hop)
        XCTAssertLessThanOrEqual(rise, attack + 2_048)
        XCTAssertGreaterThanOrEqual(fall, release - hop)
        XCTAssertLessThanOrEqual(fall, release + 2_048)
    }

    func testWeightingOrdersEqualAmplitudeTones() throws {
        let a: Float = Self.amplitude(dBFS: -20)
        let low = try Self.window(Self.sine(100, amplitude: a, range: 0..<2_048))
        let mid = try Self.window(Self.sine(1_000, amplitude: a, range: 0..<2_048))
        let high = try Self.window(Self.sine(2_000, amplitude: a, range: 0..<2_048))
        let deep = try Self.window(Self.sine(20, amplitude: a, range: 0..<2_048))
        print("ANL-014 weighting at -20 dBFS: 20 Hz \(deep.decibels), 100 Hz \(low.decibels), 1 kHz \(mid.decibels), 2 kHz \(high.decibels) dB")
        XCTAssertGreaterThan(high.decibels, low.decibels)
        XCTAssertGreaterThan(high.envelope, low.envelope)
        XCTAssertLessThan(deep.decibels, mid.decibels)
    }

    func testLevelRaisesTheEnvelopeMonotonically() throws {
        var previous: Float = -1
        var table: [String] = []
        for level: Double in [-50, -40, -30, -20, -10] {
            let r = try Self.window(Self.sine(1_000, amplitude: Self.amplitude(dBFS: level), range: 0..<2_048))
            table.append("\(Int(level)) dBFS → \(r.decibels) dB, \(r.envelope)")
            XCTAssertGreaterThan(r.envelope, previous, "\(level) dBFS")
            previous = r.envelope
        }
        print("ANL-014 levels: " + table.joined(separator: "; "))
    }

    // MARK: User story 2 (T05)

    func testExtremeAndNonFiniteInputStaysBounded() throws {
        let noise = TestSupport.noise(count: 2_048, seed: 0x5EED, amplitude: 1)
        let noiseReading = try Self.window(noise)
        let square: [Float] = (0..<2_048).map { (n: Int) -> Float in
            let s: Double = sin(2 * Double.pi * 1_000 * Double(n) / 44_100)
            return s >= 0 ? 1 : -1
        }
        let squareReading = try Self.window(square)
        let silence = try Self.window([Float](repeating: 0, count: 2_048))
        print("ANL-014 bounds: noise \(noiseReading.decibels) dB/\(noiseReading.envelope), square \(squareReading.decibels) dB/\(squareReading.envelope)")
        for r in [noiseReading, squareReading, silence] { XCTAssertTrue(Self.inRange(r), "\(r)") }
        XCTAssertEqual(squareReading.envelope, 1, "a full-scale square wave clamps at 1")
        XCTAssertEqual(silence.decibels, -120)
        XCTAssertEqual(silence.envelope, 0)

        // Non-finite and huge magnitudes, many frames.
        var envelope = LoudnessEnvelope()
        var magnitudes = SpectrumAnalyzer().magnitudes(of: Self.sine(1_000, amplitude: 0.1, range: 0..<2_048), size: .n2048)
        magnitudes[3] = .nan
        magnitudes[40] = .infinity
        magnitudes[41] = -.infinity
        magnitudes[500] = 3e38
        let frame = SpectrumFrame(index: 0, size: .n2048, sampleRate: 44_100, timestampNanoseconds: 0, hop: 512)
        for _ in 0..<20 {
            let r = magnitudes.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> LoudnessReading in envelope.process(frame, magnitudes: b) }
            XCTAssertTrue(Self.inRange(r), "\(r)")
        }
        let allBad = [Float](repeating: .nan, count: FFTSize.n2048.binCount)
        let r = allBad.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> LoudnessReading in envelope.process(frame, magnitudes: b) }
        XCTAssertTrue(Self.inRange(r))
        XCTAssertEqual(r.decibels, -120)
    }

    func testSilenceDecaysToExactlyZeroAndResetSnaps() throws {
        let loudLength = 8_820
        let silenceLength = 66_150     // 1.5 s
        var samples = Self.sine(1_000, amplitude: Self.amplitude(dBFS: -10), range: 0..<loudLength)
        samples += [Float](repeating: 0, count: silenceLength)
        var envelope = LoudnessEnvelope()
        let frames = try Self.stream(samples, into: &envelope)
        XCTAssertTrue(frames.allSatisfy { (f: (end: Int, reading: LoudnessReading)) -> Bool in Self.inRange(f.reading) })
        let last = try XCTUnwrap(frames.last)
        XCTAssertEqual(last.reading.envelope, 0, "exactly 0 within 1.5 s of silence")
        let firstZero = try XCTUnwrap(frames.firstIndex { (f: (end: Int, reading: LoudnessReading)) -> Bool in f.reading.envelope == 0 })
        XCTAssertTrue(frames[firstZero...].allSatisfy { (f: (end: Int, reading: LoudnessReading)) -> Bool in f.reading.envelope == 0 }, "stays 0")
        print("ANL-014 silence: 0 reached \(Double(frames[firstZero].end - loudLength) / Self.rate) s after the tone ended")

        envelope.reset()
        XCTAssertEqual(envelope.reading, .silent)
        let loudReading = try Self.window(Self.sine(1_000, amplitude: Self.amplitude(dBFS: -10), range: 0..<2_048))
        let magnitudes = SpectrumAnalyzer().magnitudes(of: Self.sine(1_000, amplitude: Self.amplitude(dBFS: -10), range: 0..<2_048), size: .n2048)
        let frame = SpectrumFrame(index: 0, size: .n2048, sampleRate: 44_100, timestampNanoseconds: 0, hop: 512)
        let snapped = magnitudes.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> LoudnessReading in envelope.process(frame, magnitudes: b) }
        XCTAssertEqual(snapped, loudReading, "the first frame after reset takes its value directly")

        // Frames this envelope was not built for leave the reading unchanged.
        let otherRate = SpectrumFrame(index: 0, size: .n2048, sampleRate: 48_000, timestampNanoseconds: 0, hop: 512)
        let otherSize = SpectrumFrame(index: 0, size: .n1024, sampleRate: 44_100, timestampNanoseconds: 0, hop: 512)
        let silent = [Float](repeating: 0, count: FFTSize.n2048.binCount)
        let short = [Float](repeating: 0, count: FFTSize.n1024.binCount)
        silent.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(envelope.process(otherRate, magnitudes: b), snapped)
            XCTAssertEqual(envelope.process(otherSize, magnitudes: b), snapped)
        }
        short.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(envelope.process(frame, magnitudes: b), snapped, "wrong magnitude count")
        }
    }

    // MARK: User story 3: the bus (T06)

    func testThePipelineCarriesTheEnvelopeInEveryFrame() throws {
        let lead = 2_205                       // 0.05 s of silence
        let segment = 11_025                   // 0.25 s per level
        var mono = [Float](repeating: 0, count: lead)
        mono += Self.sine(1_000, amplitude: Self.amplitude(dBFS: -40), range: 0..<segment)
        mono += Self.sine(1_000, amplitude: Self.amplitude(dBFS: -10), range: segment..<(2 * segment))
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
        let silent = frames.filter { (f: AnalysisFrame) -> Bool in Int(f.time.sessionSample) <= lead }
        let quiet = try XCTUnwrap(frames.last { (f: AnalysisFrame) -> Bool in Int(f.time.sessionSample) <= lead + segment })
        let loud = try XCTUnwrap(frames.last)
        print("ANL-014 bus: \(frames.count) frames; silent \(silent.count); quiet \(quiet.loudness) (\(quiet.loudnessDecibels) dB), loud \(loud.loudness) (\(loud.loudnessDecibels) dB)")
        XCTAssertFalse(silent.isEmpty)
        for f in silent {
            XCTAssertEqual(f.loudness, 0)
            XCTAssertEqual(f.loudnessDecibels, -120)
        }
        XCTAssertGreaterThan(loud.loudness, quiet.loudness)
        XCTAssertGreaterThan(loud.loudnessDecibels, quiet.loudnessDecibels)
        XCTAssertTrue(frames.allSatisfy { (f: AnalysisFrame) -> Bool in
            f.loudness.isFinite && (0...1).contains(f.loudness) && f.loudnessDecibels.isFinite
        })
        XCTAssertThrowsError(try AnalysisPipelineConfiguration(loudness: try LoudnessConfiguration(sampleRate: 48_000))) {
            (error: Error) -> Void in XCTAssertEqual(error as? AnalysisBusError, .sampleRateMismatch)
        }
    }
}
