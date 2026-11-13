// MED-009-T10, T19: the text layer on the GPU (MED-009-R9, R17, S5). 64 × 64 pictures; skipped
// without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(CoreText)
import AnalysisFeatures
import Compositor
import Metal
import TextLayer
import XCTest

final class TextLayerSourceTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment; the CPU tests cover the rest.")
        }
        self.device = device
        self.queue = queue
    }

    private func picture(_ width: Int = 64, _ height: Int = 64) throws -> MTLTexture {
        let d = try XCTUnwrap(LayerPictureDescriptor(width: width, height: height)).textureDescriptor()
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    /// Fills the picture with opaque magenta so a missing clear would show.
    private func dirty(_ texture: MTLTexture) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 1)
        try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass)).endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
    }

    private func draw(_ layer: TextLayerSource, into texture: MTLTexture) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        do throws(LayerSourceError) {
            try layer.render(into: texture, commandBuffer: commands, frame: LayerFrameContext(presentationTimeNanoseconds: 1, frameIndex: 0, frameDuration: 1.0 / 60,
                                                                                               outputWidth: texture.width, outputHeight: texture.height,
                                                                                               contentScale: 1, reduceFlashing: false),
                             audio: .empty)
        } catch {
            commands.commit()
            throw error
        }
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
    }

    /// Half-float bit patterns, RGBA, rows top first.
    private func read(_ texture: MTLTexture) throws -> [UInt16] {
        let rowBytes = texture.width * 8
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let count = texture.width * texture.height * 4
        return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt16.self, capacity: count), count: count))
    }

    private static func srgb(_ linear: Float) -> Float {
        linear <= 0.0031308 ? linear * 12.92 : 1.055 * powf(linear, 1 / 2.4) - 0.055
    }

    func testPictureMatchesTheRenderingWithin1Over255() throws {
        let layer = TextLayerSource(device: device)
        XCTAssertEqual(layer.fallback, .transparent)
        let output = try picture()
        try dirty(output)
        XCTAssertThrowsError(try draw(layer, into: output), "no text yet: not ready")
        layer.spec = TextOverlaySpec(message: "Ab 👋🏽", size: 0.25, color: TextColor(red: 1, green: 0.5, blue: 0.25, alpha: 0.8),
                                     outlineWidth: 0.1, showsBox: true)
        try layer.prepare(picture: try XCTUnwrap(LayerPictureDescriptor(width: 64, height: 64)), device: device)
        layer.waitUntilRendered()
        let rendering = try XCTUnwrap(layer.lastRendering)
        guard case .ready(rendering.width, rendering.height, rendering.checksum) = layer.state else { return XCTFail("\(layer.state)") }
        try draw(layer, into: output)
        XCTAssertEqual(layer.framesShown, 1)
        let got = try read(output)
        let expected = rendering.linearHalfPixels()
        var compared = 0
        for py in 0..<64 {
            for px in 0..<64 {
                let i = (py * 64 + px) * 4
                let inside = px >= rendering.x && px < rendering.x + rendering.width && py >= rendering.y && py < rendering.y + rendering.height
                if !inside {
                    XCTAssertEqual(Array(got[i..<(i + 4)]), [0, 0, 0, 0], "cleared outside the canvas at \(px),\(py)")
                    continue
                }
                let j = ((py - rendering.y) * rendering.width + (px - rendering.x)) * 4
                XCTAssertEqual(Array(got[i..<(i + 4)]), Array(expected[j..<(j + 4)]), "the uploaded bytes at \(px),\(py)")
                // Back to 8-bit premultiplied sRGB: within 1/255 of what the rasterizer drew.
                let a = HalfFloat.float(got[i + 3])
                XCTAssertEqual(a * 255, Float(rendering.pixels[j + 3]), accuracy: 1)
                if a > 0 {
                    for c in 0..<3 {
                        let straight = Self.srgb(HalfFloat.float(got[i + c]) / a)
                        XCTAssertEqual(straight * a * 255, Float(rendering.pixels[j + c]), accuracy: 1.0 + 1e-3, "channel \(c) at \(px),\(py)")
                    }
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 500)
    }

    func testEmptyMessageIsTransparentAndASpecChangeReplacesThePicture() throws {
        let layer = TextLayerSource(device: device)
        try layer.prepare(picture: try XCTUnwrap(LayerPictureDescriptor(width: 64, height: 64)), device: device)
        XCTAssertEqual(layer.state, .empty)
        layer.spec = TextOverlaySpec(message: "A", size: 0.25)
        layer.waitUntilRendered()
        let first = try XCTUnwrap(layer.lastRendering).checksum
        layer.spec = TextOverlaySpec(message: "B", size: 0.25)
        layer.waitUntilRendered()
        XCTAssertNotEqual(try XCTUnwrap(layer.lastRendering).checksum, first, "the new message replaces the old")
        let output = try picture()
        try draw(layer, into: output)
        layer.spec = TextOverlaySpec(message: " ")
        XCTAssertEqual(layer.state, .empty)
        XCTAssertThrowsError(try draw(layer, into: output), "an empty message drops the text at once")
        XCTAssertNil(layer.lastRendering)
    }

    func testANewSizeRedrawsAndTheOldSizeIsNotShown() throws {
        let layer = TextLayerSource(device: device)
        layer.spec = TextOverlaySpec(message: "Hi", size: 0.25)
        try layer.prepare(picture: try XCTUnwrap(LayerPictureDescriptor(width: 64, height: 64)), device: device)
        layer.waitUntilRendered()
        try layer.prepare(picture: try XCTUnwrap(LayerPictureDescriptor(width: 96, height: 48)), device: device)
        layer.waitUntilRendered()
        let r = try XCTUnwrap(layer.lastRendering)
        XCTAssertEqual([r.pictureWidth, r.pictureHeight], [96, 48])
        try draw(layer, into: try picture(96, 48))
    }

    func testThroughTheCompositorWithALayerStack() throws {
        let layer = TextLayerSource(device: device)
        layer.spec = TextOverlaySpec(message: "Hi", size: 0.25)
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .text))
        XCTAssertThrowsError(try stack.add(LayerDescriptor(kind: .text)), "one text layer per stack")
        let compositor = try Compositor(device: device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in layer }
        let output = try picture()
        for time: UInt64 in [1, 2] {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time, contentScale: 1,
                                     reduceFlashing: false, audio: .empty)
            commands.commit()
            commands.waitUntilCompleted()
            layer.waitUntilRendered()
        }
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "the second frame shows the text")
    }
}
#endif
