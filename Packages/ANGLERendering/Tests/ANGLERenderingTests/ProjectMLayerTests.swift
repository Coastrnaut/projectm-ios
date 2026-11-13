// CMP-001-T16 (US6: projectM as a layer; CMP-001-S7). A `ProjectMLayerSource` in a `Compositor` at
// 64 × 64 on the iOS simulator: (a) the internal test pattern (GL bottom-left quadrant encoded
// 0.5 red, the rest encoded blue) reads back upright, linear and opaque; (b) a test preset draws a
// non-black opaque frame; (c) the caller's EGL binding is restored. Simulator results are not device
// evidence (CMP-001-T20 {device}).
import XCTest
import AudioCore
import CANGLE
import Compositor
import Metal
@testable import ProjectMLayer

final class ProjectMLayerTests: XCTestCase {
    private static let presets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device")
        }
        self.device = device
        self.queue = queue
    }

    private func output() throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    private func frame(_ compositor: Compositor, _ output: MTLTexture, _ t: UInt64) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: t, contentScale: 1,
                                           reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
    }

    /// Linear RGBA, rows top first.
    private func read(_ texture: MTLTexture) throws -> [SIMD4<Float>] {
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
        let halves = buffer.contents().bindMemory(to: Float16.self, capacity: texture.width * texture.height * 4)
        return (0..<(texture.width * texture.height)).map {
            SIMD4(Float(halves[$0 * 4]), Float(halves[$0 * 4 + 1]), Float(halves[$0 * 4 + 2]), Float(halves[$0 * 4 + 3]))
        }
    }

    private func near(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ tolerance: Float = 2.0 / 255) -> Bool {
        (0..<4).allSatisfy { abs(a[$0] - b[$0]) <= tolerance }
    }

    func testTestPatternReadsBackUprightLinearAndOpaque() throws {
        let layer = try ProjectMLayerSource(device: device)
        layer.drawsTestPattern = true
        let compositor = try Compositor(device: device, layers: [layer])
        let out = try output()
        try frame(compositor, out, 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        let pixels = try read(out)
        let red = SIMD4<Float>(Float(128.0 / 255.0).srgbDecoded, 0, 0, 1)   // GL stores 0.5 as 128/255
        let blue = SIMD4<Float>(0, 0, 1, 1)
        // Metal rows are top first: the picture's bottom-left quadrant is rows 32…63, columns 0…31.
        XCTAssertTrue(near(pixels[63 * 64 + 0], red), "bottom-left is red: \(pixels[63 * 64])")
        XCTAssertTrue(near(pixels[32 * 64 + 31], red), "inner corner of the quadrant: \(pixels[32 * 64 + 31])")
        XCTAssertTrue(near(pixels[0], blue), "top-left is blue (upright): \(pixels[0])")
        XCTAssertTrue(near(pixels[63 * 64 + 63], blue), "bottom-right is blue: \(pixels[63 * 64 + 63])")
        XCTAssertTrue(pixels.allSatisfy { abs($0.w - 1) < 1e-3 }, "opaque")
    }

    func testPresetDrawsAnOpaqueNonBlackFrame() throws {
        let layer = try ProjectMLayerSource(device: device)
        try layer.loadPreset(atPath: Self.presets.appendingPathComponent("100-square.milk").path)
        let ring = NormalizedPCMRing()
        let samples = [Float](repeating: 0, count: 2 * 2_000)
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 2_000) }
        layer.attach(pcm: ring)
        let compositor = try Compositor(device: device, layers: [layer])
        let out = try output()
        for t in 0..<30 { try frame(compositor, out, UInt64(t) * 16_666_667) }
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        let pixels = try read(out)
        XCTAssertTrue(pixels.allSatisfy { abs($0.w - 1) < 1e-3 }, "opaque")
        XCTAssertGreaterThan(pixels.filter { $0.x + $0.y + $0.z > 0.01 }.count, 0, "the preset drew something")
        XCTAssertLessThan(ring.availableFrames, 2_000, "the layer feeds PCM to its engine")
    }

    func testRestoresTheCallersEGLBinding() throws {
        let layer = try ProjectMLayerSource(device: device)
        layer.drawsTestPattern = true
        let before = (eglGetCurrentContext(), eglGetCurrentSurface(EGL_DRAW))
        let compositor = try Compositor(device: device, layers: [layer])
        try frame(compositor, try output(), 1)
        XCTAssertEqual(eglGetCurrentContext(), before.0)
        XCTAssertEqual(eglGetCurrentSurface(EGL_DRAW), before.1)
    }
}

private extension Float {
    var srgbDecoded: Float { self <= 0.04045 ? self / 12.92 : powf((self + 0.055) / 1.055, 2.4) }
}
