// FX-014-T03: the edge outline's value, colour, Sobel strength, mask and CPU reference (FX-014-R2 to R6, R13, R15;
// research FX-014-D2 to D6). Plain Swift, no GPU: runs on Linux too.
import Compositor
import FlashSafety
import XCTest

final class EdgeOutlineModelTests: XCTestCase {
    func testEdgeOutlineClampsDefaultsAndHex() {
        XCTAssertEqual(EdgeOutline.off, EdgeOutline(isEnabled: false, threshold: 0.2, width: 1, color: .white, mode: .overlay))
        XCTAssertEqual(EdgeOutline.clampThreshold(.nan), 0.2)
        XCTAssertEqual(EdgeOutline.clampThreshold(0), 0.02)
        XCTAssertEqual(EdgeOutline.clampThreshold(7), 1)
        XCTAssertEqual(EdgeOutline.clampWidth(2.6), 3, "rounded")
        XCTAssertEqual(EdgeOutline.clampWidth(Double.nan), 1)
        XCTAssertEqual(EdgeOutline.clampWidth(-Double.infinity), 1)
        XCTAssertEqual(EdgeOutline.clampWidth(9), 3)
        XCTAssertEqual(EdgeOutlineColor(hex: "#FF8000"), EdgeOutlineColor(red: 1, green: 128.0 / 255, blue: 0))
        XCTAssertEqual(EdgeOutlineColor(hex: "ff8000")?.hex, "FF8000")
        XCTAssertNil(EdgeOutlineColor(hex: "red"))
        XCTAssertNil(EdgeOutlineColor(hex: "12345"))
        XCTAssertEqual(EdgeOutlineColor(red: 2, green: -1, blue: .nan), EdgeOutlineColor(red: 1, green: 0, blue: 1))
        XCTAssertEqual(EdgeOutlineColor.white.hex, "FFFFFF")
        XCTAssertEqual(EdgeOutlineColor.linear(1), 1, accuracy: 1e-12)
        XCTAssertEqual(EdgeOutlineColor.linear(0.5), 0.21404, accuracy: 1e-4)
        XCTAssertFalse(EdgeOutline.off.isActive(width: 64, height: 64))
        XCTAssertFalse(EdgeOutline(isEnabled: true).isActive(width: 1, height: 64))
        XCTAssertTrue(EdgeOutline(isEnabled: true).isActive(width: 2, height: 2))
        XCTAssertEqual(MemoryLayout<EdgeOutline.Block>.stride, 48, "the shader's CMPEdgeOutline")
    }

    /// Flat pictures: strength 0 at every pixel (the border included) and the reference is the input.
    func testEdgeOutlineFlatPictureHasNoEdgesAnywhere() {
        let w = 9, h = 7
        for value in [SIMD4<Float>(0, 0, 0, 1), SIMD4<Float>(0.3, 0.7, 0.1, 1), SIMD4<Float>(1, 1, 1, 1), SIMD4<Float>(0.2, 0.1, 0.4, 0.5)] {
            let pixels = [SIMD4<Float>](repeating: value, count: w * h)
            for width in 1...3 {
                let outline = EdgeOutline(isEnabled: true, threshold: 0.02, width: width)
                XCTAssertEqual(outline.referenceMask(pixels, width: w, height: h), [Float](repeating: 0, count: w * h))
                XCTAssertEqual(outline.reference(pixels, width: w, height: h), pixels, "overlay: the input")
                var only = outline
                only.mode = .outlineOnly
                XCTAssertEqual(only.reference(pixels, width: w, height: h),
                               [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 1), count: w * h), "outline only: black")
            }
        }
    }

    /// A vertical black/white step between x = 4 and 5: outlined on 2 × width columns, strength 1 at the step.
    func testEdgeOutlineStepIsOutlinedOnTwiceTheWidth() {
        let w = 10, h = 4
        let pixels: [SIMD4<Float>] = (0..<(w * h)).map { (i: Int) -> SIMD4<Float> in
            i % w < 5 ? SIMD4<Float>(0, 0, 0, 1) : SIMD4<Float>(1, 1, 1, 1)
        }
        let lum: [Float] = pixels.map(EdgeOutline.luminance)
        XCTAssertEqual(EdgeOutline.strength(lum, width: w, height: h, x: 4, y: 1, tap: 1), 1, accuracy: 1e-5)
        for width in 1...3 {
            let mask = EdgeOutline(isEnabled: true, width: width).referenceMask(pixels, width: w, height: h)
            let columns: [Int] = (0..<w).filter { (x: Int) -> Bool in mask[x] > 0 }
            XCTAssertEqual(columns, Array((5 - width)...(4 + width)), "width \(width)")
            for y in 0..<h { for x in 0..<w { XCTAssertEqual(mask[y * w + x] > 0, columns.contains(x)) } }
        }
        let faint: [SIMD4<Float>] = pixels.map { (p: SIMD4<Float>) -> SIMD4<Float> in p.x > 0 ? SIMD4<Float>(0.3, 0.3, 0.3, 1) : p }
        let maxStrength: Float = 0.3
        XCTAssertEqual(EdgeOutline(isEnabled: true, threshold: 0.31).referenceMask(faint, width: w, height: h).max(), 0,
                       "threshold above the contrast (\(maxStrength)): no outline")
        XCTAssertGreaterThan(EdgeOutline(isEnabled: true, threshold: 0.2).referenceMask(faint, width: w, height: h).max() ?? 0, 0)
        XCTAssertEqual(EdgeOutline.mask(strength: .nan, threshold: 0.2), 0)
        XCTAssertEqual(EdgeOutline.mask(strength: .infinity, threshold: 0.2), 0)
        XCTAssertEqual(EdgeOutline.mask(strength: 0.2, threshold: 0.2), 0, "at the threshold: none")
        XCTAssertEqual(EdgeOutline.mask(strength: 0.3, threshold: 0.2), 1, accuracy: 1e-6)
    }

    func testEdgeOutlineSafetyLimitScalesTheColour() {
        let outline = EdgeOutline(isEnabled: true, color: EdgeOutlineColor(red: 1, green: 0.5, blue: 0))
        let standard = outline.limited(by: .standard)
        XCTAssertEqual(standard, outline, "Standard: unchanged")
        let strict = outline.limited(by: SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false))
        XCTAssertEqual(strict.colorScale, 0.25)
        let block = strict.block(width: 8, height: 8)
        XCTAssertEqual(block.colour.x, 0.25, accuracy: 1e-6)
        XCTAssertEqual(block.colour.y, Float(EdgeOutlineColor.linear(0.5)) * 0.25, accuracy: 1e-6)
        XCTAssertEqual(block.colour.w, 1, "the outline stays opaque")
        XCTAssertEqual(block.last, SIMD2<UInt32>(7, 7))
    }
}
