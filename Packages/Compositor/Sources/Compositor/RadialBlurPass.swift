// RadialBlurPass.swift — FX-008 "Radial blur" on the GPU (specs/296-fx-008-radial-blur, contracts/radial-blur.md C1,
// C2, research FX-008-D1 to D4, D7; ADR-0107).
//
// One full-screen pass `cmp_radial_blur` while the blur is active: it reads its input (the composite, or the output of
// the effect before it) and writes one pooled picture (composite size, `rgba16Float`), which the next effect, the flash
// guard and every output read. Its source is a module constant spliced after `ChromaticSplitPass.source` at the
// compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed in `CompositorShaderSources.archived`.
// The picture is taken from the pool on the first active frame at a size and returned (fenced by the last command
// buffer) when the blur turns inactive, at a size change and with the compositor. Per frame only Metal's own command
// objects are created; the 24-byte block is copied by `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class RadialBlurPass {
    /// `cmp_radial_blur` (the same maths as `RadialBlur.referencePixel`, with the GPU's linear filter).
    static let source = """

    struct CMPRadialBlur { float2 focus; float2 last; float strength; };

    // FX-008: the mean of \(RadialBlur.tapCount) samples (a fixed budget) at F + (P − F) ÷ (1 + s·k/\(RadialBlur.tapCount - 1)), sample 0 the
    // pixel itself; every position lies between P and the focus and is clamped to the frame as well. The focus pixel
    // (zero spread) and a non-finite pixel pass through bit for bit.
    fragment float4 cmp_radial_blur(FullScreenOut in [[stage_in]], texture2d<float, access::sample> source [[texture(0)]],
                                    constant CMPRadialBlur &c [[buffer(0)]]) {
        constexpr sampler linearPixels(coord::pixel, address::clamp_to_edge, filter::linear);
        uint2 p = uint2(in.position.xy);
        float4 own = source.read(p);
        if (any(isnan(own) || isinf(own))) return own;
        float2 d = float2(p) - c.focus;
        if (all(d == float2(0.0)) || c.strength == 0.0) return own;
        float4 sum = own;
        for (int k = 1; k < \(RadialBlur.tapCount); ++k) {
            float2 q = c.focus + d * (1.0 / (1.0 + c.strength * float(k) / \(RadialBlur.tapCount - 1).0));
            q = clamp(q, float2(0.0), c.last);
            sum += source.sample(linearPixels, q + 0.5);
        }
        return sum * (1.0 / \(RadialBlur.tapCount).0);
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_radial_blur"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-008 radial blur")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the blur of `input` with `blur`; returns it (owned by this pass, valid in `commandBuffer` until the next
    /// frame), nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, blur: RadialBlur, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-008 radial blur"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-008 radial blur"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var block: RadialBlur.Block = blur.block(width: input.width, height: input.height)
        encoder.setFragmentBytes(&block, length: MemoryLayout<RadialBlur.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
