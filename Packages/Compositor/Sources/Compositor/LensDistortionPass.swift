// LensDistortionPass.swift — FX-016 "Lens distortion" on the GPU (specs/306-fx-016-lens-distortion,
// contracts/lens-distortion.md C1, C2, research FX-016-D1 to D5; ADR-0117).
//
// One full-screen pass `cmp_lens_distortion` while the warp is active: per output pixel it reads at most four pixels of
// its input (the composite, or the output of the effect before it), each tap clamped to the frame, and writes one pooled
// picture (composite size, `rgba16Float`), which the next effect, the flash guard and every output read. Its source is a
// module constant spliced after `EdgeOutlinePass.source` at the compositor's existing reviewed compile site (SHD-011,
// ADR-0024) and listed in `CompositorShaderSources.archived`. The picture is taken from the pool on the first active
// frame at a size and returned (fenced by the last command buffer) when the warp turns inactive, at a size change and
// with the compositor. Per frame only Metal's own command objects are created; the 32-byte block is copied by
// `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class LensDistortionPass {
    /// `cmp_lens_distortion` (the same steps as `LensDistortion.referencePixel`).
    static let source = """

    struct CMPLensDistortion { float2 centre; float2 size; float inverseRadiusSquared; float coefficient;
                               float inverseZoom; float pad; };

    // FX-016: s = centre + d × (1 + k r²) × inverseZoom; outside the picture (or NaN: every comparison fails) →
    // transparent black; on a pixel centre → that pixel exactly; else bilinear with every tap clamped to the frame.
    fragment float4 cmp_lens_distortion(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                                        constant CMPLensDistortion &c [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float2 d = (float2(p) + 0.5) - c.centre;
        float r2 = (d.x * d.x + d.y * d.y) * c.inverseRadiusSquared;
        float f = (1.0 + c.coefficient * r2) * c.inverseZoom;
        float2 s = c.centre + d * f;
        if (!(s.x >= 0.0 && s.x <= c.size.x && s.y >= 0.0 && s.y <= c.size.y)) { return float4(0.0); }
        float2 q = s - 0.5;
        float2 base = floor(q);
        float2 t = q - base;
        int2 last = int2(c.size) - 1;
        int2 b = int2(base);
        int2 i0 = clamp(b, int2(0), last);
        int2 i1 = clamp(b + 1, int2(0), last);
        if (t.x == 0.0 && t.y == 0.0) { return source.read(uint2(i0)); }
        float4 top = mix(source.read(uint2(i0.x, i0.y)), source.read(uint2(i1.x, i0.y)), t.x);
        float4 bottom = mix(source.read(uint2(i0.x, i1.y)), source.read(uint2(i1.x, i1.y)), t.x);
        return mix(top, bottom, t.y);
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_lens_distortion"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-016 lens distortion")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the warp of `input` with `block`; returns it (owned by this pass, valid in `commandBuffer` until the next
    /// frame), nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, block: LensDistortion.Block, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-016 lens distortion"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-016 lens distortion"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var bytes: LensDistortion.Block = block
        encoder.setFragmentBytes(&bytes, length: MemoryLayout<LensDistortion.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
