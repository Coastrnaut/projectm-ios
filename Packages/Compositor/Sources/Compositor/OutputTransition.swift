// OutputTransition.swift — a frozen-frame scene transition in the compositor's own output path (XFADE-R2 to R7;
// specs/167-cue-transitions-on-screen).
//
// A cue that changes the scene freezes the shown frame of the compositor on screen (`Compositor.freezeShownFrame`: one
// pooled `rgba16Float` copy of the texture its flash guard and output pass last used) and starts the transition on the
// compositor shown after the change (`beginOutputTransition`; the same compositor or another one on the same device and
// pool). Per frame the shown texture is then the frozen frame at progress 0, the CMP-014 mix of the frozen and the live
// frame in between (into one pooled blend target), and the live frame alone from progress 1, when both textures go back
// to the pool. CMP-014's pieces are reused exactly: `SceneTransitionClock` (frame presentation times),
// `SceneTransitionMix.weights` and the bus's weighted-sum formula (ADR-0042). The flash guard, output pass,
// `encodeOutput` and frame capture run on the shown texture, so they all see the blend (XFADE-R3).
// Cross-queue safety: the copy signals a Metal event that every transition frame waits for, and the copy's command
// buffer fences the outgoing compositor's pictures in the pool.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

/// A copy of a compositor's last shown frame, waiting to be blended out (XFADE). Released to its pool exactly once:
/// by the compositor that used it, or in `deinit` (fenced by its copy) when no transition took it.
public final class FrozenOutputFrame {
    public let texture: MTLTexture
    let pool: TexturePool
    let event: MTLEvent
    static let signalValue: UInt64 = 1
    private let copy: MTLCommandBuffer
    private var released = false

    init(texture: MTLTexture, pool: TexturePool, event: MTLEvent, copy: MTLCommandBuffer) {
        self.texture = texture
        self.pool = pool
        self.event = event
        self.copy = copy
    }

    public var width: Int { texture.width }
    public var height: Int { texture.height }

    /// Back to the pool once `fence` (and the copy) completed.
    func release(after fence: MTLCommandBuffer?) {
        guard !released else { return }
        released = true
        pool.recycle(texture, after: fence ?? copy)
    }

    deinit { release(after: nil) }
}

/// The running frozen-frame transition of one compositor (internal; `Compositor` drives it).
final class OutputTransitionPass {
    private let device: MTLDevice
    private var pipeline: MTLRenderPipelineState?
    private(set) var frozen: FrozenOutputFrame?
    private(set) var clock: SceneTransitionClock?
    private(set) var spec: SceneTransitionSpec?
    private var blendTarget: MTLTexture?
    /// Frames drawn through the mix pass so far, and transitions started (tests, diagnostics).
    private(set) var blendedFrames = 0
    private(set) var started = 0
    /// The raw clock progress of the last frame (1 with no transition).
    private(set) var lastProgress = 1.0

    init(device: MTLDevice) { self.device = device }

    var isActive: Bool { frozen != nil }
    var holdsTextures: Bool { frozen != nil || blendTarget != nil }

    /// The bus's mix (`SceneTransitionBus.mixSource`) with its own full-screen triangle, built at the first transition.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct XfadeOut { float4 position [[position]]; };
    vertex XfadeOut cmp_xfade_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        XfadeOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }
    fragment float4 cmp_xfade_mix(XfadeOut in [[stage_in]], texture2d<float, access::read> outgoing [[texture(0)]],
                                  texture2d<float, access::read> incoming [[texture(1)]], constant float2 &w [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        return outgoing.read(p) * w.x + incoming.read(p) * w.y;
    }
    """

    private func mixPipeline() -> MTLRenderPipelineState? {
        if let pipeline { return pipeline }
        guard let library = try? CompositorShaders.library(device: device, source: Self.source),
              let vertex = try? CompositorShaders.function(library, "cmp_xfade_fullscreen"),
              let fragment = try? CompositorShaders.function(library, "cmp_xfade_mix"),
              let made = try? CompositorShaders.pipeline(device: device, vertex: vertex, fragment: fragment,
                                                         format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                         label: "XFADE transition mix") else { return nil }
        pipeline = made
        return made
    }

    /// Starts (or restarts) a transition from `frame` with a non-instant resolved `spec`.
    func begin(_ frame: FrozenOutputFrame, spec: SceneTransitionSpec, pool: TexturePool, fence: MTLCommandBuffer?) {
        end(pool: pool, fence: fence)
        frozen = frame
        self.spec = spec
        clock = SceneTransitionClock(spec: spec)
        started += 1
        lastProgress = 0
    }

    /// Releases the frozen frame and the blend target (fenced by `fence`).
    func end(pool: TexturePool, fence: MTLCommandBuffer?) {
        frozen?.release(after: fence)
        frozen = nil
        clock = nil
        spec = nil
        if let blendTarget { pool.recycle(blendTarget, after: fence) }
        blendTarget = nil
    }

    /// The texture to show this frame for the live frame `live`. Ends the transition (returning `live`) at progress 1,
    /// on a size change and when the mix cannot be encoded, so a failure degrades to a cut.
    func shown(live: MTLTexture, commandBuffer: MTLCommandBuffer, presentationTimeNanoseconds: UInt64, pool: TexturePool,
               fence: MTLCommandBuffer?) -> MTLTexture {
        guard let frame = frozen, var running = clock, let spec else { return live }
        guard frame.width == live.width, frame.height == live.height else {
            lastProgress = 1
            end(pool: pool, fence: fence)
            return live
        }
        let progress: Double = running.advance(presentationTimeNanoseconds: presentationTimeNanoseconds)
        clock = running
        lastProgress = progress
        if progress >= 1 {
            end(pool: pool, fence: fence)   // the live scene alone from this frame
            return live
        }
        commandBuffer.encodeWaitForEvent(frame.event, value: FrozenOutputFrame.signalValue)
        if progress <= 0 { return frame.texture }   // the exact start: the outgoing frame alone
        let weights: SceneTransitionWeights = SceneTransitionMix.weights(style: spec.style, eased: running.easedProgress)
        guard let mixed = encodeMix(frame.texture, live, weights: weights, commandBuffer: commandBuffer, pool: pool) else {
            end(pool: pool, fence: fence)
            return live
        }
        blendedFrames += 1
        return mixed
    }

    private func encodeMix(_ a: MTLTexture, _ b: MTLTexture, weights: SceneTransitionWeights, commandBuffer: MTLCommandBuffer,
                           pool: TexturePool) -> MTLTexture? {
        guard let pipeline = mixPipeline(), let size = LayerPictureDescriptor(width: b.width, height: b.height) else { return nil }
        if blendTarget == nil {
            guard let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "XFADE blend target"
            blendTarget = made
        }
        guard let target = blendTarget else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "XFADE transition mix"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(a, index: 0)
        encoder.setFragmentTexture(b, index: 1)
        var w = SIMD2<Float>(weights.outgoing, weights.incoming)
        encoder.setFragmentBytes(&w, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return target
    }
}
#endif
