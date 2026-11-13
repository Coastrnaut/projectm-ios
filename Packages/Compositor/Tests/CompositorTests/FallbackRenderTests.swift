// CMP-001-T09 (US3: a failing layer never takes the picture down; CMP-001-S3) and T11 (US4: resize
// and ownership; CMP-001-S4). GPU tests at 64 × 64; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

final class FallbackRenderTests: XCTestCase {
    private let blue = Pixel(0, 0, 1, 1)
    private let halfRed = Pixel(0.5, 0, 0, 0.5)
    private let redOverBlue = Pixel(0.5, 0, 0.5, 1)

    func testTransparentFallbackShowsTheOtherLayerOnly() throws {
        let rig = try GPURig()
        let failing = FailingLayer(color: halfRed, fallback: .transparent, failingFrames: [0])
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), failing])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: blue, "failed transparent layer: blue only")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackTransparent(.frameSkipped))
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        try rig.frame(compositor, into: output, time: 2)
        assertAll(try rig.read(output), equal: redOverBlue, "it reappears on the next good frame")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered)
    }

    func testLastGoodFallbackKeepsTheLastGoodPicture() throws {
        let rig = try GPURig()
        let failing = FailingLayer(color: halfRed, fallback: .lastGoodFrame, failingFrames: [1, 2],
                                   error: .engineFailure("test"))
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), failing])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: redOverBlue, "frame 0 good")
        for t in [UInt64(2), 3] {
            try rig.frame(compositor, into: output, time: t)
            assertAll(try rig.read(output), equal: redOverBlue, "frames 1-2 failed: the last good picture, never the half-drawn one")
            XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackLastGood(.engineFailure("test")))
        }
    }

    func testLastGoodBeforeAnySuccessIsTransparent() throws {
        let rig = try GPURig()
        let failing = FailingLayer(color: halfRed, fallback: .lastGoodFrame, failingFrames: [0])
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), failing])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: blue, "no good frame yet")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackLastGood(.frameSkipped))
    }

    func testPrepareFailureMakesTheLayerUnavailableUntilRetry() throws {
        let rig = try GPURig()
        let broken = SolidLayer("broken", color: halfRed)
        broken.failPrepare = true
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), broken])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: blue, "unavailable layer skipped")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .unavailable(.resourceUnavailable("test prepare failure")))
        broken.failPrepare = false
        compositor.retryUnavailableLayers()
        try rig.frame(compositor, into: output, time: 2)
        assertAll(try rig.read(output), equal: redOverBlue, "back after a successful retry")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered)
    }

    func testNonFiniteLayerOutputStaysFinite() throws {
        let rig = try GPURig()
        let broken = SolidLayer("nan", color: Pixel(.nan, .infinity, -.infinity, .nan))
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), broken])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        // Non-finite channels read 0: the broken layer is (0, 0, 0, 0) and blue shows through.
        assertAll(try rig.read(output), equal: blue, "finite output")
    }

    // MARK: - US4 (CMP-001-T11)

    func testResizeReallocatesExactlyOncePerSize() throws {
        let rig = try GPURig()
        let plain = SolidLayer("plain", color: blue)                                 // 1 picture
        let kept = SolidLayer("kept", color: halfRed, fallback: .lastGoodFrame)      // 2 pictures
        let compositor = try Compositor(device: rig.device, layers: [plain, kept])
        let small = try rig.output(width: 64, height: 64)
        for t in 1...5 { try rig.frame(compositor, into: small, time: UInt64(t)) }
        XCTAssertEqual(compositor.pictureAllocations, 1 + 1 + 2, "composite + 1 + 2 pictures, created once at 64 × 64")
        let other = try rig.output(width: 32, height: 48)
        for t in 6...10 { try rig.frame(compositor, into: other, time: UInt64(t)) }
        XCTAssertEqual(compositor.pictureAllocations, 2 * (1 + 1 + 2), "created once more at 32 × 48")
        let sizes = [try XCTUnwrap(LayerPictureDescriptor(width: 64, height: 64)), try XCTUnwrap(LayerPictureDescriptor(width: 32, height: 48))]
        XCTAssertEqual(plain.prepared, sizes, "prepared exactly once per size")
        XCTAssertEqual(kept.prepared, sizes)
        assertAll(try rig.read(other), equal: redOverBlue, "renders at the new size")
    }

    func testEmptyOutputRendersAndAllocatesNothing() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue)])
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        // A 1 × 1 texture stands in for "no size" only through the descriptor rule; Metal cannot make 0-sized textures,
        // so the rule is checked through `LayerPictureDescriptor` (ContractTests) and an unsupported format here.
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 8, height: 8, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        let unsupported = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        XCTAssertFalse(compositor.composite(into: unsupported, commandBuffer: commands, presentationTimeNanoseconds: 1, contentScale: 1,
                                            reduceFlashing: false, audio: .empty))
        commands.commit()
        XCTAssertEqual(compositor.pictureAllocations, 0)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .notRendered)
    }
}
#endif
