// FixtureAcceptanceTests.swift — the roadmap acceptance of ANL-001 against the AUD-016 fixtures
// (ANL-001-T09, T10, T12; ANL-001-R16, R10, S1 to S4; AUD-016-R22 hand-off):
//   "Single-tone fixture peaks within one frequency bin and has finite values."
// Every sine fixture × 5 sizes × 44.1/48 kHz: the first window peaks at the catalog's documented
// bin; every frame of the whole loop peaks within one bin of it; all values finite. Every sine and
// sweep fixture analysed twice gives bit-identical frames. Runs for every backend in the build.
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class FixtureAcceptanceTests: XCTestCase {
    /// One check of a tone: a fixture, which channel carries it, and its frequency.
    private struct ToneCheck {
        let fixture: ReferenceToneFixture
        let mode: ChannelMode
        let frequency: Double
        var label: String { "\(fixture.id)\(mode == .mid ? "" : mode == .left ? " L" : " R")" }
    }

    private func toneChecks() throws -> [ToneCheck] {
        var checks: [ToneCheck] = []
        for fixture in ReferenceToneCatalog.fixtures {
            guard case .sine(let tone) = fixture.signal else { continue }
            if let left = tone.left, let right = tone.right, left != right {
                checks.append(ToneCheck(fixture: fixture, mode: .left, frequency: left))
                checks.append(ToneCheck(fixture: fixture, mode: .right, frequency: right))
            } else {
                checks.append(ToneCheck(fixture: fixture, mode: .mid, frequency: try XCTUnwrap(tone.left ?? tone.right)))
            }
        }
        return checks
    }

    /// Analyses a whole 10 s stereo loop through a stream; returns frame indices and all magnitudes.
    private func analyseLoop(_ stereo: [Float], configuration: SpectrumConfiguration,
                             backend: SpectrumBackend) -> (indices: [Int64], magnitudes: [Float]) {
        let stream = SpectrumStream(configuration: configuration, backend: backend, clock: { 0 })
        var indices: [Int64] = []
        var magnitudes: [Float] = []
        magnitudes.reserveCapacity((stereo.count / 2 / configuration.hop + 1) * configuration.binCount)
        stereo.withUnsafeBufferPointer { buffer in
            let frames = buffer.count / 2
            var offset = 0
            while offset < frames {
                offset += stream.append(interleaved: buffer.baseAddress! + 2 * offset, frames: frames - offset, channels: 2)
                while let frame = stream.nextFrame() {
                    indices.append(frame.index)
                    magnitudes.append(contentsOf: stream.magnitudes)
                }
            }
        }
        return (indices, magnitudes)
    }

    // MARK: Sines (US1, US2)

    func testSineFixturesPeakAtTheDocumentedBinOnEveryRunAndBackend() throws {
        var firstWindowChecks = 0
        var matrix: [String] = []
        for backend in TestSupport.backends {
            for check in try toneChecks() {
                for rate in ReferenceToneCatalog.variantRates {
                    let stereo = try check.fixture.loop(sampleRate: rate, channels: 2)
                    for size in FFTSize.allCases {
                        let configuration = try SpectrumConfiguration(size: size, sampleRate: Double(rate), channelMode: check.mode)
                        let expected = ReferenceToneCatalog.nearestBin(frequency: check.frequency, fftSize: size.rawValue, sampleRate: rate)
                        let label = "\(backend) \(check.label) \(rate) Hz N=\(size.rawValue)"
                        let first = analyseLoop(stereo, configuration: configuration, backend: backend)
                        let bins = size.binCount
                        XCTAssertEqual(first.indices.count, (stereo.count / 2 - size.rawValue) / configuration.hop + 1, label)
                        XCTAssertEqual(first.indices.first, 0, label)
                        XCTAssertTrue(first.magnitudes.allSatisfy { $0.isFinite && $0 >= 0 }, label)
                        // First window from frame 0: exactly the documented bin.
                        let firstPeak = first.magnitudes[0..<bins].indices.max { first.magnitudes[$0] < first.magnitudes[$1] }!
                        XCTAssertEqual(firstPeak, expected, label)
                        if backend == TestSupport.backends.first {
                            firstWindowChecks += 1
                            matrix.append("\(check.label) | \(rate) | \(size.rawValue) | \(expected) | \(firstPeak)")
                        }
                        // Every frame of the loop: within one bin.
                        var worst = 0
                        for f in 0..<first.indices.count {
                            let base = f * bins
                            var peak = 0
                            for k in 1..<bins where first.magnitudes[base + k] > first.magnitudes[base + peak] { peak = k }
                            worst = max(worst, abs(peak - expected))
                        }
                        XCTAssertLessThanOrEqual(worst, 1, "\(label): a frame peaked \(worst) bins away")
                        // A bin-centred tone reads its amplitude.
                        if ReferenceToneCatalog.isBinCentered(frequency: check.frequency, fftSize: size.rawValue, sampleRate: rate) {
                            XCTAssertEqual(first.magnitudes[expected], 0.25, accuracy: 1e-4, label)
                        }
                        // Repeated run: bit-identical (AUD-016-R22, ANL-001-R10).
                        let second = analyseLoop(stereo, configuration: configuration, backend: backend)
                        XCTAssertEqual(second.indices, first.indices, label)
                        XCTAssertTrue(TestSupport.bitPattern(second.magnitudes) == TestSupport.bitPattern(first.magnitudes), "\(label): repeated run differs")
                    }
                }
            }
        }
        XCTAssertEqual(firstWindowChecks, 50, "4 sine fixtures (sine-split per channel) × 2 rates × 5 sizes")
        print("ANL001-MATRIX fixture | rate | N | documented bin | measured bin\n" + matrix.map { "ANL001-MATRIX " + $0 }.joined(separator: "\n"))
    }

    func testSineSplitMidShowsBothTones() throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "sine-split"))
        for rate in ReferenceToneCatalog.variantRates {
            let stereo = try fixture.loop(sampleRate: rate, channels: 2)
            let configuration = try SpectrumConfiguration(size: .n4096, sampleRate: Double(rate))
            let frame = analyseLoop(Array(stereo[0..<(2 * 4_096)]), configuration: configuration, backend: .automatic)
            let low = ReferenceToneCatalog.nearestBin(frequency: 440, fftSize: 4_096, sampleRate: rate)
            let high = ReferenceToneCatalog.nearestBin(frequency: 1_000, fftSize: 4_096, sampleRate: rate)
            // Mid halves each channel: each tone reads about 0.125 (less when it falls between bins).
            XCTAssertGreaterThan(frame.magnitudes[low], 0.05)
            XCTAssertGreaterThan(frame.magnitudes[high], 0.05)
            XCTAssertLessThanOrEqual(frame.magnitudes[low], 0.125 + 1e-4)
        }
    }

    // MARK: Sweeps (US1, US2)

    func testSweepFixturesAreFiniteIdenticalAndPeakNearTheDocumentedFrequency() throws {
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            for fixture in ReferenceToneCatalog.fixtures {
                guard case .sweep = fixture.signal else { continue }
                for rate in ReferenceToneCatalog.variantRates {
                    let stereo = try fixture.loop(sampleRate: rate, channels: 2)
                    for size in FFTSize.allCases {
                        let configuration = try SpectrumConfiguration(size: size, sampleRate: Double(rate))
                        let label = "\(backend) \(fixture.id) \(rate) Hz N=\(size.rawValue)"
                        let first = analyseLoop(stereo, configuration: configuration, backend: backend)
                        XCTAssertTrue(first.magnitudes.allSatisfy { $0.isFinite && $0 >= 0 }, label)
                        let second = analyseLoop(stereo, configuration: configuration, backend: backend)
                        XCTAssertEqual(second.indices, first.indices, label)
                        XCTAssertTrue(TestSupport.bitPattern(second.magnitudes) == TestSupport.bitPattern(first.magnitudes), "\(label): repeated run differs")
                    }
                    // Peak of the 2,048-point window centred at each check time.
                    let mono = try fixture.loop(sampleRate: rate, channels: 1)
                    for t in ReferenceToneCatalog.sweepCheckSeconds where t > 0 {
                        let centre = Int((t * Double(rate)).rounded())
                        let start = centre - 1_024
                        let spectrum = analyzer.magnitudes(of: Array(mono[start..<(start + 2_048)]), size: .n2048)
                        let expected = FFTSize.n2048.nearestBin(toFrequency: try XCTUnwrap(fixture.instantaneousFrequency(atSeconds: t)), sampleRate: Double(rate))
                        let peak = TestSupport.peakBin(spectrum)
                        XCTAssertLessThanOrEqual(abs(peak - expected), 2, "\(backend) \(fixture.id) \(rate) Hz t=\(t): peak \(peak), documented \(expected)")
                    }
                }
            }
        }
    }

    // MARK: Silence and reuse

    func testSilenceFixtureIsExactlyZero() throws {
        let silence = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "silence"))
        for backend in TestSupport.backends {
            for rate in ReferenceToneCatalog.variantRates {
                let stereo = try silence.loop(sampleRate: rate, channels: 2)
                for size in FFTSize.allCases {
                    let result = analyseLoop(stereo, configuration: try SpectrumConfiguration(size: size, sampleRate: Double(rate)), backend: backend)
                    XCTAssertFalse(result.indices.isEmpty)
                    XCTAssertTrue(result.magnitudes.allSatisfy { $0 == 0 }, "\(backend) \(rate) N=\(size.rawValue)")
                }
            }
        }
    }

    func testResetStreamEqualsFreshStream() throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "sweep-log"))
        let mono = Array(try fixture.loop(sampleRate: 48_000, channels: 1)[0..<96_000])
        for backend in TestSupport.backends {
            for size in FFTSize.allCases {
                let configuration = try SpectrumConfiguration(size: size, sampleRate: 48_000)
                let fresh = TestSupport.frames(of: mono, configuration: configuration, backend: backend)
                // A stream that analysed noise first, then reset.
                let used = SpectrumStream(configuration: configuration, backend: backend, clock: { 0 })
                let noise = TestSupport.noise(count: 30_000)
                noise.withUnsafeBufferPointer { b in
                    var offset = 0
                    while offset < b.count {
                        offset += used.append(mono: b.baseAddress! + offset, count: b.count - offset)
                        while used.nextFrame() != nil {}
                    }
                }
                used.reset()
                var reused: [(SpectrumFrame, [Float])] = []
                mono.withUnsafeBufferPointer { b in
                    var offset = 0
                    while offset < b.count {
                        offset += used.append(mono: b.baseAddress! + offset, count: b.count - offset)
                        while let frame = used.nextFrame() { reused.append((frame, Array(used.magnitudes))) }
                    }
                }
                XCTAssertEqual(reused.map(\.0), fresh.map(\.frame), "\(backend) N=\(size.rawValue)")
                XCTAssertEqual(reused.map { TestSupport.bitPattern($0.1) }, fresh.map { TestSupport.bitPattern($0.magnitudes) })
            }
        }
    }
}
