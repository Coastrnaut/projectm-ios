// NoiseFieldGenerator.swift — the noise field on Metal (VIS-013-R1, R3, R5 to R8; contracts/noise-field.md C2, C3;
// research VIS-013-D2 to D4).
//
// Per frame: VIS-007's band groups of the input bands → `NoiseFieldDrive` (smoothed warp and brightness, drift on the
// frame context's clock) → the CPU mirror's 64 samples → the strobe safety envelope's gain over 17 areas (after the
// downstream stages when `downstreamLuminance` is set; FX-001-R10, FX-019-R9) → one full-screen triangle whose
// fragment shader evaluates SHD-006's seeded noise (`SeededNoiseShader.functions`, module-authored constants only;
// SHD-011) and multiplies the palette colour by brightness × gain. Uniforms go by `setFragmentBytes` from storage
// allocated in `init`: no allocation, lock or wait per frame. The frame depends only on the configuration, the
// (bands, context) sequence and the GPU. Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal

public final class NoiseFieldGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats: [MTLPixelFormat] = [.bgra8Unorm_srgb, .rgba16Float]
    /// Floats of the uniform block: 12 scalars (48 bytes), then 16 float4 palette colours.
    static let uniformFloats = 12 + 4 * NoiseFieldConfiguration.paletteColors

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    public let limiter = FlashSafetyLimiter()
    /// The 64-sample estimate of the last frame (tests).
    public let flashAreas = NoiseFieldFlashAreas()
    /// Warp, brightness and drift of the last frame.
    public private(set) var drive = NoiseFieldDrive()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    /// Changes apply from the next frame.
    public var configuration: NoiseFieldConfiguration {
        didSet {
            configuration = configuration.clamped()
            if configuration.palette != oldValue.palette { fillPalette() }
        }
    }

    private let pipeline: MTLRenderPipelineState
    private let pass = MTLRenderPassDescriptor()
    private let uniforms: UnsafeMutablePointer<Float>
    private let palette: UnsafeMutablePointer<LinearColor>

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: NoiseFieldConfiguration = NoiseFieldConfiguration()) throws(VisualGeneratorError) {
        guard Self.supportedPixelFormats.contains(pixelFormat) else { throw .unsupportedPixelFormat(pixelFormat.rawValue) }
        self.device = device
        self.pixelFormat = pixelFormat
        self.configuration = configuration.clamped()
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw .pipelineUnavailable("shader compile: \(error.localizedDescription)")
        }
        guard let vertex = library.makeFunction(name: "vis_noise_vertex"),
              let fragment = library.makeFunction(name: "vis_noise_fragment") else {
            throw .pipelineUnavailable("shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VIS-013 Noise field"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            pipeline = try NativePipelineArchive.makeRenderPipelineState(device: device, descriptor: descriptor)   // PERF-009
        } catch {
            throw .pipelineUnavailable("pipeline: \(error.localizedDescription)")
        }
        uniforms = .allocate(capacity: Self.uniformFloats)
        uniforms.initialize(repeating: 0, count: Self.uniformFloats)
        palette = .allocate(capacity: NoiseFieldConfiguration.paletteColors)
        palette.initialize(repeating: .opaqueBlack, count: NoiseFieldConfiguration.paletteColors)
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        fillPalette()
    }

    deinit {
        uniforms.deinitialize(count: Self.uniformFloats); uniforms.deallocate()
        palette.deinitialize(count: NoiseFieldConfiguration.paletteColors); palette.deallocate()
    }

    private func fillPalette() {
        let n: Int = NoiseFieldConfiguration.paletteColors
        for k in 0..<n { palette[k] = configuration.palette.color(bar: k, of: n).clamped }
    }

    /// The host's loop restart: drift and smoothing start over; the envelope's history is kept (FX-019-R11).
    public func restartLoop() {
        limiter.reset()
        drive.reset()
    }

    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat else { return false }
        let c: NoiseFieldConfiguration = configuration
        drive.advance(groups: MandalaBandGroups.from(bands), timeNanoseconds: context.timeNanoseconds,
                      frameDuration: context.frameDuration, configuration: c)
        flashAreas.sample(configuration: c, drive: drive, paletteStops: palette, width: target.width, height: target.height)
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: downstream, frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        } else {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        }
        lastGain = gain
        writeUniforms(width: target.width, height: target.height, gain: gain)
        pass.colorAttachments[0].texture = target
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "VIS-013 Noise field"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(uniforms, length: Self.uniformFloats * MemoryLayout<Float>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        pass.colorAttachments[0].texture = nil
        return true
    }

    private func writeUniforms(width: Int, height: Int, gain: Float) {
        let c: NoiseFieldConfiguration = configuration
        uniforms[0] = Float(width)
        uniforms[1] = Float(height)
        uniforms[2] = Float(drive.phase)
        uniforms[3] = Float(drive.brightness) * gain
        uniforms[4] = Float(c.frequency)
        uniforms[5] = Float(drive.warp)
        uniforms[6] = Float(c.octaves)
        uniforms[7] = Float(c.seed)
        uniforms[8] = NoiseFieldConfiguration.lacunarity
        uniforms[9] = NoiseFieldConfiguration.gain
        for k in 0..<NoiseFieldConfiguration.paletteColors {
            let color: LinearColor = palette[k]
            uniforms[12 + 4 * k] = color.red
            uniforms[13 + 4 * k] = color.green
            uniforms[14 + 4 * k] = color.blue
            uniforms[15 + 4 * k] = 1
        }
    }

    /// Module-authored shader: SHD-006's shared noise functions, then the field (no user text; SHD-011).
    public static let shaderSource: String = shaderHeader + SeededNoiseShader.functions + shaderBody

    static let shaderHeader = """
    #include <metal_stdlib>
    using namespace metal;

    """

    static let shaderBody = """

    struct NoiseOut { float4 position [[position]]; };

    // Matches NoiseFieldGenerator.writeUniforms (304 bytes).
    struct NoiseUniforms {
        float2 size;
        float phase;
        float brightness;
        float frequency;
        float warp;
        float octaves;
        float seed;
        float lacunarity;
        float gain;
        float2 pad;
        float4 palette[16];
    };

    vertex NoiseOut vis_noise_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        NoiseOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    fragment float4 vis_noise_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]]) {
        float2 size = max(u.size, float2(1.0));
        float2 p = (in.position.xy - 0.5 * size) / min(size.x, size.y);
        int octaves = clamp(int(u.octaves + 0.5), 1, 8);
        uint seed = uint(clamp(u.seed, 0.0, 65535.0) + 0.5);
        float2 q = p * u.frequency + float2(u.phase, 0.5 * u.phase);
        if (u.warp > 0.0) {
            float2 wq = q;
            float wx = mat_sfbm(wq + float2(3.1, 7.7), octaves, u.lacunarity, u.gain, seed, 1u);
            float wy = mat_sfbm(wq + float2(8.3, 2.8), octaves, u.lacunarity, u.gain, seed, 2u);
            q += u.warp * (float2(wx, wy) - 0.5);
        }
        float n = mat_sfbm(q, octaves, u.lacunarity, u.gain, seed, 0u);
        float position = clamp((n - 0.2) / 0.6, 0.0, 1.0) * 15.0;
        int i = min(int(position), 14);
        float f = position - float(i);
        float3 c = mix(u.palette[i].rgb, u.palette[i + 1].rgb, f) * (0.25 + 0.75 * n) * u.brightness;
        c = select(c, float3(0.0), isnan(c) || isinf(c));
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }
    """
}
#endif
