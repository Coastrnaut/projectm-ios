// ReferenceToneOracleTests.swift — checks the catalog's expected analysis values against an
// independent reference computation (AUD-016-T08; AUD-016-R12, S2 to S4). The direct DFT, the onset
// scan and the zero-crossing frequency estimate below are test oracles: plain, slow and obviously
// correct. They live in the test target only and never ship (Constitution VIII; the production
// analyzers are ANL-001 and ANL-004/ANL-005, which inherit these fixtures).
import Foundation
import XCTest
@testable import AudioCore

final class ReferenceToneOracleTests: XCTestCase {
    // MARK: Oracles

    /// One-sided magnitudes |X[k]|, k = 0…N/2, of the first `size` samples with a periodic Hann
    /// window, by the defining sum (cosine and sine from a table indexed by k·n mod N).
    private func hannMagnitudes(_ samples: ArraySlice<Float>, size: Int) -> [Double] {
        let start = samples.startIndex
        var cosines = [Double](repeating: 0, count: size)
        var sines = [Double](repeating: 0, count: size)
        var windowed = [Double](repeating: 0, count: size)
        for n in 0..<size {
            let angle = 2 * Double.pi * Double(n) / Double(size)
            cosines[n] = cos(angle)
            sines[n] = sin(angle)
            windowed[n] = Double(samples[start + n]) * (0.5 - 0.5 * cos(angle))
        }
        var magnitudes = [Double](repeating: 0, count: size / 2 + 1)
        cosines.withUnsafeBufferPointer { c in
            sines.withUnsafeBufferPointer { s in
                windowed.withUnsafeBufferPointer { x in
                    let mask = size - 1                      // sizes are powers of two
                    for k in 0...(size / 2) {
                        var re = 0.0, im = 0.0, index = 0
                        for n in 0..<size {
                            re += x[n] * c[index]
                            im -= x[n] * s[index]
                            index = (index + k) & mask
                        }
                        magnitudes[k] = (re * re + im * im).squareRoot()
                    }
                }
            }
        }
        return magnitudes
    }

    /// Frames where a pulse begins: a non-zero sample after a zero one (or at frame 0).
    private func onsets(_ samples: [Float]) -> [(frame: Int64, level: Double)] {
        var found: [(Int64, Double)] = []
        for n in samples.indices where samples[n] != 0 && (n == 0 || samples[n - 1] == 0) {
            found.append((Int64(n), Double(samples[n])))
        }
        return found
    }

    /// Frequency from rising zero crossings (linearly interpolated) within ±`halfWidth` frames of `center`.
    private func zeroCrossingFrequency(_ samples: [Float], center: Int, halfWidth: Int, rate: Int) -> Double? {
        var crossings: [Double] = []
        for n in max(1, center - halfWidth)..<min(samples.count, center + halfWidth) where samples[n - 1] < 0 && samples[n] >= 0 {
            let a = Double(samples[n - 1]), b = Double(samples[n])
            crossings.append(Double(n - 1) + (-a) / (b - a))
        }
        guard crossings.count >= 3, let first = crossings.first, let last = crossings.last else { return nil }
        return Double(crossings.count - 1) / (last - first) * Double(rate)
    }

    private func channel(_ interleaved: [Float], _ index: Int, of channels: Int) -> [Float] {
        stride(from: index, to: interleaved.count, by: channels).map { interleaved[$0] }
    }

    // MARK: Sines (AUD-016-S2)

    func testReferenceDFTPeaksAtTheDocumentedBin() throws {
        for fixture in ReferenceToneCatalog.fixtures where !fixture.sineFrequencies.isEmpty {
            for rate in ReferenceToneCatalog.variantRates {
                let largest = ReferenceToneCatalog.fftSizes.max()!
                let frames = try fixture.generator(sampleRate: rate, channels: 2).interleaved(frames: largest)
                guard case .sine(let tone) = fixture.signal else { return XCTFail("\(fixture.id) is not a sine") }
                for (index, frequency) in [tone.left, tone.right].enumerated() {
                    // A frequency already checked on the left channel (or in an earlier fixture) is not repeated.
                    guard let frequency, index == 0 || frequency != tone.left, !(fixture.id == "sine-split" && frequency == 1_000) else { continue }
                    let samples = channel(frames, index, of: 2)
                    for size in ReferenceToneCatalog.fftSizes {
                        let magnitudes = hannMagnitudes(samples[0..<size], size: size)
                        let peak = magnitudes.indices.max { magnitudes[$0] < magnitudes[$1] }!
                        XCTAssertEqual(peak, ReferenceToneCatalog.nearestBin(frequency: frequency, fftSize: size, sampleRate: rate),
                                       "\(fixture.id) channel \(index) \(rate) Hz N=\(size)")
                        XCTAssertTrue(magnitudes.allSatisfy(\.isFinite))
                        if ReferenceToneCatalog.isBinCentered(frequency: frequency, fftSize: size, sampleRate: rate) {
                            // A·N/4 for a bin-centered tone under a periodic Hann window.
                            XCTAssertEqual(magnitudes[peak] / (0.25 * Double(size) / 4), 1, accuracy: 1e-6, "\(fixture.id) N=\(size)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Pulses (AUD-016-S3)

    func testOnsetScanFindsExactlyTheDocumentedOnsets() throws {
        for fixture in ReferenceToneCatalog.fixtures where fixture.beatsPerMinute != nil {
            for rate in ReferenceToneCatalog.variantRates {
                let loop = try fixture.loop(sampleRate: rate, channels: 1)
                let found = onsets(loop)
                XCTAssertEqual(found.map(\.frame), fixture.onsetFrames(sampleRate: rate), "\(fixture.id) \(rate)")
                XCTAssertEqual(found.map(\.level), fixture.onsetLevels(sampleRate: rate), "\(fixture.id) \(rate)")
                // Tempo from the found onsets: the mean interval over the loop is the exact beat.
                let mean = Double(fixture.loopFrames(sampleRate: rate)) / Double(found.count)
                XCTAssertEqual(60 * Double(rate) / mean, fixture.beatsPerMinute!, accuracy: 1e-9, "\(fixture.id) \(rate)")
                // Width: every pulse lasts round(2 ms) frames.
                let width = Int((0.002 * Double(rate)).rounded())
                for onset in found {
                    let n = Int(onset.frame)
                    XCTAssertNotEqual(loop[n + width - 1], 0, "\(fixture.id) pulse at \(n)")
                    XCTAssertEqual(loop[n + width], 0, "\(fixture.id) pulse at \(n)")
                }
            }
        }
    }

    func testSilenceHasNoOnsetsAndNoEnergy() throws {
        let silence = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "silence"))
        for rate in ReferenceToneCatalog.variantRates {
            let loop = try silence.loop(sampleRate: rate, channels: 2)
            XCTAssertTrue(onsets(loop).isEmpty)
            XCTAssertTrue(hannMagnitudes(loop[0..<512], size: 512).allSatisfy { $0 == 0 })
        }
    }

    // MARK: Sweeps (AUD-016-S4)

    func testSweepLocalFrequencyMatchesTheDocumentedValue() throws {
        for fixture in ReferenceToneCatalog.fixtures {
            guard case .sweep = fixture.signal else { continue }
            for rate in ReferenceToneCatalog.variantRates {
                let loop = try fixture.loop(sampleRate: rate, channels: 1)
                XCTAssertEqual(loop[0], 0, "\(fixture.id): phase 0 at t = 0")
                for t in ReferenceToneCatalog.sweepCheckSeconds where t > 0 {
                    let expected = try XCTUnwrap(fixture.instantaneousFrequency(atSeconds: t))
                    let halfWidth = Int((3 / expected * Double(rate)).rounded(.up))
                    let measured = try XCTUnwrap(zeroCrossingFrequency(loop, center: Int(t * Double(rate)), halfWidth: halfWidth, rate: rate),
                                                 "\(fixture.id) at \(t) s")
                    XCTAssertEqual(measured / expected, 1, accuracy: 0.01, "\(fixture.id) \(rate) Hz at \(t) s: \(measured) Hz")
                }
            }
        }
    }
}
