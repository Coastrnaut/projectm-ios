// FX-015-T03: the vignette's value, falloff weight and CPU reference (FX-015-R2 to R5, R12; research FX-015-D2 to D5).
// Plain Swift, no GPU: runs on Linux too.
import Compositor
import XCTest

final class VignetteModelTests: XCTestCase {
    private static func vignetteRandom(_ count: Int, seed: UInt64) -> [SIMD4<Float>] {
        var state: UInt64 = seed
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float((state >> 40) % 1024) / 1024
        }
        return (0..<count).map { (_: Int) -> SIMD4<Float> in
            let a: Float = 0.25 + next() * 0.75
            return SIMD4<Float>(next() * a, next() * a, next() * a, a)
        }
    }

    func testVignetteClampsAndDefaults() {
        XCTAssertEqual(Vignette.off, Vignette(isEnabled: false, intensity: 0.5, softness: 0.5, centerX: 0.5, centerY: 0.5))
        XCTAssertEqual(Vignette.clampIntensity(.nan), 0.5)
        XCTAssertEqual(Vignette.clampIntensity(-1), 0)
        XCTAssertEqual(Vignette.clampIntensity(.infinity), 1)
        XCTAssertEqual(Vignette.clampSoftness(0), 0.1)
        XCTAssertEqual(Vignette.clampSoftness(2), 0.9)
        XCTAssertEqual(Vignette.clampSoftness(.nan), 0.5)
        XCTAssertEqual(Vignette.clampCenter(-.infinity), 0)
        XCTAssertEqual(Vignette.clampCenter(.nan), 0.5)
        XCTAssertEqual(Vignette(isEnabled: true, intensity: 3, softness: -1, centerX: 9, centerY: -9).clamped,
                       Vignette(isEnabled: true, intensity: 1, softness: 0.1, centerX: 1, centerY: 0))
    }

    func testVignetteActiveOnlyWhenOnWithIntensityAndTwoPixels() {
        XCTAssertFalse(Vignette.off.isActive(width: 100, height: 100))
        XCTAssertFalse(Vignette(isEnabled: true, intensity: 0).isActive(width: 100, height: 100), "zero intensity is the frame")
        XCTAssertFalse(Vignette(isEnabled: true).isActive(width: 1, height: 100))
        XCTAssertTrue(Vignette(isEnabled: true, intensity: 0.01).isActive(width: 2, height: 2))
    }

    /// The roadmap acceptance on the reference: zero intensity changes nothing, centre and corners included.
    func testVignetteZeroIntensityIsExactIdentityAtCentreAndCorners() {
        let w = 33, h = 21
        let pixels: [SIMD4<Float>] = Self.vignetteRandom(w * h, seed: 3)
        for softness in [0.1, 0.5, 0.9] {
            for centre in [0.0, 0.5, 1.0] {
                let v = Vignette(isEnabled: true, intensity: 0, softness: softness, centerX: centre, centerY: 1 - centre)
                XCTAssertEqual(v.reference(pixels, width: w, height: h), pixels)
                let b: Vignette.Block = Vignette(isEnabled: true, intensity: 0, softness: softness, centerX: centre).block(width: w, height: h)
                for (x, y) in [(16, 10), (0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
                    XCTAssertEqual(Vignette.factor(x: x, y: y, block: b), 1, "(\(x), \(y)) factor is exactly 1")
                }
            }
        }
    }

    func testVignetteCentreIsExactAtAnyIntensityAndCornersDarken() {
        let w = 40, h = 30
        for intensity in [0.3, 1.0] {
            for softness in [0.1, 0.5, 0.9] {
                let b = Vignette(isEnabled: true, intensity: intensity, softness: softness).block(width: w, height: h)
                for (x, y) in [(19, 14), (20, 15), (19, 15), (20, 14)] {
                    XCTAssertEqual(Vignette.factor(x: x, y: y, block: b), 1, "middle pixel (\(x), \(y)) unchanged")
                }
                XCTAssertLessThan(Vignette.factor(x: 0, y: 0, block: b), 1, "a corner darkens")
                XCTAssertGreaterThanOrEqual(Vignette.factor(x: 0, y: 0, block: b), Float(1 - intensity) - 1e-6)
            }
        }
    }

    func testVignetteFalloffIsMonotonicAlongRaysToEveryCorner() {
        let w = 64, h = 48
        let b = Vignette(isEnabled: true, intensity: 0.8, softness: 0.6).block(width: w, height: h)
        for corner in [SIMD2(0, 0), SIMD2(w - 1, 0), SIMD2(0, h - 1), SIMD2(w - 1, h - 1)] {
            var previous: Float = 1
            for k in 0...32 {
                let x: Int = 32 + (corner.x - 32) * k / 32
                let y: Int = 24 + (corner.y - 24) * k / 32
                let f: Float = Vignette.factor(x: x, y: y, block: b)
                XCTAssertLessThanOrEqual(f, previous, "corner \(corner), step \(k)")
                previous = f
            }
            XCTAssertLessThan(previous, 0.35, "corner \(corner) is close to 1 − intensity")
        }
    }

    func testVignetteCentreControlMovesTheClearCore() {
        let w = 80, h = 40
        let b = Vignette(isEnabled: true, intensity: 1, softness: 0.9, centerX: 0.25, centerY: 0.5).block(width: w, height: h)
        var sum = SIMD2<Float>(0, 0)
        var count: Float = 0
        for y in 0..<h {
            for x in 0..<w where Vignette.factor(x: x, y: y, block: b) == 1 {
                sum += SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                count += 1
            }
        }
        XCTAssertGreaterThan(count, 0)
        let centroid: SIMD2<Float> = sum / count
        XCTAssertEqual(centroid.x, 20, accuracy: 1, "the clear core is centred at a quarter of the width")
        XCTAssertEqual(centroid.y, 20, accuracy: 1)
        XCTAssertEqual(Vignette.factor(x: 20, y: 20, block: b), 1, "the pixel nearest the new centre is unchanged")
        XCTAssertGreaterThan(Vignette.factor(x: 0, y: 20, block: b), Vignette.factor(x: w - 1, y: 20, block: b),
                             "the left edge is brighter than the right edge")
    }

    func testVignetteOutputsAreFiniteAndNeverBrighter() {
        let w = 17, h = 13
        var pixels: [SIMD4<Float>] = Self.vignetteRandom(w * h, seed: 9)
        pixels[0] = SIMD4<Float>(60_000, 1_000, 0, 1)   // HDR near the half-float limit
        pixels[w * h - 1] = SIMD4<Float>(0, 0, 0, 0)
        let v = Vignette(isEnabled: true, intensity: 1, softness: 0.1, centerX: 0, centerY: 1)
        let out: [SIMD4<Float>] = v.reference(pixels, width: w, height: h)
        for (o, i) in zip(out, pixels) {
            for c in 0..<4 { XCTAssertTrue(o[c].isFinite) }
            for c in 0..<3 { XCTAssertLessThanOrEqual(o[c], i[c]); XCTAssertGreaterThanOrEqual(o[c], 0) }
            XCTAssertEqual(o.w, i.w, "alpha kept")
        }
    }
}
