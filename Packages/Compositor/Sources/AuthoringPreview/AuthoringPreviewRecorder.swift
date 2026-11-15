// AuthoringPreviewRecorder.swift — draws every frame of a preview run with the material's own GPU code and hashes
// it (SHD-012-R4, R5, R7; contract P3; research SHD-012-D3, D4). Apple only (Metal, CryptoKit).
//
// One `ProceduralMaterialLayer` per recording, prepared once for a `width` × `height` layer picture, motion reset.
// Frame n: the layer takes the sequencer's values for n, renders with n's context (the sequencer's presentation time
// and frame duration, Reduce flashing on) and n's bands, then the same command buffer blits the picture into a shared
// buffer; after it completes the linear half-float RGBA bytes are hashed (SHA-256, as REC-013 hashes its frames) and,
// when asked, converted to 8-bit sRGB for display (REC-001's conversion, opaque over black). The run digest is the
// SHA-256 of the concatenated frame digests. Not Sendable: use it from one task.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import CryptoKit
import FrameCapture
import Metal
import ProceduralMaterials

/// A recorded run: the trajectory, one checksum per frame and (optionally) the frames for display.
public struct AuthoringPreviewRecording: Sendable, Equatable {
    public var trajectory: AuthoringPreviewTrajectory
    /// SHA-256 of each frame's read-back bytes, 64 lowercase hex characters.
    public var checksums: [String]
    /// SHA-256 of the concatenated frame digests.
    public var runDigest: String
    /// 8-bit sRGB frames, when requested (empty otherwise).
    public var images: [RGBA8Image]
    /// The material layer's motion after each frame (`phase`, `audioLevel`), to cross-check the trajectory.
    public var layerMotion: [MaterialMotion]

    /// The first 8 characters of the run digest (the editor's summary).
    public var shortDigest: String { String(runDigest.prefix(8)) }
}

public final class AuthoringPreviewRecorder {
    public let device: MTLDevice
    private let queue: MTLCommandQueue

    public init(device: MTLDevice) throws(AuthoringPreviewError) {
        guard let queue = device.makeCommandQueue() else { throw .render("no command queue") }
        queue.label = "SHD-012 authoring preview"
        self.device = device
        self.queue = queue
    }

    /// The system default device's recorder, or nil without Metal.
    public static func makeDefault() -> AuthoringPreviewRecorder? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try? AuthoringPreviewRecorder(device: device)
    }

    /// Records the whole run of `request` at `width` × `height` pixels. `isCancelled` is read before each frame
    /// (a cancelled run throws `.render("cancelled")`).
    public func record(_ request: AuthoringPreviewRequest, width: Int, height: Int, keepImages: Bool = false,
                       variant: String? = nil,
                       isCancelled: () -> Bool = { () -> Bool in false }) throws(AuthoringPreviewError) -> AuthoringPreviewRecording {
        let sequencer = try AuthoringPreviewSequencer(request: request)
        let layer = ProceduralMaterialLayer(request.values.definition, variant: variant)
        guard let descriptor = LayerPictureDescriptor(width: width, height: height),
              let picture = device.makeTexture(descriptor: descriptor.textureDescriptor()) else {
            throw .render("picture \(width) × \(height)")
        }
        do {
            try layer.prepare(picture: descriptor, device: device)
        } catch {
            throw .render(String(describing: error))
        }
        layer.resetMotion()
        let rowBytes: Int = width * 8
        guard let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared) else {
            throw .render("read-back buffer")
        }
        var trajectory = AuthoringPreviewTrajectory(parameters: request.boundParameters)
        var checksums: [String] = []
        var digests: [UInt8] = []
        var images: [RGBA8Image] = []
        var motions: [MaterialMotion] = []
        while let frame = sequencer.step() {
            if isCancelled() { throw .render("cancelled") }
            try draw(frame, layer: layer, picture: picture, buffer: buffer, width: width, height: height)
            let bytes = UnsafeRawBufferPointer(start: buffer.contents(), count: rowBytes * height)
            let digest: [UInt8] = Array(SHA256.hash(data: bytes))
            digests.append(contentsOf: digest)
            checksums.append(Self.hex(digest))
            trajectory.append(frame)
            motions.append(layer.motion)
            if keepImages { images.append(try Self.image(bytes, width: width, height: height)) }
        }
        let run: String = Self.hex(Array(SHA256.hash(data: digests)))
        return AuthoringPreviewRecording(trajectory: trajectory, checksums: checksums, runDigest: run, images: images,
                                         layerMotion: motions)
    }

    private func draw(_ frame: AuthoringPreviewFrame, layer: ProceduralMaterialLayer, picture: MTLTexture, buffer: MTLBuffer,
                      width: Int, height: Int) throws(AuthoringPreviewError) {
        for (d, v) in zip(frame.values.definition.parameters, frame.values.values) { _ = try? layer.set(v, for: d.id) }
        let context = LayerFrameContext(presentationTimeNanoseconds: frame.presentationTimeNanoseconds, frameIndex: UInt64(frame.index),
                                        frameDuration: frame.frameDuration, outputWidth: width, outputHeight: height,
                                        contentScale: 1, reduceFlashing: true)
        guard let commands = queue.makeCommandBuffer() else { throw .render("command buffer") }
        let failure: LayerSourceError? = frame.bands.withUnsafeBufferPointer { (bands: UnsafeBufferPointer<Float>) -> LayerSourceError? in
            let audio = LayerAudioContext(frame: nil, bands: bands, events: UnsafeBufferPointer(start: nil, count: 0), droppedEvents: 0)
            do throws(LayerSourceError) {
                try layer.render(into: picture, commandBuffer: commands, frame: context, audio: audio)
                return nil
            } catch {
                return error
            }
        }
        if let failure { throw .render(String(describing: failure)) }
        guard let blit = commands.makeBlitCommandEncoder() else { throw .render("blit encoder") }
        let rowBytes: Int = width * 8
        blit.copy(from: picture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        if let error = commands.error { throw .render(error.localizedDescription) }
    }

    private static func image(_ bytes: UnsafeRawBufferPointer, width: Int, height: Int) throws(AuthoringPreviewError) -> RGBA8Image {
        let half: [UInt16] = Array(bytes.bindMemory(to: UInt16.self))
        guard let pixels = CapturedPixels(width: width, height: height, layout: .linearPremultipliedHalfRGBA(half)) else {
            throw .render("frame pixels")
        }
        return FrameColorConversion.rgba8(pixels, policy: .opaqueOverBlack)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        let digits: [Character] = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0f)])
        }
        return out
    }
}
#endif
