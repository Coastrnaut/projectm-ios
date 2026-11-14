// MotionFeedbackPass.swift — FX-009 "Trails" on the GPU (contracts/motion-feedback.md in specs/130, research FX-009-D1,
// D3, D4, D7; ADR-0051).
//
// One full-screen pass `cmp_trails` per frame while Trails are active: it reads the finished composite and the history
// (the previous trails frame) and writes the other picture of a pooled ping-pong pair (composite size, `rgba16Float`);
// the two then swap, so the frame just written is the next frame's history. The compositor hands that frame to the
// flash guard and the output pass (and `encodeScene` to CMP-014's bus), so safety and every output see the trails.
// A reset frame (`resetPending`) writes the composite unchanged — a half-float read and write of the same format is
// exact — so it is bit-identical to Trails off and the history restarts from the new scene. Inactive Trails hold no
// picture: the pair is taken from the pool on the first active frame at a size and returned (fenced by the last
// command buffer) when Trails turn inactive, at a size change and when the compositor is released. Per frame only
// Metal's own command objects are created; the 16-byte block is copied by `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class TrailsPass {
    /// `cmp_trails` (spliced after `CompositorShaders.source`; research FX-009-D1, D4).
    static let source = """

    struct CMPTrails { float decay; uint reset; uint pad0; uint pad1; };

    // FX-009: out = composite on a reset frame or for a non-finite composite pixel (FX-002's output pass then maps it to 0
    // and counts it, as without Trails); else max(composite, decay × history) per channel, premultiplied alpha included,
    // with the history sanitised (NaN/±Inf → 0, ≥ 0, alpha ≤ 1) so nothing non-finite spreads into later frames.
    fragment float4 cmp_trails(FullScreenOut in [[stage_in]], texture2d<float, access::read> composite [[texture(0)]],
                               texture2d<float, access::read> history [[texture(1)]], constant CMPTrails &t [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float4 c = composite.read(p);
        if (t.reset != 0u || any(isnan(c) || isinf(c))) return c;
        float4 h = history.read(p);
        h = select(h, float4(0.0), isnan(h) || isinf(h));
        h = max(h, float4(0.0));
        h.a = min(h.a, 1.0);
        return max(c, clamp(t.decay, 0.0, 1.0) * h);
    }
    """

    /// `CMPTrails` in the shader (16 bytes).
    struct Block {
        var decay: Float
        var reset: UInt32
        var pad0: UInt32 = 0
        var pad1: UInt32 = 0
    }

    private let pipeline: MTLRenderPipelineState
    /// The last trails frame (nil while inactive or before the first active frame at a size).
    private var history: MTLTexture?
    /// The picture the next frame writes.
    private var target: MTLTexture?
    /// The next frame writes the composite only (a scene change, a new size, Trails turned on).
    var resetPending = true
    /// Frames drawn through the pass, and reset frames among them (tests, diagnostics).
    private(set) var frames = 0
    private(set) var resets = 0
    /// Pictures taken from the pool so far (the compositor adds them to `pictureAllocations`).
    private(set) var allocations = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_trails"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-009 trails")
    }

    var holdsPictures: Bool { history != nil || target != nil }

    /// Both pictures back to the pool, reusable once `fence` completed; the next active frame starts clean.
    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let history { pool.recycle(history, after: fence) }
        if let target { pool.recycle(target, after: fence) }
        history = nil
        target = nil
        resetPending = true
    }

    /// Encodes one trails frame of `composite` with `decay`; returns it (owned by this pass, valid in `commandBuffer`
    /// until the next frame), nil when a picture or the encoder cannot be created.
    func encode(composite: MTLTexture, decay: Double, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard preparePair(like: composite, pool: pool, fence: fence), let output = target else { return nil }
        let reset: Bool = resetPending || history == nil
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = reset ? "FX-009 trails (reset)" : "FX-009 trails"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.setFragmentTexture(reset ? composite : history, index: 1)
        var block = Block(decay: reset ? 0 : Float(decay), reset: reset ? 1 : 0)
        encoder.setFragmentBytes(&block, length: MemoryLayout<Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        if reset { resets += 1 }
        resetPending = false
        target = history   // swap: the frame just written is the next history
        history = output
        return output
    }

    /// Takes the pair from the pool when missing or of another size (an allocation point).
    private func preparePair(like composite: MTLTexture, pool: TexturePool, fence: MTLCommandBuffer?) -> Bool {
        if let current = history ?? target, current.width != composite.width || current.height != composite.height {
            release(to: pool, after: fence)
        }
        guard let size = LayerPictureDescriptor(width: composite.width, height: composite.height) else { return false }
        if history == nil {   // first frame at this size: history is filled by this frame's reset write
            guard let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return false }
            made.label = "FX-009 trails A"
            history = made
            allocations += 1
            resetPending = true
        }
        if target == nil {
            guard let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return false }
            made.label = "FX-009 trails B"
            target = made
            allocations += 1
        }
        return true
    }
}
#endif
