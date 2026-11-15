// PreviewPixelMappingTests.swift — UIX-012-T03: the tap → output pixel transform (contract C1) and one-pixel
// colour reads (contract C2). Plain Swift: runs on Linux.
import FrameCapture
import XCTest

final class PreviewPixelMappingTests: XCTestCase {
    private func px(_ x: Int, _ y: Int) -> PreviewPixel { PreviewPixel(x: x, y: y) }

    /// An iPhone at Retina scale 3: 393 × 852 points, a 1179 × 2556 picture stretched over the view.
    func testStretchAtRetinaScale3() {
        let m = PreviewPixelMapping(viewWidth: 393, viewHeight: 852, pictureWidth: 1179, pictureHeight: 2556)
        XCTAssertEqual(m.pixel(atX: 0, y: 0), px(0, 0))
        XCTAssertEqual(m.pixel(atX: 100.5, y: 200.2), px(301, 600))
        XCTAssertEqual(m.pixel(atX: 100 + 1.0 / 3, y: 0), px(301, 0), "a pixel boundary picks the pixel it starts")
        XCTAssertEqual(m.pixel(atX: 393, y: 852), px(1178, 2555), "the far edge clamps to the last pixel")
        XCTAssertNil(m.pixel(atX: -0.1, y: 10))
        XCTAssertNil(m.pixel(atX: 10, y: 852.1))
        XCTAssertNil(m.pixel(atX: .nan, y: 10))
    }

    /// Fit: a 2:1 picture in a 100 × 100 view is letterboxed (rect y 25…75); bar taps are rejected.
    func testFitLetterboxRejectsBarTaps() {
        let m = PreviewPixelMapping(viewWidth: 100, viewHeight: 100, fit: .fit, pictureWidth: 200, pictureHeight: 100)
        XCTAssertNil(m.pixel(atX: 50, y: 10), "top bar")
        XCTAssertNil(m.pixel(atX: 50, y: 80), "bottom bar")
        XCTAssertEqual(m.pixel(atX: 50, y: 50), px(100, 50))
        XCTAssertEqual(m.pixel(atX: 0, y: 25), px(0, 0))
        XCTAssertEqual(m.pixel(atX: 99.9, y: 74.9), px(199, 99))
        // Pillarbox: a 1:2 picture in a wide view.
        let p = PreviewPixelMapping(viewWidth: 200, viewHeight: 100, fit: .fit, pictureWidth: 50, pictureHeight: 100)
        XCTAssertNil(p.pixel(atX: 50, y: 50))
        XCTAssertEqual(p.pixel(atX: 100, y: 50), px(25, 50))
    }

    /// Fill: a 2:1 picture in a 100 × 100 view is cropped at the sides (rect x −50…150); every tap maps inside.
    func testFillCropsAndEveryTapMaps() {
        let m = PreviewPixelMapping(viewWidth: 100, viewHeight: 100, fit: .fill, pictureWidth: 200, pictureHeight: 100)
        XCTAssertEqual(m.pixel(atX: 0, y: 0), px(50, 0))
        XCTAssertEqual(m.pixel(atX: 50, y: 50), px(100, 50))
        XCTAssertEqual(m.pixel(atX: 100, y: 100), px(150, 99))
    }

    /// UIX-007: the visual drawn at half size at (40, 30): window (40 + x/2, 30 + y/2) is view (x, y).
    func testSplitScaledPreview() {
        let m = PreviewPixelMapping(viewWidth: 400, viewHeight: 300, splitScale: 0.5, splitOriginX: 40, splitOriginY: 30,
                                    pictureWidth: 800, pictureHeight: 600)
        XCTAssertEqual(m.pixel(atX: 40, y: 30), px(0, 0))
        XCTAssertEqual(m.pixel(atX: 140, y: 105), px(400, 300))
        XCTAssertEqual(m.pixel(atX: 240, y: 180), px(799, 599))
        XCTAssertNil(m.pixel(atX: 30, y: 100), "left of the scaled output")
        XCTAssertNil(m.pixel(atX: 250, y: 100), "right of the scaled output (the editor side)")
    }

    /// OUT-004: 100 × 100 pixels that are twice as wide as tall are a 2:1 picture; in a 2:1 view it fits exactly,
    /// in a square view it letterboxes like a 2:1 picture.
    func testNonSquarePixelAspect() {
        let exact = PreviewPixelMapping(viewWidth: 200, viewHeight: 100, fit: .fit, pictureWidth: 100, pictureHeight: 100,
                                        pixelAspect: 2)
        XCTAssertEqual(exact.pixel(atX: 0, y: 0), px(0, 0))
        XCTAssertEqual(exact.pixel(atX: 150, y: 50), px(75, 50))
        let square = PreviewPixelMapping(viewWidth: 100, viewHeight: 100, fit: .fit, pictureWidth: 100, pictureHeight: 100,
                                         pixelAspect: 2)
        XCTAssertNil(square.pixel(atX: 50, y: 20))
        XCTAssertEqual(square.pixel(atX: 50, y: 50), px(50, 50))
        XCTAssertEqual(square.pixel(atX: 50, y: 30), px(50, 10))
    }

    // MARK: - One pixel (contract C2)

    func testHalfPixelIsUnpremultipliedAndClamped() {
        // (0.25, 0, 0.5, 0.5) premultiplied → straight (0.5, 0, 1, 0.5); then HDR 2.0 clamps; then no coverage.
        let halves: [UInt16] = [0x3400, 0x0000, 0x3800, 0x3800,   0x4000, 0x3C00, 0xBC00, 0x3C00,   0x3C00, 0x3C00, 0x3C00, 0x0000]
        let pixels = CapturedPixels(width: 3, height: 1, layout: .linearPremultipliedHalfRGBA(halves))!
        XCTAssertEqual(pixels.sampledColor(x: 0, y: 0), SampledColor(red: 0.5, green: 0, blue: 1, alpha: 0.5))
        XCTAssertEqual(pixels.sampledColor(x: 1, y: 0), SampledColor(red: 1, green: 1, blue: 0, alpha: 1))
        XCTAssertEqual(pixels.sampledColor(x: 2, y: 0), SampledColor(red: 0, green: 0, blue: 0, alpha: 0))
        XCTAssertNil(pixels.sampledColor(x: 3, y: 0))
    }

    func testEightBitLayoutsDecodeSRGBAndFlipBottomUpRows() {
        // Two rows: top (255, 0, 0), bottom (0, 0, 188).
        let bgra: [UInt8] = [0, 0, 255, 255,   188, 0, 0, 255]
        let top = CapturedPixels(width: 1, height: 2, layout: .sRGBBGRA8TopDown(bgra))!
        XCTAssertEqual(top.sampledColor(x: 0, y: 0), SampledColor(red: 1, green: 0, blue: 0))
        let bottomUp: [UInt8] = [0, 0, 188, 255,   255, 0, 0, 255]   // rows bottom first
        let flipped = CapturedPixels(width: 1, height: 2, layout: .sRGBRGBA8BottomUp(bottomUp))!
        XCTAssertEqual(flipped.sampledColor(x: 0, y: 0), SampledColor(red: 1, green: 0, blue: 0))
        let blue = try! XCTUnwrap(flipped.sampledColor(x: 0, y: 1))
        XCTAssertEqual(blue.blue, 0.5, accuracy: 0.003, "sRGB 188 is linear 0.5")
        XCTAssertEqual(blue.sRGB.blue * 255, 188, accuracy: 0.01)
    }

    func testSpokenTextUsesWholeSRGBPercents() {
        XCTAssertEqual(SampledColor(red: 1, green: 0, blue: 0.5).spoken, "red 100%, green 0%, blue 74%")
        XCTAssertEqual(SampledColor.spoken(sRGBRed: 0.2, green: 0.4, blue: 0.6), "red 20%, green 40%, blue 60%")
    }
}
