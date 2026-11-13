// CompositorCaptureTests.swift — REC-001-T09: the compositor's frame capture (research REC-001-D1).
// GPU tests at 64 × 48 through the real Metal compositor; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import FrameCapture
import Metal
import XCTest

/// Collects handler results across Metal's completion thread.
private final class CaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CapturedPixels?] = []
    func append(_ value: CapturedPixels?) { lock.lock(); values.append(value); lock.unlock() }
    var all: [CapturedPixels?] { lock.lock(); defer { lock.unlock() }; return values }
}

final class CompositorCaptureTests: XCTestCase {
    private let halfRed = Pixel(0.5, 0, 0, 0.5)   // premultiplied

    private func capture(_ compositor: Compositor, rig: GPURig, output: MTLTexture, time: UInt64,
                         reduceFlashing: Bool = false) throws -> CapturedPixels {
        let done = expectation(description: "capture")
        let box = CaptureBox()
        compositor.requestFrameCapture { (pixels: CapturedPixels?) in
            box.append(pixels)
            done.fulfill()
        }
        XCTAssertTrue(compositor.hasPendingFrameCapture)
        try rig.frame(compositor, into: output, time: time, reduceFlashing: reduceFlashing)
        wait(for: [done], timeout: 5)
        XCTAssertFalse(compositor.hasPendingFrameCapture)
        return try XCTUnwrap(box.all.first ?? nil)
    }

    private func floats(_ pixels: CapturedPixels) -> [Pixel] {
        guard case .linearPremultipliedHalfRGBA(let h) = pixels.layout else { XCTFail("layout"); return [] }
        return stride(from: 0, to: h.count, by: 4).map { (i: Int) -> Pixel in
            Pixel(Half.toFloat(h[i]), Half.toFloat(h[i + 1]), Half.toFloat(h[i + 2]), Half.toFloat(h[i + 3]))
        }
    }

    /// The capture has the output's size and the composite's linear premultiplied values (coverage kept).
    func testCaptureHasOutputSizeAndCompositeValues() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("red", color: halfRed)])
        let output = try rig.output(.bgra8Unorm, width: 64, height: 48)
        let pixels = try capture(compositor, rig: rig, output: output, time: 1)
        XCTAssertEqual(pixels.width, 64)
        XCTAssertEqual(pixels.height, 48)
        assertAll(floats(pixels), equal: halfRed, tolerance: 1e-3, "captured composite")
        // PNG keeps the coverage, HEIF flattens it (REC-001-R5, R6).
        let png = FrameColorConversion.rgba8(pixels, policy: .preserveCoverage)
        XCTAssertTrue(png.hasAlpha)
        XCTAssertTrue(png.pixel(x: 10, y: 10) == (255, 0, 0, 128))
        let heif = FrameColorConversion.rgba8(pixels, policy: .opaqueOverBlack)
        XCTAssertTrue(heif.pixel(x: 10, y: 10) == (188, 0, 0, 255))
    }

    /// No request: no capture work; a pending request does not change the shown frame (REC-001-R4).
    func testPendingCaptureLeavesTheOutputUnchanged() throws {
        let rig = try GPURig()
        let blue = Pixel(0, 0, 1, 1)
        let plain = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), SolidLayer("red", color: halfRed)])
        let capturing = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), SolidLayer("red", color: halfRed)])
        let a = try rig.output(.rgba16Float, width: 64, height: 48)
        let b = try rig.output(.rgba16Float, width: 64, height: 48)
        try rig.frame(plain, into: a, time: 1)
        XCTAssertFalse(plain.hasPendingFrameCapture)
        let pixels = try capture(capturing, rig: rig, output: b, time: 1)
        XCTAssertEqual(try rig.read(a), try rig.read(b))
        assertAll(floats(pixels), equal: Pixel(0.5, 0, 0.5, 1), tolerance: 1e-3, "half red over blue")
        // The next frame captures nothing more.
        try rig.frame(capturing, into: b, time: 2)
        XCTAssertFalse(capturing.hasPendingFrameCapture)
    }

    /// The capture is the frame after the flash guard (FX-019): a black → white step under Reduce
    /// flashing is limited in the output, and the capture shows the same limited value.
    func testCaptureIsTheFlashLimitedFrame() throws {
        let rig = try GPURig()
        let layer = SolidLayer("level", color: Pixel(0, 0, 0, 1))
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output(.rgba16Float, width: 64, height: 48)
        let frame: UInt64 = 16_666_667
        for i in 0..<30 { try rig.frame(compositor, into: output, time: UInt64(i) * frame, reduceFlashing: true) }
        layer.color = Pixel(1, 1, 1, 1)
        let pixels = try capture(compositor, rig: rig, output: output, time: 30 * frame, reduceFlashing: true)
        let gain = compositor.lastFlashGain
        XCTAssertLessThan(gain, 1, "the guard limits the step")
        let shown = try rig.read(output)
        assertAll(floats(pixels), equal: shown[0], tolerance: 1e-3, "capture equals the shown frame")
        XCTAssertEqual(shown[0].x, gain, accuracy: 2e-3)
    }

    /// A newer request replaces an older one (nil to the old); cancel gives nil.
    func testReplacedAndCancelledRequestsGetNil() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("red", color: halfRed)])
        let box = CaptureBox()
        compositor.requestFrameCapture { (p: CapturedPixels?) in box.append(p) }
        compositor.requestFrameCapture { (p: CapturedPixels?) in box.append(p) }
        XCTAssertEqual(box.all.count, 1)
        XCTAssertNil(box.all[0] ?? nil)
        compositor.cancelFrameCapture()
        XCTAssertEqual(box.all.count, 2)
        XCTAssertFalse(compositor.hasPendingFrameCapture)
    }
}
#endif
