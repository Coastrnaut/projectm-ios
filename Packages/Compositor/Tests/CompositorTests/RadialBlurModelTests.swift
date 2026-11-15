// FX-008-T03: the radial blur's value, sample positions and CPU reference (FX-008-R2 to R6, R12; research FX-008-D2 to
// D5). Plain Swift, no GPU: runs on Linux too.
import Compositor
import XCTest

final class RadialBlurModelTests: XCTestCase {
    private let maximum = RadialBlur(isEnabled: true, strength: 0.25)

    func testClampsAndDefaults() {
        XCTAssertEqual(RadialBlur.off, RadialBlur(isEnabled: false, strength: 0.1, focusX: 0.5, focusY: 0.5))
        XCTAssertEqual(RadialBlur.clampStrength(.nan), RadialBlur.defaultStrength)
        XCTAssertEqual(RadialBlur.clampStrength(3), 0.25)
        XCTAssertEqual(RadialBlur.clampStrength(-.infinity), 0)
        XCTAssertEqual(RadialBlur.clampFocus(.nan), 0.5)
        XCTAssertEqual(RadialBlur.clampFocus(-2), 0)
        XCTAssertEqual(RadialBlur.clampFocus(.infinity), 1)
        XCTAssertEqual(RadialBlur(isEnabled: true, strength: 9, focusX: -1, focusY: 7).clamped,
                       RadialBlur(isEnabled: true, strength: 0.25, focusX: 0, focusY: 1))
    }

    func testActiveOnlyWhenOnWithStrengthAndTwoPixels() {
        XCTAssertFalse(RadialBlur.off.isActive(width: 100, height: 100))
        XCTAssertFalse(RadialBlur(isEnabled: true, strength: 0).isActive(width: 100, height: 100))
        XCTAssertFalse(maximum.isActive(width: 1, height: 100))
        XCTAssertTrue(maximum.isActive(width: 2, height: 2))
        XCTAssertEqual(RadialBlur(isEnabled: true, focusX: 0.25, focusY: 1).focusPixels(width: 101, height: 81),
                       SIMD2<Float>(25, 80), "0 = left/top, pixel centres at whole numbers")
    }

    func testTapCountIsFixedAndSampleZeroIsThePixel() {
        XCTAssertEqual(RadialBlur.tapCount, 16)
        for strength in [0.01, 0.1, 0.25] {
            let b = RadialBlur(isEnabled: true, strength: strength).block(width: 64, height: 48)
            for (x, y) in [(0, 0), (31, 23), (63, 47), (10, 40)] {
                let p = RadialBlur.samplePositions(x: x, y: y, block: b)
                XCTAssertEqual(p.count, 16, "the same budget for every pixel and strength")
                XCTAssertEqual(p[0], SIMD2<Float>(Float(x), Float(y)))
            }
        }
    }

    func testEverySampleInsideTheFrameForAnyFocus() {
        let w = 40, h = 30
        for (fx, fy) in [(0.0, 0.0), (1.0, 1.0), (0.5, 0.5), (1.0, 0.0), (0.3, 0.9)] {
            let b = RadialBlur(isEnabled: true, strength: 0.25, focusX: fx, focusY: fy).block(width: w, height: h)
            for y in 0..<h {
                for x in 0..<w {
                    for p in RadialBlur.samplePositions(x: x, y: y, block: b) {
                        XCTAssertTrue(p.x >= 0 && p.y >= 0 && p.x <= Float(w - 1) && p.y <= Float(h - 1), "(\(fx), \(fy)) \(p)")
                    }
                }
            }
        }
    }

    func testSpreadIsZeroAtTheFocusAndLinearInDistance() {
        let b = maximum.block(width: 101, height: 81)   // focus (50, 40)
        XCTAssertEqual(RadialBlur.spread(x: 50, y: 40, block: b), 0)
        XCTAssertEqual(RadialBlur.spread(x: 60, y: 40, block: b), 2, accuracy: 1e-5, "10 × 0.25 ÷ 1.25")
        XCTAssertEqual(RadialBlur.spread(x: 70, y: 40, block: b), 4, accuracy: 1e-5, "twice as far, twice the spread")
        XCTAssertEqual(RadialBlur.spread(x: 50, y: 0, block: b), 8, accuracy: 1e-5)
        let last = RadialBlur.samplePositions(x: 90, y: 40, block: b)[15]
        XCTAssertEqual(last.x, 82, accuracy: 1e-4, "the last sample at F + 40 ÷ 1.25: on the segment towards the focus")
        XCTAssertEqual(last.y, 40)
    }

    func testReferenceStreakOfAPointRunsFromDToDTimesOnePlusS() {
        let w = 101, h = 41
        var pixels = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 1), count: w * h)
        let focus = SIMD2<Int>(50, 20)
        pixels[20 * w + 70] = SIMD4<Float>(1, 1, 1, 1)   // d = 20 right of the focus
        let out = maximum.reference(pixels, width: w, height: h)
        let lit: [Int] = (0..<w).filter { (x: Int) -> Bool in out[20 * w + x].x >= 0.5 / 16 }
        XCTAssertEqual(lit.first, focus.x + 20, "the streak starts at the point")
        XCTAssertEqual(lit.last, focus.x + 25, "and ends at d × (1 + s) = 25")
    }

    func testReferenceIdentityCases() {
        let w = 9, h = 7
        var pixels: [SIMD4<Float>] = (0..<(w * h)).map { (i: Int) -> SIMD4<Float> in
            SIMD4<Float>(Float(i % 5) / 4, Float(i % 3) / 2, 0.5, 1)
        }
        XCTAssertEqual(RadialBlur(isEnabled: true, strength: 0).reference(pixels, width: w, height: h), pixels)
        XCTAssertEqual(RadialBlur.off.reference(pixels, width: w, height: h), pixels)
        pixels[0] = SIMD4<Float>(.nan, 0, 0, 1)
        let out = maximum.reference(pixels, width: w, height: h)
        XCTAssertTrue(out[0].x.isNaN, "a non-finite pixel passes through")
        XCTAssertEqual(out[3 * w + 4], pixels[3 * w + 4], "the focus pixel (4, 3) is unchanged")
        XCTAssertNotEqual(out[3 * w + 8], pixels[3 * w + 8], "an outer pixel is blurred")
    }
}
