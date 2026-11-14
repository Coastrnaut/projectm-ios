// SnapshotStillRenderer.swift — REC-002 one batch image, rendered offscreen (specs/234-rec-002-image-batch-export;
// R3; contract B3; research REC-002-D2, D4).
//
// * The same generator factory as the screen (`NativeSpectrumHost.makeGenerator`) and the same FX-001 glow: a
//   `BloomEffect` in an `EffectChain` while the clamped glow is not pass-through, the generator's downstream luminance
//   set to the bloom's model, so the generators' Reduce-flashing limiter bounds the glowing frame as on screen (FX-001-R10).
//   The glow is limited by the safety clamp (ACC-012-R4) and the frame context carries its envelope (ACC-012-R5).
// * Deterministic: four frames at t = 1 s + n/60 s into a private `bgra8Unorm_srgb` texture of the job's size, with
//   `SnapshotSyntheticAudio` as input; the last frame is blitted into a shared buffer and read as REC-001's
//   `CapturedPixels(.sRGBBGRA8TopDown)`, then encoded as PNG with `FrameImageEncoder`. Same inputs, same bytes.
// * Never touches the screen, the live host or any setting. One renderer serves one batch at a time, off the main actor.
import FlashSafety
import Foundation
import FrameCapture
import Metal
import VisualEffects
import VisualGenerators

enum SnapshotRenderError: Error, Equatable, CustomStringConvertible {
    case noDevice
    case resource(String)
    case gpu(String)
    case encode(String)

    var description: String {
        switch self {
        case .noDevice: "no Metal device"
        case let .resource(s): "could not create \(s)"
        case let .gpu(s): "the frame failed: \(s)"
        case let .encode(s): "the image could not be encoded: \(s)"
        }
    }
}

/// Renders batch images. `@unchecked Sendable`: a batch uses it from one task at a time (the coordinator refuses a
/// second export while one renders) and it holds only Metal objects that are thread-safe to use from that task.
final class SnapshotStillRenderer: @unchecked Sendable {
    static let frameCount = 4
    static let startNanoseconds: UInt64 = 1_000_000_000
    static let intervalNanoseconds: UInt64 = 16_666_667

    private let device: MTLDevice
    private let queue: MTLCommandQueue

    init() throws(SnapshotRenderError) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw .noDevice }
        self.device = device
        self.queue = queue
    }

    /// One item of `job` as PNG bytes of exactly the job's size.
    func render(job: SnapshotBatchJob, item: SnapshotBatchItem) throws -> Data {
        let pixels: CapturedPixels = try renderPixels(style: job.style(for: item), values: item.values,
                                                      reduceFlashing: job.reduceFlashing, clamp: job.clamp,
                                                      width: job.size.width, height: job.size.height)
        do {
            return try FrameImageEncoder.encode(pixels, as: .png).data
        } catch {
            throw SnapshotRenderError.encode("\(error)")
        }
    }

    func renderPixels(style: NativeSpectrumStyle, values: SnapshotRenderValues, reduceFlashing: Bool, clamp: SafetyClamp,
                      width: Int, height: Int) throws -> CapturedPixels {
        let generator: any SpectrumTextureGenerator = try NativeSpectrumHost.makeGenerator(device: device, style: style,
                                                                                         barCount: values.barCount)
        let glow: BloomParameters = values.glow.limited(by: clamp)
        let chain: EffectChain? = try makeChain(glow: glow, width: width, height: height)
        if chain != nil { generator.downstreamLuminance = BloomLuminanceModel(parameters: glow) }
        let target: MTLTexture = try makeTarget(width: width, height: height)
        let rowBytes: Int = width * 4
        guard let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared) else {
            throw SnapshotRenderError.resource("the read-back buffer")
        }
        let input: [Float] = SnapshotSyntheticAudio.input(for: style, barCount: values.barCount)
        for frame in 0..<Self.frameCount {
            guard let commands = queue.makeCommandBuffer() else { throw SnapshotRenderError.resource("a command buffer") }
            let time: UInt64 = Self.startNanoseconds + UInt64(frame) * Self.intervalNanoseconds
            let context = VisualFrameContext(timeNanoseconds: time, frameDuration: 1.0 / 60, reduceFlashing: reduceFlashing,
                                             flashLimits: clamp.flashLimitsOverride)
            let drawn: Bool = input.withUnsafeBufferPointer { (bands: UnsafeBufferPointer<Float>) -> Bool in
                guard let chain else {
                    return generator.encode(into: target, commandBuffer: commands, bands: bands, context: context)
                }
                return chain.encode(output: target, commandBuffer: commands) { (image: MTLTexture) -> Bool in
                    generator.encode(into: image, commandBuffer: commands, bands: bands, context: context)
                }
            }
            guard drawn else { throw SnapshotRenderError.gpu("frame \(frame) was not drawn") }
            if frame == Self.frameCount - 1 { try encodeReadBack(target, into: buffer, commands: commands) }
            commands.commit()
            commands.waitUntilCompleted()
            if let error = commands.error { throw SnapshotRenderError.gpu("\(error)") }
        }
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let copy: [UInt8] = Array(UnsafeBufferPointer(start: bytes, count: rowBytes * height))
        guard let pixels = CapturedPixels(width: width, height: height, layout: .sRGBBGRA8TopDown(copy)) else {
            throw SnapshotRenderError.resource("the pixels")
        }
        return pixels
    }

    private func makeChain(glow: BloomParameters, width: Int, height: Int) throws -> EffectChain? {
        guard !glow.isPassThrough else { return nil }
        let bloom = try BloomEffect(device: device, pixelFormat: .bgra8Unorm_srgb, parameters: glow)
        let chain = try EffectChain(device: device, pixelFormat: .bgra8Unorm_srgb, effects: [bloom])
        try chain.prepare(width: width, height: height)
        return chain
    }

    private func makeTarget(width: Int, height: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height,
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        d.storageMode = .private
        guard let texture = device.makeTexture(descriptor: d) else { throw SnapshotRenderError.resource("a \(width)×\(height) image") }
        texture.label = "REC-002 batch image"
        return texture
    }

    private func encodeReadBack(_ target: MTLTexture, into buffer: MTLBuffer, commands: MTLCommandBuffer) throws {
        guard let blit = commands.makeBlitCommandEncoder() else { throw SnapshotRenderError.resource("a blit encoder") }
        let rowBytes: Int = target.width * 4
        blit.label = "REC-002 read-back"
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: target.width, height: target.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * target.height)
        blit.endEncoding()
    }
}

/// REC-002-D4: fixed audio for the batch, the same on every run.
enum SnapshotSyntheticAudio {
    static let seed: UInt64 = 0x5245_4332   // "REC2"

    /// Bands for the spectra and the event-driven visuals; the mono history for the oscilloscope and the radial
    /// waveform; the interleaved stereo history for the Lissajous.
    static func input(for style: NativeSpectrumStyle, barCount: SpectrumBarCount) -> [Float] {
        if style.drawsMonoHistory { return mono(count: WaveformFrameBuffer.capacity) }
        if case .lissajous = style { return stereo(frames: WaveformFrameBuffer.capacity / 2) }
        return bands(count: barCount.rawValue)
    }

    /// A falling tilt from 0.85 to 0.25 with a seeded ±15 % ripple, kept in 0.05…1.
    static func bands(count: Int) -> [Float] {
        var state: UInt64 = seed
        var out: [Float] = []
        out.reserveCapacity(count)
        let last = Float(max(count - 1, 1))
        for i in 0..<count {
            let tilt: Float = 0.85 - 0.6 * Float(i) / last
            let ripple: Float = (unitFloat(&state) * 2 - 1) * 0.15
            out.append(min(max(tilt * (1 + ripple), 0.05), 1))
        }
        return out
    }

    /// Two sines (5 and 13 cycles over the history), amplitude 0.7.
    static func mono(count: Int) -> [Float] {
        let n = Float(count)
        return (0..<count).map { (i: Int) -> Float in
            let t = Float(i) / n
            let a: Float = 0.5 * sinf(2 * .pi * 5 * t)
            let b: Float = 0.2 * sinf(2 * .pi * 13 * t)
            return a + b
        }
    }

    /// Left and right sines with a quarter-period offset (a tilted ellipse), interleaved.
    static func stereo(frames: Int) -> [Float] {
        let n = Float(frames)
        var out: [Float] = []
        out.reserveCapacity(frames * 2)
        for i in 0..<frames {
            let t = Float(i) / n
            out.append(0.7 * sinf(2 * .pi * 3 * t))
            out.append(0.5 * sinf(2 * .pi * 3 * t + .pi / 2))
        }
        return out
    }

    /// SplitMix64 → a Float in 0..<1.
    private static func unitFloat(_ state: inout UInt64) -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }
}
