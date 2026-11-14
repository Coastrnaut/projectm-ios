// MED-010-T06: logo placement maths and premultiplication (MED-010-R4, R6, R13, S4). Plain Swift: runs in
// the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) too.
import Compositor
import Foundation
import ImageLayer
import XCTest

final class LogoPlacementTests: XCTestCase {
    private func assertRect(_ r: LogoRect, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let actual: [Double] = [r.x, r.y, r.width, r.height]
        let expected: [Double] = [x, y, w, h]
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 1.0, "\(message): \(r)", file: file, line: line)
        }
    }

    /// S4: every corner at 390 × 844 and 844 × 390 (shorter side 390): size 0.15 → 58.5 px, margin 0.04 → 15.6 px.
    func testEveryCornerInPortraitAndLandscape() {
        let side: Double = 0.15 * 390
        let pad: Double = 0.04 * 390
        for (w, h) in [(390, 844), (844, 390)] {
            let W: Double = Double(w)
            let H: Double = Double(h)
            let right: Double = W - pad - side
            let bottom: Double = H - pad - side
            let cases: [(LogoCorner, Double, Double)] = [
                (.topLeft, pad, pad), (.topRight, right, pad), (.bottomLeft, pad, bottom), (.bottomRight, right, bottom),
                (.center, (W - side) / 2, (H - side) / 2),
            ]
            for (corner, x, y) in cases {
                let rect = LogoPlacement(corner: corner).rect(logoWidth: 200, logoHeight: 200, outputWidth: w, outputHeight: h)
                assertRect(rect, x, y, side, side, "\(corner) at \(w)×\(h)")
            }
        }
    }

    func testTheSizeAppliesToTheLongerSideOfWideAndTallLogos() {
        let p = LogoPlacement(corner: .topLeft, size: 0.2, margin: 0)
        assertRect(p.rect(logoWidth: 400, logoHeight: 100, outputWidth: 1000, outputHeight: 500), 0, 0, 100, 25, "wide")
        assertRect(p.rect(logoWidth: 100, logoHeight: 400, outputWidth: 1000, outputHeight: 500), 0, 0, 25, 100, "tall")
    }

    func testCustomAnchorAndClamping() {
        let p = LogoPlacement(corner: .custom, anchorX: 0.25, anchorY: 2, size: 9, margin: -1, opacity: 3)
        XCTAssertEqual(p.size, 0.5)
        XCTAssertEqual(p.margin, 0)
        XCTAssertEqual(p.opacity, 1)
        XCTAssertEqual(p.anchor, LayerPoint(x: 0.25, y: 1))
        assertRect(p.rect(logoWidth: 10, logoHeight: 10, outputWidth: 200, outputHeight: 100), 37.5, 50, 50, 50, "custom")
        let nan = LogoPlacement(corner: .custom, anchorX: .nan, anchorY: .infinity, size: .nan, margin: .nan, opacity: .nan)
        XCTAssertEqual(nan.anchor, LayerPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(nan.size, LogoPlacement.defaultSize)
        XCTAssertEqual(nan.opacity, 1)
        XCTAssertEqual(LogoPlacement().rect(logoWidth: 0, logoHeight: 10, outputWidth: 10, outputHeight: 10), .empty)
        XCTAssertEqual(LogoPlacement(corner: .topLeft).with(corner: .custom).anchor, LayerPoint(x: 1, y: 1), "the custom anchor is kept")
    }

    func testJSONRoundTripAndLenientReading() {
        let p = LogoPlacement(corner: .custom, anchorX: 0, anchorY: 0.3, size: 0.1, margin: 0.02, opacity: 0.6)
        XCTAssertEqual(LogoPlacement(jsonData: p.jsonData), p)
        XCTAssertEqual(LogoPlacement(jsonData: nil), .default)
        XCTAssertEqual(LogoPlacement(jsonData: Data("garbage".utf8)), .default)
        let partial = LogoPlacement(jsonData: Data(#"{"corner":"topLeft","size":"big","opacity":0.5}"#.utf8))
        XCTAssertEqual(partial, LogoPlacement(corner: .topLeft, opacity: 0.5))
        XCTAssertEqual(LogoPlacement(jsonData: Data(#"{"corner":"diagonal"}"#.utf8)).corner, .bottomRight)
    }

    func testLogoLimitsAndMessages() {
        XCTAssertEqual(LogoImport.limits.maxFileBytes, 10_485_760)
        XCTAssertEqual(LogoImport.limits.maxPixelCount, 4096 * 4096)
        XCTAssertEqual(LogoImport.limits.maxStoredLongestSide, 1024)
        XCTAssertTrue(LogoImport.message(for: .tooLarge).contains("10 MB"))
        XCTAssertEqual(LayerKind.logo.identifier, "logo")
    }
}

final class PremultipliedLinearTests: XCTestCase {
    func testHalfConversionOfRepresentativeValues() {
        let cases: [(Float, UInt16)] = [(0, 0x0000), (1, 0x3C00), (0.5, 0x3800), (-2, 0xC000), (65504, 0x7BFF),
                                        (1e6, 0x7C00), (0x1p-24, 0x0001), (0x1p-14, 0x0400)]
        for (value, bits) in cases {
            XCTAssertEqual(PremultipliedLinear.halfBits(value), bits, "\(value)")
            if value < 1e5 { XCTAssertEqual(PremultipliedLinear.float(halfBits: bits), value, "\(bits)") }
        }
        // Round trip of every byte's linear value within half precision (relative 2^-11).
        for code in 0..<256 {
            let v: Float = PremultipliedLinear.linear(UInt8(code))
            let back: Float = PremultipliedLinear.float(halfBits: PremultipliedLinear.halfBits(v))
            XCTAssertEqual(back, v, accuracy: max(v * 0x1p-11, 0x1p-24), "code \(code)")
        }
        XCTAssertEqual(PremultipliedLinear.linear(255), 1)
        XCTAssertEqual(PremultipliedLinear.linear(188), 0.5029, accuracy: 0.0005)
    }

    func testTexelsArePremultipliedLinearAndTransparentIsZero() {
        // Three pixels: opaque grey 188, half-transparent white, fully transparent "red" (colour must not leak).
        let image = DecodedImage(width: 3, height: 1, pixels: [188, 188, 188, 255, 255, 255, 255, 128, 255, 0, 0, 0])
        let t: [Float] = PremultipliedLinear.texels(image).map { (h: UInt16) -> Float in PremultipliedLinear.float(halfBits: h) }
        let grey: Float = PremultipliedLinear.linear(188)
        let half: Float = 128.0 / 255
        let expected: [Float] = [grey, grey, grey, 1, half, half, half, half, 0, 0, 0, 0]
        for (a, e) in zip(t, expected) { XCTAssertEqual(a, e, accuracy: 0.001) }
        XCTAssertEqual(PremultipliedLinear.texels(DecodedImage(width: 2, height: 1, pixels: [1, 2, 3])), [], "size mismatch")
    }
}
