// SpectrumAnalyzerTests.swift — window, normalization, silence and sanitizing, for every backend in
// the build (ANL-001-T04; ANL-001-R1, R3, R4, R8).
import XCTest
@testable import AnalysisFeatures

final class SpectrumAnalyzerTests: XCTestCase {
    func testOutputLengthAndSilence() {
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            for size in FFTSize.allCases {
                let spectrum = analyzer.magnitudes(of: [Float](repeating: 0, count: size.rawValue), size: size)
                XCTAssertEqual(spectrum.count, size.binCount)
                XCTAssertTrue(spectrum.allSatisfy { $0 == 0 }, "\(backend) N=\(size.rawValue): silence is exactly 0")
            }
        }
    }

    func testResolvedBackend() {
        XCTAssertEqual(SpectrumAnalyzer(backend: .portable).resolvedBackend, .portable)
        XCTAssertEqual(SpectrumAnalyzer().resolvedBackend,
                       SpectrumBackend.isAcceleratedAvailable ? .accelerated : .portable)
        // Asking for the accelerated path where it is compiled out falls back to the portable one.
        XCTAssertEqual(SpectrumAnalyzer(backend: .accelerated).resolvedBackend,
                       SpectrumBackend.isAcceleratedAvailable ? .accelerated : .portable)
    }

    func testBinCentredSineReadsItsAmplitude() {
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            for size in FFTSize.allCases {
                for amplitude: Float in [0.25, 1.0] {
                    let bin = size.rawValue / 16
                    let spectrum = analyzer.magnitudes(of: TestSupport.binCentredSine(bin: bin, size: size.rawValue, amplitude: amplitude), size: size)
                    XCTAssertEqual(TestSupport.peakBin(spectrum), bin)
                    XCTAssertEqual(spectrum[bin], amplitude, accuracy: 1e-4 * amplitude, "\(backend) N=\(size.rawValue) A=\(amplitude)")
                    // Hann main lobe: the neighbours read A/2, everything else ~0.
                    XCTAssertEqual(spectrum[bin - 1], amplitude / 2, accuracy: 1e-4)
                    XCTAssertEqual(spectrum[bin + 1], amplitude / 2, accuracy: 1e-4)
                    XCTAssertLessThan(spectrum[bin + 3], 1e-4)
                }
            }
        }
    }

    func testConstantAndNyquistUseTheSameScale() {
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            for size in FFTSize.allCases {
                let n = size.rawValue
                let constant = analyzer.magnitudes(of: [Float](repeating: 0.5, count: n), size: size)
                XCTAssertEqual(constant[0], 0.5, accuracy: 1e-4, "\(backend) DC N=\(n)")
                let alternating = analyzer.magnitudes(of: (0..<n).map { $0 % 2 == 0 ? 0.5 : -0.5 }, size: size)
                XCTAssertEqual(alternating[n / 2], 0.5, accuracy: 1e-4, "\(backend) Nyquist N=\(n)")
            }
        }
    }

    func testHannWindowIsPeriodic() {
        for size in FFTSize.allCases {
            let window = HannWindow.table(for: size)
            let n = size.rawValue
            XCTAssertEqual(window.count, n)
            XCTAssertEqual(window[0], 0)
            XCTAssertEqual(window[n / 2], 1)
            XCTAssertEqual(window[n / 4], 0.5, accuracy: 1e-7)
            for i in 1..<n { XCTAssertEqual(window[i], window[n - i], "N=\(n) i=\(i)") }
        }
    }

    func testSanitizingGivesFiniteNonNegativeValues() {
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            for size in FFTSize.allCases {
                let n = size.rawValue
                var clean = TestSupport.noise(count: n, seed: UInt64(n))
                var dirty = clean
                // NaN, infinities and denormals act as 0.
                for (i, value) in [Float.nan, .infinity, -.infinity, Float.leastNormalMagnitude / 4, -Float.leastNormalMagnitude / 4, .leastNonzeroMagnitude, -Float.signalingNaN].enumerated() {
                    let index = (i * 37 + 5) % n
                    dirty[index] = value
                    clean[index] = 0
                }
                XCTAssertEqual(TestSupport.bitPattern(analyzer.magnitudes(of: dirty, size: size)),
                               TestSupport.bitPattern(analyzer.magnitudes(of: clean, size: size)), "\(backend) N=\(n)")
                // Huge finite values are clamped to ±64.
                var huge = TestSupport.noise(count: n, seed: 7)
                var clamped = huge
                let hugeValues: [Float] = [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, 1e30, -1e30, 64.5]
                for (i, value) in hugeValues.enumerated() {
                    let index = (i * 101 + 3) % n
                    huge[index] = value
                    clamped[index] = value > 0 ? 64 : -64
                }
                let hugeSpectrum = analyzer.magnitudes(of: huge, size: size)
                XCTAssertTrue(hugeSpectrum.allSatisfy { $0.isFinite && $0 >= 0 })
                XCTAssertEqual(TestSupport.bitPattern(hugeSpectrum),
                               TestSupport.bitPattern(analyzer.magnitudes(of: clamped, size: size)))
                // All non-finite: still finite output, all zero.
                let allNaN = analyzer.magnitudes(of: [Float](repeating: .nan, count: n), size: size)
                XCTAssertTrue(allNaN.allSatisfy { $0 == 0 })
                let fullScale = analyzer.magnitudes(of: [Float](repeating: .greatestFiniteMagnitude, count: n), size: size)
                XCTAssertTrue(fullScale.allSatisfy { $0.isFinite && $0 >= 0 })
                XCTAssertEqual(fullScale[0], 64, accuracy: 1e-2)
            }
        }
    }

    func testPointerAPIEqualsArrayAPI() {
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            for size in FFTSize.allCases {
                let input = TestSupport.noise(count: size.rawValue, seed: 99)
                var output = [Float](repeating: -1, count: size.binCount)
                input.withUnsafeBufferPointer { src in
                    output.withUnsafeMutableBufferPointer { dst in
                        analyzer.magnitudes(of: src.baseAddress!, size: size, into: dst.baseAddress!)
                    }
                }
                XCTAssertEqual(TestSupport.bitPattern(output), TestSupport.bitPattern(analyzer.magnitudes(of: input, size: size)))
            }
        }
    }

    func testSizesCanBeMixedOnOneAnalyzer() {
        for backend in TestSupport.backends {
            let shared = SpectrumAnalyzer(backend: backend)
            for size in FFTSize.allCases.reversed() + FFTSize.allCases {
                let input = TestSupport.noise(count: size.rawValue, seed: UInt64(size.rawValue) + 1)
                let fresh = SpectrumAnalyzer(backend: backend).magnitudes(of: input, size: size)
                XCTAssertEqual(TestSupport.bitPattern(shared.magnitudes(of: input, size: size)), TestSupport.bitPattern(fresh))
            }
        }
    }
}
