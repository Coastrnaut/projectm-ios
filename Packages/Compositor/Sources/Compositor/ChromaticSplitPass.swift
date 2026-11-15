// ChromaticSplitPass.swift — FX-006 "Chromatic split" on the GPU (specs/293-fx-006-chromatic-split,
// contracts/chromatic-split.md C1, C2, research FX-006-D1 to D4, D7; ADR-0104).
//
// One full-screen pass `cmp_chromatic` while the split is active: it reads its input (the composite, or the output of
// the effect before it) and writes one pooled picture (composite size, `rgba16Float`), which the next effect, the
// flash guard and every output read. Its source is a module constant spliced after `CompositorShaders.source` at the
// compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed in `CompositorShaderSources.archived`.
// The picture is taken from the pool on the first active frame at a size and returned (fenced by the last command
// buffer) when the split turns inactive, at a size change and with the compositor. Per frame only Metal's own command
// objects are created; the 32-byte block is copied by `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class ChromaticSplitPass {
    /// `cmp_chromatic` (the same maths as `ChromaticSplit.referencePixel`).
    static let source = """

    struct CMPChromatic { float2 linear; float2 centre; float amountPx; float band; float invRadius; uint radial; };

    // FX-006: `a` when the weight is exactly 0, so a whole-pixel distance copies values and a non-finite neighbour
    // cannot leak in through 0 × Inf.
    static float4 cmp_chroma_lerp(float4 a, float4 b, float t) { return t == 0.0 ? a : a + t * (b - a); }

    // Bilinear from `read`, every texel index clamped to the frame.
    static float4 cmp_chroma_sample(texture2d<float, access::read> t, float2 p, float2 last) {
        p = clamp(p, float2(0.0), last);
        float2 f0 = floor(p);
        float2 f = p - f0;
        uint2 a = uint2(f0);
        uint2 b = uint2(min(f0 + 1.0, last));
        float4 top = cmp_chroma_lerp(t.read(uint2(a.x, a.y)), t.read(uint2(b.x, a.y)), f.x);
        float4 bottom = cmp_chroma_lerp(t.read(uint2(a.x, b.y)), t.read(uint2(b.x, b.y)), f.x);
        return cmp_chroma_lerp(top, bottom, f.y);
    }

    // FX-006: red read at p − v, blue at p + v, green and the pixel's own value at p; v fades to 0 at the border, so the
    // outer ring and the radial centre pass through unchanged, as does a non-finite pixel (FX-002 then counts it).
    fragment float4 cmp_chromatic(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                                  constant CMPChromatic &c [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float4 own = source.read(p);
        if (any(isnan(own) || isinf(own))) return own;
        float2 last = float2(float(source.get_width()) - 1.0, float(source.get_height()) - 1.0);
        float2 q = float2(p);
        float2 v = c.linear;
        if (c.radial != 0u) v = c.amountPx * (q - c.centre) * c.invRadius;
        float e = min(min(q.x, last.x - q.x), min(q.y, last.y - q.y));
        v *= clamp(e / c.band, 0.0, 1.0);
        if (all(v == float2(0.0))) return own;
        float4 r = cmp_chroma_sample(source, q - v, last);
        float4 b = cmp_chroma_sample(source, q + v, last);
        return float4(r.r, own.g, b.b, max(own.a, max(r.a, b.a)));
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_chromatic"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-006 chromatic split")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the split of `input` with `split`; returns it (owned by this pass, valid in `commandBuffer` until the next
    /// frame), nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, split: ChromaticSplit, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-006 chromatic split"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-006 chromatic split"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var block: ChromaticSplit.Block = split.block(width: input.width, height: input.height)
        encoder.setFragmentBytes(&block, length: MemoryLayout<ChromaticSplit.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
