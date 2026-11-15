// NoiseFieldGenerator.swift — the noise field on Metal (VIS-013-R1, R3, R5 to R8; contracts/noise-field.md C2, C3;
// research VIS-013-D2 to D4).
//
// VIS-014: `configuration.wedges` ≥ 2 draws with a second entry point that folds every pixel into one kaleidoscope wedge
// first (`KaleidoscopeFold`, turned by the drive's rotation); 0 uses the plain entry point, frame for frame as before.
// VIS-015: `configuration.tunnelPace` > 0 draws the tunnel with a third entry point (`TunnelShader`), moved by
// `TunnelDrive` at the speed `tempo` (set by the host every frame) gives; its phase and brightness go into the same
// uniform slots, so the block's layout is unchanged.
// VIS-020: `configuration.waterfall` draws the spectrum waterfall with a fourth entry point that reads `historyTexture`
// (256 × 512 levels, made in `init` with its staging buffer and never replaced): each frame the bands go into
// `SpectrumWaterfallHistory`, the rows it wrote are copied ring → staging → texture by a blit in the frame's own command
// buffer before the draw, and the newest row's index goes in the phase slot. Entering the mode or a loop restart clears
// the history (same storage).
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
    /// VIS-015: the tempo the tunnel follows (the host sets it every frame; `.none` → base speed).
    public var tempo: TunnelTempo = .none
    /// VIS-015: the tunnel's speed, brightness and phase of the last frame.
    public private(set) var tunnelDrive = TunnelDrive()
    /// VIS-020: the waterfall's history ring (fixed storage).
    public let waterfallHistory = SpectrumWaterfallHistory()
    /// VIS-020: the GPU copy of the ring (256 × 512 `r8Unorm`, private), made once in `init`.
    public let historyTexture: MTLTexture
    /// VIS-020: what each flash estimate cell shows.
    public let waterfallCells = WaterfallFlashCells()
    private let historyStaging: MTLBuffer
    private var waterfallPipeline: MTLRenderPipelineState?
    /// The mode of the last frame drawn (VIS-020: entering the waterfall clears its history).
    private var lastMode: Mode?
    /// VIS-020: the cells' sums were made with an older palette.
    private var cellsStale = true
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    /// Changes apply from the next frame.
    public var configuration: NoiseFieldConfiguration {
        didSet {
            configuration = configuration.clamped()
            if configuration.palette != oldValue.palette { fillPalette(); cellsStale = true }
        }
    }

    private let library: MTLLibrary
    /// The plain field's, the kaleidoscope's and the tunnel's pipelines (VIS-014, VIS-015: separate entry points); the
    /// one the initial configuration needs is built in `init`, the others on the first frame that needs them.
    private var plainPipeline: MTLRenderPipelineState?
    private var foldedPipeline: MTLRenderPipelineState?
    private var tunnelPipeline: MTLRenderPipelineState?

    /// Which entry point draws.
    enum Mode { case plain, folded, tunnel, waterfall }

    static func mode(_ c: NoiseFieldConfiguration) -> Mode {
        if c.waterfall { return .waterfall }   // VIS-020
        if c.isTunnel { return .tunnel }
        return c.isKaleidoscope ? .folded : .plain
    }
    private let pass = MTLRenderPassDescriptor()
    private let uniforms: UnsafeMutablePointer<Float>
    private let palette: UnsafeMutablePointer<LinearColor>

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: NoiseFieldConfiguration = NoiseFieldConfiguration()) throws(VisualGeneratorError) {
        guard Self.supportedPixelFormats.contains(pixelFormat) else { throw .unsupportedPixelFormat(pixelFormat.rawValue) }
        self.device = device
        self.pixelFormat = pixelFormat
        self.configuration = configuration.clamped()
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw .pipelineUnavailable("shader compile: \(error.localizedDescription)")
        }
        let initial: MTLRenderPipelineState = try Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat,
                                                                   mode: Self.mode(self.configuration))
        switch Self.mode(self.configuration) {
        case .plain: plainPipeline = initial
        case .folded: foldedPipeline = initial
        case .tunnel: tunnelPipeline = initial
        case .waterfall: waterfallPipeline = initial
        }
        // VIS-020: the history's GPU copy and staging rows, once; independent of any output size.
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: SpectrumWaterfallHistory.columns,
                                                         height: SpectrumWaterfallHistory.rows, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .private
        guard let texture = device.makeTexture(descriptor: d),
              let staging = device.makeBuffer(length: SpectrumWaterfallHistory.byteCount, options: .storageModeShared) else {
            throw .pipelineUnavailable("waterfall history storage")
        }
        texture.label = "VIS-020 Waterfall history"
        historyTexture = texture
        historyStaging = staging
        uniforms = .allocate(capacity: Self.uniformFloats)
        uniforms.initialize(repeating: 0, count: Self.uniformFloats)
        palette = .allocate(capacity: NoiseFieldConfiguration.paletteColors)
        palette.initialize(repeating: .opaqueBlack, count: NoiseFieldConfiguration.paletteColors)
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        fillPalette()
    }

    private static func makePipeline(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat,
                                     mode: Mode) throws(VisualGeneratorError) -> MTLRenderPipelineState {
        let name: String
        switch mode {
        case .plain: name = "vis_noise_fragment"
        case .folded: name = "vis_kaleido_fragment"
        case .tunnel: name = "vis_tunnel_fragment"
        case .waterfall: name = "vis_waterfall_fragment"
        }
        guard let vertex = library.makeFunction(name: "vis_noise_vertex"),
              let fragment = library.makeFunction(name: name) else {
            throw .pipelineUnavailable("shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = Self.label(mode)
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try NativePipelineArchive.makeRenderPipelineState(device: device, descriptor: descriptor)   // PERF-009
        } catch {
            throw .pipelineUnavailable("pipeline: \(error.localizedDescription)")
        }
    }

    static func label(_ mode: Mode) -> String {
        switch mode {
        case .plain: "VIS-013 Noise field"
        case .folded: "VIS-014 Kaleidoscope"
        case .tunnel: "VIS-015 Tunnel"
        case .waterfall: "VIS-020 Spectrum waterfall"
        }
    }

    /// The pipeline for this frame's mode, built once (nil when it cannot be built).
    private func pipeline(_ mode: Mode) -> MTLRenderPipelineState? {
        switch mode {
        case .folded:
            if foldedPipeline == nil { foldedPipeline = try? Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat, mode: .folded) }
            return foldedPipeline
        case .tunnel:
            if tunnelPipeline == nil { tunnelPipeline = try? Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat, mode: .tunnel) }
            return tunnelPipeline
        case .waterfall:
            if waterfallPipeline == nil { waterfallPipeline = try? Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat, mode: .waterfall) }
            return waterfallPipeline
        case .plain:
            if plainPipeline == nil { plainPipeline = try? Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat, mode: .plain) }
            return plainPipeline
        }
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
        tunnelDrive.reset()   // VIS-015
        waterfallHistory.clear()   // VIS-020: storage kept
    }

    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat else { return false }
        let c: NoiseFieldConfiguration = configuration
        let mode: Mode = Self.mode(c)
        guard let state = pipeline(mode) else { return false }
        if mode == .waterfall {   // VIS-020
            if lastMode != .waterfall { waterfallHistory.clear() }
            waterfallHistory.advance(bands: bands, timeNanoseconds: context.timeNanoseconds, reduceMotion: c.reduceMotion)
            uploadWaterfallRows(commandBuffer: commandBuffer)
            flashAreas.loadWaterfall(waterfallCells, history: waterfallHistory, brightness: Float(NoiseFieldConfiguration.maximumBrightness))
        } else if mode == .tunnel {   // VIS-015
            tunnelDrive.advance(groups: MandalaBandGroups.from(bands), tempo: tempo, timeNanoseconds: context.timeNanoseconds,
                                configuration: c)
            flashAreas.sampleTunnel(configuration: c, drive: tunnelDrive, paletteStops: palette, width: target.width, height: target.height)
        } else {
            drive.advance(groups: MandalaBandGroups.from(bands), timeNanoseconds: context.timeNanoseconds,
                          frameDuration: context.frameDuration, configuration: c)
            flashAreas.sample(configuration: c, drive: drive, paletteStops: palette, width: target.width, height: target.height)
        }
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: downstream, frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        } else {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        }
        lastGain = gain
        lastMode = mode
        writeUniforms(width: target.width, height: target.height, gain: gain)
        pass.colorAttachments[0].texture = target
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = Self.label(mode)
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(uniforms, length: Self.uniformFloats * MemoryLayout<Float>.stride, index: 0)
        if mode == .waterfall { encoder.setFragmentTexture(historyTexture, index: 0) }   // VIS-020
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        pass.colorAttachments[0].texture = nil
        return true
    }

    /// VIS-020: copies the rows the history wrote since the last frame to the texture, in this command buffer (before
    /// the draw), and updates their flash cell sums (all rows after a palette change). A staging row is rewritten only
    /// after 512 more rows, so no earlier frame's copy reads a row being written.
    private func uploadWaterfallRows(commandBuffer: MTLCommandBuffer) {
        let history: SpectrumWaterfallHistory = waterfallHistory
        let width: Int = SpectrumWaterfallHistory.columns
        let staging: UnsafeMutablePointer<UInt8> = historyStaging.contents().bindMemory(to: UInt8.self, capacity: SpectrumWaterfallHistory.byteCount)
        var blit: MTLBlitCommandEncoder?
        history.drainPending { (ring: Int) -> Void in
            (staging + ring * width).update(from: history.levels + ring * width, count: width)
            if blit == nil { blit = commandBuffer.makeBlitCommandEncoder() }
            blit?.copy(from: historyStaging, sourceOffset: ring * width, sourceBytesPerRow: width, sourceBytesPerImage: width,
                       sourceSize: MTLSize(width: width, height: 1, depth: 1), to: historyTexture, destinationSlice: 0,
                       destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: ring, z: 0))
            if !cellsStale { waterfallCells.update(ring: ring, history: history, stops: palette) }
        }
        blit?.endEncoding()
        if cellsStale {
            waterfallCells.updateAll(history: history, stops: palette)
            cellsStale = false
        }
    }

    private func writeUniforms(width: Int, height: Int, gain: Float) {
        let c: NoiseFieldConfiguration = configuration
        uniforms[0] = Float(width)
        uniforms[1] = Float(height)
        let tunnel: Bool = c.isTunnel   // VIS-015: the tunnel's phase (rings) and brightness in the same slots
        uniforms[2] = tunnel ? Float(tunnelDrive.phase) : Float(drive.phase)
        uniforms[3] = (tunnel ? Float(tunnelDrive.brightness) : Float(drive.brightness)) * gain
        if c.waterfall {   // VIS-020: the newest ring row and the fixed brightness (ACC-012) in the same slots
            uniforms[2] = Float(max(waterfallHistory.newestRow, 0))
            uniforms[3] = Float(NoiseFieldConfiguration.maximumBrightness) * gain
        }
        uniforms[4] = Float(c.frequency)
        uniforms[5] = Float(drive.warp)
        uniforms[6] = Float(c.octaves)
        uniforms[7] = Float(c.seed)
        uniforms[8] = NoiseFieldConfiguration.lacunarity
        uniforms[9] = NoiseFieldConfiguration.gain
        uniforms[10] = Float(c.wedges)   // VIS-014: 0 = no fold
        uniforms[11] = Float(drive.rotation)
        for k in 0..<NoiseFieldConfiguration.paletteColors {
            let color: LinearColor = palette[k]
            uniforms[12 + 4 * k] = color.red
            uniforms[13 + 4 * k] = color.green
            uniforms[14 + 4 * k] = color.blue
            uniforms[15 + 4 * k] = 1
        }
    }

    /// Module-authored shader: SHD-006's shared noise functions, VIS-014's fold, VIS-015's tunnel, then the field (no user
    /// text; SHD-011).
    public static let shaderSource: String = shaderHeader + SeededNoiseShader.functions + KaleidoscopeFoldShader.function
        + TunnelShader.function + WaterfallShader.function + shaderBody

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
        float wedges;
        float rotation;
        float4 palette[16];
    };

    vertex NoiseOut vis_noise_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        NoiseOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    // The field at domain point q (after scale and drift): warp, fBm, palette, brightness.
    static float4 vis_noise_shade(float2 q, constant NoiseUniforms &u) {
        int octaves = clamp(int(u.octaves + 0.5), 1, 8);
        uint seed = uint(clamp(u.seed, 0.0, 65535.0) + 0.5);
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

    fragment float4 vis_noise_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]]) {
        float2 size = max(u.size, float2(1.0));
        float2 p = (in.position.xy - 0.5 * size) / min(size.x, size.y);
        return vis_noise_shade(p * u.frequency + float2(u.phase, 0.5 * u.phase), u);
    }

    // VIS-014: the kaleidoscope folds p into one wedge first (its own entry point, so the plain field's code is untouched).
    fragment float4 vis_kaleido_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]]) {
        float2 size = max(u.size, float2(1.0));
        float2 p = (in.position.xy - 0.5 * size) / min(size.x, size.y);
        return vis_noise_shade(vis_kfold(p, u.wedges, u.rotation) * u.frequency + float2(u.phase, 0.5 * u.phase), u);
    }

    // VIS-015: the tunnel (its own entry point): palette at the wall's texture × light × brightness; phase in rings.
    fragment float4 vis_tunnel_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]]) {
        float2 size = max(u.size, float2(1.0));
        float2 p = (in.position.xy - 0.5 * size) / min(size.x, size.y);
        uint seed = uint(clamp(u.seed, 0.0, 65535.0) + 0.5);
        float2 s = vis_tunnel_sample(p, u.phase, seed);
        float position = clamp((s.x - 0.2) / 0.6, 0.0, 1.0) * 15.0;
        int i = min(int(position), 14);
        float f = position - float(i);
        float3 c = mix(u.palette[i].rgb, u.palette[i + 1].rgb, f) * s.y * u.brightness;
        c = select(c, float3(0.0), isnan(c) || isinf(c));
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }

    // VIS-020: the spectrum waterfall (its own entry point): palette at level v × v × brightness; newest row (phase slot)
    // at the top.
    fragment float4 vis_waterfall_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]],
                                           texture2d<float, access::read> history [[texture(0)]]) {
        float2 size = max(u.size, float2(1.0));
        float v = clamp(vis_waterfall_level(history, in.position.xy, size, u.phase), 0.0, 1.0);
        float position = v * 15.0;
        int i = min(int(position), 14);
        float f = position - float(i);
        float3 c = mix(u.palette[i].rgb, u.palette[i + 1].rgb, f) * v * u.brightness;
        c = select(c, float3(0.0), isnan(c) || isinf(c));
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }
    """
}
#endif
