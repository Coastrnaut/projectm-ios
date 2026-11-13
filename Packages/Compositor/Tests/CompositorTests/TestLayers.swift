// CMP-001-T06: test layers and GPU read-back for the compositor tests. The layers import only
// Compositor, Metal and AnalysisFeatures (the acceptance's "without direct engine coupling";
// `testLayersImportNoEngine` checks this file's imports). Pictures are read back through a blit to a
// shared buffer (works on the Mac host and the simulator); half floats are converted by hand so the
// code builds on every Mac. Without a Metal device every GPU test throws `XCTSkip`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import AnalysisFeatures
import Compositor
import Metal
import XCTest

/// Linear premultiplied RGBA.
typealias Pixel = SIMD4<Float>

enum Half {
    static func toFloat(_ h: UInt16) -> Float {
        let sign: UInt32 = UInt32(h & 0x8000) << 16
        let exponent = Int((h >> 10) & 0x1F)
        let mantissa = UInt32(h & 0x3FF)
        if exponent == 0 {
            let value = Float(mantissa) * powf(2, -24)
            return sign == 0 ? value : -value
        }
        if exponent == 31 { return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13)) }
        return Float(bitPattern: sign | (UInt32(exponent - 15 + 127) << 23) | (mantissa << 13))
    }
}

/// Clears its picture to one premultiplied color every frame.
final class SolidLayer: LayerSource {
    let layerName: String
    let fallback: LayerFallback
    var color: Pixel
    var settings = LayerCompositeSettings()
    private(set) var prepared: [LayerPictureDescriptor] = []
    var failPrepare = false

    init(_ name: String, color: Pixel, fallback: LayerFallback = .transparent) {
        layerName = name
        self.color = color
        self.fallback = fallback
    }

    var compositeSettings: LayerCompositeSettings { settings }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        prepared.append(picture)
        if failPrepare { throw .resourceUnavailable("test prepare failure") }
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        SolidLayer.clear(picture, to: color, commandBuffer: commandBuffer)
    }

    static func clear(_ picture: MTLTexture, to color: Pixel, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(color.x), green: Double(color.y), blue: Double(color.z),
                                                            alpha: Double(color.w))
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }
}

/// Draws its color, then fails on the frames listed (after drawing a different color, to prove a
/// failed frame's picture is never shown).
final class FailingLayer: LayerSource {
    let layerName = "failing"
    let fallback: LayerFallback
    let color: Pixel
    var failingFrames: Set<UInt64>
    let error: LayerSourceError

    init(color: Pixel, fallback: LayerFallback, failingFrames: Set<UInt64>, error: LayerSourceError = .frameSkipped) {
        self.color = color
        self.fallback = fallback
        self.failingFrames = failingFrames
        self.error = error
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        if failingFrames.contains(frame.frameIndex) {
            SolidLayer.clear(picture, to: Pixel(0, 1, 0, 1), commandBuffer: commandBuffer)   // half-drawn garbage
            throw error
        }
        SolidLayer.clear(picture, to: color, commandBuffer: commandBuffer)
    }
}

/// Records what it receives (copies; tests only).
final class ProbeLayer: LayerSource {
    let layerName = "probe"
    let fallback = LayerFallback.transparent
    private(set) var frames: [LayerFrameContext] = []
    private(set) var bands: [[Float]] = []
    private(set) var events: [[AnalysisEvent]] = []
    private(set) var analysisFrames: [AnalysisFrame?] = []

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        frames.append(frame)
        bands.append(Array(audio.bands))
        events.append(Array(audio.events))
        analysisFrames.append(audio.frame)
        SolidLayer.clear(picture, to: .zero, commandBuffer: commandBuffer)
    }
}

final class GPURig {
    let device: MTLDevice
    let queue: MTLCommandQueue

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment (CI simulator or Linux); the CPU tests cover the contract.")
        }
        self.device = device
        self.queue = queue
    }

    /// An output texture (render target, private) of the given format.
    func output(_ format: MTLPixelFormat = .rgba16Float, width: Int = 64, height: Int = 64) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    /// One composite, committed and waited for. Returns `composite`'s result.
    @discardableResult
    func frame(_ compositor: Compositor, into output: MTLTexture, time: UInt64, reduceFlashing: Bool = false,
               scale: Double = 2, audio: LayerAudioContext = .empty) throws -> Bool {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let ok = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time,
                                      contentScale: scale, reduceFlashing: reduceFlashing, audio: audio)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error, "command buffer error")
        return ok
    }

    /// Reads a texture back as linear RGBA floats, rows top first (formats used by the tests).
    func read(_ texture: MTLTexture) throws -> [Pixel] {
        let bytesPerPixel = texture.pixelFormat == .rgba16Float ? 8 : 4
        let rowBytes = texture.width * bytesPerPixel
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        var pixels: [Pixel] = []
        pixels.reserveCapacity(texture.width * texture.height)
        switch texture.pixelFormat {
        case .rgba16Float:
            let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: texture.width * texture.height * 4)
            for i in 0..<(texture.width * texture.height) {
                pixels.append(Pixel(Half.toFloat(halves[i * 4]), Half.toFloat(halves[i * 4 + 1]), Half.toFloat(halves[i * 4 + 2]),
                                    Half.toFloat(halves[i * 4 + 3])))
            }
        case .bgra8Unorm, .rgba8Unorm:
            let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: texture.width * texture.height * 4)
            let bgra = texture.pixelFormat == .bgra8Unorm
            for i in 0..<(texture.width * texture.height) {
                let b0 = Float(bytes[i * 4]) / 255, b1 = Float(bytes[i * 4 + 1]) / 255, b2 = Float(bytes[i * 4 + 2]) / 255
                let a = Float(bytes[i * 4 + 3]) / 255
                pixels.append(bgra ? Pixel(b2, b1, b0, a) : Pixel(b0, b1, b2, a))
            }
        default:
            XCTFail("unsupported read-back format \(texture.pixelFormat.rawValue)")
        }
        return pixels
    }
}

/// Every pixel within `tolerance` of `expected` (per channel).
func assertAll(_ pixels: [Pixel], equal expected: Pixel, tolerance: Float = 1.0 / 255, _ message: String,
               file: StaticString = #filePath, line: UInt = #line) {
    var worst: Float = 0
    var worstPixel = Pixel.zero
    for p in pixels {
        var d: Float = 0
        for c in 0..<4 { d = max(d, Swift.abs(p[c] - expected[c])); if p[c].isNaN { d = .infinity } }
        if !(d <= worst) { worst = d; worstPixel = p }   // also catches NaN
    }
    XCTAssertTrue(worst <= tolerance, "\(message): worst pixel \(worstPixel) vs \(expected) (difference \(worst))", file: file, line: line)
}
#endif
