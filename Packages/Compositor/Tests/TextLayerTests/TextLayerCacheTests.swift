// CMP-013-T11: the text layer's render caching through the real compositor (CMP-013-R11). 64 × 64 output;
// skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(CoreText)
import AnalysisFeatures
import Compositor
import Metal
import TextLayer
import XCTest

final class TextLayerCacheTests: XCTestCase {
    func testStaticTextRendersOnceAndANewMessageRendersExactlyOnceMore() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment; the CPU tests cover the rest.")
        }
        let layer = TextLayerSource(device: device)
        let compositor = try Compositor(device: device, layers: [layer])
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        var time: UInt64 = 1
        func frames(_ n: Int) throws {
            for _ in 0..<n {
                let commands = try XCTUnwrap(queue.makeCommandBuffer())
                XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time,
                                                   contentScale: 2, reduceFlashing: false, audio: .empty))
                commands.commit()
                commands.waitUntilCompleted()
                time += 16_666_667
            }
        }
        try frames(1)   // prepares the layer at 64 × 64 (nothing to draw yet)
        layer.spec = TextOverlaySpec(message: "A", size: 0.25)
        layer.waitUntilRendered()
        try frames(10)
        XCTAssertEqual(layer.renderCount, 1, "static text renders once over ten frames")
        XCTAssertEqual(layer.framesShown, 10, "and is shown in all ten")
        XCTAssertTrue(compositor.wasReused(layer: 0))

        layer.spec = TextOverlaySpec(message: "B", size: 0.25)
        try frames(1)   // the old rendering may still show while "B" is drawn (MED-009), never a stale "B"
        layer.waitUntilRendered()
        let before = layer.renderCount
        try frames(5)
        XCTAssertEqual(layer.renderCount, before + 1, "the new message renders exactly once")
        XCTAssertTrue(compositor.wasReused(layer: 0))

        layer.spec = TextOverlaySpec(message: "")
        let shownBefore = layer.framesShown
        try frames(2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "an empty message is dropped at once")
        XCTAssertEqual(layer.framesShown, shownBefore)
    }
}
#endif
