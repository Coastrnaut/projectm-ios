// MaterialPreviewRenderer.swift — one still frame of a material layer as 8-bit sRGB pixels (SHD-006-R6; contract N4;
// research SHD-006-D7).
//
// The Noise editor's live preview: the layer's own pipeline draws one frame at phase 0 (motion reset, first-frame
// duration 0, no music) into a layer picture, which is read back with a blit and encoded to sRGB with REC-001's
// conversion (opaque over black). The same code path the GPU tests pin, so the preview is the reference texture.
// Not Sendable: use it from one thread (the app's main actor).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FrameCapture
import Metal

public final class MaterialPreviewRenderer {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    /// Never filled: the preview has no music.
    private let audio = LayerAudioBuffer()

    public init(device: MTLDevice) throws(LayerSourceError) {
        guard let queue = device.makeCommandQueue() else { throw .resourceUnavailable("preview command queue") }
        self.device = device
        self.queue = queue
    }

    /// The system default device's renderer, or nil without Metal.
    public static func makeDefault() -> MaterialPreviewRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try? MaterialPreviewRenderer(device: device)
    }

    /// The linear half-float pixels (RGBA, rows top first) of one frame at phase 0.
    public func renderHalf(_ layer: ProceduralMaterialLayer, width: Int, height: Int) throws(LayerSourceError) -> [UInt16] {
        guard let descriptor = LayerPictureDescriptor(width: width, height: height),
              let picture = device.makeTexture(descriptor: descriptor.textureDescriptor()) else {
            throw .resourceUnavailable("preview picture \(width) × \(height)")
        }
        try layer.prepare(picture: descriptor, device: device)
        layer.resetMotion()
        var clock = LayerFrameClock()
        let frame: LayerFrameContext = clock.next(presentationTimeNanoseconds: 1_000_000_000, outputWidth: width, outputHeight: height,
                                                  contentScale: 1, reduceFlashing: true)
        let rowBytes: Int = width * 8
        guard let commands = queue.makeCommandBuffer(),
              let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared) else {
            throw .resourceUnavailable("preview buffers")
        }
        try layer.render(into: picture, commandBuffer: commands, frame: frame, audio: audio.context)
        guard let blit = commands.makeBlitCommandEncoder() else { throw .frameSkipped }
        blit.copy(from: picture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        if commands.error != nil { throw .frameSkipped }
        let count: Int = width * height * 4
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: count)
        return Array(UnsafeBufferPointer(start: halves, count: count))
    }

    /// One frame at phase 0 as opaque 8-bit sRGB.
    public func render(_ layer: ProceduralMaterialLayer, width: Int, height: Int) throws(LayerSourceError) -> RGBA8Image {
        let half: [UInt16] = try renderHalf(layer, width: width, height: height)
        guard let pixels = CapturedPixels(width: width, height: height, layout: .linearPremultipliedHalfRGBA(half)) else {
            throw .resourceUnavailable("preview pixels")
        }
        return FrameColorConversion.rgba8(pixels, policy: .opaqueOverBlack)
    }
}
#endif
