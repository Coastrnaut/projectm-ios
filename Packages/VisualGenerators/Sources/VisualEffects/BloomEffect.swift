// BloomEffect.swift — the thresholded glow on Metal (FX-001-R3 to R9, R12, R14, R15; research
// FX-001-D2, D3, D8; contracts/post-process-effect.md).
//
// Passes, all reading with `read` and explicit zero padding (no sampler filtering):
// 1. compute `fx_bloom_prefilter`: soft-knee threshold per input pixel, D × D block sum / D²
//    → reduced image A (`rgba16Float`);
// 2. compute `fx_bloom_blur_h`: A → B, normalized Gaussian taps −R…R;
// 3. compute `fx_bloom_blur_v`: B → A;
// 4. render `fx_bloom_composite` into the output: input + k · bilinear(A), alpha min(1, ·).
// When pass-through (off or intensity 0) `encode` copies the input exactly: a blit, or a copy render
// pass when the output is `framebufferOnly`.
//
// Working textures A and B are sized for the smallest factor (D = 2) when the output size changes, so
// changing the radius (and with it D) never creates a texture; the kernels use only the plan's
// reduced region. Uniforms go through `setBytes`. Per frame this file creates nothing (Metal's
// encoders are the system's). Shader source is compiled at runtime from `shaderSource` (ADR-0009
// decision 3) with safe math. Not Sendable: one thread drives the effect.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import VisualGenerators

/// Mirrors `BloomUniforms` in `BloomEffect.shaderSource` (104 bytes).
struct BloomUniforms {
    var threshold: Float = 0.7
    var knee: Float = 0.35
    var intensity: Float = 0
    var downsample: Int32 = 2
    var radius: Int32 = 1
    var width: Int32 = 1
    var height: Int32 = 1
    var reducedWidth: Int32 = 1
    var reducedHeight: Int32 = 1
    var weights: (Float, Float, Float, Float, Float, Float, Float, Float, Float,
                  Float, Float, Float, Float, Float, Float, Float, Float) =
        (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

public final class BloomEffect: PostProcessEffect {
    public static let supportedPixelFormats: [MTLPixelFormat] = [.bgra8Unorm_srgb, .rgba16Float]
    static let workingFormat: MTLPixelFormat = .rgba16Float
    static let threadgroup = MTLSize(width: 8, height: 8, depth: 1)

    public let identifier = EffectIdentifier.bloom
    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat

    /// Changing them is a CPU-only update from the next frame (FX-001-R12).
    public var parameters: BloomParameters {
        didSet {
            parameters = parameters.clamped()
            // The plan never reads the intensity: an intensity-only change (MOD-002 modulation, every
            // frame) updates the uniforms without building a new plan and its weight array.
            var sameExceptIntensity = oldValue
            sameExceptIntensity.intensity = parameters.intensity
            if sameExceptIntensity == parameters {
                updateUniforms()
            } else {
                updatePlan()
            }
        }
    }

    /// PERF-003-R6: the effect quality level. A change rebuilds the plan once (no texture is created: the working
    /// textures are sized for D = 2); `.minimal` makes the effect pass-through, so a chain skips it.
    public var quality: EffectQualityLevel = .full {
        didSet { if quality != oldValue { updatePlan() } }
    }
    /// PERF-003-S2: compute dispatches and render passes encoded so far (4 per glowing frame; 1 per copy).
    public private(set) var encodedPassCount = 0

    /// The plan for the prepared size and current parameters (nil before `prepare`).
    public private(set) var plan: BloomPlan?
    /// Counts working-texture creations (tests, diagnostics).
    public private(set) var resourceGeneration = 0
    /// Counts plan builds (tests: MOD-002 keeps intensity-only changes from rebuilding the plan).
    public private(set) var planBuildCount = 0

    private let prefilter: MTLComputePipelineState
    private let blurH: MTLComputePipelineState
    private let blurV: MTLComputePipelineState
    private let composite: MTLRenderPipelineState
    private let copy: MTLRenderPipelineState
    private let pass = MTLRenderPassDescriptor()
    private var reducedA: MTLTexture?
    private var reducedB: MTLTexture?
    private var uniforms = BloomUniforms()

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                parameters: BloomParameters = BloomParameters()) throws(VisualGeneratorError) {
        guard Self.supportedPixelFormats.contains(pixelFormat) else { throw .unsupportedPixelFormat(pixelFormat.rawValue) }
        self.device = device
        self.pixelFormat = pixelFormat
        self.parameters = parameters.clamped()
        let library = try EffectShaderCompiler.library(device: device, source: Self.shaderSource)
        func function(_ name: String) throws(VisualGeneratorError) -> MTLFunction {
            guard let f = library.makeFunction(name: name) else { throw .pipelineUnavailable("shader function \(name) missing") }
            return f
        }
        func computePipeline(_ name: String) throws(VisualGeneratorError) -> MTLComputePipelineState {
            let f = try function(name)
            do { return try device.makeComputePipelineState(function: f) } catch {
                throw .pipelineUnavailable("pipeline \(name): \(error.localizedDescription)")
            }
        }
        func renderPipeline(_ fragment: String) throws(VisualGeneratorError) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.label = "FX-001 \(fragment)"
            d.vertexFunction = try function("fx_fullscreen_vertex")
            d.fragmentFunction = try function(fragment)
            d.colorAttachments[0].pixelFormat = pixelFormat
            d.colorAttachments[0].isBlendingEnabled = false
            do { return try device.makeRenderPipelineState(descriptor: d) } catch {
                throw .pipelineUnavailable("pipeline \(fragment): \(error.localizedDescription)")
            }
        }
        prefilter = try computePipeline("fx_bloom_prefilter")
        blurH = try computePipeline("fx_bloom_blur_h")
        blurV = try computePipeline("fx_bloom_blur_v")
        composite = try renderPipeline("fx_bloom_composite")
        copy = try renderPipeline("fx_copy")
        pass.colorAttachments[0].loadAction = .dontCare   // the triangle covers every pixel
        pass.colorAttachments[0].storeAction = .store
    }

    public var isPassThrough: Bool { parameters.isPassThrough || quality == .minimal }

    public func prepare(width: Int, height: Int) throws(VisualGeneratorError) {
        let w = max(width, 1), h = max(height, 1)
        if let plan, plan.width == w, plan.height == h, reducedA != nil { return }
        let rw = (w + 1) / 2, rh = (h + 1) / 2   // D = 2, the largest reduced image
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.workingFormat, width: rw, height: rh, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .private
        guard let a = device.makeTexture(descriptor: d), let b = device.makeTexture(descriptor: d) else {
            throw .pipelineUnavailable("bloom working textures \(rw)×\(rh)")
        }
        a.label = "FX-001 bloom A"
        b.label = "FX-001 bloom B"
        reducedA = a
        reducedB = b
        resourceGeneration += 1
        plan = BloomPlan(parameters: parameters, width: w, height: h, quality: quality)
        planBuildCount += 1
        updateUniforms()
    }

    private func updatePlan() {
        guard let old = plan else { return }
        plan = BloomPlan(parameters: parameters, width: old.width, height: old.height, quality: quality)
        planBuildCount += 1
        updateUniforms()
    }

    private func updateUniforms() {
        guard let plan else { return }
        var u = BloomUniforms()
        u.threshold = parameters.threshold
        u.knee = parameters.kneeWidth
        u.intensity = parameters.intensity
        u.downsample = Int32(plan.downsample)
        u.radius = Int32(plan.blurRadius)
        u.width = Int32(plan.width)
        u.height = Int32(plan.height)
        u.reducedWidth = Int32(plan.reducedWidth)
        u.reducedHeight = Int32(plan.reducedHeight)
        withUnsafeMutableBytes(of: &u.weights) { raw in
            let w = raw.bindMemory(to: Float.self)
            for i in 0..<w.count { w[i] = i < plan.weights.count ? plan.weights[i] : 0 }
        }
        uniforms = u
    }

    public func encode(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let plan, let a = reducedA, let b = reducedB, input !== output,
              input.pixelFormat == pixelFormat, output.pixelFormat == pixelFormat,
              input.width == plan.width, input.height == plan.height,
              output.width == plan.width, output.height == plan.height else { return false }
        if isPassThrough { return encodeCopy(input: input, output: output, commandBuffer: commandBuffer) }

        let groups = MTLSize(width: (plan.reducedWidth + 7) / 8, height: (plan.reducedHeight + 7) / 8, depth: 1)
        guard let compute = commandBuffer.makeComputeCommandEncoder() else { return false }
        compute.label = "FX-001 bloom threshold and blur"
        withUnsafeBytes(of: &uniforms) { compute.setBytes($0.baseAddress!, length: $0.count, index: 0) }
        compute.setComputePipelineState(prefilter)
        compute.setTexture(input, index: 0)
        compute.setTexture(a, index: 1)
        compute.dispatchThreadgroups(groups, threadsPerThreadgroup: Self.threadgroup)
        compute.setComputePipelineState(blurH)
        compute.setTexture(a, index: 0)
        compute.setTexture(b, index: 1)
        compute.dispatchThreadgroups(groups, threadsPerThreadgroup: Self.threadgroup)
        compute.setComputePipelineState(blurV)
        compute.setTexture(b, index: 0)
        compute.setTexture(a, index: 1)
        compute.dispatchThreadgroups(groups, threadsPerThreadgroup: Self.threadgroup)
        compute.endEncoding()

        let attachment = pass.colorAttachments[0]!
        attachment.texture = output
        defer { attachment.texture = nil }   // do not keep the caller's drawable alive
        guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        render.label = "FX-001 bloom composite"
        render.setRenderPipelineState(composite)
        render.setFragmentTexture(input, index: 0)
        render.setFragmentTexture(a, index: 1)
        withUnsafeBytes(of: &uniforms) { render.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
        encodedPassCount += 4   // three dispatches + the composite
        return true
    }

    private func encodeCopy(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        if !output.isFramebufferOnly {
            guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
            blit.copy(from: input, to: output)
            blit.endEncoding()
            encodedPassCount += 1
            return true
        }
        let attachment = pass.colorAttachments[0]!
        attachment.texture = output
        defer { attachment.texture = nil }
        guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        render.setRenderPipelineState(copy)
        render.setFragmentTexture(input, index: 0)
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
        encodedPassCount += 1
        return true
    }

    /// The shaders (ADR-0009 decision 3). `fx_bloom_weight` is `BloomParameters.contribution`.
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct BloomUniforms {
        float threshold;
        float knee;
        float intensity;
        int downsample;
        int radius;
        int width;
        int height;
        int reducedWidth;
        int reducedHeight;
        float weights[17];
    };

    static float4 fx_sanitize(float4 c) {
        c = select(c, float4(0.0), isnan(c) || isinf(c));
        return clamp(c, 0.0, 64.0);
    }

    static float fx_bloom_weight(float b, float t, float k) {
        float low = t - k;
        float soft = clamp(b - low, 0.0, 2.0 * k);
        soft = soft * soft / (4.0 * k + 1e-5);
        float w = max(soft, b - t) / max(b, 1e-5);
        return clamp(w, 0.0, 1.0);
    }

    kernel void fx_bloom_prefilter(texture2d<float, access::read> src [[texture(0)]],
                                   texture2d<float, access::write> dst [[texture(1)]],
                                   constant BloomUniforms &u [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
        if (int(gid.x) >= u.reducedWidth || int(gid.y) >= u.reducedHeight) return;
        int d = u.downsample;
        float4 sum = float4(0.0);
        for (int dy = 0; dy < d; dy++) {
            int y = int(gid.y) * d + dy;
            if (y >= u.height) break;
            for (int dx = 0; dx < d; dx++) {
                int x = int(gid.x) * d + dx;
                if (x >= u.width) break;
                float4 c = fx_sanitize(src.read(uint2(x, y)));
                float b = max(c.r, max(c.g, c.b));
                sum += c * fx_bloom_weight(b, u.threshold, u.knee);
            }
        }
        dst.write(sum / float(d * d), gid);
    }

    kernel void fx_bloom_blur_h(texture2d<float, access::read> src [[texture(0)]],
                                texture2d<float, access::write> dst [[texture(1)]],
                                constant BloomUniforms &u [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
        if (int(gid.x) >= u.reducedWidth || int(gid.y) >= u.reducedHeight) return;
        float4 sum = src.read(gid) * u.weights[0];
        for (int i = 1; i <= u.radius; i++) {
            int l = int(gid.x) - i, r = int(gid.x) + i;
            if (l >= 0) sum += src.read(uint2(l, gid.y)) * u.weights[i];
            if (r < u.reducedWidth) sum += src.read(uint2(r, gid.y)) * u.weights[i];
        }
        dst.write(sum, gid);
    }

    kernel void fx_bloom_blur_v(texture2d<float, access::read> src [[texture(0)]],
                                texture2d<float, access::write> dst [[texture(1)]],
                                constant BloomUniforms &u [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
        if (int(gid.x) >= u.reducedWidth || int(gid.y) >= u.reducedHeight) return;
        float4 sum = src.read(gid) * u.weights[0];
        for (int i = 1; i <= u.radius; i++) {
            int t = int(gid.y) - i, b = int(gid.y) + i;
            if (t >= 0) sum += src.read(uint2(gid.x, t)) * u.weights[i];
            if (b < u.reducedHeight) sum += src.read(uint2(gid.x, b)) * u.weights[i];
        }
        dst.write(sum, gid);
    }

    struct FullscreenOut {
        float4 position [[position]];
    };

    vertex FullscreenOut fx_fullscreen_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        FullscreenOut out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    static float4 fx_glow_texel(texture2d<float, access::read> glow, int x, int y, constant BloomUniforms &u) {
        if (x < 0 || y < 0 || x >= u.reducedWidth || y >= u.reducedHeight) return float4(0.0);
        return glow.read(uint2(x, y));
    }

    fragment float4 fx_bloom_composite(FullscreenOut in [[stage_in]],
                                       texture2d<float, access::read> src [[texture(0)]],
                                       texture2d<float, access::read> glow [[texture(1)]],
                                       constant BloomUniforms &u [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        float4 c = src.read(p);
        float d = float(u.downsample);
        float gx = (float(p.x) + 0.5) / d - 0.5;
        float gy = (float(p.y) + 0.5) / d - 0.5;
        float fx = floor(gx), fy = floor(gy);
        float ax = gx - fx, ay = gy - fy;
        int x0 = int(fx), y0 = int(fy);
        float4 top = mix(fx_glow_texel(glow, x0, y0, u), fx_glow_texel(glow, x0 + 1, y0, u), ax);
        float4 bottom = mix(fx_glow_texel(glow, x0, y0 + 1, u), fx_glow_texel(glow, x0 + 1, y0 + 1, u), ax);
        float4 g = mix(top, bottom, ay);
        float4 o = c + u.intensity * g;
        o.a = min(1.0, c.a + u.intensity * g.a);
        return o;
    }

    fragment float4 fx_copy(FullscreenOut in [[stage_in]],
                            texture2d<float, access::read> src [[texture(0)]]) {
        return src.read(uint2(in.position.xy));
    }
    """
}
#endif
