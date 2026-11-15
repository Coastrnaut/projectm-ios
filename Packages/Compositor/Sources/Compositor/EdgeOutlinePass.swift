// EdgeOutlinePass.swift — FX-014 "Edge outline" on the GPU (specs/303-fx-014-edge-outline, contracts/edge-outline.md
// C1, C2, research FX-014-D1 to D5; ADR-0114).
//
// One full-screen pass `cmp_edge_outline` while the outline is active: it reads its input (the composite, or the
// output of the effect before it) at nine clamped places per pixel and writes one pooled picture (composite size,
// `rgba16Float`), which the next effect, the flash guard and every output read. Its source is a module constant
// spliced after `MosaicPass.source` at the compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed
// in `CompositorShaderSources.archived`. The picture is taken from the pool on the first active frame at a size and
// returned (fenced by the last command buffer) when the outline turns inactive, at a size change and with the
// compositor. Per frame only Metal's own command objects are created; the 48-byte block is copied by
// `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class EdgeOutlinePass {
    /// `cmp_edge_outline` (the same maths as `EdgeOutline.reference`).
    static let source = """

    struct CMPEdgeOutline { float4 colour; uint2 last; float threshold; uint width; uint mode; };

    // FX-014: Rec. 709 linear luminance of the pixel at `p + d * width`, clamped to the frame.
    static float cmp_edge_lum(texture2d<float, access::read> source, int2 p, int2 d, constant CMPEdgeOutline &c) {
        int2 q = clamp(p + d * int(c.width), int2(0), int2(c.last));
        float4 v = source.read(uint2(q));
        return 0.2126 * v.r + 0.7152 * v.g + 0.0722 * v.b;
    }

    // FX-014: 3 x 3 Sobel at a tap distance of `width`; strength = |G| / 4; mask = smoothstep(t, t + 0.1, strength),
    // 0 at or below the threshold and where the strength is not finite. Overlay keeps the input pixel exactly where
    // the mask is 0; outline only draws on opaque black.
    fragment float4 cmp_edge_outline(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                                     constant CMPEdgeOutline &c [[buffer(0)]]) {
        int2 p = int2(in.position.xy);
        float tl = cmp_edge_lum(source, p, int2(-1, -1), c);
        float tm = cmp_edge_lum(source, p, int2(0, -1), c);
        float tr = cmp_edge_lum(source, p, int2(1, -1), c);
        float ml = cmp_edge_lum(source, p, int2(-1, 0), c);
        float mr = cmp_edge_lum(source, p, int2(1, 0), c);
        float bl = cmp_edge_lum(source, p, int2(-1, 1), c);
        float bm = cmp_edge_lum(source, p, int2(0, 1), c);
        float br = cmp_edge_lum(source, p, int2(1, 1), c);
        float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
        float gy = (bl + 2.0 * bm + br) - (tl + 2.0 * tm + tr);
        float e = sqrt(gx * gx + gy * gy) * 0.25;
        float4 base = c.mode == 1u ? float4(0.0, 0.0, 0.0, 1.0) : source.read(uint2(p));
        if (!isfinite(e) || !(e > c.threshold)) {
            return base;
        }
        float m = smoothstep(c.threshold, c.threshold + \(EdgeOutline.softBand), e);
        if (!(m > 0.0)) {
            return base;
        }
        return mix(base, c.colour, m);
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_edge_outline"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-014 edge outline")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the outline of `input`; returns it (owned by this pass, valid in `commandBuffer` until the next frame),
    /// nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, outline: EdgeOutline, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-014 edge outline"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-014 edge outline"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var block: EdgeOutline.Block = outline.block(width: input.width, height: input.height)
        encoder.setFragmentBytes(&block, length: MemoryLayout<EdgeOutline.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
