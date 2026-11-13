// BandReducerTests.swift — the reduction of ANL-002 (ANL-002-T04; ANL-002-R4, R5, R7 to R9, S4) and
// the normalizers, for every backend in the build.
import XCTest
@testable import AnalysisFeatures
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class BandReducerTests: XCTestCase {
    private let rates: [Double] = [44_100, 48_000]

    func testZeroSpectrumGivesExactlyZero() throws {
        for backend in TestSupport.backends {
            for rate in rates {
                let reducer = try BandReducer(sampleRate: rate, backend: backend)
                for size in FFTSize.allCases {
                    let zero = [Float](repeating: 0, count: size.binCount)
                    for count in BandCount.allCases {
                        let bands = reducer.reduce(zero, size: size, bandCount: count)
                        XCTAssertEqual(bands.count, count.rawValue)
                        XCTAssertEqual(bands.map(\.bitPattern), [UInt32](repeating: 0, count: count.rawValue),
                                       "\(backend) R=\(rate) N=\(size.rawValue) B=\(count.rawValue)")
                    }
                }
            }
        }
    }

    func testInvalidMagnitudesCountAsZeroAndOutputStaysFinite() throws {
        for backend in TestSupport.backends {
            let reducer = try BandReducer(sampleRate: 44_100, backend: backend)
            for size in FFTSize.allCases {
                let clean = (0..<size.binCount).map { Float(($0 * 37) % 11) * 0.01 }
                var dirty = clean
                var zeroed = clean
                let invalid: [Float] = [.nan, .infinity, -.infinity, -0.5, -1e30]
                for (i, value) in invalid.enumerated() {
                    let k = 3 + i * (size.binCount / 7)
                    dirty[k] = value
                    zeroed[k] = 0
                }
                var huge = clean
                huge[size.binCount / 2] = 1e30
                for count in BandCount.allCases {
                    let a = reducer.reduce(dirty, size: size, bandCount: count)
                    let b = reducer.reduce(zeroed, size: size, bandCount: count)
                    XCTAssertEqual(a.map(\.bitPattern), b.map(\.bitPattern), "\(backend) N=\(size.rawValue) B=\(count.rawValue)")
                    let h = reducer.reduce(huge, size: size, bandCount: count)
                    XCTAssertTrue(h.allSatisfy { $0.isFinite && $0 >= 0 }, "\(backend) N=\(size.rawValue) B=\(count.rawValue)")
                    XCTAssertTrue(a.allSatisfy { $0.isFinite && $0 >= 0 })
                }
            }
        }
    }

    /// Band 9 of 16 at 8,192 points, 44.1 kHz: about 974–1,500 Hz, roughly 98 bins wide.
    private func centreBin(_ layout: BandLayout, band: Int) -> Int {
        layout.size.nearestBin(toFrequency: layout.centerFrequency(ofBand: band), sampleRate: layout.sampleRate)
    }

    func testSingleBinInsideAWideBandReadsItsPowerOverTheENBW() throws {
        for backend in TestSupport.backends {
            let reducer = try BandReducer(sampleRate: 44_100, backend: backend)
            let layout = reducer.layout(bandCount: .b16, size: .n8192)
            XCTAssertGreaterThan(layout.widthInBins(ofBand: 9), 90)
            var spectrum = [Float](repeating: 0, count: FFTSize.n8192.binCount)
            spectrum[centreBin(layout, band: 9)] = 1
            let bands = reducer.reduce(spectrum, size: .n8192, bandCount: .b16)
            XCTAssertEqual(bands[9], Float((1 / 1.5).squareRoot()), accuracy: 1e-6)
            for band in 0..<16 where band != 9 { XCTAssertEqual(bands[band].bitPattern, 0) }
        }
    }

    func testSineInsideAWideBandReadsItsAmplitude() throws {
        let size = FFTSize.n8192
        let n = size.rawValue
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            let reducer = try BandReducer(sampleRate: 44_100, backend: backend)
            let bin = Double(centreBin(reducer.layout(bandCount: .b16, size: size), band: 9))
            for amplitude in [0.25, 1.0] {
                for offset in [0.0, 0.37] {
                    let signal = (0..<n).map { Float(amplitude * sin(2 * Double.pi * (bin + offset) * Double($0) / Double(n))) }
                    let bands = reducer.reduce(analyzer.magnitudes(of: signal, size: size), size: size, bandCount: .b16)
                    XCTAssertEqual(Double(bands[9]), amplitude, accuracy: amplitude * 1e-3, "\(backend) A=\(amplitude) offset \(offset)")
                }
            }
        }
    }

    /// m ≡ c gives c·sqrt(max(W_b, 1)/1.5): wide bands sum, sub-bin bands read the level (ANL-002-R4, R5).
    func testConstantSpectrumFollowsTheFormulaInEveryBand() throws {
        let c: Float = 0.5
        for backend in TestSupport.backends {
            for rate in rates {
                let reducer = try BandReducer(sampleRate: rate, backend: backend)
                for size in FFTSize.allCases {
                    let spectrum = [Float](repeating: c, count: size.binCount)
                    for count in BandCount.allCases {
                        let layout = reducer.layout(bandCount: count, size: size)
                        let bands = reducer.reduce(spectrum, size: size, bandCount: count)
                        for band in 0..<count.rawValue {
                            let expected = Double(c) * (max(layout.widthInBins(ofBand: band), 1) / 1.5).squareRoot()
                            XCTAssertEqual(Double(bands[band]), expected, accuracy: expected * 1e-5,
                                           "\(backend) R=\(rate) N=\(size.rawValue) B=\(count.rawValue) band \(band)")
                        }
                    }
                }
            }
        }
    }

    func testArrayConveniencePointerAPIAndSwitchingAreBitIdentical() throws {
        for backend in TestSupport.backends {
            let switching = try BandReducer(sampleRate: 48_000, backend: backend)
            let noise = TestSupport.noise(count: FFTSize.maximum.rawValue)
            let analyzer = SpectrumAnalyzer(backend: backend)
            var output = [Float](repeating: -1, count: 128)
            // Every (size, count) pair in an interleaved order on one reducer vs a fresh reducer each.
            for size in FFTSize.allCases.reversed() {
                let magnitudes = analyzer.magnitudes(of: noise, size: size)
                for count in [BandCount.b64, .b16, .b128, .b32] {
                    let fresh = try BandReducer(sampleRate: 48_000, backend: backend).reduce(magnitudes, size: size, bandCount: count)
                    magnitudes.withUnsafeBufferPointer { m in
                        output.withUnsafeMutableBufferPointer { o in
                            switching.reduce(magnitudes: m.baseAddress!, size: size, bandCount: count, into: o.baseAddress!)
                        }
                    }
                    XCTAssertEqual(Array(output[0..<count.rawValue]).map(\.bitPattern), fresh.map(\.bitPattern))
                    XCTAssertEqual(switching.layout(bandCount: count, size: size),
                                   try BandLayout(bandCount: count, size: size, sampleRate: 48_000))
                }
            }
            XCTAssertEqual(switching.sampleRate, 48_000)
            XCTAssertEqual(switching.resolvedBackend, backend)
        }
    }

    // MARK: Normalizers (ANL-002-R8)

    func testLinearNormalization() {
        XCTAssertEqual(BandMath.normalizedLinear(0).bitPattern, 0)
        XCTAssertEqual(BandMath.normalizedLinear(0.5), 0.5)
        XCTAssertEqual(BandMath.normalizedLinear(2), 1)
        XCTAssertEqual(BandMath.normalizedLinear(0.25, reference: 0.5), 0.5)
        XCTAssertEqual(BandMath.normalizedLinear(.infinity), 1)
        XCTAssertEqual(BandMath.normalizedLinear(.nan), 0)
        XCTAssertEqual(BandMath.normalizedLinear(-1), 0)
        XCTAssertEqual(BandMath.normalizedLinear(0.5, reference: 0), 0)
        XCTAssertEqual(BandMath.normalizedLinear(0.5, reference: -1), 0)
        XCTAssertEqual(BandMath.normalizedLinear(0.5, reference: .nan), 0)
    }

    func testDecibelNormalization() {
        XCTAssertEqual(BandMath.defaultFloorDecibels, -80)
        XCTAssertEqual(BandMath.normalizedDecibels(0).bitPattern, 0)
        XCTAssertEqual(BandMath.normalizedDecibels(1), 1, accuracy: 1e-6)
        XCTAssertEqual(BandMath.normalizedDecibels(0.1), 0.75, accuracy: 1e-6)
        XCTAssertEqual(BandMath.normalizedDecibels(0.01, floorDecibels: -60), 1.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(BandMath.normalizedDecibels(1e-5), 0)
        XCTAssertEqual(BandMath.normalizedDecibels(2), 1)
        XCTAssertEqual(BandMath.normalizedDecibels(.infinity), 1)
        XCTAssertEqual(BandMath.normalizedDecibels(.nan), 0)
        XCTAssertEqual(BandMath.normalizedDecibels(0.5, floorDecibels: 0), 0)
        XCTAssertEqual(BandMath.normalizedDecibels(0.5, floorDecibels: 10), 0)
        XCTAssertEqual(BandMath.normalizedDecibels(0.5, floorDecibels: -.infinity), 0)
    }

    func testInPlaceNormalizeEqualsTheScalarFunctions() {
        let values: [Float] = [0, 1e-6, 1e-3, 0.1, 0.5, 1, 3, .nan, .infinity, -2]
        for scale in [BandScale.linear(reference: 1), .linear(reference: 0.25), .decibels(floorDecibels: -80), .decibels(floorDecibels: -40)] {
            var copy = values
            copy.withUnsafeMutableBufferPointer { BandMath.normalize($0.baseAddress!, count: $0.count, scale: scale) }
            let expected: [Float] = values.map {
                switch scale {
                case .linear(let reference): return BandMath.normalizedLinear($0, reference: reference)
                case .decibels(let floor): return BandMath.normalizedDecibels($0, floorDecibels: floor)
                }
            }
            XCTAssertEqual(copy.map(\.bitPattern), expected.map(\.bitPattern), "\(scale)")
            XCTAssertTrue(copy.allSatisfy { (0...1).contains($0) })
        }
    }
}
