// ScanlinesPass.swift — FX-018 "Scanline texture" on the GPU (specs/312-fx-018-scanline-texture,
// contracts/scanlines.md C1, C2, research FX-018-D1 to D5; ADR-0123).
//
// One full-screen pass `cmp_scanlines` while the scanlines are active: it reads its input (the composite, or the
// output of the effect before it) once per pixel and writes one pooled picture (composite size, `rgba16Float`), which
// the next effect, the flash guard and every output read. Per pixel: one exact read, an integer modulo and at most one
// multiply, no loop (FX-018-R6). Its source is a module constant spliced after `PixelSortPass.source` (FX-011) at the
// compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed in `CompositorShaderSources.archived`.
// The picture is taken from the pool on the first active frame at a size and returned (fenced by the last command
// buffer) when the effect turns inactive, at a size change and with the compositor. Per frame only Metal's own command
// objects are created; the 16-byte block is copied by `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class ScanlinesPass {
    /// `cmp_scanlines` (the same rule as `Scanlines.isDark` and `referencePixel`).
    static let source = """

    struct CMPScanlines { uint period; uint thickness; uint vertical; float factor; };

    // FX-018: rows (columns) with index mod period < thickness, counted from the picture's top-left pixel, are
    // multiplied by one factor; every other pixel is returned as read (bit-identical). No time input.
    fragment float4 cmp_scanlines(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                                  constant CMPScanlines &c [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float4 v = source.read(p);
        uint index = c.vertical != 0 ? p.x : p.y;
        if (index % c.period >= c.thickness) { return v; }
        return float4(v.rgb * c.factor, v.a);
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_scanlines"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-018 scanlines")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the scanlines of `input` with `block`; returns the result (owned by this pass, valid in `commandBuffer`
    /// until the next frame), nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, block: Scanlines.Block, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-018 scanlines"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-018 scanlines"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var bytes: Scanlines.Block = block
        encoder.setFragmentBytes(&bytes, length: MemoryLayout<Scanlines.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
