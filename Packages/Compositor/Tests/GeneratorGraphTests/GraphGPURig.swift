// SHD-002-T13: GPU helpers for the graph tests (adapted from SHD-001's GraphGPURig). A graph layer is driven directly (its own
// frame clock and command buffers, no compositor) so its raw picture can be read back; pictures are
// copied to a shared buffer with a blit and half floats converted by hand. Without a Metal device
// every GPU test throws `XCTSkip`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import Metal
import GeneratorGraph
import XCTest

typealias GPixel = SIMD4<Float>

final class GraphGPURig {
    static let frameNanoseconds: UInt64 = 16_666_667

    let device: MTLDevice
    let queue: MTLCommandQueue
    private var sharedPipeline: GeneratorGraphPipeline?

    /// One interpreter pipeline for every layer of this rig.
    func pipeline() throws -> GeneratorGraphPipeline {
        if let sharedPipeline { return sharedPipeline }
        let p = try GeneratorGraphPipeline(device: device)
        sharedPipeline = p
        return p
    }

    /// A layer for `document` sharing the rig's pipeline.
    func layer(_ document: GeneratorGraphDocument) throws -> GeneratorGraphLayer {
        try GeneratorGraphLayer(compiled: GeneratorGraphCompiler.compile(document), pipeline: pipeline())
    }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment; the CPU tests cover the compiler.")
        }
        self.device = device
        self.queue = queue
    }

    /// A layer picture of the given size (private, as the compositor makes them).
    func picture(width: Int = 64, height: Int = 64) throws -> MTLTexture {
        let descriptor = try XCTUnwrap(LayerPictureDescriptor(width: width, height: height))
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor.textureDescriptor()))
    }

    /// Drives one layer frame by frame at 60 Hz.
    final class Driver {
        let rig: GraphGPURig
        let layer: GeneratorGraphLayer
        let picture: MTLTexture
        private var clock = LayerFrameClock()
        private let audio = LayerAudioBuffer()
        private var index: UInt64 = 0

        init(rig: GraphGPURig, layer: GeneratorGraphLayer, width: Int = 64, height: Int = 64) throws {
            self.rig = rig
            self.layer = layer
            picture = try rig.picture(width: width, height: height)
            try layer.prepare(picture: XCTUnwrap(LayerPictureDescriptor(width: width, height: height)), device: rig.device)
        }

        /// Renders the next frame with `bands` (empty = no analysis) and waits.
        func step(bands: [Float] = []) throws {
            let frame = clock.next(presentationTimeNanoseconds: 1_000_000_000 + index * GraphGPURig.frameNanoseconds,
                                   outputWidth: picture.width, outputHeight: picture.height, contentScale: 2,
                                   reduceFlashing: false)
            index += 1
            audio.set(frame: nil, bands: bands, events: [])
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            try layer.render(into: picture, commandBuffer: commands, frame: frame, audio: audio.context)
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error, "command buffer error")
        }

        func read() throws -> [GPixel] { try rig.read(picture) }
    }

    /// Reads an rgba16Float texture back as linear RGBA, rows top first.
    func read(_ texture: MTLTexture) throws -> [GPixel] {
        let rowBytes = texture.width * 8
        let count = texture.width * texture.height
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: count * 4)
        var pixels: [GPixel] = []
        pixels.reserveCapacity(count)
        for i in 0..<count {
            pixels.append(GPixel(Self.half(halves[i * 4]), Self.half(halves[i * 4 + 1]), Self.half(halves[i * 4 + 2]),
                                Self.half(halves[i * 4 + 3])))
        }
        return pixels
    }

    static func half(_ h: UInt16) -> Float {
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

    /// The 17 FX-019 area levels of a square picture: 16 tiles (row 0 at the top), then their mean.
    static func areas(_ pixels: [GPixel], side: Int = 64) -> [FlashLevels] {
        var out: [FlashLevels] = []
        let tile = side / 4
        for ty in 0..<4 {
            for tx in 0..<4 {
                var y = 0.0, r = 0.0
                for py in (ty * tile)..<((ty + 1) * tile) {
                    for px in (tx * tile)..<((tx + 1) * tile) {
                        let p = pixels[py * side + px]
                        y += FlashColor.relativeLuminance(red: Double(p.x), green: Double(p.y), blue: Double(p.z))
                        r += FlashColor.redness(red: Double(p.x), green: Double(p.y), blue: Double(p.z))
                    }
                }
                out.append(FlashLevels(luminance: y / Double(tile * tile), redness: r / Double(tile * tile)))
            }
        }
        let meanY = out.reduce(0.0) { (s: Double, l: FlashLevels) -> Double in s + l.luminance } / 16
        let meanR = out.reduce(0.0) { (s: Double, l: FlashLevels) -> Double in s + l.redness } / 16
        out.append(FlashLevels(luminance: meanY, redness: meanR))
        return out
    }
}

/// Every pixel finite, alpha 1, color 0…alpha (premultiplied-valid opaque). Returns the problem count.
func invalidGraphPixelCount(_ pixels: [GPixel]) -> Int {
    pixels.reduce(0) { (n: Int, p: GPixel) -> Int in
        let ok = p.x.isFinite && p.y.isFinite && p.z.isFinite && p.w == 1
            && p.x >= 0 && p.y >= 0 && p.z >= 0 && p.x <= p.w && p.y <= p.w && p.z <= p.w
        return ok ? n : n + 1
    }
}
#endif
