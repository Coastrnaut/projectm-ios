// ParticleTrailPass.swift — VIS-010 particle trails on Metal (contracts/particle-trails.md C2, C3; research VIS-010-D1,
// D4 to D7).
//
// Two private `rgba16Float` textures of 512 × 512, made once when the pass is made (the generator makes it on its first
// frame with trails on) and never recreated, resized or freed while the generator lives: their count, identities and
// allocated size are constant whatever the output size or setting (the roadmap row's acceptance). Per frame:
//   1. into the other texture: the newest one decayed (`vis_trail_decay`: cut(min(d · prev, 0.8))), then the frame's
//      particle squares with max blending (`vis_trail_stamp`, capped at 0.8) — FX-009's rule;
//   2. into the target (`FlatShapePass`'s pass): clear to the background, the newest texture before this frame sampled
//      across the whole output, decayed and × gain (`vis_trail_present`, premultiplied "over"), then the particles.
// A reset (first use, `reset()`, an output size change, trails turned on again) clears the next texture and shows no
// trail. The pipelines come from `FlatShapePass`'s library (its module constant includes `ParticleTrailShader`), through
// PERF-009's archive: no new compile site (SHD-011). Uniforms go by `setFragmentBytes` from a stack value; nothing is
// allocated per frame. Not Sendable: one thread.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal

public final class ParticleTrailPass {
    public static let accumulationFormat: MTLPixelFormat = .rgba16Float

    /// The fixed pair (tests: identities and `allocatedSize` never change).
    public let textures: [MTLTexture]
    /// VIS-010-R7: the trail's light bound for the envelope.
    public let flashBound = ParticleTrailFlashBound()
    /// Index of the texture holding the newest accumulation.
    public private(set) var newest = 0
    /// The next frame starts without a trail.
    public private(set) var needsReset = true
    /// Frames drawn with a trail shown (tests).
    public private(set) var framesWithTrail = 0
    private var lastWidth = -1
    private var lastHeight = -1

    private let decayPipeline: MTLRenderPipelineState
    private let stampPipeline: MTLRenderPipelineState
    private let presentPipeline: MTLRenderPipelineState
    private let accumulation = MTLRenderPassDescriptor()

    /// Total bytes the pair holds.
    public var allocatedBytes: Int { textures.reduce(0) { (sum: Int, t: MTLTexture) -> Int in sum + t.allocatedSize } }

    init(device: MTLDevice, library: MTLLibrary, targetFormat: MTLPixelFormat, label: String) throws(VisualGeneratorError) {
        let side: Int = ParticleTrails.textureSide
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.accumulationFormat, width: side, height: side, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        var made: [MTLTexture] = []
        for i in 0..<2 {
            guard let t = device.makeTexture(descriptor: d) else { throw .pipelineUnavailable("trail texture \(i)") }
            t.label = "\(label) trail \(i)"
            made.append(t)
        }
        textures = made
        decayPipeline = try Self.pipeline(device: device, library: library, vertex: "vis_trail_vertex", fragment: "vis_trail_decay",
                                          format: Self.accumulationFormat, blend: .none, label: "\(label) trail decay")
        stampPipeline = try Self.pipeline(device: device, library: library, vertex: "vis_flat_vertex", fragment: "vis_trail_stamp",
                                          format: Self.accumulationFormat, blend: .maximum, label: "\(label) trail stamp")
        presentPipeline = try Self.pipeline(device: device, library: library, vertex: "vis_trail_vertex", fragment: "vis_trail_present",
                                            format: targetFormat, blend: .over, label: "\(label) trail present")
        accumulation.colorAttachments[0].storeAction = .store
        accumulation.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }

    enum Blend { case none, maximum, over }

    private static func pipeline(device: MTLDevice, library: MTLLibrary, vertex: String, fragment: String, format: MTLPixelFormat,
                                 blend: Blend, label: String) throws(VisualGeneratorError) -> MTLRenderPipelineState {
        guard let v = library.makeFunction(name: vertex), let f = library.makeFunction(name: fragment) else {
            throw .pipelineUnavailable("trail shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = v
        descriptor.fragmentFunction = f
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = format
        switch blend {
        case .none:
            attachment.isBlendingEnabled = false
        case .maximum:   // FX-009: max(particle, decayed history), alpha included
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .max
            attachment.alphaBlendOperation = .max
        case .over:   // premultiplied "over", as FlatShapePass
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        do {
            return try NativePipelineArchive.makeRenderPipelineState(device: device, descriptor: descriptor)   // PERF-009
        } catch {
            throw .pipelineUnavailable("trail pipeline: \(error.localizedDescription)")
        }
    }

    /// The next frame starts without a trail (loop restart, trails turned off); storage kept.
    public func reset() {
        needsReset = true
        flashBound.reset()
    }

    /// The gain for this frame: the envelope over the particles at gain g plus g × the shown trail (VIS-010-R7).
    func gain<Source: FlashAreaLevelSource, Transfer: FrameLuminanceTransfer>(layout: Source, transfer: Transfer, limiter: FlashSafetyLimiter,
                                                                            decay: Double, width: Int, height: Int,
                                                                            context: VisualFrameContext) -> Float {
        if width != lastWidth || height != lastHeight { reset() }   // the size check runs again in encode (no-op then)
        return flashBound.gain(layout: layout, transfer: transfer, limiter: limiter, decay: decay, showsTrail: !needsReset,
                               frameTime: context.frameDuration, configuration: context.flashConfiguration)
    }

    /// After the frame: the bound takes the particles drawn at `gain`.
    func recordFrame<Source: FlashAreaLevelSource, Transfer: FrameLuminanceTransfer>(layout: Source, transfer: Transfer, gain: Float,
                                                                                   background: LinearColor, decay: Double) {
        flashBound.record(layout: layout, transfer: transfer, gain: gain, background: background, decay: decay)
    }

    /// Encodes the accumulation update and the target pass for `count` vertices of `shapes`' `slot`.
    func encode(shapes: FlatShapePass, slot: Int, count: Int, into target: MTLTexture, background: LinearColor,
                commandBuffer: MTLCommandBuffer, decay: Double, gain: Float) -> Bool {
        if target.width != lastWidth || target.height != lastHeight {
            lastWidth = target.width
            lastHeight = target.height
            needsReset = true   // VIS-010: a resized output starts without a trail (no stretched history)
        }
        let reset: Bool = needsReset
        let previous: MTLTexture = textures[newest]
        let next: MTLTexture = textures[1 - newest]
        var uniforms = SIMD8<Float>(Float(decay), ParticleTrails.cap, ParticleTrails.cut, gain,
                                    Float(max(target.width, 1)), Float(max(target.height, 1)), 0, 0)
        let attachment = accumulation.colorAttachments[0]!
        attachment.texture = next
        attachment.loadAction = reset ? .clear : .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: accumulation) else {
            attachment.texture = nil
            return false
        }
        encoder.label = "VIS-010 trail accumulation"
        if !reset {
            encoder.setRenderPipelineState(decayPipeline)
            encoder.setFragmentTexture(previous, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD8<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if count > 0 {
            encoder.setRenderPipelineState(stampPipeline)
            encoder.setVertexBuffer(shapes.buffer(slot), offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        encoder.endEncoding()
        attachment.texture = nil
        newest = 1 - newest
        needsReset = false
        if !reset { framesWithTrail += 1 }
        let present: MTLRenderPipelineState = presentPipeline
        return shapes.draw(slot: slot, count: count, into: target, background: background, commandBuffer: commandBuffer) {
            (encoder: MTLRenderCommandEncoder) -> Void in
            guard !reset else { return }
            encoder.setRenderPipelineState(present)
            encoder.setFragmentTexture(previous, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD8<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }
}

/// The generators' trail step (VIS-008, VIS-009): one call replaces the gain and draw of a frame when trails are on.
struct ParticleTrailFrame {
    /// Makes the pass on first use (the only allocation), computes the gain with the trail bound, tessellates and draws.
    /// Returns (drawn, gain, vertex count).
    static func encode<Source: FlashAreaLevelSource>(pass existing: ParticleTrailPass?, make: () throws(VisualGeneratorError) -> ParticleTrailPass,
                                                     store: (ParticleTrailPass) -> Void, length: ParticleTrailLength, reduceMotion: Bool,
                                                     layout: Source, background: LinearColor, limiter: FlashSafetyLimiter,
                                                     downstream: (any FrameLuminanceTransfer)?, shapes: FlatShapePass, slot: Int,
                                                     target: MTLTexture, commandBuffer: MTLCommandBuffer, context: VisualFrameContext,
                                                     tessellate: (Float) -> Int) -> (drawn: Bool, gain: Float, count: Int) {
        let pass: ParticleTrailPass
        if let existing {
            pass = existing
        } else {
            guard let made = try? make() else { return (false, 1, 0) }
            store(made)
            pass = made
        }
        let reduceFlashing: Bool = context.reduceFlashing || context.flashLimits != nil
        let h: Double = ParticleTrails.halfLife(length, reduceMotion: reduceMotion, reduceFlashing: reduceFlashing)
        let d: Double = ParticleTrails.decay(frameDuration: context.frameDuration, halfLife: h)
        let gain: Float
        if let downstream {
            gain = pass.gain(layout: layout, transfer: downstream, limiter: limiter, decay: d,
                             width: target.width, height: target.height, context: context)
        } else {
            gain = pass.gain(layout: layout, transfer: IdentityLuminanceTransfer(), limiter: limiter, decay: d,
                             width: target.width, height: target.height, context: context)
        }
        let count: Int = tessellate(gain)
        let drawn: Bool = pass.encode(shapes: shapes, slot: slot, count: count, into: target, background: background,
                                      commandBuffer: commandBuffer, decay: d, gain: gain)
        if drawn {
            if let downstream {
                pass.recordFrame(layout: layout, transfer: downstream, gain: gain, background: background, decay: d)
            } else {
                pass.recordFrame(layout: layout, transfer: IdentityLuminanceTransfer(), gain: gain, background: background, decay: d)
            }
        }
        return (drawn, gain, count)
    }
}

/// VIS-010: the trail MSL, module-authored (SHD-011), appended to `FlatShapePass.shaderSource` so it compiles at that
/// reviewed site and is part of PERF-009's archive key. Mirrored by `ParticleTrails.decayed` and `.accumulate`.
public enum ParticleTrailShader {
    public static let functions = """

    // VIS-010 particle trails. Uniforms: decay, cap, cut, gain, output size (32 bytes).
    struct TrailUniforms {
        float decay;
        float cap;
        float cut;
        float gain;
        float2 size;
        float2 unused;
    };

    struct TrailOut { float4 position [[position]]; };

    vertex TrailOut vis_trail_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        TrailOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    static float4 vis_trail_decayed(float4 v, constant TrailUniforms &u) {
        v = select(v, float4(0.0), isnan(v) || isinf(v));
        v = min(max(v, float4(0.0)) * clamp(u.decay, 0.0, 1.0), float4(u.cap));
        return select(v, float4(0.0), v < float4(u.cut));
    }

    // Accumulation: the previous texture at the same texel, decayed (same size as the target texture).
    fragment float4 vis_trail_decay(TrailOut in [[stage_in]], constant TrailUniforms &u [[buffer(0)]],
                                    texture2d<float, access::read> previous [[texture(0)]]) {
        return vis_trail_decayed(previous.read(uint2(in.position.xy)), u);
    }

    // Accumulation: a particle square (premultiplied, max-blended), never above the cap.
    fragment float4 vis_trail_stamp(SpectrumVertexOut in [[stage_in]]) {
        float4 c = select(in.color, float4(0.0), isnan(in.color) || isinf(in.color));
        return min(max(c, float4(0.0)), float4(0.8));
    }

    // Target: the previous accumulation across the whole output, decayed, × gain (premultiplied "over").
    fragment float4 vis_trail_present(TrailOut in [[stage_in]], constant TrailUniforms &u [[buffer(0)]],
                                      texture2d<float> previous [[texture(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge, coord::normalized);
        float2 uv = in.position.xy / max(u.size, float2(1.0));
        return vis_trail_decayed(previous.sample(s, uv), u) * clamp(u.gain, 0.0, 1.0);
    }
    """
}
#endif
