// FX-007-T03: the directional blur's value and kernel on the CPU (FX-007-R2 to R7, R13, S3; research FX-007-D2 to
// D5). Plain Swift, no GPU: runs on Linux too.
import Compositor
import XCTest

final class DirectionalBlurModelTests: XCTestCase {
    private let maximum = DirectionalBlur(isEnabled: true, radius: 0.02)

    func testClampAndFold() {
        XCTAssertEqual(DirectionalBlur.clampRadius(.nan), DirectionalBlur.defaultRadius)
        XCTAssertEqual(DirectionalBlur.clampRadius(1), 0.02)
        XCTAssertEqual(DirectionalBlur.clampRadius(-.infinity), 0)
        XCTAssertEqual(DirectionalBlur.clampAngle(180), 180)
        XCTAssertEqual(DirectionalBlur.clampAngle(225), 45, "the axis has no sign")
        XCTAssertEqual(DirectionalBlur.clampAngle(-30), 150)
        XCTAssertEqual(DirectionalBlur.clampAngle(.infinity), 0)
        XCTAssertEqual(DirectionalBlur(isEnabled: true, radius: 9, angleDegrees: 270).clamped,
                       DirectionalBlur(isEnabled: true, radius: 0.02, angleDegrees: 90))
    }

    func testActiveOnlyWhenOnWithAPositiveRadius() {
        XCTAssertFalse(DirectionalBlur.off.isActive(width: 100, height: 100))
        XCTAssertFalse(DirectionalBlur(isEnabled: true, radius: 0).isActive(width: 100, height: 100))
        XCTAssertTrue(maximum.isActive(width: 100, height: 50))
        XCTAssertEqual(maximum.radiusPixels(width: 100, height: 50), 1, "2% of the shorter side")
    }

    /// Fixed tap budget: 16 taps, symmetric, reaching ±radius, weights summing to 1, the same at every radius.
    func testKernelHasSixteenSymmetricTapsWithUnitWeight() {
        XCTAssertEqual(DirectionalBlur.tapCount, 16)
        XCTAssertEqual(DirectionalBlur.unitOffsets.count, 16)
        XCTAssertEqual(DirectionalBlur.unitOffsets.first, -1)
        XCTAssertEqual(DirectionalBlur.unitOffsets.last, 1)
        XCTAssertEqual(DirectionalBlur.weights.reduce(0, +), 1, accuracy: 1e-6)
        for i in 0..<8 {
            XCTAssertEqual(DirectionalBlur.unitOffsets[i], -DirectionalBlur.unitOffsets[15 - i], accuracy: 1e-12)
            XCTAssertEqual(DirectionalBlur.weights[i], DirectionalBlur.weights[15 - i], accuracy: 1e-7)
        }
        XCTAssertGreaterThan(DirectionalBlur.weights[7], DirectionalBlur.weights[0], "Gaussian: heavier in the middle")
        for radius in [0.001, 0.005, 0.02] {
            let b: DirectionalBlur.Block = DirectionalBlur(isEnabled: true, radius: radius).block(width: 200, height: 100)
            XCTAssertEqual(b.weights, DirectionalBlur.weights, "\(radius): the weights do not depend on the radius")
            let r = Float(radius * 100)
            XCTAssertEqual(b.start.x, -r, accuracy: 1e-5)
            XCTAssertEqual(b.start.x + 15 * b.step.x, r, accuracy: 1e-5, "\(radius): the last tap reaches +radius")
        }
    }

    /// The CPU reference reads exactly 16 samples per pixel at every radius (the cost does not grow).
    func testReferenceReadsSixteenSamplesPerPixelAtEveryRadius() {
        let w = 12, h = 10
        let pixels = [SIMD4<Float>](repeating: SIMD4<Float>(0.5, 0.5, 0.5, 1), count: w * h)
        for radius in [0.001, 0.01, 0.02] {
            var samples = 0
            _ = DirectionalBlur(isEnabled: true, radius: radius, angleDegrees: 30).reference(pixels, width: w, height: h,
                                                                                             samples: &samples)
            XCTAssertEqual(samples, w * h * 16, "\(radius)")
        }
    }

    func testAngleZeroVariesOnlyInXAndNinetyOnlyInY() {
        let horizontal: DirectionalBlur.Block = maximum.block(width: 100, height: 100)
        XCTAssertEqual(horizontal.step.y, 0)
        XCTAssertEqual(horizontal.start.y, 0)
        XCTAssertEqual(horizontal.start.x, -2)
        let vertical: DirectionalBlur.Block = DirectionalBlur(isEnabled: true, radius: 0.02, angleDegrees: 90)
            .block(width: 100, height: 100)
        XCTAssertEqual(vertical.step.x, 0)
        XCTAssertEqual(vertical.start.x, 0)
        XCTAssertEqual(DirectionalBlur.direction(angleDegrees: 180), SIMD2<Float>(-1, 0), "180° is the same axis as 0°")
    }

    /// Every sample position lies inside the frame at the maximum radius, at several angles, including corners.
    func testEverySamplePositionIsInsideTheFrame() {
        let w = 30, h = 20
        for angle in [0.0, 45, 90, 135, 170] {
            let b: DirectionalBlur.Block = DirectionalBlur(isEnabled: true, radius: 0.02, angleDegrees: angle).block(width: w, height: h)
            for (x, y) in [(0, 0), (29, 19), (0, 19), (15, 10), (29, 0)] {
                for i in 0..<16 {
                    let p: SIMD2<Float> = DirectionalBlur.samplePosition(x: x, y: y, tap: i, width: w, height: h, block: b)
                    XCTAssertTrue(p.x >= 0 && p.x <= Float(w - 1) && p.y >= 0 && p.y <= Float(h - 1), "\(angle)° (\(x), \(y)) tap \(i)")
                }
            }
        }
    }

    func testReferenceSpreadsALineHorizontallyAndKeepsItsEnergy() {
        let w = 300, tall = 300   // 0.02 × 300 = a 6-px radius
        let wide = DirectionalBlur(isEnabled: true, radius: 0.02)
        var big = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 1), count: w * tall)
        for y in 100...104 { big[y * w + 30] = SIMD4<Float>(1, 1, 1, 1) }
        let out: [SIMD4<Float>] = wide.reference(big, width: w, height: tall)
        for y in [0, 99, 105, 299] {
            for x in 0..<w { XCTAssertEqual(out[y * w + x], big[y * w + x], "row \(y) unchanged") }
        }
        for y in 100...104 {
            let row: Float = (0..<w).reduce(Float(0)) { (s: Float, x: Int) -> Float in s + out[y * w + x].x }
            XCTAssertEqual(row, 1, accuracy: 0.01, "row \(y) keeps its energy")
            XCTAssertGreaterThan(out[y * w + 34].x, 0, "spread to the right")
            XCTAssertGreaterThan(out[y * w + 26].x, 0, "spread to the left")
            XCTAssertEqual(out[y * w + 37].x, 0, "nothing beyond the 6-px radius")
            XCTAssertEqual(out[y * w + 30].w, 1, "alpha stays")
        }
    }

    func testNonFiniteNeverSpreadsAndZeroIsIdentity() {
        let w = 100, h = 100
        var pixels = [SIMD4<Float>](repeating: SIMD4<Float>(0.25, 0.25, 0.25, 1), count: w * h)
        pixels[50 * w + 50] = SIMD4<Float>(.nan, 0, .infinity, 1)
        let out: [SIMD4<Float>] = maximum.reference(pixels, width: w, height: h)
        XCTAssertTrue(out[50 * w + 50].x.isNaN, "a non-finite own pixel passes through")
        for x in [48, 49, 51, 52] {
            let v: SIMD4<Float> = out[50 * w + x]
            XCTAssertTrue(v.x.isFinite && v.z.isFinite, "pixel \(x) stays finite")
            XCTAssertEqual(v.x, 0.25, accuracy: 1e-6, "the remaining weights are renormalised")
        }
        XCTAssertEqual(DirectionalBlur(isEnabled: true, radius: 0).reference(pixels, width: w, height: h).count, pixels.count)
        let zero: [SIMD4<Float>] = DirectionalBlur(isEnabled: true, radius: 0).reference(pixels, width: w, height: h)
        XCTAssertTrue(zero[50 * w + 50].x.isNaN)
        XCTAssertEqual(zero[0], pixels[0])
    }
}
