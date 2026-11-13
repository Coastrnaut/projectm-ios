// OnsetDetectorTests.swift — the onset detector on synthetic spectra (ANL-004-T05; ANL-004-R1 to
// R6, R9 to R12): silence, a rise, timing rule, re-arming, minimum interval, decreases, sequence
// across reset, baselines after gaps and size changes, ignored frames, sanitizing, bounds.
// Runs for every backend in the build.
import XCTest
@testable import AnalysisFeatures

final class OnsetDetectorTests: XCTestCase {
    private let size = FFTSize.n512
    private let hop = 256
    private let rate = 44_100.0

    private func frame(_ k: Int, size: FFTSize = .n512, hop: Int = 256, rate: Double = 44_100, offset: Int64 = 0) -> SpectrumFrame {
        SpectrumFrame(index: Int64(k * hop) + offset, size: size, sampleRate: rate, timestampNanoseconds: UInt64(k), hop: hop)
    }

    /// A flat broadband spectrum: every bin `level` (−40 dB per bin by default).
    private func flat(_ level: Float = 0.01, size: FFTSize = .n512) -> [Float] {
        [Float](repeating: level, count: size.binCount)
    }

    private var zeros: [Float] { flat(0) }

    private func detector(_ backend: SpectrumBackend, multiplier: Float = 1.5, interval: Double = 0.05) throws -> SpectralFluxOnsetDetector {
        SpectralFluxOnsetDetector(configuration: try OnsetDetectorConfiguration(thresholdMultiplier: multiplier,
                                                                               minimumInterOnsetSeconds: interval),
                                  backend: backend)
    }

    func testSilenceGivesNoEventAndExactlyZeroFlux() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend)
            for k in 0..<50 {
                XCTAssertNil(d.process(frame(k), magnitudes: zeros))
                XCTAssertEqual(d.lastFlux.bitPattern, 0, "\(backend)")
            }
            XCTAssertEqual(d.eventCount, 0)
            XCTAssertEqual(d.processedFrames, 50)
        }
    }

    func testARiseFiresOnceWithTheTimingRuleAndEventFields() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend)
            XCTAssertNil(d.process(frame(0), magnitudes: zeros))
            let event = try XCTUnwrap(d.process(frame(1), magnitudes: flat()), "\(backend)")
            XCTAssertEqual(event.sequence, 1)
            XCTAssertEqual(event.frameIndex, 256)
            XCTAssertEqual(event.sampleIndex, 256 + 512 - 256)
            XCTAssertEqual(event.timestampNanoseconds, 1)
            XCTAssertEqual(event.sampleRate, rate)
            XCTAssertEqual(event.threshold, 0.06 + 1.5 * 0 / 1)    // history: one 0
            XCTAssertEqual(event.strength, d.lastFlux)
            XCTAssertGreaterThan(event.strength, event.threshold)
            XCTAssertLessThanOrEqual(event.strength, 1)
            XCTAssertEqual(d.lastThreshold, event.threshold)
            // The same spectrum again: no change, no event.
            XCTAssertNil(d.process(frame(2), magnitudes: flat()))
            XCTAssertEqual(d.lastFlux, 0)
            // A decrease contributes nothing.
            XCTAssertNil(d.process(frame(3), magnitudes: flat(0.001)))
            XCTAssertEqual(d.lastFlux, 0)
            XCTAssertEqual(d.eventCount, 1)
        }
    }

    func testFirstFrameAfterCreationIsComparedWithSilence() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend)
            let event = try XCTUnwrap(d.process(frame(7), magnitudes: flat()))
            XCTAssertEqual(event.threshold, 0.06)   // empty history: mean 0
            XCTAssertEqual(event.sampleIndex, 7 * 256 + 256)
        }
    }

    func testRearmingNeedsAFrameAtOrBelowTheThreshold() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend, multiplier: 0, interval: 0)    // threshold = 0.06 exactly
            XCTAssertNil(d.process(frame(0), magnitudes: zeros))
            XCTAssertNotNil(d.process(frame(1), magnitudes: flat(0.001)))
            // +12 dB in every band: 0.172 > 0.06, but the detector is still disarmed.
            XCTAssertNil(d.process(frame(2), magnitudes: flat(0.004)))
            XCTAssertGreaterThan(d.lastFlux, 0.06)
            XCTAssertNil(d.process(frame(3), magnitudes: flat(0.004)))      // flux 0: re-arms
            let event = try XCTUnwrap(d.process(frame(4), magnitudes: flat(0.016)), "\(backend)")
            XCTAssertEqual(event.sequence, 2)
        }
    }

    func testMinimumInterOnsetIntervalSuppressesCloseRises() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend)
            XCTAssertNil(d.process(frame(0), magnitudes: zeros))
            XCTAssertEqual(d.process(frame(1), magnitudes: flat())?.sampleIndex, 512)
            XCTAssertNil(d.process(frame(2), magnitudes: zeros))              // re-armed
            XCTAssertNil(d.process(frame(3), magnitudes: flat()))             // 512 samples later: inside 2,205
            XCTAssertGreaterThan(d.lastFlux, d.lastThreshold)
            for k in 4..<12 { XCTAssertNil(d.process(frame(k), magnitudes: zeros)) }
            // Frame 12: sample 3,328, 2,816 samples (0.064 s) after the first event.
            let event = try XCTUnwrap(d.process(frame(12), magnitudes: flat()), "\(backend)")
            XCTAssertEqual(event.sampleIndex, 3_328)
            XCTAssertEqual(event.sequence, 2)
        }
    }

    func testSequenceContinuesAcrossResetAndResetRestoresSilence() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend, interval: 0)
            XCTAssertEqual(d.process(frame(0), magnitudes: flat())?.sequence, 1)
            XCTAssertNil(d.process(frame(1), magnitudes: zeros))
            XCTAssertEqual(d.process(frame(2), magnitudes: flat())?.sequence, 2)
            d.reset()
            XCTAssertEqual(d.lastFlux, 0)
            XCTAssertEqual(d.eventCount, 2)
            // After reset the reference is silence again, so the same spectrum fires at once, at any index.
            let event = try XCTUnwrap(d.process(frame(0), magnitudes: flat()))
            XCTAssertEqual(event.sequence, 3)
            XCTAssertEqual(event.threshold, 0.06)
        }
    }

    func testGapsAndSizeChangesOnlyReestablishTheReference() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend, interval: 0)
            XCTAssertNil(d.process(frame(0), magnitudes: zeros))
            // Gap: index jumps by 1,000 extra samples. Baseline: no event even though energy rose.
            XCTAssertNil(d.process(frame(1, offset: 1_000), magnitudes: flat()))
            XCTAssertEqual(d.lastFlux, 0)
            XCTAssertEqual(d.lastThreshold, 0)
            XCTAssertNil(d.process(frame(2, offset: 1_000), magnitudes: flat()))   // contiguous, unchanged
            XCTAssertNil(d.process(frame(3, offset: 1_000), magnitudes: zeros))
            XCTAssertNotNil(d.process(frame(4, offset: 1_000), magnitudes: flat()))
            // Size change (512 → 1,024) at the contiguous index: baseline.
            let bigger = SpectrumFrame(index: 5 * 256 + 1_000, size: .n1024, sampleRate: rate, timestampNanoseconds: 5, hop: 512)
            XCTAssertNil(d.process(bigger, magnitudes: flat(0.1, size: .n1024)))
            XCTAssertEqual(d.lastFlux, 0)
            // Next contiguous 1,024-point frame is processed normally (a further rise fires).
            let next = SpectrumFrame(index: 5 * 256 + 1_000 + 512, size: .n1024, sampleRate: rate, timestampNanoseconds: 6, hop: 512)
            XCTAssertNil(d.process(next, magnitudes: flat(0, size: .n1024)))
            let after = SpectrumFrame(index: 5 * 256 + 1_000 + 1_024, size: .n1024, sampleRate: rate, timestampNanoseconds: 7, hop: 512)
            XCTAssertEqual(d.process(after, magnitudes: flat(0.1, size: .n1024))?.sampleIndex, 5 * 256 + 1_000 + 1_024 + 512)
            XCTAssertEqual(d.ignoredFrames, 0)
        }
    }

    func testMismatchedFramesAreIgnoredAndCounted() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend, interval: 0)
            XCTAssertNil(d.process(frame(0), magnitudes: zeros))
            XCTAssertNil(d.process(frame(1, rate: 48_000), magnitudes: flat()))
            XCTAssertEqual(d.ignoredFrames, 1)
            XCTAssertNil(d.process(frame(2), magnitudes: [Float](repeating: 0.01, count: 100)))
            XCTAssertEqual(d.ignoredFrames, 2)
            // The next accepted frame is a baseline even though it rises from silence.
            XCTAssertNil(d.process(frame(3), magnitudes: flat()))
            XCTAssertEqual(d.lastFlux, 0)
            XCTAssertEqual(d.processedFrames, 2)
            XCTAssertNil(d.process(frame(4), magnitudes: zeros))
            XCTAssertNotNil(d.process(frame(5), magnitudes: flat()))
        }
    }

    func testNonFiniteAndExtremeInputGivesBoundedFlux() throws {
        for backend in TestSupport.backends {
            let d = try detector(backend, interval: 0)
            var bad = flat()
            for k in stride(from: 0, to: bad.count, by: 4) { bad[k] = .nan }
            for k in stride(from: 1, to: bad.count, by: 4) { bad[k] = .infinity }
            for k in stride(from: 2, to: bad.count, by: 4) { bad[k] = -1 }
            _ = d.process(frame(0), magnitudes: bad)
            XCTAssertTrue(d.lastFlux.isFinite && d.lastFlux >= 0 && d.lastFlux <= 1, "\(d.lastFlux)")
            d.reset()
            _ = d.process(frame(0), magnitudes: flat(1e6))
            XCTAssertGreaterThan(d.lastFlux, 0.9)
            XCTAssertLessThanOrEqual(d.lastFlux, 1)
        }
    }

    func testArrayConvenienceEqualsPointerAPI() throws {
        for backend in TestSupport.backends {
            let a = try detector(backend), b = try detector(backend)
            let spectra = (0..<40).map { k in k % 7 == 3 ? flat(0.02) : TestSupport.noise(count: 257, seed: UInt64(k), amplitude: 0.001).map(abs) }
            for (k, s) in spectra.enumerated() {
                let x = a.process(frame(k), magnitudes: s)
                let y = s.withUnsafeBufferPointer { b.process(frame(k), magnitudes: $0) }
                XCTAssertEqual(x, y)
                XCTAssertEqual(a.lastFlux.bitPattern, b.lastFlux.bitPattern)
            }
            XCTAssertGreaterThan(a.eventCount, 0)
        }
    }
}
