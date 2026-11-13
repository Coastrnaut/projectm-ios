// BandLayoutTests.swift — the band tables of ANL-002 (ANL-002-T03; ANL-002-R1 to R3, R6, R10, S4).
// Every check compares the production table with `BandOracle`, which recomputes the spec's formulas.
import XCTest
@testable import AnalysisFeatures

final class BandLayoutTests: XCTestCase {
    private let rates: [Double] = [44_100, 48_000]

    func testBandCountsAreExactlyTheFourOffered() {
        XCTAssertEqual(BandCount.allCases.map(\.rawValue), [16, 32, 64, 128])
        XCTAssertNil(BandCount(rawValue: 24))
        XCTAssertNil(BandCount(rawValue: 0))
    }

    func testEdgesFollowTheLogFormula() throws {
        for rate in rates {
            for count in BandCount.allCases {
                for size in FFTSize.allCases {
                    let layout = try BandLayout(bandCount: count, size: size, sampleRate: rate)
                    let b = count.rawValue
                    let oracle = BandOracle.edges(count: b, sampleRate: rate)
                    XCTAssertEqual(layout.edges.count, b + 1)
                    XCTAssertEqual(layout.edges[0], 20)
                    XCTAssertEqual(layout.edges[b], 20_000)
                    XCTAssertEqual(layout.lowerEdge, 20)
                    XCTAssertEqual(layout.upperEdge, 20_000)
                    let ratio = layout.edges[1] / layout.edges[0]
                    for i in 0...b {
                        XCTAssertEqual(layout.edges[i], oracle[i], accuracy: oracle[i] * 1e-9)
                        if i > 0 {
                            XCTAssertGreaterThan(layout.edges[i], layout.edges[i - 1])
                            XCTAssertEqual(layout.edges[i] / layout.edges[i - 1], ratio, accuracy: ratio * 1e-9)
                        }
                    }
                    for band in 0..<b {
                        XCTAssertEqual(layout.lowerEdge(ofBand: band), layout.edges[band])
                        XCTAssertEqual(layout.upperEdge(ofBand: band), layout.edges[band + 1])
                        XCTAssertEqual(layout.centerFrequency(ofBand: band),
                                       (layout.edges[band] * layout.edges[band + 1]).squareRoot(), accuracy: 1e-9 * layout.edges[band + 1])
                    }
                    XCTAssertNil(layout.band(containingFrequency: 19.9))
                    XCTAssertEqual(layout.band(containingFrequency: 20), 0)
                    XCTAssertEqual(layout.band(containingFrequency: 19_999), b - 1)
                    XCTAssertNil(layout.band(containingFrequency: 20_000))
                    XCTAssertNil(layout.band(containingFrequency: .nan))
                    XCTAssertEqual(layout.band(containingFrequency: layout.centerFrequency(ofBand: b / 2)), b / 2)
                }
            }
        }
    }

    /// No empty band in any of the 40 tables; weights, coverage and ownership equal the oracle.
    func testWeightsCoverEveryBandAndMatchTheOracle() throws {
        var tables = 0
        var mismatches = 0
        for rate in rates {
            for count in BandCount.allCases {
                for size in FFTSize.allCases {
                    let layout = try BandLayout(bandCount: count, size: size, sampleRate: rate)
                    let n = size.rawValue
                    let edges = BandOracle.edges(count: count.rawValue, sampleRate: rate)
                    var binTotals = [Double](repeating: 0, count: size.binCount)
                    for band in 0..<count.rawValue {
                        let range = layout.binRange(ofBand: band)
                        let weights = layout.weights(ofBand: band)
                        XCTAssertFalse(range.isEmpty, "empty band \(band) B=\(count.rawValue) N=\(n) R=\(rate)")
                        XCTAssertGreaterThan(layout.widthInBins(ofBand: band), 0)
                        XCTAssertEqual(weights.count, range.count)
                        XCTAssertGreaterThanOrEqual(range.lowerBound, 1, "DC never contributes")
                        var width = 0.0
                        for k in 0..<size.binCount {
                            let expected = BandOracle.weight(bin: k, lo: edges[band], hi: edges[band + 1], size: n, sampleRate: rate)
                            let actual = range.contains(k) ? Double(weights[k - range.lowerBound]) : 0
                            // Count mismatches instead of asserting per bin (millions of checks).
                            if abs(actual - expected) > 1e-6 || (range.contains(k) && !(actual > 0 && actual <= 1)) {
                                if mismatches < 5 { XCTFail("band \(band) bin \(k) B=\(count.rawValue) N=\(n) R=\(rate): \(actual) vs \(expected)") }
                                mismatches += 1
                            }
                            binTotals[k] += actual
                            width += expected
                        }
                        XCTAssertEqual(layout.widthInBins(ofBand: band), width, accuracy: 1e-6)
                    }
                    for k in 0..<size.binCount {
                        XCTAssertLessThanOrEqual(binTotals[k], 1 + 1e-6, "bin \(k) counted more than once")
                        XCTAssertEqual(layout.ownerBand(ofBin: k),
                                       BandOracle.ownerBand(ofBin: k, edges: edges, size: n, sampleRate: rate),
                                       "owner of bin \(k) B=\(count.rawValue) N=\(n) R=\(rate)")
                    }
                    XCTAssertNil(layout.ownerBand(ofBin: 0))
                    tables += 1
                }
            }
        }
        XCTAssertEqual(tables, 40)
        XCTAssertEqual(mismatches, 0)
    }

    func testLowSampleRateUsesNyquistAsTheUpperEdge() throws {
        let layout = try BandLayout(bandCount: .b32, size: .n512, sampleRate: 8_000)
        XCTAssertEqual(layout.upperEdge, 4_000)
        XCTAssertEqual(layout.edges.last, 4_000)
        let nyquist = FFTSize.n512.binCount - 1
        let top = layout.binRange(ofBand: 31)
        XCTAssertEqual(top.upperBound - 1, nyquist)
        // The Nyquist bin's interval is the half bin below R/2, wholly inside the top band.
        XCTAssertEqual(layout.weights(ofBand: 31).last!, 1)
        XCTAssertEqual(layout.ownerBand(ofBin: nyquist), 31)
        let edges = BandOracle.edges(count: 32, sampleRate: 8_000)
        XCTAssertEqual(Double(layout.weights(ofBand: 31).last!),
                       BandOracle.weight(bin: nyquist, lo: edges[31], hi: edges[32], size: 512, sampleRate: 8_000))
        for band in 0..<32 { XCTAssertFalse(layout.binRange(ofBand: band).isEmpty) }
    }

    func testInvalidSampleRatesAreRejected() {
        for rate in [7_999, 0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try BandLayout(bandCount: .b16, size: .n2048, sampleRate: rate), "\(rate)") { error in
                XCTAssertEqual(error as? BandLayoutError, .invalidSampleRate(rate))
            }
            XCTAssertThrowsError(try BandReducer(sampleRate: rate), "\(rate)") { error in
                XCTAssertEqual(error as? BandLayoutError, .invalidSampleRate(rate))
            }
        }
    }
}
