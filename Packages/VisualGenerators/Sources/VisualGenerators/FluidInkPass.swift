// FluidInkPass.swift — VIS-011 fluid ink on Metal (contracts/fluid-ink.md C2; research VIS-011-D1, D2, D4, D5).
//
// Eight private textures on an N × N grid (N = 128 in the app), made once when the pass is made (the noise field
// generator makes it on its first fluid frame) and never recreated, resized or freed while the generator lives: a
// velocity pair (`rg32Float`), a pressure pair and the divergence (`r32Float`), an ink pair (`rgba32Float`) and the
// 16 × 16 health image (`rgba32Float`). They do not depend on the output size. Per fixed step (FluidInk.swift's order):
// splat (both fields, one pass with two attachments; skipped without impulses), velocity advection, divergence, 20
// Jacobi iterations, projection, ink advection — each a full-grid triangle with `FluidInkShader`'s fragment functions,
// reading texels exactly and interpolating by hand, so the GPU follows the reference solver's formulas. After the
// frame's steps: the health pass and its copy into one of three shared buffers (rewritten only after the command buffer
// that last filled it completed; nothing waits), then the display pass (ink across the output × the envelope's gain,
// clamped to 0.8, opaque). `pollHealth` reads the newest completed copy; a non-finite flag or an over-cap value resets
// the field on the next frame (VIS-011-R7). Pipelines come from the noise field generator's library (its module
// constant includes `FluidInkShader`) through PERF-009's archive: no new compile site (SHD-011). Uniforms go by
// `setFragmentBytes` from storage made in `init`; nothing is allocated per frame. Not Sendable: one thread.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

public final class FluidInkPass {
    /// Floats of the uniform block: 12 scalars, then 4 float4 (two splats).
    static let uniformFloats = 28
    static let healthSide = 16
    static let healthBufferCount = 3

    public let gridSize: Int
    /// Every texture the pass holds (tests: count, identities and `allocatedSize` never change).
    public let textures: [MTLTexture]
    /// Health of the newest completed readback (nil before the first).
    public private(set) var lastHealth: FluidInkHealth?
    /// Field resets (mode entry, loop restart, the health check).
    public private(set) var resets = 0
    /// Fixed steps encoded since the pass was made.
    public private(set) var encodedSteps = 0

    /// Total bytes the textures hold.
    public var allocatedBytes: Int { textures.reduce(0) { (sum: Int, t: MTLTexture) -> Int in sum + t.allocatedSize } }

    private let velocity: [MTLTexture]
    private let pressure: [MTLTexture]
    private let divergence: MTLTexture
    private let ink: [MTLTexture]
    private let health: MTLTexture
    private var velocityIndex = 0
    private var inkIndex = 0
    private var needsClear = true

    private let splatPipeline: MTLRenderPipelineState
    private let advectVelocityPipeline: MTLRenderPipelineState
    private let divergencePipeline: MTLRenderPipelineState
    private let jacobiPipeline: MTLRenderPipelineState
    private let gradientPipeline: MTLRenderPipelineState
    private let advectInkPipeline: MTLRenderPipelineState
    private let healthPipeline: MTLRenderPipelineState
    private let displayPipeline: MTLRenderPipelineState

    private let single = MTLRenderPassDescriptor()
    private let pair = MTLRenderPassDescriptor()
    private let uniforms: UnsafeMutablePointer<Float>
    private let healthBuffers: [MTLBuffer]
    private var healthReaders: [MTLCommandBuffer?]
    private var healthSerials: [UInt64]
    private var healthSerial: UInt64 = 0
    private var readSerial: UInt64 = 0

    init(device: MTLDevice, library: MTLLibrary, targetFormat: MTLPixelFormat,
         gridSize: Int = FluidInk.gridSize) throws(VisualGeneratorError) {
        let n: Int = max(16, gridSize / Self.healthSide * Self.healthSide)
        self.gridSize = n
        func texture(_ format: MTLPixelFormat, side: Int, label: String) throws(VisualGeneratorError) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: side, height: side, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            guard let t = device.makeTexture(descriptor: d) else { throw .pipelineUnavailable("fluid texture \(label)") }
            t.label = "VIS-011 \(label)"
            return t
        }
        velocity = [try texture(.rg32Float, side: n, label: "velocity 0"), try texture(.rg32Float, side: n, label: "velocity 1")]
        pressure = [try texture(.r32Float, side: n, label: "pressure 0"), try texture(.r32Float, side: n, label: "pressure 1")]
        divergence = try texture(.r32Float, side: n, label: "divergence")
        ink = [try texture(.rgba32Float, side: n, label: "ink 0"), try texture(.rgba32Float, side: n, label: "ink 1")]
        health = try texture(.rgba32Float, side: Self.healthSide, label: "health")
        textures = velocity + pressure + [divergence] + ink + [health]

        splatPipeline = try Self.pipeline(device, library, "vis_fluid_splat", [.rg32Float, .rgba32Float])
        advectVelocityPipeline = try Self.pipeline(device, library, "vis_fluid_advect_velocity", [.rg32Float])
        divergencePipeline = try Self.pipeline(device, library, "vis_fluid_divergence", [.r32Float])
        jacobiPipeline = try Self.pipeline(device, library, "vis_fluid_jacobi", [.r32Float])
        gradientPipeline = try Self.pipeline(device, library, "vis_fluid_gradient", [.rg32Float])
        advectInkPipeline = try Self.pipeline(device, library, "vis_fluid_advect_ink", [.rgba32Float])
        healthPipeline = try Self.pipeline(device, library, "vis_fluid_health", [.rgba32Float])
        displayPipeline = try Self.pipeline(device, library, "vis_fluid_display", [targetFormat])

        let healthBytes: Int = Self.healthSide * Self.healthSide * 4 * MemoryLayout<Float>.stride
        var buffers: [MTLBuffer] = []
        for i in 0..<Self.healthBufferCount {
            guard let b = device.makeBuffer(length: healthBytes, options: .storageModeShared) else {
                throw .pipelineUnavailable("fluid health buffer \(i)")
            }
            b.label = "VIS-011 health \(i)"
            buffers.append(b)
        }
        healthBuffers = buffers
        healthReaders = [MTLCommandBuffer?](repeating: nil, count: Self.healthBufferCount)
        healthSerials = [UInt64](repeating: 0, count: Self.healthBufferCount)
        uniforms = .allocate(capacity: Self.uniformFloats)
        uniforms.initialize(repeating: 0, count: Self.uniformFloats)
        for d in [single, pair] {
            d.colorAttachments[0].loadAction = .dontCare
            d.colorAttachments[0].storeAction = .store
        }
        pair.colorAttachments[1].loadAction = .dontCare
        pair.colorAttachments[1].storeAction = .store
    }

    deinit {
        uniforms.deinitialize(count: Self.uniformFloats)
        uniforms.deallocate()
    }

    private static func pipeline(_ device: MTLDevice, _ library: MTLLibrary, _ fragment: String,
                                 _ formats: [MTLPixelFormat]) throws(VisualGeneratorError) -> MTLRenderPipelineState {
        guard let v = library.makeFunction(name: "vis_noise_vertex"), let f = library.makeFunction(name: fragment) else {
            throw .pipelineUnavailable("fluid shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VIS-011 \(fragment)"
        descriptor.vertexFunction = v
        descriptor.fragmentFunction = f
        for (k, format) in formats.enumerated() { descriptor.colorAttachments[k].pixelFormat = format }
        do {
            return try NativePipelineArchive.makeRenderPipelineState(device: device, descriptor: descriptor)   // PERF-009
        } catch {
            throw .pipelineUnavailable("fluid pipeline: \(error.localizedDescription)")
        }
    }

    /// The next frame starts at rest with no ink (mode entry, loop restart); storage kept.
    public func reset() {
        needsClear = true
        resets += 1
    }

    /// Reads the newest completed health copy not read yet (no waiting). True when it asks for a reset (VIS-011-R7).
    @discardableResult
    public func pollHealth(speedCap: Float) -> Bool {
        var newest: Int?
        for i in 0..<Self.healthBufferCount {
            guard let reader = healthReaders[i], reader.status == .completed, healthSerials[i] > readSerial else { continue }
            if newest == nil || healthSerials[i] > healthSerials[newest!] { newest = i }
        }
        guard let i = newest else { return false }
        readSerial = healthSerials[i]
        let values = healthBuffers[i].contents().bindMemory(to: Float.self, capacity: Self.healthSide * Self.healthSide * 4)
        var h = FluidInkHealth()
        for k in 0..<(Self.healthSide * Self.healthSide) {
            let speed: Float = values[4 * k], inkLevel: Float = values[4 * k + 1]
            let energy: Float = values[4 * k + 2], flag: Float = values[4 * k + 3]
            if flag != 0 || !speed.isFinite || !inkLevel.isFinite || !energy.isFinite { h.nonFinite = true; continue }
            h.maxSpeed = max(h.maxSpeed, speed)
            h.maxInk = max(h.maxInk, inkLevel)
            h.kineticEnergy += energy
        }
        lastHealth = h
        return h.needsReset(speedCap: speedCap)
    }

    /// Encodes the planned steps of `scheduler`, the health pass and, when `target` is given, the display at `gain`.
    @discardableResult
    func encode(scheduler: FluidStepScheduler, speedCap: Float, commandBuffer: MTLCommandBuffer, target: MTLTexture?,
                gain: Float) -> Bool {
        if needsClear {
            guard clear(commandBuffer: commandBuffer) else { return false }
            needsClear = false
        }
        for s in 0..<scheduler.plannedSteps {
            guard encodeStep(scheduler: scheduler, step: s, speedCap: speedCap, commandBuffer: commandBuffer) else { return false }
        }
        encodeHealth(commandBuffer: commandBuffer)
        guard let target else { return true }
        return encodeDisplay(into: target, gain: gain, commandBuffer: commandBuffer)
    }

    private func writeBase(speedCap: Float) {
        let n = Float(gridSize)
        uniforms[0] = n
        uniforms[1] = 1 / n
        uniforms[2] = FluidInk.stepSeconds
        uniforms[3] = 1
        uniforms[4] = speedCap
        uniforms[5] = FluidInk.inkCap
        uniforms[6] = 0
        uniforms[7] = 0
        uniforms[8] = FluidInk.splatRadius
    }

    private func clear(commandBuffer: MTLCommandBuffer) -> Bool {
        let d = MTLRenderPassDescriptor()   // only on a reset, never per frame
        d.colorAttachments[0].texture = velocity[velocityIndex]
        d.colorAttachments[0].loadAction = .clear
        d.colorAttachments[0].storeAction = .store
        d.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        d.colorAttachments[1].texture = ink[inkIndex]
        d.colorAttachments[1].loadAction = .clear
        d.colorAttachments[1].storeAction = .store
        d.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: d) else { return false }
        encoder.label = "VIS-011 clear"
        encoder.endEncoding()
        return true
    }

    /// One full-grid triangle into `outputs` reading `inputs`.
    private func draw(_ state: MTLRenderPipelineState, outputs: [MTLTexture], inputs: [MTLTexture],
                      commandBuffer: MTLCommandBuffer, label: String) -> Bool {
        let descriptor: MTLRenderPassDescriptor = outputs.count == 2 ? pair : single
        for (k, t) in outputs.enumerated() { descriptor.colorAttachments[k].texture = t }
        defer { for k in 0..<outputs.count { descriptor.colorAttachments[k].texture = nil } }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        encoder.label = label
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(uniforms, length: Self.uniformFloats * MemoryLayout<Float>.stride, index: 0)
        for (k, t) in inputs.enumerated() { encoder.setFragmentTexture(t, index: k) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func encodeStep(scheduler: FluidStepScheduler, step s: Int, speedCap: Float, commandBuffer: MTLCommandBuffer) -> Bool {
        writeBase(speedCap: speedCap)
        let count: Int = scheduler.splatCount(step: s)
        if count > 0 {
            uniforms[7] = Float(count)
            for k in 0..<count {
                let splat: FluidSplat = scheduler.splat(step: s, k)
                uniforms[12 + 8 * k] = splat.centerX
                uniforms[13 + 8 * k] = splat.centerY
                uniforms[14 + 8 * k] = splat.velocityX
                uniforms[15 + 8 * k] = splat.velocityY
                uniforms[16 + 8 * k] = splat.red
                uniforms[17 + 8 * k] = splat.green
                uniforms[18 + 8 * k] = splat.blue
                uniforms[19 + 8 * k] = 0
            }
            guard draw(splatPipeline, outputs: [velocity[1 - velocityIndex], ink[1 - inkIndex]],
                       inputs: [velocity[velocityIndex], ink[inkIndex]], commandBuffer: commandBuffer, label: "VIS-011 splat") else { return false }
            velocityIndex = 1 - velocityIndex
            inkIndex = 1 - inkIndex
        }
        uniforms[3] = FluidInk.velocityFactor
        guard draw(advectVelocityPipeline, outputs: [velocity[1 - velocityIndex]], inputs: [velocity[velocityIndex]],
                   commandBuffer: commandBuffer, label: "VIS-011 advect velocity") else { return false }
        velocityIndex = 1 - velocityIndex
        guard draw(divergencePipeline, outputs: [divergence], inputs: [velocity[velocityIndex]],
                   commandBuffer: commandBuffer, label: "VIS-011 divergence") else { return false }
        var p = 0
        for iteration in 0..<FluidInk.jacobiIterations {
            uniforms[6] = iteration == 0 ? 1 : 0   // the first iteration reads p = 0
            guard draw(jacobiPipeline, outputs: [pressure[1 - p]], inputs: [pressure[p], divergence],
                       commandBuffer: commandBuffer, label: "VIS-011 pressure") else { return false }
            p = 1 - p
        }
        uniforms[6] = 0
        guard draw(gradientPipeline, outputs: [velocity[1 - velocityIndex]], inputs: [velocity[velocityIndex], pressure[p]],
                   commandBuffer: commandBuffer, label: "VIS-011 projection") else { return false }
        velocityIndex = 1 - velocityIndex
        uniforms[3] = FluidInk.inkFactor
        guard draw(advectInkPipeline, outputs: [ink[1 - inkIndex]], inputs: [velocity[velocityIndex], ink[inkIndex]],
                   commandBuffer: commandBuffer, label: "VIS-011 advect ink") else { return false }
        inkIndex = 1 - inkIndex
        encodedSteps += 1
        return true
    }

    private func encodeHealth(commandBuffer: MTLCommandBuffer) {
        var slot: Int?
        for i in 0..<Self.healthBufferCount {
            guard let reader = healthReaders[i] else { slot = i; break }
            if reader.status == .completed || reader.status == .error { slot = i; break }
        }
        guard let i = slot else { return }   // every copy still in flight: skip this frame's check
        guard draw(healthPipeline, outputs: [health], inputs: [velocity[velocityIndex], ink[inkIndex]],
                   commandBuffer: commandBuffer, label: "VIS-011 health") else { return }
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

    private func encodeDisplay(into target: MTLTexture, gain: Float, commandBuffer: MTLCommandBuffer) -> Bool {
        writeBase(speedCap: FluidInk.speedCap)
        uniforms[3] = gain.isFinite ? min(max(gain, 0), 1) : 0
        uniforms[9] = Float(max(target.width, 1))
        uniforms[10] = Float(max(target.height, 1))
        return draw(displayPipeline, outputs: [target], inputs: [ink[inkIndex]], commandBuffer: commandBuffer, label: "VIS-011 display")
    }

    /// Copies the current velocity and ink into new shared buffers (tests and diagnostics only; allocates). Read them
    /// after `commandBuffer` completed: velocity as N² float2, ink as N² float4, rows top first.
    func copyFields(commandBuffer: MTLCommandBuffer) -> (velocity: MTLBuffer, ink: MTLBuffer)? {
        let n: Int = gridSize
        let device: MTLDevice = commandBuffer.device
        guard let v = device.makeBuffer(length: n * n * 8, options: .storageModeShared),
              let k = device.makeBuffer(length: n * n * 16, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        let size = MTLSize(width: n, height: n, depth: 1)
        blit.copy(from: velocity[velocityIndex], sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: size, to: v, destinationOffset: 0, destinationBytesPerRow: n * 8, destinationBytesPerImage: n * n * 8)
        blit.copy(from: ink[inkIndex], sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: size, to: k, destinationOffset: 0, destinationBytesPerRow: n * 16, destinationBytesPerImage: n * n * 16)
        blit.endEncoding()
        return (v, k)
    }
}
#endif

/// VIS-011: the fluid's MSL, module-authored (SHD-011), appended to `NoiseFieldGenerator.shaderSource` after its body (it
/// uses `NoiseOut` and `vis_noise_vertex`), so it compiles at that reviewed site and is part of PERF-009's archive key.
/// Mirrors `FluidInkSolver`. Non-finite tests look at the exponent bits, so the library's fast math cannot remove them.
public enum FluidInkShader {
    public static let functions = """

    // VIS-011 fluid ink. Matches FluidInkPass's uniform block (112 bytes).
    struct FluidUniforms {
        float n;
        float h;
        float dt;
        float factor;
        float speedCap;
        float inkCap;
        float first;
        float count;
        float radius;
        float width;
        float height;
        float unused;
        float4 splat[4];
    };

    static bool vis_fl_bad(float v) { return (as_type<uint>(v) & 0x7f800000u) == 0x7f800000u; }
    static float vis_fl_finite(float v) { return vis_fl_bad(v) ? 0.0 : v; }
    static float vis_fl_clamp(float v, float lo, float hi) { return vis_fl_bad(v) ? 0.0 : clamp(v, lo, hi); }
    static float vis_fl_lerp(float a, float b, float f) { return a + (b - a) * f; }

    static float2 vis_fl_cap(float2 v, float cap) {
        v = float2(vis_fl_finite(v.x), vis_fl_finite(v.y));
        float s2 = v.x * v.x + v.y * v.y;
        if (s2 > cap * cap) { v *= cap / sqrt(s2); }
        return v;
    }

    // Grid coordinate of domain point x: lower index (<= n - 2) and fraction.
    static int vis_fl_coord(float x, float n, thread float &f) {
        float g = vis_fl_clamp(x * n - 0.5, 0.0, n - 1.0);
        int i = min(int(g), int(n) - 2);
        f = g - float(i);
        return i;
    }

    static float4 vis_fl_sample(texture2d<float, access::read> t, float2 p, float n) {
        float fx, fy;
        int i = vis_fl_coord(p.x, n, fx);
        int j = vis_fl_coord(p.y, n, fy);
        float4 a = t.read(uint2(i, j)), b = t.read(uint2(i + 1, j));
        float4 c = t.read(uint2(i, j + 1)), d = t.read(uint2(i + 1, j + 1));
        float4 top = a + (b - a) * fx;
        float4 bottom = c + (d - c) * fx;
        return top + (bottom - top) * fy;
    }

    static float4 vis_fl_ink(float3 k, float cap) {
        return float4(vis_fl_clamp(k.x, 0.0, cap), vis_fl_clamp(k.y, 0.0, cap), vis_fl_clamp(k.z, 0.0, cap), 0.0);
    }

    struct FluidPairOut { float4 velocity [[color(0)]]; float4 ink [[color(1)]]; };

    fragment FluidPairOut vis_fluid_splat(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                          texture2d<float, access::read> velocity [[texture(0)]],
                                          texture2d<float, access::read> ink [[texture(1)]]) {
        uint2 c = uint2(in.position.xy);
        float2 x = (float2(c) + 0.5) * u.h;
        float2 v = velocity.read(c).xy;
        float3 k = ink.read(c).rgb;
        int count = min(int(u.count + 0.5), 2);
        float r2 = u.radius * u.radius;
        for (int s = 0; s < count; s++) {
            float4 a = u.splat[2 * s];
            float4 b = u.splat[2 * s + 1];
            float2 d = x - a.xy;
            float w = exp(-(d.x * d.x + d.y * d.y) / r2);
            v += w * a.zw;
            k += w * b.rgb;
        }
        FluidPairOut o;
        o.velocity = float4(vis_fl_cap(v, u.speedCap), 0.0, 0.0);
        o.ink = vis_fl_ink(k, u.inkCap);
        return o;
    }

    fragment float4 vis_fluid_advect_velocity(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                              texture2d<float, access::read> velocity [[texture(0)]]) {
        uint2 c = uint2(in.position.xy);
        float2 v = velocity.read(c).xy;
        float2 p = (float2(c) + 0.5) * u.h - u.dt * v;
        float2 s = vis_fl_sample(velocity, p, u.n).xy * u.factor;
        return float4(vis_fl_cap(s, u.speedCap), 0.0, 0.0);
    }

    fragment float4 vis_fluid_divergence(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                         texture2d<float, access::read> velocity [[texture(0)]]) {
        int2 c = int2(in.position.xy);
        int last = int(u.n) - 1;
        float l = velocity.read(uint2(max(c.x - 1, 0), c.y)).x;
        float r = velocity.read(uint2(min(c.x + 1, last), c.y)).x;
        float t = velocity.read(uint2(c.x, max(c.y - 1, 0))).y;
        float b = velocity.read(uint2(c.x, min(c.y + 1, last))).y;
        return float4(vis_fl_finite(((r - l) + (b - t)) * (0.5 / u.h)), 0.0, 0.0, 0.0);
    }

    fragment float4 vis_fluid_jacobi(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                     texture2d<float, access::read> pressure [[texture(0)]],
                                     texture2d<float, access::read> divergence [[texture(1)]]) {
        int2 c = int2(in.position.xy);
        int last = int(u.n) - 1;
        float sum = 0.0;
        if (u.first < 0.5) {
            float l = pressure.read(uint2(max(c.x - 1, 0), c.y)).x;
            float r = pressure.read(uint2(min(c.x + 1, last), c.y)).x;
            float t = pressure.read(uint2(c.x, max(c.y - 1, 0))).x;
            float b = pressure.read(uint2(c.x, min(c.y + 1, last))).x;
            sum = (l + r) + (t + b);
        }
        float d = divergence.read(uint2(c)).x;
        return float4(vis_fl_finite((sum - u.h * u.h * d) * 0.25), 0.0, 0.0, 0.0);
    }

    fragment float4 vis_fluid_gradient(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                       texture2d<float, access::read> velocity [[texture(0)]],
                                       texture2d<float, access::read> pressure [[texture(1)]]) {
        int2 c = int2(in.position.xy);
        int last = int(u.n) - 1;
        float l = pressure.read(uint2(max(c.x - 1, 0), c.y)).x;
        float r = pressure.read(uint2(min(c.x + 1, last), c.y)).x;
        float t = pressure.read(uint2(c.x, max(c.y - 1, 0))).x;
        float b = pressure.read(uint2(c.x, min(c.y + 1, last))).x;
        float scale = 0.5 / u.h;
        float2 v = velocity.read(uint2(c)).xy - float2((r - l) * scale, (b - t) * scale);
        return float4(vis_fl_cap(v, u.speedCap), 0.0, 0.0);
    }

    fragment float4 vis_fluid_advect_ink(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                         texture2d<float, access::read> velocity [[texture(0)]],
                                         texture2d<float, access::read> ink [[texture(1)]]) {
        uint2 c = uint2(in.position.xy);
        float2 v = velocity.read(c).xy;
        float2 p = (float2(c) + 0.5) * u.h - u.dt * v;
        return vis_fl_ink(vis_fl_sample(ink, p, u.n).rgb * u.factor, u.inkCap);
    }

    // Per 16 x 16 block: max speed, max ink channel, kinetic energy (1/2 |v|^2 h^2 summed), non-finite flag.
    fragment float4 vis_fluid_health(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                     texture2d<float, access::read> velocity [[texture(0)]],
                                     texture2d<float, access::read> ink [[texture(1)]]) {
        int block = int(u.n) / 16;
        int2 origin = int2(in.position.xy) * block;
        float maxSpeed2 = 0.0, maxInk = 0.0, energy = 0.0, flag = 0.0;
        for (int j = 0; j < block; j++) {
            for (int i = 0; i < block; i++) {
                uint2 c = uint2(origin + int2(i, j));
                float2 v = velocity.read(c).xy;
                float3 k = ink.read(c).rgb;
                if (vis_fl_bad(v.x) || vis_fl_bad(v.y) || vis_fl_bad(k.x) || vis_fl_bad(k.y) || vis_fl_bad(k.z)) {
                    flag = 1.0;
                    continue;
                }
                float s2 = v.x * v.x + v.y * v.y;
                maxSpeed2 = max(maxSpeed2, s2);
                maxInk = max(maxInk, max(k.x, max(k.y, k.z)));
                energy += 0.5 * s2 * u.h * u.h;
            }
        }
        return float4(sqrt(maxSpeed2), maxInk, energy, flag);
    }

    // The ink across the output (stretched), x gain, never above the cap; opaque.
    fragment float4 vis_fluid_display(NoiseOut in [[stage_in]], constant FluidUniforms &u [[buffer(0)]],
                                      texture2d<float, access::read> ink [[texture(0)]]) {
        float2 size = max(float2(u.width, u.height), float2(1.0));
        float3 k = vis_fl_sample(ink, in.position.xy / size, u.n).rgb * u.factor;
        return float4(vis_fl_ink(k, u.inkCap).rgb, 1.0);
    }
    """
}
