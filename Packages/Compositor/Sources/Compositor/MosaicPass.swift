// MosaicPass.swift — FX-012 "Mosaic pixelation" on the GPU (specs/299-fx-012-mosaic-pixelation, contracts/mosaic.md
// C1, C2, research FX-012-D1 to D4; ADR-0110).
//
// One full-screen pass `cmp_mosaic` while the mosaic is active: it reads its input (the composite, or the output of the
// effect before it) and writes one pooled picture (composite size, `rgba16Float`), which the next effect, the flash
// guard and every output read. Its source is a module constant spliced after `RadialBlurPass.source` at the
// compositor's existing reviewed compile site (SHD-011, ADR-0024) and listed in `CompositorShaderSources.archived`.
// The picture is taken from the pool on the first active frame at a size and returned (fenced by the last command
// buffer) when the mosaic turns inactive, at a size change and with the compositor. Per frame only Metal's own command
// objects are created; the 16-byte block is copied by `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class MosaicPass {
    /// `cmp_mosaic` (the same maths as `Mosaic.samplePixel`): one exact read per pixel.
    static let source = """

    struct CMPMosaic { uint size; uint shape; uint2 last; };

    // FX-012: each pixel shows its cell's centre pixel, read exactly and clamped to the frame. Squares: blocks of
    // size × size from the top-left corner. Hexagons: pointy-top, spacing `size` in a row, cell (0, 0) centred on the
    // top-left corner, nearest centre by cube rounding (the same Float steps as `Mosaic.hexCell`).
    fragment float4 cmp_mosaic(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                               constant CMPMosaic &c [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        int2 q;
        if (c.shape == 1u) {
            float n = float(c.size);
            float px = float(p.x) + 0.5;
            float py = float(p.y) + 0.5;
            float rf = (2.0 * py) / (\(Mosaic.root3) * n);
            float qf = px / n - rf * 0.5;
            float sf = -qf - rf;
            float rq = round(qf);
            float rr = round(rf);
            float rs = round(sf);
            float dq = fabs(rq - qf);
            float dr = fabs(rr - rf);
            float ds = fabs(rs - sf);
            if (dq > dr && dq > ds) {
                rq = -rr - rs;
            } else if (dr > ds) {
                rr = -rq - rs;
            }
            float cx = n * (rq + rr * 0.5);
            float cy = \(Mosaic.root3) * n * rr * 0.5;
            q = int2(int(floor(cx)), int(floor(cy)));
        } else {
            q = int2((p / c.size) * c.size + c.size / 2u);
        }
        q = clamp(q, int2(0), int2(c.last));
        return source.read(uint2(q));
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_mosaic"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-012 mosaic")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the mosaic of `input`; returns it (owned by this pass, valid in `commandBuffer` until the next frame),
    /// nil when the picture or the encoder cannot be created.
    func encode(input: MTLTexture, mosaic: Mosaic, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != input.width || current.height != input.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: input.width, height: input.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-012 mosaic"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-012 mosaic"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(input, index: 0)
        var block: Mosaic.Block = mosaic.block(width: input.width, height: input.height)
        encoder.setFragmentBytes(&block, length: MemoryLayout<Mosaic.Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
