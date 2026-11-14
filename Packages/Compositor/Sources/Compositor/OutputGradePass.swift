// OutputGradePass.swift — FX-020: Color before Trails (specs/142-fx-020-effect-chains, contracts/effect-chain.md E1,
// research FX-020-D2; ADR-0052).
//
// Used only when the order puts Color first, Trails are active and the grade is not neutral: one full-screen pass
// `cmp_grade_pass` writes FX-003's grade (`cmp_grade`, the same function the output pass uses, without the tone map)
// of the finished composite into one pooled picture (composite size, `rgba16Float`), which Trails then read. The
// compositor's guard and outputs then use the neutral grade block, so the grade is applied exactly once and the guard
// still measures the frame as shown. The picture is taken from the pool on the first such frame at a size and returned
// (fenced by the last command buffer) when the pass stops being used, at a size change and with the compositor.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class OutputGradePass {
    /// `cmp_grade_pass` (spliced after `CompositorShaders.source`, which defines `CMPGrade` and `cmp_grade`).
    static let source = """

    // FX-020: the composite graded (no tone map; FX-002 runs in the output pass).
    fragment float4 cmp_grade_pass(FullScreenOut in [[stage_in]], texture2d<float, access::read> composite [[texture(0)]],
                                   constant CMPGrade &grade [[buffer(0)]]) {
        return cmp_grade(composite.read(uint2(in.position.xy)), grade);
    }
    """

    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        pipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                  fragment: try CompositorShaders.function(library, "cmp_grade_pass"),
                                                  format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                  label: "FX-020 grade pass")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    /// Encodes the graded composite; returns it (owned by this pass, valid in `commandBuffer` until the next frame),
    /// nil when the picture or the encoder cannot be created.
    func encode(composite: MTLTexture, grade: CompositorShaders.GradeBlock, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let current = picture, current.width != composite.width || current.height != composite.height {
            release(to: pool, after: fence)
        }
        if picture == nil {
            guard let size = LayerPictureDescriptor(width: composite.width, height: composite.height),
                  let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "FX-020 graded composite"
            picture = made
            allocations += 1
        }
        guard let output = picture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-020 grade pass"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(composite, index: 0)
        var block = grade
        encoder.setFragmentBytes(&block, length: MemoryLayout<CompositorShaders.GradeBlock>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return output
    }
}
#endif
