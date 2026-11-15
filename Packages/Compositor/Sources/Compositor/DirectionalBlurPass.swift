// DirectionalBlurPass.swift — FX-007 "Directional blur" on the GPU (specs/295-fx-007-directional-blur,
// contracts/directional-blur.md C1, C2, research FX-007-D1 to D4; ADR-0106).
//
// One full-screen pass `cmp_directional_blur` while the blur is active: it reads its input (the composite, or the
// output of the effect before it) and writes one pooled picture (composite size, `rgba16Float`), which the next
// effect, the flash guard and every output read. Its source is a module constant spliced after
// `CompositorShaders.source` at the compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed in
// `CompositorShaderSources.archived`. The picture is taken from the pool on the first active frame at a size and
// returned (fenced by the last command buffer) when the blur turns inactive, at a size change and with the
// compositor. Per frame only Metal's own command objects are created; the 80-byte block is copied by
// `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class DirectionalBlurPass {
    /// `cmp_directional_blur` (the same maths as `DirectionalBlur.referencePixel`, with hardware linear filtering).
    static let source = """

    struct CMPDirBlur { float2 step; float2 start; float4 weights[4]; };

    // FX-007: the fixed tap budget; every pixel reads exactly this many samples at every radius.
    constant uint cmp_dirblur_taps = 16;

    // FX-007: 16 filtered samples evenly from −radius to +radius along the axis, positions clamped to the frame's pixel
    // centres, fixed Gaussian weights summing to 1. A non-finite own pixel passes through (FX-002 then counts it);
    // non-finite samples are skipped and the weights renormalised, so they never spread.
    fragment float4 cmp_directional_blur(FullScreenOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                         constant CMPDirBlur &b [[buffer(0)]]) {
        constexpr sampler linearClamp(coord::pixel, filter::linear, address::clamp_to_edge);
        uint2 p = uint2(in.position.xy);
        float4 own = source.read(p);
        if (any(isnan(own) || isinf(own))) return own;
        float2 last = float2(float(source.get_width()) - 1.0, float(source.get_height()) - 1.0);
        float2 q = float2(p);
        float4 sum = float4(0.0);
        float total = 0.0;
        for (uint i = 0; i < cmp_dirblur_taps; i++) {
            float2 position = clamp(q + (b.start + float(i) * b.step), float2(0.0), last);
            float4 s = source.sample(linearClamp, position + 0.5);
            if (any(isnan(s) || isinf(s))) continue;
            float w = b.weights[i / 4][i % 4];
            sum += w * s;
            total += w;
        }
        return total > 0.0 ? sum / total : own;
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_directional_blur"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-007 directional blur")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the blur of `input` with `blur`; returns it (owned by this pass, valid in `commandBuffer` until the next
    /// frame), nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, blur: DirectionalBlur, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-007 directional blur"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-007 directional blur"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var block: DirectionalBlur.Block = blur.block(width: input.width, height: input.height)
        encoder.setFragmentBytes(&block, length: MemoryLayout<DirectionalBlur.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
