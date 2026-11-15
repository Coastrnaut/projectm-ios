// ReactionDiffusionPass.swift — VIS-012 reaction diffusion on Metal (contracts/reaction-diffusion.md C2; research
// VIS-012-D1, D2, D4, D7, D8).
//
// Three private textures, made once when the pass is made and never recreated, resized or freed while the generator
// lives: the state pair (`rg32Float`, U and V, N × N with N = 128 in the app) and the 16 × 16 health image
// (`rgba32Float`); plus one shared staging buffer (N² × 8 bytes) the seed is written into and three shared health
// buffers. A reload fills the staging buffer on the CPU (`ReactionDiffusionSeed.fill`) and blits it into the state, so
// the GPU starts bit-identical to the reference. Nothing waits: an earlier command buffer still in flight may copy the
// newer seed (or a mix) into the state it then iterates, but that state is overwritten by this reload's own blit, which
// is encoded after the CPU finished writing, so every reload's result is exact. Per planned step: `iterations` full-grid triangles of `vis_rd_iterate` (the
// injection on the first), each reading texels exactly; then the health pass and its copy into a free health buffer,
// then the display (palette × t × scale, channels ≤ 0.8, opaque). Pipelines come from the noise field generator's
// library (its module constant includes `ReactionDiffusionShader`) through PERF-009's archive: no new compile site
// (SHD-011). Uniforms go by `setFragmentBytes` from storage made in `init`; nothing is allocated per frame.
// Not Sendable: one thread.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

public final class ReactionDiffusionPass {
    /// Floats of the uniform block: 16 scalars, then 8 float4 palette stops.
    static let uniformFloats = 16 + 4 * ReactionDiffusion.paletteStops
    static let healthSide = 16
    static let healthBufferCount = 3

    public let gridSize: Int
    /// Every texture the pass holds (tests: count, identities and `allocatedSize` never change).
    public let textures: [MTLTexture]
    /// Health of the newest completed readback (nil before the first).
    public private(set) var lastHealth: ReactionDiffusionHealth?
    /// Seeds written into the state (reloads done).
    public private(set) var reloads = 0
    /// Iterations encoded since the pass was made.
    public private(set) var encodedIterations = 0
    /// The palette stops the display interpolates (linear rgb; the generator fills them).
    public let stops: UnsafeMutablePointer<SIMD3<Float>>

    /// Total bytes the textures and the staging buffer hold.
    public var allocatedBytes: Int {
        textures.reduce(staging.allocatedSize) { (sum: Int, t: MTLTexture) -> Int in sum + t.allocatedSize }
    }

    private let state: [MTLTexture]
    private let health: MTLTexture
    private let staging: MTLBuffer
    private var stateIndex = 0
    private var pendingSeed: (pattern: ReactionDiffusionPattern, seed: Int)?

    private let iteratePipeline: MTLRenderPipelineState
    private let healthPipeline: MTLRenderPipelineState
    private let displayPipeline: MTLRenderPipelineState

    private let single = MTLRenderPassDescriptor()
    private let uniforms: UnsafeMutablePointer<Float>
    private let healthBuffers: [MTLBuffer]
    private var healthReaders: [MTLCommandBuffer?]
    private var healthSerials: [UInt64]
    private var healthSerial: UInt64 = 0
    private var readSerial: UInt64 = 0

    init(device: MTLDevice, library: MTLLibrary, targetFormat: MTLPixelFormat,
         gridSize: Int = ReactionDiffusion.gridSize) throws(VisualGeneratorError) {
        let n: Int = max(16, gridSize / Self.healthSide * Self.healthSide)
        self.gridSize = n
        func texture(_ format: MTLPixelFormat, side: Int, label: String) throws(VisualGeneratorError) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: side, height: side, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            guard let t = device.makeTexture(descriptor: d) else { throw .pipelineUnavailable("reaction texture \(label)") }
            t.label = "VIS-012 \(label)"
            return t
        }
        state = [try texture(.rg32Float, side: n, label: "state 0"), try texture(.rg32Float, side: n, label: "state 1")]
        health = try texture(.rgba32Float, side: Self.healthSide, label: "health")
        textures = state + [health]
        guard let buffer = device.makeBuffer(length: n * n * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared) else {
            throw .pipelineUnavailable("reaction staging buffer")
        }
        buffer.label = "VIS-012 seed staging"
        staging = buffer

        iteratePipeline = try Self.pipeline(device, library, "vis_rd_iterate", .rg32Float)
        healthPipeline = try Self.pipeline(device, library, "vis_rd_health", .rgba32Float)
        displayPipeline = try Self.pipeline(device, library, "vis_rd_display", targetFormat)

        let healthBytes: Int = Self.healthSide * Self.healthSide * 4 * MemoryLayout<Float>.stride
        var buffers: [MTLBuffer] = []
        for i in 0..<Self.healthBufferCount {
            guard let b = device.makeBuffer(length: healthBytes, options: .storageModeShared) else {
                throw .pipelineUnavailable("reaction health buffer \(i)")
            }
            b.label = "VIS-012 health \(i)"
            buffers.append(b)
        }
        healthBuffers = buffers
        healthReaders = [MTLCommandBuffer?](repeating: nil, count: Self.healthBufferCount)
        healthSerials = [UInt64](repeating: 0, count: Self.healthBufferCount)
        uniforms = .allocate(capacity: Self.uniformFloats)
        uniforms.initialize(repeating: 0, count: Self.uniformFloats)
        stops = .allocate(capacity: ReactionDiffusion.paletteStops)
        stops.initialize(repeating: SIMD3<Float>(1, 1, 1), count: ReactionDiffusion.paletteStops)
        single.colorAttachments[0].loadAction = .dontCare
        single.colorAttachments[0].storeAction = .store
    }

    deinit {
        uniforms.deinitialize(count: Self.uniformFloats)
        uniforms.deallocate()
        stops.deinitialize(count: ReactionDiffusion.paletteStops)
        stops.deallocate()
    }

    private static func pipeline(_ device: MTLDevice, _ library: MTLLibrary, _ fragment: String,
                                 _ format: MTLPixelFormat) throws(VisualGeneratorError) -> MTLRenderPipelineState {
        guard let v = library.makeFunction(name: "vis_noise_vertex"), let f = library.makeFunction(name: fragment) else {
            throw .pipelineUnavailable("reaction shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VIS-012 \(fragment)"
        descriptor.vertexFunction = v
        descriptor.fragmentFunction = f
        descriptor.colorAttachments[0].pixelFormat = format
        do {
            return try NativePipelineArchive.makeRenderPipelineState(device: device, descriptor: descriptor)   // PERF-009
        } catch {
            throw .pipelineUnavailable("reaction pipeline: \(error.localizedDescription)")
        }
    }

    /// The next frame starts from `pattern` and `seed` (a reload; storage kept).
    public func requestSeed(pattern: ReactionDiffusionPattern, seed: Int) {
        pendingSeed = (pattern, seed)
    }

    /// True while a requested seed has not been written yet.
    public var seedPending: Bool { pendingSeed != nil }

    /// Reads the newest completed health copy not read yet (no waiting). True when it flags the grid (VIS-012-R9).
    @discardableResult
    public func pollHealth() -> Bool {
        var newest: Int?
        for i in 0..<Self.healthBufferCount {
            guard let reader = healthReaders[i], reader.status == .completed, healthSerials[i] > readSerial else { continue }
            if newest == nil || healthSerials[i] > healthSerials[newest!] { newest = i }
        }
        guard let i = newest else { return false }
        readSerial = healthSerials[i]
        let values = healthBuffers[i].contents().bindMemory(to: Float.self, capacity: Self.healthSide * Self.healthSide * 4)
        var h = ReactionDiffusionHealth()
        for k in 0..<(Self.healthSide * Self.healthSide) {
            let u: Float = values[4 * k], v: Float = values[4 * k + 1], low: Float = values[4 * k + 2]
            if values[4 * k + 3] != 0 || !u.isFinite || !v.isFinite || !low.isFinite { h.flagged = true; continue }
            h.maxU = max(h.maxU, u)
            h.maxV = max(h.maxV, v)
            h.minValue = min(h.minValue, low)
        }
        lastHealth = h
        return !h.isHealthy
    }

    /// Encodes a pending seed, the planned iterations of `scheduler`, the health pass and, when `target` is given, the
    /// display at `scale` (the fade-in ramp × the envelope's gain).
    @discardableResult
    func encode(scheduler: ReactionDiffusionScheduler, parameters: GrayScottParameters, commandBuffer: MTLCommandBuffer,
                target: MTLTexture?, scale: Float) -> Bool {
        if pendingSeed != nil { encodeSeed(commandBuffer: commandBuffer) }
        writeBase(parameters)
        for s in 0..<scheduler.plannedSteps {
            for k in 0..<scheduler.iterations(step: s) {
                if k == 0, let injection = scheduler.injection(step: s) {
                    uniforms[5] = 1
                    uniforms[6] = injection.x
                    uniforms[7] = injection.y
                    uniforms[8] = injection.amount
                } else {
                    uniforms[5] = 0
                }
                guard draw(iteratePipeline, output: state[1 - stateIndex], input: state[stateIndex],
                           commandBuffer: commandBuffer, label: "VIS-012 iterate") else { return false }
                stateIndex = 1 - stateIndex
                encodedIterations += 1
            }
        }
        uniforms[5] = 0
        encodeHealth(commandBuffer: commandBuffer)
        guard let target else { return true }
        uniforms[10] = Float(max(target.width, 1))
        uniforms[11] = Float(max(target.height, 1))
        uniforms[12] = scale.isFinite ? min(max(scale, 0), 1) : 0
        for k in 0..<ReactionDiffusion.paletteStops {
            let c: SIMD3<Float> = stops[k]
            uniforms[16 + 4 * k] = c.x
            uniforms[17 + 4 * k] = c.y
            uniforms[18 + 4 * k] = c.z
            uniforms[19 + 4 * k] = 1
        }
        return draw(displayPipeline, output: target, input: state[stateIndex], commandBuffer: commandBuffer,
                    label: "VIS-012 display")
    }

    private func writeBase(_ p: GrayScottParameters) {
        uniforms[0] = Float(gridSize)
        uniforms[1] = p.feed
        uniforms[2] = p.kill
        uniforms[3] = p.du
        uniforms[4] = p.dv
        uniforms[9] = ReactionDiffusion.injectionRadius
        uniforms[13] = ReactionDiffusion.displayCap
        uniforms[14] = ReactionDiffusion.displayLow
        uniforms[15] = ReactionDiffusion.displayHigh
    }

    /// Writes the pending seed into the staging buffer and blits it into the state.
    private func encodeSeed(commandBuffer: MTLCommandBuffer) {
        guard let seed = pendingSeed else { return }
        let n: Int = gridSize
        let cells = staging.contents().bindMemory(to: SIMD2<Float>.self, capacity: n * n)
        ReactionDiffusionSeed.fill(pattern: seed.pattern, seed: seed.seed, gridSize: n, into: cells)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.label = "VIS-012 seed"
        let rowBytes: Int = n * MemoryLayout<SIMD2<Float>>.stride
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: rowBytes * n,
                  sourceSize: MTLSize(width: n, height: n, depth: 1), to: state[0], destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        stateIndex = 0
        pendingSeed = nil
        reloads += 1
    }

    /// One full-grid triangle into `output` reading `input`.
    private func draw(_ pipeline: MTLRenderPipelineState, output: MTLTexture, input: MTLTexture,
                      commandBuffer: MTLCommandBuffer, label: String) -> Bool {
        single.colorAttachments[0].texture = output
        defer { single.colorAttachments[0].texture = nil }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: single) else { return false }
        encoder.label = label
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(uniforms, length: Self.uniformFloats * MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentTexture(input, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func encodeHealth(commandBuffer: MTLCommandBuffer) {
        var slot: Int?
        for i in 0..<Self.healthBufferCount {
            guard let reader = healthReaders[i] else { slot = i; break }
            if reader.status == .completed || reader.status == .error { slot = i; break }
        }
        guard let i = slot else { return }   // every copy still in flight: skip this frame's check
        guard draw(healthPipeline, output: health, input: state[stateIndex], commandBuffer: commandBuffer,
                   label: "VIS-012 health") else { return }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        let side: Int = Self.healthSide
        blit.copy(from: health, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: side, height: side, depth: 1), to: healthBuffers[i], destinationOffset: 0,
                  destinationBytesPerRow: side * 16, destinationBytesPerImage: side * side * 16)
        blit.endEncoding()
        healthSerial += 1
        healthSerials[i] = healthSerial
        healthReaders[i] = commandBuffer
    }

    /// Copies the current state into a new shared buffer (tests and diagnostics only; allocates). Read it after
    /// `commandBuffer` completed: N² (U, V) float pairs, rows top first.
    func copyState(commandBuffer: MTLCommandBuffer) -> MTLBuffer? {
        let n: Int = gridSize
        let rowBytes: Int = n * MemoryLayout<SIMD2<Float>>.stride
        guard let buffer = commandBuffer.device.makeBuffer(length: rowBytes * n, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: state[stateIndex], sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: n, height: n, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * n)
        blit.endEncoding()
        return buffer
    }

    /// Writes `value` into one cell through the staging buffer (tests: a corrupt texel for the health check). Allocates
    /// nothing; the next seed overwrites the staging buffer.
    func corrupt(cellX x: Int, y: Int, value: SIMD2<Float>, commandBuffer: MTLCommandBuffer) {
        let cells = staging.contents().bindMemory(to: SIMD2<Float>.self, capacity: gridSize * gridSize)
        cells[0] = value
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        let stride: Int = MemoryLayout<SIMD2<Float>>.stride
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: stride, sourceBytesPerImage: stride,
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1), to: state[stateIndex], destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: x, y: y, z: 0))
        blit.endEncoding()
    }
}
#endif

/// VIS-012: the reaction's MSL, module-authored (SHD-011), appended to `NoiseFieldGenerator.shaderSource` after its
/// body (it uses `NoiseOut` and `vis_noise_vertex`), so it compiles at that reviewed site and is part of PERF-009's
/// archive key. Mirrors `GrayScottSolver`. Non-finite tests look at the exponent bits, so fast math cannot remove them.
public enum ReactionDiffusionShader {
    public static let functions = """

    // VIS-012 reaction diffusion. Matches ReactionDiffusionPass's uniform block (192 bytes).
    struct ReactionUniforms {
        float n;
        float feed;
        float kill;
        float du;
        float dv;
        float inject;
        float injX;
        float injY;
        float injAmount;
        float injRadius;
        float width;
        float height;
        float scale;
        float cap;
        float low;
        float high;
        float4 stops[8];
    };

    static bool vis_rd_bad(float v) { return (as_type<uint>(v) & 0x7f800000u) == 0x7f800000u; }
    static float vis_rd_clean(float v) { return vis_rd_bad(v) ? 0.0 : clamp(v, 0.0, 1.0); }

    static float2 vis_rd_at(texture2d<float, access::read> t, int x, int y, int n) {
        return t.read(uint2((x + n) % n, (y + n) % n)).xy;
    }

    fragment float4 vis_rd_iterate(NoiseOut in [[stage_in]], constant ReactionUniforms &u [[buffer(0)]],
                                   texture2d<float, access::read> state [[texture(0)]]) {
        int n = int(u.n);
        int2 c = int2(in.position.xy);
        float2 s = vis_rd_at(state, c.x, c.y, n);
        float2 e = (vis_rd_at(state, c.x - 1, c.y, n) + vis_rd_at(state, c.x + 1, c.y, n))
            + (vis_rd_at(state, c.x, c.y - 1, n) + vis_rd_at(state, c.x, c.y + 1, n));
        float2 d = (vis_rd_at(state, c.x - 1, c.y - 1, n) + vis_rd_at(state, c.x + 1, c.y - 1, n))
            + (vis_rd_at(state, c.x - 1, c.y + 1, n) + vis_rd_at(state, c.x + 1, c.y + 1, n));
        float2 lap = 0.2 * e + 0.05 * d - s;
        float uvv = s.x * s.y * s.y;
        float un = s.x + (u.du * lap.x - uvv + u.feed * (1.0 - s.x));
        float vn = s.y + (u.dv * lap.y + uvv - (u.feed + u.kill) * s.y);
        if (u.inject > 0.5) {
            float2 x = (float2(c) + 0.5) / u.n - float2(u.injX, u.injY);
            float a = u.injAmount * exp(-(x.x * x.x + x.y * x.y) / (u.injRadius * u.injRadius));
            vn += a;
            un -= a;
        }
        return float4(vis_rd_clean(un), vis_rd_clean(vn), 0.0, 0.0);
    }

    // Per 16 x 16 block: max U, max V, min value, flag (non-finite or outside [0, 1]).
    fragment float4 vis_rd_health(NoiseOut in [[stage_in]], constant ReactionUniforms &u [[buffer(0)]],
                                  texture2d<float, access::read> state [[texture(0)]]) {
        int block = int(u.n) / 16;
        int2 origin = int2(in.position.xy) * block;
        float maxU = 0.0, maxV = 0.0, low = 1.0, flag = 0.0;
        for (int j = 0; j < block; j++) {
            for (int i = 0; i < block; i++) {
                float2 s = state.read(uint2(origin + int2(i, j))).xy;
                if (vis_rd_bad(s.x) || vis_rd_bad(s.y)) { flag = 1.0; continue; }
                if (s.x < 0.0 || s.x > 1.0 || s.y < 0.0 || s.y > 1.0) { flag = 1.0; }
                maxU = max(maxU, s.x);
                maxV = max(maxV, s.y);
                low = min(low, min(s.x, s.y));
            }
        }
        return float4(maxU, maxV, low, flag);
    }

    // V across the output (square cells over the longer side; the torus is sampled bilinearly), through the palette,
    // x t, channels <= cap, x scale (fade-in x envelope gain); opaque.
    fragment float4 vis_rd_display(NoiseOut in [[stage_in]], constant ReactionUniforms &u [[buffer(0)]],
                                   texture2d<float, access::read> state [[texture(0)]]) {
        int n = int(u.n);
        float side = max(max(u.width, u.height), 1.0);
        float2 g = in.position.xy / side * u.n - 0.5;
        float2 f0 = floor(g);
        float2 f = g - f0;
        int x = int(f0.x), y = int(f0.y);
        float a = vis_rd_at(state, x, y, n).y, b = vis_rd_at(state, x + 1, y, n).y;
        float c = vis_rd_at(state, x, y + 1, n).y, d = vis_rd_at(state, x + 1, y + 1, n).y;
        float top = a + (b - a) * f.x;
        float bottom = c + (d - c) * f.x;
        float v = vis_rd_clean(top + (bottom - top) * f.y);
        float t = smoothstep(u.low, u.high, v);
        float pos = t * 7.0;
        int i = min(int(pos), 6);
        float3 col = mix(u.stops[i].rgb, u.stops[i + 1].rgb, pos - float(i)) * t;
        col = clamp(col, 0.0, u.cap) * clamp(u.scale, 0.0, 1.0);
        return float4(col, 1.0);
    }
    """
}
