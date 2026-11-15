// ColorSampleCompositorTests.swift — UIX-012-T04, the roadmap acceptance "Tapped pixel returns expected color after
// coordinate transform" (UIX-012-S1). A 4 × 3 grid of distinct premultiplied colours (some with coverage below 1)
// goes through the real Metal compositor at 64 × 48 and REC-001's capture; taps at chosen view points are mapped
// with `PreviewPixelMapping` for the device (stretch at scale 2), a UIX-007 split placement and a pillarboxed fit,
// and the sampled straight colour must equal the grid colour of the mapped cell within 1/255, linear and 8-bit
// sRGB. One frame per test. Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import FrameCapture
import Metal
import XCTest

private final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CapturedPixels?
    func set(_ v: CapturedPixels?) { lock.lock(); value = v; lock.unlock() }
    var pixels: CapturedPixels? { lock.lock(); defer { lock.unlock() }; return value }
}

final class ColorSampleCompositorTests: XCTestCase {
    private static let width = 64, height = 48, cell = 16

    /// Straight colours (k / 16, exact in halves) and coverages, one per 16 × 16 cell, row by row.
    private static let straight: [Pixel] = (0..<12).map { (i: Int) -> Pixel in
        let r: Float = Float(i % 4) / 4, g: Float = Float(i / 4) / 4, b: Float = Float((i * 5) % 16) / 16
        let a: Float = i % 3 == 0 ? 0.5 : 1
        return Pixel(r, g, b, a)
    }

    private static func cellIndex(x: Int, y: Int) -> Int { (y / cell) * 4 + x / cell }

    private static var pattern: [Pixel] {
        var pixels: [Pixel] = []
        for y in 0..<height {
            for x in 0..<width {
                let s: Pixel = straight[cellIndex(x: x, y: y)]
                pixels.append(Pixel(s.x * s.w, s.y * s.w, s.z * s.w, s.w))   // premultiplied
            }
        }
        return pixels
    }

    private func capture() throws -> CapturedPixels {
        let rig = try GPURig()
        let layer = PixelsLayer(width: Self.width, height: Self.height, pixels: Self.pattern)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output(.bgra8Unorm, width: Self.width, height: Self.height)
        let done = expectation(description: "capture")
        let box = SampleBox()
        compositor.requestFrameCapture { (pixels: CapturedPixels?) in
            box.set(pixels)
            done.fulfill()
        }
        try rig.frame(compositor, into: output, time: 1)
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(box.pixels)
    }

    /// Samples each tap and compares with the grid colour at the expected pixel.
    private func check(_ mapping: PreviewPixelMapping, taps: [(x: Double, y: Double, expected: PreviewPixel)],
                       pixels: CapturedPixels, _ label: String) throws {
        for tap in taps {
            let pixel = try XCTUnwrap(mapping.pixel(atX: tap.x, y: tap.y), "\(label): tap \(tap) maps")
            XCTAssertEqual(pixel, tap.expected, "\(label): tap (\(tap.x), \(tap.y))")
            let sampled = try XCTUnwrap(pixels.sampledColor(x: pixel.x, y: pixel.y))
            let want: Pixel = Self.straight[Self.cellIndex(x: pixel.x, y: pixel.y)]
            let tolerance: Double = 1.0 / 255
            XCTAssertEqual(sampled.red, Double(want.x), accuracy: tolerance, "\(label) red at \(pixel)")
            XCTAssertEqual(sampled.green, Double(want.y), accuracy: tolerance, "\(label) green at \(pixel)")
            XCTAssertEqual(sampled.blue, Double(want.z), accuracy: tolerance, "\(label) blue at \(pixel)")
            XCTAssertEqual(sampled.alpha, Double(want.w), accuracy: tolerance, "\(label) alpha at \(pixel)")
            let encoded = sampled.sRGB
            XCTAssertEqual(encoded.red, SampledColor.encode(Double(want.x)), accuracy: tolerance, "\(label) sRGB red")
            XCTAssertEqual(encoded.blue, SampledColor.encode(Double(want.z)), accuracy: tolerance, "\(label) sRGB blue")
        }
    }

    func testTappedPixelReturnsThePatternColourAfterEachTransform() throws {
        let pixels = try capture()
        XCTAssertEqual(pixels.width, Self.width)
        XCTAssertEqual(pixels.height, Self.height)
        // The device: a 32 × 24 point view at scale 2, the picture stretched over it.
        let device = PreviewPixelMapping(viewWidth: 32, viewHeight: 24, pictureWidth: 64, pictureHeight: 48)
        try check(device, taps: [(1, 1, PreviewPixel(x: 2, y: 2)), (12.25, 20, PreviewPixel(x: 24, y: 40)),
                                 (31.9, 9, PreviewPixel(x: 63, y: 18))], pixels: pixels, "stretch")
        // UIX-007: the same view drawn at 0.5 from window (100, 20).
        let split = PreviewPixelMapping(viewWidth: 32, viewHeight: 24, splitScale: 0.5, splitOriginX: 100, splitOriginY: 20,
                                        pictureWidth: 64, pictureHeight: 48)
        try check(split, taps: [(100.5, 20.5, PreviewPixel(x: 2, y: 2)), (101.5, 21, PreviewPixel(x: 6, y: 4)), (110, 30, PreviewPixel(x: 40, y: 40))],
                  pixels: pixels, "split")
        XCTAssertNil(split.pixel(atX: 99, y: 25), "beside the scaled output")
        // Fit in a 128 × 48 view: pillarboxed, the picture at x 32…96.
        let fit = PreviewPixelMapping(viewWidth: 128, viewHeight: 48, fit: .fit, pictureWidth: 64, pictureHeight: 48)
        try check(fit, taps: [(40, 5, PreviewPixel(x: 8, y: 5)), (90, 47, PreviewPixel(x: 58, y: 47))],
                  pixels: pixels, "fit")
        XCTAssertNil(fit.pixel(atX: 10, y: 10), "the bar")
    }
}
#endif
