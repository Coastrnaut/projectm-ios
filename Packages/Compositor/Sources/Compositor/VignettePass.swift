// VignettePass.swift — FX-015 "Vignette" on the GPU (specs/305-fx-015-vignette, contracts/vignette.md C1, C2,
// research FX-015-D1 to D5; ADR-0116).
//
// One full-screen pass `cmp_vignette` while the vignette is active: it reads its input (the composite, or the output
// of the effect before it) once per pixel and writes one pooled picture (composite size, `rgba16Float`), which the next
// effect, the flash guard and every output read. Its source is a module constant spliced after `MosaicPass.source` at
// the compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed in `CompositorShaderSources.archived`.
// The picture is taken from the pool on the first active frame at a size and returned (fenced by the last command
// buffer) when the vignette turns inactive, at a size change and with the compositor. Per frame only Metal's own
// command objects are created; the 32-byte block is copied by `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class VignettePass {
    /// `cmp_vignette` (the same steps as `Vignette.factor`): one exact read per pixel, colour × (1 − intensity × w).
    static let source = """

    struct CMPVignette { float2 centre; float2 scale; float inner; float softness; float intensity; float pad; };

    // FX-015: an ellipse following the frame (corners at distance 1 from the middle); smoothstep weight from
    // 1 − softness to 1, written out like `Vignette.weight`; alpha kept. The factor is exactly 1 in the clear core.
    fragment float4 cmp_vignette(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                                 constant CMPVignette &c [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float4 v = source.read(p);
        float dx = (float(p.x) + 0.5 - c.centre.x) * c.scale.x;
        float dy = (float(p.y) + 0.5 - c.centre.y) * c.scale.y;
        float d = sqrt(dx * dx + dy * dy);
        float t = clamp((d - c.inner) / c.softness, 0.0, 1.0);
        float w = t * t * (3.0 - 2.0 * t);
        float f = 1.0 - c.intensity * w;
        return float4(v.rgb * f, v.a);
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_vignette"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-015 vignette")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the vignette of `input`; returns it (owned by this pass, valid in `commandBuffer` until the next
    /// frame), nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, vignette: Vignette, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-015 vignette"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-015 vignette"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var block: Vignette.Block = vignette.block(width: input.width, height: input.height)
        encoder.setFragmentBytes(&block, length: MemoryLayout<Vignette.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
