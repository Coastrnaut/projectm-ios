// FilmGrainPass.swift — FX-017 "Film grain" on the GPU (specs/311-fx-017-film-grain, contracts/film-grain.md C1, C2,
// research FX-017-D1 to D5; ADR-0122).
//
// One full-screen pass `cmp_film_grain` while the grain is active: it reads its input (the composite, or the output of
// the effect before it) once per pixel, hashes at most three channels and writes one pooled picture (composite size,
// `rgba16Float`), which the flash guard and every output read. Its source is a module constant spliced after
// `VignettePass.source` at the compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed in
// `CompositorShaderSources.archived`. The picture is taken from the pool on the first active frame at a size and
// returned (fenced by the last command buffer) when the grain turns inactive, at a size change and with the compositor.
// Per frame only Metal's own command objects are created; the 32-byte block is copied by `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class FilmGrainPass {
    /// `cmp_pcg`, `cmp_grain_hash`, `cmp_grain_noise` (the same integer steps as `FilmGrain.pcg`, `hash`, `noise`) and
    /// `cmp_film_grain`: one exact read per pixel, colour + (scale × n) × alpha with the zero floor, alpha kept.
    static let source = """

    struct CMPFilmGrain { float scale; uint size; uint seed; uint frame; uint channels; uint pad0; uint pad1; uint pad2; };

    // FX-017: the PCG hash (Jarzynski and Olano), 32-bit wrapping; integer only, so every GPU gives the same value.
    static inline uint cmp_pcg(uint v) {
        uint state = v * 747796405u + 2891336453u;
        uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
        return (word >> 22u) ^ word;
    }

    static inline uint cmp_grain_hash(uint cx, uint cy, uint seed, uint frame, uint channel) {
        uint a = cmp_pcg(seed * 4u + channel);
        uint b = cmp_pcg(frame + a);
        uint c = cmp_pcg(cy + b);
        return cmp_pcg(cx + c);
    }

    // 24 bits → a multiple of 2^-23 in [-1, 1), exact in float.
    static inline float cmp_grain_noise(uint h) {
        return float(h >> 8u) * 0x1p-23f - 1.0;
    }

    fragment float4 cmp_film_grain(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                                   constant CMPFilmGrain &c [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float4 v = source.read(p);
        if (c.scale == 0.0) { return v; }
        uint s = max(c.size, 1u);
        uint cx = p.x / s;
        uint cy = p.y / s;
        float nr = cmp_grain_noise(cmp_grain_hash(cx, cy, c.seed, c.frame, 0u));
        float ng = nr;
        float nb = nr;
        if (c.channels == 3u) {
            ng = cmp_grain_noise(cmp_grain_hash(cx, cy, c.seed, c.frame, 1u));
            nb = cmp_grain_noise(cmp_grain_hash(cx, cy, c.seed, c.frame, 2u));
        }
        float3 d = float3(c.scale * nr * v.a, c.scale * ng * v.a, c.scale * nb * v.a);
        return float4(max(v.rgb + d, min(v.rgb, float3(0.0))), v.a);
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, frames drawn and the last grain frame used (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0
    private(set) var lastGrainFrame: UInt32 = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_film_grain"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-017 film grain")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the grain over `input`; returns it (owned by this pass, valid in `commandBuffer` until the next frame),
    /// nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, block: FilmGrain.Block, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-017 film grain"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-017 film grain"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var copy: FilmGrain.Block = block
        encoder.setFragmentBytes(&copy, length: MemoryLayout<FilmGrain.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        lastGrainFrame = block.frame
        return output
    }
}
#endif
