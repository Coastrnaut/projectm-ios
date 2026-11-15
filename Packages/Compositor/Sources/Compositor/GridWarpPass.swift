// GridWarpPass.swift — OUT-008 grid warp on the GPU (specs/309-out-008-grid-warp, contract C2; research OUT-008-D3, D5,
// D7).
//
// While `Compositor.outputWarp` is active, the screen pass of `composite(into:)` draws into one pooled picture of the
// output's size and format (everything it does is unchanged), then this pass clears the output to opaque black and draws
// that picture through the mesh: `cmp_warp_vertex` turns `vertex_id` into a lattice vertex (16 × 16 quads per control
// cell, two triangles each, the same integer steps as `GridWarp.latticePoint`), places it on the Catmull-Rom surface
// through the control points and passes its lattice position as the sampling coordinate; `cmp_warp_fragment` samples
// the picture bilinearly there and, with guides on, draws white lines on the control grid. No vertex buffer: the 16-byte
// grid block and the points (at most 81 × 8 bytes) go by `setVertexBytes`. The source is appended to
// `CompositorShaders.source` (the existing reviewed compile site; in the PERF-009 archive key). The picture returns to
// the pool when the warp turns off and with the compositor.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class GridWarpPass {
    static let source = """

    // OUT-008: the grid warp (GridWarpPass). g = (columns, rows, subdivisions, guides); p = points, row by row.
    struct CMPWarpOut { float4 position [[position]]; float2 uv; };

    static float4 cmp_warp_weights(float t) {
        float t2 = t * t;
        float t3 = t2 * t;
        return 0.5 * float4(-t3 + 2.0 * t2 - t, 3.0 * t3 - 5.0 * t2 + 2.0, -3.0 * t3 + 4.0 * t2 + t, t3 - t2);
    }

    // A point of row r (inside the grid) with linear extrapolation past the first and last column.
    static float2 cmp_warp_row_point(constant float2 *p, int4 g, int r, int c) {
        if (c < 0) return 2.0 * p[r * g.x] - p[r * g.x + 1];
        if (c >= g.x) return 2.0 * p[r * g.x + g.x - 1] - p[r * g.x + g.x - 2];
        return p[r * g.x + c];
    }

    // Any point of the padded grid (the Catmull-Rom phantom points).
    static float2 cmp_warp_point(constant float2 *p, int4 g, int r, int c) {
        if (r < 0) return 2.0 * cmp_warp_row_point(p, g, 0, c) - cmp_warp_row_point(p, g, 1, c);
        if (r >= g.y) return 2.0 * cmp_warp_row_point(p, g, g.y - 1, c) - cmp_warp_row_point(p, g, g.y - 2, c);
        return cmp_warp_row_point(p, g, r, c);
    }

    vertex CMPWarpOut cmp_warp_vertex(uint vid [[vertex_id]], constant int4 &g [[buffer(0)]], constant float2 *p [[buffer(1)]]) {
        int n = g.z;
        int cx = g.x - 1;
        int cy = g.y - 1;
        int quadsX = cx * n;
        int q = int(vid) / 6;
        int k = int(vid) % 6;
        int i = q % quadsX + ((k == 1 || k == 3 || k == 4) ? 1 : 0);
        int j = q / quadsX + ((k == 2 || k == 4 || k == 5) ? 1 : 0);
        int c = min(i / n, cx - 1);
        int r = min(j / n, cy - 1);
        float4 wx = cmp_warp_weights(float(i - c * n) / float(n));
        float4 wy = cmp_warp_weights(float(j - r * n) / float(n));
        float2 s = float2(0.0);
        for (int b = 0; b < 4; b++) {
            float2 row = float2(0.0);
            for (int a = 0; a < 4; a++) row += wx[a] * cmp_warp_point(p, g, r - 1 + b, c - 1 + a);
            s += wy[b] * row;
        }
        CMPWarpOut o;
        o.position = float4(s.x * 2.0 - 1.0, 1.0 - s.y * 2.0, 0.0, 1.0);
        o.uv = float2(float(i) / float(quadsX), float(j) / float(cy * n));
        return o;
    }

    fragment float4 cmp_warp_fragment(CMPWarpOut in [[stage_in]], texture2d<float, access::sample> picture [[texture(0)]],
                                      constant int4 &g [[buffer(0)]]) {
        constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 c = picture.sample(bilinear, in.uv);
        if (g.w != 0) {
            float2 q = in.uv * float2(float(g.x - 1), float(g.y - 1));
            float2 d = abs(q - round(q)) / max(fwidth(q), float2(1e-6));
            if (min(d.x, d.y) < 0.75) c = float4(1.0, 1.0, 1.0, 1.0);
        }
        return c;
    }
    """

    private let device: MTLDevice
    private let vertex: MTLFunction
    private let fragment: MTLFunction
    private var pipelines: [(format: MTLPixelFormat, state: MTLRenderPipelineState)] = []
    private var picture: MTLTexture?
    /// Pictures taken from the pool so far, and frames drawn (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0

    init(device: MTLDevice, library: MTLLibrary) throws(CompositorError) {
        self.device = device
        vertex = try CompositorShaders.function(library, "cmp_warp_vertex")
        fragment = try CompositorShaders.function(library, "cmp_warp_fragment")
    }

    var holdsPicture: Bool { picture != nil }

    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        if let picture { pool.recycle(picture, after: fence) }
        picture = nil
    }

    private func pipeline(for format: MTLPixelFormat) -> MTLRenderPipelineState? {
        for entry in pipelines where entry.format == format { return entry.state }
        guard let state = try? CompositorShaders.pipeline(device: device, vertex: vertex, fragment: fragment, format: format,
                                                          blendOver: false, label: "OUT-008 grid warp \(format.rawValue)") else {
            return nil
        }
        pipelines.append((format, state))
        return state
    }

    /// The picture the screen pass draws into this frame (the output's size and format), or nil when it cannot be made.
    func target(like output: MTLTexture, pool: TexturePool, fence: MTLCommandBuffer?) -> MTLTexture? {
        if let current = picture,
           current.width != output.width || current.height != output.height || current.pixelFormat != output.pixelFormat {
            release(to: pool, after: fence)
        }
        if picture == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: output.pixelFormat, width: output.width,
                                                             height: output.height, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            guard let made = pool.makeTexture(descriptor: d) else { return nil }
            made.label = "OUT-008 grid warp"
            picture = made
            allocations += 1
        }
        return picture
    }

    /// Draws `source` through `mesh` into `output` (cleared to opaque black first). False when nothing was encoded.
    func encode(source: MTLTexture, mesh: OutputWarpMesh, into output: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard mesh.isActive, let state = pipeline(for: output.pixelFormat) else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "OUT-008 grid warp"
        encoder.setRenderPipelineState(state)
        var grid = SIMD4<Int32>(Int32(mesh.columns), Int32(mesh.rows), Int32(OutputWarpMesh.subdivisions), mesh.showsGuides ? 1 : 0)
        let points: [Float] = mesh.flattened
        encoder.setVertexBytes(&grid, length: MemoryLayout<SIMD4<Int32>>.size, index: 0)
        points.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            if let base = raw.baseAddress { encoder.setVertexBytes(base, length: raw.count, index: 1) }
        }
        encoder.setFragmentBytes(&grid, length: MemoryLayout<SIMD4<Int32>>.size, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
        encoder.endEncoding()
        frames += 1
        return true
    }
}
#endif
