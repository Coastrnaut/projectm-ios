// FX-002-T03: the plain-Swift reference of the output tone map (FX-002-R2 to R5, S5). CPU only; runs on Linux
// and on the Mac in the Linux shape (-DCOMPOSITOR_NO_METAL).
import Compositor
import XCTest

final class ToneMapReferenceTests: XCTestCase {
    private typealias P = ToneMap.Pixel

    private func assertClose(_ a: P, _ b: P, _ tolerance: Double = 1e-12, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        for c in 0..<4 {
            XCTAssertEqual(a[c], b[c], accuracy: tolerance, "\(message) channel \(c): \(a) vs \(b)", file: file, line: line)
        }
    }

    func testInRangePixelsAreUnchangedBitForBit() {
        let samples: [P] = [P(0, 0, 0, 0), P(1, 1, 1, 1), P(0.25, 0.5, 0.75, 1), P(1, 0, 0, 0.5), P(0.9, 0.9, 0.9, 1),
                            P(0.0031308, 0.04, 0.999, 0.3), P(0.7, 0.2, 1, 0)]
        for p in samples {
            let out: P = ToneMap.map(p)
            for c in 0..<4 { XCTAssertEqual(out[c].bitPattern, p[c].bitPattern, "\(p) channel \(c)") }
        }
    }

    func testSpecialValuesSanitise() {
        let nan: Double = .nan
        let inf: Double = .infinity
        assertClose(ToneMap.map(P(nan, 0.5, 0.5, 1)), P(0, 0.5, 0.5, 1), 0, "NaN channel")
        assertClose(ToneMap.map(P(inf, 0.5, 0.5, 1)), P(0, 0.5, 0.5, 1), 0, "+Inf channel")
        assertClose(ToneMap.map(P(-inf, 0.5, 0.5, 1)), P(0, 0.5, 0.5, 1), 0, "-Inf channel")
        assertClose(ToneMap.map(P(-0.5, 0.5, 0.5, 1)), P(0, 0.5, 0.5, 1), 0, "negative channel")
        assertClose(ToneMap.map(P(0.5, 0.5, 0.5, nan)), P(0.5, 0.5, 0.5, 0), 0, "NaN alpha")
        assertClose(ToneMap.map(P(0.5, 0.5, 0.5, 2)), P(0.5, 0.5, 0.5, 1), 0, "alpha above 1")
        assertClose(ToneMap.map(P(0.5, 0.5, 0.5, -1)), P(0.5, 0.5, 0.5, 0), 0, "negative alpha")
        assertClose(ToneMap.map(P(nan, nan, nan, nan)), P(0, 0, 0, 0), 0, "all NaN")
        XCTAssertTrue(ToneMap.isNonFinite(P(1, inf, 0, 1)))
        XCTAssertTrue(ToneMap.isNonFinite(P(1, 0, 0, nan)))
        XCTAssertFalse(ToneMap.isNonFinite(P(16, -3, 0, 1)), "large and negative values are finite")
    }

    func testHandCheckedOverRangeValues() {
        assertClose(ToneMap.map(P(16, 16, 16, 1)), P(1, 1, 1, 1), 0, "grey above 1 is white")
        assertClose(ToneMap.map(P(1.0001, 1.0001, 1.0001, 1)), P(1, 1, 1, 1), 0, "grey just above 1")
        // (2, 0.5, 0.25): Y = 0.4252 + 0.3576 + 0.01805 = 0.80085, s = 0.19915 / 1.19915.
        let y: Double = 0.80085
        let s: Double = (1 - y) / (2 - y)
        let expected = P(1, y + s * (0.5 - y), y + s * (0.25 - y), 1)
        let out: P = ToneMap.map(P(2, 0.5, 0.25, 1))
        assertClose(out, expected, 1e-12, "orange above 1")
        XCTAssertEqual(ToneMap.luminance(out), y, accuracy: 1e-12, "luminance kept")
        XCTAssertGreaterThan(out.y, out.z, "hue order kept (green above blue)")
        // A saturated red whose luminance is below 1 keeps it: (4, 0.1, 0.1) → Y = 0.8504 + 0.07874 = 0.92914.
        let red: P = ToneMap.map(P(4, 0.1, 0.1, 1))
        XCTAssertEqual(red.x, 1, accuracy: 1e-12)
        XCTAssertEqual(ToneMap.luminance(red), 0.8504 + 0.07152 + 0.00722, accuracy: 1e-12)
        XCTAssertEqual(red.y, red.z, accuracy: 1e-12, "equal channels stay equal")
        assertClose(ToneMap.map(P(10, 10, 0, 1)), P(1, 1, 1, 1), 0, "luminance 9.3: white")
    }

    /// Output luminance is min(Y, 1) of the sanitised pixel, so it never falls when a channel rises.
    func testOutputLuminanceIsClampedInputLuminance() {
        var generator = SplitMix(seed: 7)
        for _ in 0..<2_000 {
            let p = P(generator.next(upTo: 6), generator.next(upTo: 6), generator.next(upTo: 6), 1)
            let expected: Double = min(ToneMap.luminance(p), 1)
            XCTAssertEqual(ToneMap.luminance(ToneMap.map(p)), expected, accuracy: 1e-9, "\(p)")
        }
    }

    /// FX-002-R5, research D2: along every ray t·v (t from 0 to 64) no output channel decreases.
    func testMonotonicAlongColourRays() {
        let hues: [SIMD3<Double>] = [SIMD3(1, 1, 1), SIMD3(1, 0.5, 0.25), SIMD3(0.2, 0.4, 1), SIMD3(1, 0.05, 0.05),
                                     SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 1, 0), SIMD3(0.3, 0, 0.9)]
        for v in hues {
            var previous: P = ToneMap.map(P(0, 0, 0, 1))
            for step in 1...4_096 {
                let t: Double = Double(step) / 64
                let out: P = ToneMap.map(P(t * v.x, t * v.y, t * v.z, 1))
                for c in 0..<3 {
                    XCTAssertGreaterThanOrEqual(out[c], previous[c] - 1e-12, "hue \(v) at t \(t) channel \(c)")
                }
                previous = out
            }
            XCTAssertEqual(previous, P(1, 1, 1, 1), "hue \(v) reaches white")
        }
    }

    /// FX-002-S5: 10,000 random colours (finite, over-range, negative and special values) map into 0…1, never NaN,
    /// and random rays stay ordered.
    func testRandomColoursStayInRangeAndOrdered() {
        var generator = SplitMix(seed: 42)
        let specials: [Double] = [.nan, .infinity, -.infinity, -1, 0, 1, 65504]
        for i in 0..<10_000 {
            var p = P(generator.next(upTo: 20) - 2, generator.next(upTo: 20) - 2, generator.next(upTo: 20) - 2,
                      generator.next(upTo: 1.5))
            if i % 10 == 0 { p[i / 10 % 4] = specials[i / 40 % specials.count] }
            let out: P = ToneMap.map(p)
            for c in 0..<4 {
                XCTAssertFalse(out[c].isNaN, "\(p) → NaN")
                XCTAssertTrue(out[c] >= 0 && out[c] <= 1, "\(p) → \(out)")
            }
            // A ray through a random finite non-negative colour: t and 1.5·t keep the order.
            let v = P(generator.next(upTo: 4), generator.next(upTo: 4), generator.next(upTo: 4), 1)
            let near: P = ToneMap.map(v)
            let far: P = ToneMap.map(P(1.5 * v.x, 1.5 * v.y, 1.5 * v.z, 1))
            for c in 0..<3 { XCTAssertGreaterThanOrEqual(far[c], near[c] - 1e-12, "ray \(v) channel \(c)") }
        }
    }
}

/// A small deterministic generator (no Foundation randomness; same sequence on every platform).
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextBits() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<limit.
    mutating func next(upTo limit: Double) -> Double {
        let unit: Double = Double(nextBits() >> 11) / Double(UInt64(1) << 53)
        return unit * limit
    }
}
