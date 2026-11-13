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

    /// One-sided magnitudes |X[k]|, k in `bins` (default 0…N/2), of the first `size` samples with a
    /// periodic Hann window, by the defining sum (cosine and sine from a table indexed by k·n mod N).
    /// Also returns the windowed signal's energy Σ x_w[n]² for the Parseval bound below.
    private func hannMagnitudes(_ samples: ArraySlice<Float>, size: Int,
                                bins: ClosedRange<Int>? = nil) -> (magnitudes: [Int: Double], energy: Double) {
        let start = samples.startIndex
        let bins = bins ?? 0...(size / 2)
        var cosines = [Double](repeating: 0, count: size)
        var sines = [Double](repeating: 0, count: size)
        var windowed = [Double](repeating: 0, count: size)
        var energy = 0.0
        for n in 0..<size {
            let angle = 2 * Double.pi * Double(n) / Double(size)
            cosines[n] = cos(angle)
            sines[n] = sin(angle)
            windowed[n] = Double(samples[start + n]) * (0.5 - 0.5 * cos(angle))
            energy += windowed[n] * windowed[n]
        }
        var magnitudes: [Int: Double] = [:]
        cosines.withUnsafeBufferPointer { c in
            sines.withUnsafeBufferPointer { s in
                windowed.withUnsafeBufferPointer { x in
                    // Plain pointers: buffer-pointer subscripts are bounds-checked in Debug builds.
                    let c = c.baseAddress!, s = s.baseAddress!, x = x.baseAddress!
                    let mask = size - 1                      // sizes are powers of two
                    for k in bins {
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
        return (magnitudes, energy)
    }

    /// Largest FFT size whose every bin is computed by the direct sum. Above it the oracle computes
    /// the bins near the documented one and proves no other bin is larger with Parseval's theorem
    /// (shortened 2026-11-13 under owner rule 7: the all-bin sums at 4096 and 8192 took 21 s). Set
    /// `REFERENCE_TONE_ORACLE_FULL=1` to compute every bin at every size, as before.
    private static let fullDFTMaxSize = ProcessInfo.processInfo.environment["REFERENCE_TONE_ORACLE_FULL"] == nil ? 2_048 : 8_192
    private static let bandHalfWidth = 6

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
                        let documented = ReferenceToneCatalog.nearestBin(frequency: frequency, fftSize: size, sampleRate: rate)
                        let label = "\(fixture.id) channel \(index) \(rate) Hz N=\(size)"
                        let band = size <= Self.fullDFTMaxSize ? 0...(size / 2)
                            : max(0, documented - Self.bandHalfWidth)...min(size / 2, documented + Self.bandHalfWidth)
                        let (magnitudes, energy) = hannMagnitudes(samples[0..<size], size: size, bins: band)
                        XCTAssertTrue(magnitudes.values.allSatisfy(\.isFinite), label)
                        let peak = band.max { magnitudes[$0]! < magnitudes[$1]! }!
                        XCTAssertEqual(peak, documented, label)
                        if band.count < size / 2 + 1 {
                            // Parseval: Σ_{k=0}^{N-1} |X[k]|² = N·Σ x_w[n]², and |X[k]| = |X[N−k]|, so any bin
                            // outside the band has |X[k]|² ≤ (that total − the band's share). Below peak², no
                            // bin outside the band can be the largest.
                            let bandShare = band.reduce(0.0) { sum, k in
                                sum + (k == 0 || k == size / 2 ? 1 : 2) * magnitudes[k]! * magnitudes[k]!
                            }
                            let outside = Double(size) * energy - bandShare
                            XCTAssertLessThan(outside, magnitudes[peak]! * magnitudes[peak]!, "\(label): a bin outside the band could be larger")
                        }
                        if ReferenceToneCatalog.isBinCentered(frequency: frequency, fftSize: size, sampleRate: rate) {
                            // A·N/4 for a bin-centered tone under a periodic Hann window.
                            XCTAssertEqual(magnitudes[peak]! / (0.25 * Double(size) / 4), 1, accuracy: 1e-6, "\(fixture.id) N=\(size)")
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
            XCTAssertTrue(hannMagnitudes(loop[0..<512], size: 512).magnitudes.values.allSatisfy { $0 == 0 })
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
