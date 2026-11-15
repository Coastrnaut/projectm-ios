// FX-016-T03: the lens distortion model and CPU reference (FX-016-R2 to R6, R12, S2, S3), no GPU (runs on Linux). The
// roadmap acceptance "zero distortion is identity; corners remain safely sampled": at strength 0 every pixel centre maps
// to itself and the reference returns the input bit for bit; at strength ±1, zoom on and off, over every pixel of frames
// at 1:1, 16:9, 9:16, 1:64, 64:1, 2 × 2 and 2 × 4096 (corners included) every inside sample lies in 0…W × 0…H, every tap
// in 0…W − 1 × 0…H − 1, only barrel with zoom off leaves the picture, and every value is finite; the radial mapping is
// strictly increasing at every strength step.
import Compositor
import XCTest

final class LensDistortionModelTests: XCTestCase {
    private static let lensSizes: [(Int, Int)] = [(64, 64), (160, 90), (90, 160), (4, 256), (256, 4), (2, 2), (2, 4096), (4096, 2)]

    func testLensDistortionClampsAndActivity() {
        XCTAssertEqual(LensDistortion.off.isEnabled, false)
        XCTAssertEqual(LensDistortion.clampStrength(.nan), 0.3)
        XCTAssertEqual(LensDistortion.clampStrength(5), 1)
        XCTAssertEqual(LensDistortion.clampStrength(-.infinity), -1)
        XCTAssertEqual(LensDistortion(isEnabled: true, strength: 7).clamped.strength, 1)
        XCTAssertEqual(LensDistortion(isEnabled: true, strength: -1).coefficient, -0.3, accuracy: 1e-7)
        XCTAssertEqual(LensDistortion(isEnabled: false, strength: 1).coefficient, 0, "off has no coefficient")
        XCTAssertTrue(LensDistortion(isEnabled: true, strength: 0.5).isActive(width: 2, height: 2))
        XCTAssertFalse(LensDistortion(isEnabled: true, strength: 0).isActive(width: 64, height: 64), "zero strength: no pass")
        XCTAssertFalse(LensDistortion(isEnabled: true, strength: 1).isActive(width: 1, height: 64), "under 2 pixels")
        XCTAssertFalse(LensDistortion(isEnabled: false, strength: 1).isActive(width: 64, height: 64))
        let b = LensDistortion(isEnabled: true, strength: 1, zoomToFill: true).block(width: 30, height: 40)
        XCTAssertEqual(b.centre, SIMD2<Float>(15, 20))
        XCTAssertEqual(b.inverseRadiusSquared, 4 / 2500)
        XCTAssertEqual(b.inverseZoom, 1 / Float(1.3), accuracy: 1e-7)
        XCTAssertEqual(LensDistortion(isEnabled: true, strength: -1, zoomToFill: true).block(width: 30, height: 40).inverseZoom, 1,
                       "zoom never changes a pincushion warp")
        XCTAssertEqual(MemoryLayout<LensDistortion.Block>.stride, 32)
    }

    func testLensDistortionZeroStrengthIsTheIdentity() {
        for (w, h) in [(37, 29), (2, 2), (3, 1000), (1000, 3)] {
            for zoom in [true, false] {
                let b = LensDistortion(isEnabled: true, strength: 0, zoomToFill: zoom).block(width: w, height: h)
                XCTAssertEqual(b.coefficient, 0)
                XCTAssertEqual(b.inverseZoom, 1)
                for y in 0..<h {
                    for x in 0..<w {
                        let (s, inside) = LensDistortion.sample(x: x, y: y, block: b)
                        XCTAssertTrue(inside)
                        if s != SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5) { XCTFail("(\(x), \(y)) in \(w) × \(h) moved to \(s)"); return }
                    }
                }
            }
        }
        let w = 23, h = 17
        let pixels: [SIMD4<Float>] = (0..<(w * h)).map { (i: Int) -> SIMD4<Float> in
            SIMD4<Float>(Float(i % 7) / 7, -0.0, Float(i) * 1e-3, 1)
        }
        let b = LensDistortion(isEnabled: true, strength: 0).block(width: w, height: h)
        let out = LensDistortion.referenceAlways(pixels, width: w, height: h, block: b)
        XCTAssertEqual(out.map { $0.y.bitPattern }, pixels.map { $0.y.bitPattern }, "even −0 is kept: the exact read")
        XCTAssertEqual(out, pixels)
        XCTAssertEqual(LensDistortion(isEnabled: true, strength: 0).reference(pixels, width: w, height: h), pixels)
    }

    func testLensDistortionCornersAreSafelySampledAtTheExtremes() {
        for (w, h) in Self.lensSizes {
            for strength in [1.0, -1.0, 0.37, -0.63] {
                for zoom in [true, false] {
                    let b = LensDistortion(isEnabled: true, strength: strength, zoomToFill: zoom).block(width: w, height: h)
                    var outside = 0
                    for y in 0..<h {
                        for x in 0..<w {
                            let (s, inside) = LensDistortion.sample(x: x, y: y, block: b)
                            guard s.x.isFinite && s.y.isFinite else { XCTFail("non-finite sample (\(x), \(y)) \(w) × \(h)"); return }
                            guard inside else { outside += 1; continue }
                            guard s.x >= 0, s.x <= Float(w), s.y >= 0, s.y <= Float(h) else { XCTFail("inside out of range"); return }
                            let t = LensDistortion.taps(s, width: w, height: h)
                            let tapsInRange: Bool = (0..<w).contains(t.x0) && (0..<w).contains(t.x1) && (0..<h).contains(t.y0)
                                && (0..<h).contains(t.y1) && (0...1).contains(t.fx) && (0...1).contains(t.fy)
                            if !tapsInRange { XCTFail("taps \(t) out of range at (\(x), \(y)) in \(w) × \(h)"); return }
                        }
                    }
                    if strength > 0 && !zoom {
                        let corner = LensDistortion.sample(x: 0, y: 0, block: b)
                        if w >= 4 && h >= 4 { XCTAssertFalse(corner.inside, "barrel without zoom leaves the picture at the corner") }
                    } else {
                        XCTAssertEqual(outside, 0, "strength \(strength), zoom \(zoom), \(w) × \(h): every sample inside")
                    }
                }
            }
        }
    }

    func testLensDistortionReferenceOutputIsFiniteAndTheMiddleIsKept() {
        let w = 33, h = 21
        let pixels: [SIMD4<Float>] = (0..<(w * h)).map { (i: Int) -> SIMD4<Float> in
            SIMD4<Float>(i % 2 == 0 ? 65_504 : 0, Float(i % 11) / 11, 0.25, 1)
        }
        for strength in [1.0, -1.0] {
            for zoom in [true, false] {
                let v = LensDistortion(isEnabled: true, strength: strength, zoomToFill: zoom)
                let out = v.reference(pixels, width: w, height: h)
                XCTAssertTrue(out.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite })
                XCTAssertTrue(out.allSatisfy { $0.x <= 65_504 * (1 + 1e-6) && $0.x >= -1e-3 }, "a weighted average never leaves the input's range")
                XCTAssertEqual(out[(h / 2) * w + w / 2], pixels[(h / 2) * w + w / 2], "the middle pixel is unchanged")
                if strength > 0 && !zoom { XCTAssertEqual(out[0], SIMD4<Float>(0, 0, 0, 0), "outside: transparent black") }
            }
        }
    }

    func testLensDistortionRadialMappingIsStrictlyIncreasing() {
        for step in -100...100 where step != 0 {
            for zoom in [true, false] {
                let b = LensDistortion(isEnabled: true, strength: Double(step) / 100, zoomToFill: zoom).block(width: 160, height: 90)
                var previous: Float = -1
                for i in 0...1000 {
                    let g: Float = LensDistortion.radialMap(Float(i) / 1000, block: b)
                    if !(g > previous) { XCTFail("strength \(step)%: not increasing at r = \(Float(i) / 1000)"); return }
                    previous = g
                }
                if zoom || step < 0 { XCTAssertLessThanOrEqual(previous, 1.000001, "strength \(step)%: the corner stays inside") }
            }
        }
    }
}
