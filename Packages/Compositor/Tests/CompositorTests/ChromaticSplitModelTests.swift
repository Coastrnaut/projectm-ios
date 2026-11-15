// FX-006-T03: the chromatic split's value and sample-position maths on the CPU (FX-006-R3, R4, R6, R12; research
// FX-006-D2 to D5). Plain Swift, no GPU: runs on Linux too.
import Compositor
import XCTest

final class ChromaticSplitModelTests: XCTestCase {
    private let on = ChromaticSplit(isEnabled: true, amount: 0.02)

    func testClampAndWrap() {
        XCTAssertEqual(ChromaticSplit.clampAmount(.nan), ChromaticSplit.defaultAmount)
        XCTAssertEqual(ChromaticSplit.clampAmount(1), 0.02)
        XCTAssertEqual(ChromaticSplit.clampAmount(-.infinity), 0)
        XCTAssertEqual(ChromaticSplit.clampAngle(360), 360)
        XCTAssertEqual(ChromaticSplit.clampAngle(450), 90)
        XCTAssertEqual(ChromaticSplit.clampAngle(-90), 270)
        XCTAssertEqual(ChromaticSplit.clampAngle(.nan), 0)
        XCTAssertEqual(ChromaticSplit(isEnabled: true, amount: 9, angleDegrees: -30).clamped,
                       ChromaticSplit(isEnabled: true, amount: 0.02, angleDegrees: 330))
    }

    func testActiveOnlyWhenOnWithAPositiveLengthAndAnInterior() {
        XCTAssertFalse(ChromaticSplit.off.isActive(width: 100, height: 100))
        XCTAssertFalse(ChromaticSplit(isEnabled: true, amount: 0).isActive(width: 100, height: 100))
        XCTAssertFalse(on.isActive(width: 2, height: 100), "no interior")
        XCTAssertTrue(on.isActive(width: 100, height: 50))
        XCTAssertEqual(on.amountPixels(width: 100, height: 50), 1, "2% of the shorter side")
    }

    func testLinearDirectionAndFade() {
        let w = 100, h = 100
        let right: ChromaticSplit.Block = on.block(width: w, height: h)
        XCTAssertEqual(right.linear, SIMD2<Float>(2, 0), "0°: red moves right")
        XCTAssertEqual(ChromaticSplit(isEnabled: true, amount: 0.02, angleDegrees: 90).block(width: w, height: h).linear,
                       SIMD2<Float>(0, -2), "90°: red moves up (texture y points down)")
        XCTAssertEqual(ChromaticSplit.vector(x: 0, y: 50, width: w, height: h, block: right), .zero, "border ring")
        XCTAssertEqual(ChromaticSplit.vector(x: 1, y: 50, width: w, height: h, block: right), SIMD2<Float>(1, 0), "half the band")
        XCTAssertEqual(ChromaticSplit.vector(x: 50, y: 50, width: w, height: h, block: right), SIMD2<Float>(2, 0), "beyond the band")
    }

    func testRadialGrowsFromTheCentreAndNeverExceedsTheAmount() {
        let w = 101, h = 61
        let split = ChromaticSplit(isEnabled: true, amount: 0.02, isRadial: true)
        let b: ChromaticSplit.Block = split.block(width: w, height: h)
        XCTAssertEqual(ChromaticSplit.vector(x: 50, y: 30, width: w, height: h, block: b), .zero, "centre")
        for (x, y) in [(1, 1), (99, 59), (10, 30), (50, 2)] {
            let v: SIMD2<Float> = ChromaticSplit.vector(x: x, y: y, width: w, height: h, block: b)
            XCTAssertLessThanOrEqual((v * v).sum().squareRoot(), b.amountPixels + 1e-4)
        }
    }

    /// Every sample lies inside the frame before the clamp, at the maximum amount, for linear angles and radial.
    func testEverySampleIsInsideTheFrame() {
        let w = 40, h = 24
        let splits: [ChromaticSplit] = [0.0, 45, 90, 200, 315].map { (a: Double) -> ChromaticSplit in
            ChromaticSplit(isEnabled: true, amount: 0.02, angleDegrees: a)
        } + [ChromaticSplit(isEnabled: true, amount: 0.02, isRadial: true)]
        for split in splits {
            let b: ChromaticSplit.Block = split.block(width: w, height: h)
            for y in 0..<h {
                for x in 0..<w {
                    let v: SIMD2<Float> = ChromaticSplit.vector(x: x, y: y, width: w, height: h, block: b)
                    let q = SIMD2<Float>(Float(x), Float(y))
                    for s in [q - v, q + v] {
                        XCTAssertTrue(s.x >= -1e-4 && s.x <= Float(w - 1) + 1e-4 && s.y >= -1e-4 && s.y <= Float(h - 1) + 1e-4,
                                      "\(split) at (\(x), \(y)) samples \(s)")
                    }
                }
            }
        }
    }

    func testReferenceShiftsRedAndBlueByWholePixels() {
        let w = 20, h = 20
        var pixels = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 1), count: w * h)
        for y in 0..<h { pixels[y * w + 10] = SIMD4<Float>(1, 1, 1, 1) }   // a white column at x = 10
        let wide = ChromaticSplit(isEnabled: true, amount: 0.02)
        let out: [SIMD4<Float>] = wide.reference(pixels, width: w, height: h)   // 0.4 px: filtered
        XCTAssertEqual(out[10 * w + 10].x, 0.6, accuracy: 1e-6, "red read at x = 9.6")
        // A 2-pixel shift on a 100-pixel frame.
        let big = 100
        var line = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 1), count: big * big)
        for y in 0..<big { line[y * big + 50] = SIMD4<Float>(1, 1, 1, 1) }
        let shifted: [SIMD4<Float>] = wide.reference(line, width: big, height: big)
        let row: Int = 50 * big
        XCTAssertEqual(shifted[row + 52].x, 1, "red moved 2 px right")
        XCTAssertEqual(shifted[row + 48].z, 1, "blue moved 2 px left")
        XCTAssertEqual(shifted[row + 50].y, 1, "green stays")
        XCTAssertEqual(shifted[row + 50].x, 0)
        XCTAssertEqual(shifted[row + 50].z, 0)
    }

    func testAlphaIsTheLargestSampleAndNonFiniteNeverSpreads() {
        let w = 100, h = 100
        var pixels = [SIMD4<Float>](repeating: .zero, count: w * h)
        pixels[50 * w + 48] = SIMD4<Float>(0.5, 0, 0, 0.5)   // red half-transparent, read by (50, 50) at 2 px
        pixels[60 * w + 61] = SIMD4<Float>(.nan, 0, .nan, 1) // a NaN pixel
        let split = ChromaticSplit(isEnabled: true, amount: 0.02)
        let out: [SIMD4<Float>] = split.reference(pixels, width: w, height: h)
        XCTAssertEqual(out[50 * w + 50], SIMD4<Float>(0.5, 0, 0, 0.5), "colour ≤ alpha stays valid")
        XCTAssertTrue(out[60 * w + 61].x.isNaN, "a non-finite pixel passes through")
        XCTAssertTrue(out[60 * w + 63].x.isNaN, "red read 2 px left at weight 1 shows it")
        XCTAssertTrue(out[60 * w + 59].z.isNaN, "blue read 2 px right at weight 1 shows it")
        let neighbour: SIMD4<Float> = out[60 * w + 62]   // reads x = 60 and 64; 61 has weight 0
        XCTAssertTrue(neighbour.x.isFinite && neighbour.z.isFinite, "a weight-0 neighbour never leaks")
    }

    func testInactiveReferenceIsTheInput() {
        let pixels: [SIMD4<Float>] = (0..<12).map { (i: Int) -> SIMD4<Float> in SIMD4<Float>(Float(i), 1, 2, 1) }
        XCTAssertEqual(ChromaticSplit(isEnabled: true, amount: 0).reference(pixels, width: 4, height: 3), pixels)
        XCTAssertEqual(ChromaticSplit(isEnabled: true, amount: 0.02).reference(pixels, width: 2, height: 6), pixels, "under 3 px")
    }
}
