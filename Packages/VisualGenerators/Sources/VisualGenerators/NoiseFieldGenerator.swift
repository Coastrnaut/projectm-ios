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
// VIS-011: `configuration.fluidInk` draws fluid ink: `enqueueImpulse` queues onsets, `fluidScheduler` plans the fixed
// 1/60 s steps up to the frame's time (≤ 4), `fluidBound` bounds the ink for the envelope (all 64 samples), and
// `FluidInkPass` (made on the first fluid frame, never replaced) runs the steps, its health check and the display.
// Entering the mode or a loop restart starts at rest (same storage).
// VIS-012: `configuration.reactionDiffusion` draws Gray–Scott reaction diffusion: `reactionScheduler` detects bass kicks
// in the frame's bands and plans the fixed 1/60 s steps (≤ 4, Speed iterations each, ≤ 64 per frame), and
// `ReactionDiffusionPass` (made on the first reaction frame, never replaced) seeds, iterates, checks health and draws.
// Entering the mode, a preset/pattern/seed change, a loop restart or a health flag re-seeds the grid from the stored
// pattern and seed and restarts the 1 s fade-in; the envelope sees the fade-in × the brightest stop (all 64 samples).
// VIS-017: `configuration.signedDistance` draws SDF shapes with a seventh entry point (`SignedDistanceShader`): the
// bands move `signedDistanceDrive` (swell, angle, brightness), the 64 flash samples come from the CPU mirror of the same
// bounded march, and a second small uniform block (buffer 1) carries the preset's step cap and threshold and the pose.
// Entering the mode or a loop restart starts from the rest pose. `makeStepCountPipeline()` (tests) draws step counts.
// VIS-018: `configuration.tessellation` draws a polygon tiling with an eighth entry point (`TessellationShader`): the
// bands move `tessellationDrive` (inset, drift, light, brightness), the 64 flash samples come from the CPU lattice
// (`TessellationLattice`, the same tile function), and a 12-float block (buffer 1) carries the tiling, tile count,
// symmetry, mirror, the frame's drive state and the lattice origin. The drawn palette is the tessellation's own unless
// the shared one is not Spectrum (`effectivePalette`). `makeCellPipeline()` (tests) draws each pixel's tile.
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
    /// VIS-011: the fluid's step clock and impulse queue, the ink bound, and the GPU pass (nil until the first fluid frame).
    public let fluidScheduler = FluidStepScheduler()
    public private(set) var fluidBound = FluidInkBound()
    public private(set) var fluidPass: FluidInkPass?
    /// VIS-011: field resets the GPU health check forced (VIS-011-R7).
    public private(set) var fluidHealthResets = 0
    /// VIS-012: the reaction's clock, kick detector and injection queue, and the GPU pass (nil until the first frame).
    public let reactionScheduler = ReactionDiffusionScheduler()
    public private(set) var reactionPass: ReactionDiffusionPass?
    /// VIS-012: re-seeds the GPU health check forced (VIS-012-R9), and the bound of the last frame.
    public private(set) var reactionHealthReloads = 0
    public private(set) var reactionBound = SIMD3<Float>(0, 0, 0)
    /// VIS-012: the next reaction frame re-seeds; the frame time of the last re-seed (the fade-in's start).
    private var reactionReloadPending = true
    private var reactionReloadNanoseconds: UInt64 = 0
    /// VIS-012: the display's 8 palette stops (linear rgb).
    private let reactionStops: UnsafeMutablePointer<SIMD3<Float>>
    /// VIS-017: the shapes' drive (the pose of the last frame) and their uniform block.
    public private(set) var signedDistanceDrive = SignedDistanceDrive()
    private let sdfUniforms: UnsafeMutablePointer<Float>
    private var sdfPipeline: MTLRenderPipelineState?
    /// VIS-018: the tiles' drive (the state of the last frame) and their uniform block.
    public private(set) var tessellationDrive = TessellationDrive()
    private let tessUniforms: UnsafeMutablePointer<Float>
    private var tessPipeline: MTLRenderPipelineState?
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
            if configuration.effectivePalette != oldValue.effectivePalette { fillPalette(); cellsStale = true }   // VIS-018: own palette
            if let new = configuration.reactionDiffusion, let old = oldValue.reactionDiffusion, new.reloads(from: old) {
                reactionReloadPending = true   // VIS-012: a preset, pattern or seed change re-seeds
            }
        }
    }

    /// The compiled module constant (VIS-011: the fluid pass builds its pipelines from it; tests).
    let library: MTLLibrary
    /// The plain field's, the kaleidoscope's and the tunnel's pipelines (VIS-014, VIS-015: separate entry points); the
    /// one the initial configuration needs is built in `init`, the others on the first frame that needs them.
    private var plainPipeline: MTLRenderPipelineState?
    private var foldedPipeline: MTLRenderPipelineState?
    private var tunnelPipeline: MTLRenderPipelineState?

    /// Which entry point draws.
    enum Mode { case plain, folded, tunnel, waterfall, fluid, reaction, signedDistance, tessellation }

    static func mode(_ c: NoiseFieldConfiguration) -> Mode {
        if c.tessellation != nil { return .tessellation }   // VIS-018
        if c.signedDistance != nil { return .signedDistance }   // VIS-017
        if c.reactionDiffusion != nil { return .reaction }   // VIS-012
        if c.fluidInk { return .fluid }   // VIS-011
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
        let initialMode: Mode = Self.mode(self.configuration)
        reactionStops = .allocate(capacity: ReactionDiffusion.paletteStops)
        reactionStops.initialize(repeating: SIMD3<Float>(1, 1, 1), count: ReactionDiffusion.paletteStops)
        sdfUniforms = .allocate(capacity: SignedDistanceShader.uniformFloats)   // VIS-017
        sdfUniforms.initialize(repeating: 0, count: SignedDistanceShader.uniformFloats)
        tessUniforms = .allocate(capacity: TessellationShader.uniformFloats)   // VIS-018
        tessUniforms.initialize(repeating: 0, count: TessellationShader.uniformFloats)
        if initialMode == .fluid {   // VIS-011: its pass is its pipelines
            fluidPass = try FluidInkPass(device: device, library: library, targetFormat: pixelFormat)
        } else if initialMode == .reaction {   // VIS-012: likewise
            reactionPass = try ReactionDiffusionPass(device: device, library: library, targetFormat: pixelFormat)
        } else {
            let initial: MTLRenderPipelineState = try Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat,
                                                                       mode: initialMode)
            switch initialMode {
            case .plain: plainPipeline = initial
            case .folded: foldedPipeline = initial
            case .tunnel: tunnelPipeline = initial
            case .waterfall: waterfallPipeline = initial
            case .signedDistance: sdfPipeline = initial   // VIS-017
            case .tessellation: tessPipeline = initial   // VIS-018
            case .fluid, .reaction: break
            }
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
        case .plain, .fluid, .reaction: name = "vis_noise_fragment"   // VIS-011, VIS-012: drawn by their passes
        case .folded: name = "vis_kaleido_fragment"
        case .tunnel: name = "vis_tunnel_fragment"
        case .waterfall: name = "vis_waterfall_fragment"
        case .signedDistance: name = "vis_sdf_fragment"   // VIS-017
        case .tessellation: name = "vis_tess_fragment"   // VIS-018
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
        case .fluid: "VIS-011 Fluid ink"
        case .reaction: "VIS-012 Reaction diffusion"
        case .signedDistance: "VIS-017 SDF shapes"
        case .tessellation: "VIS-018 Tessellation"
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
        case .signedDistance:   // VIS-017
            if sdfPipeline == nil { sdfPipeline = try? Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat, mode: .signedDistance) }
            return sdfPipeline
        case .tessellation:   // VIS-018
            if tessPipeline == nil { tessPipeline = try? Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat, mode: .tessellation) }
            return tessPipeline
        case .fluid, .reaction:
            return nil   // VIS-011: FluidInkPass; VIS-012: ReactionDiffusionPass
        case .plain:
            if plainPipeline == nil { plainPipeline = try? Self.makePipeline(device: device, library: library, pixelFormat: pixelFormat, mode: .plain) }
            return plainPipeline
        }
    }

    deinit {
        uniforms.deinitialize(count: Self.uniformFloats); uniforms.deallocate()
        palette.deinitialize(count: NoiseFieldConfiguration.paletteColors); palette.deallocate()
        reactionStops.deinitialize(count: ReactionDiffusion.paletteStops); reactionStops.deallocate()
        sdfUniforms.deinitialize(count: SignedDistanceShader.uniformFloats); sdfUniforms.deallocate()
        tessUniforms.deinitialize(count: TessellationShader.uniformFloats); tessUniforms.deallocate()
    }

    /// VIS-018 (tests): a pipeline drawing each pixel's tile (lattice i, j, shape, edge distance in pixels) for `format`.
    func makeCellPipeline(format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        guard let vertex = library.makeFunction(name: "vis_noise_vertex"),
              let fragment = library.makeFunction(name: "vis_tess_cells_fragment") else {
            throw VisualGeneratorError.pipelineUnavailable("shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VIS-018 Tessellation cells (tests)"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = format
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// VIS-018 (tests): the tessellation uniform block the next draw uses.
    var tessellationUniforms: [Float] { (0..<TessellationShader.uniformFloats).map { (k: Int) -> Float in tessUniforms[k] } }

    /// VIS-018: writes the tessellation block for `settings` and the drive's frame; returns the frame.
    @discardableResult
    func writeTessellationUniforms(_ settings: TessellationSettings) -> TessellationFrame {
        let frame: TessellationFrame = tessellationDrive.frame
        let origin: SIMD2<Float> = TessellationLattice.origin(tiling: settings.tiling, tiles: settings.tiles)
        tessUniforms[0] = Float(settings.tiling.index)
        tessUniforms[1] = Float(settings.tiles)
        tessUniforms[2] = Float(settings.symmetry)
        tessUniforms[3] = settings.mirror ? 1 : 0
        tessUniforms[4] = frame.inset
        tessUniforms[5] = frame.drift
        tessUniforms[6] = frame.light
        tessUniforms[7] = origin.x
        tessUniforms[8] = origin.y
        return frame
    }

    /// VIS-018 (tests): draws the cell view of the current settings into `target` with `state`.
    func encodeCells(into target: MTLTexture, commandBuffer: MTLCommandBuffer, state: MTLRenderPipelineState) -> Bool {
        guard let settings = configuration.tessellation else { return false }
        writeTessellationUniforms(settings)
        writeUniforms(width: target.width, height: target.height, gain: 1)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(uniforms, length: Self.uniformFloats * MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentBytes(tessUniforms, length: TessellationShader.uniformFloats * MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    /// VIS-017-D6 (tests): a pipeline drawing each pixel's march step count in red (1 in green for a hit) for `format`.
    func makeStepCountPipeline(format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        guard let vertex = library.makeFunction(name: "vis_noise_vertex"),
              let fragment = library.makeFunction(name: "vis_sdf_steps_fragment") else {
            throw VisualGeneratorError.pipelineUnavailable("shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VIS-017 SDF step counts (tests)"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = format
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// VIS-017 (tests): the SDF uniform block the next draw uses.
    var signedDistanceUniforms: [Float] { (0..<SignedDistanceShader.uniformFloats).map { (k: Int) -> Float in sdfUniforms[k] } }

    /// VIS-017: writes the SDF block for `quality` and the drive's pose; returns the pose.
    @discardableResult
    func writeSignedDistanceUniforms(quality: SignedDistanceQuality) -> SignedDistancePose {
        let pose: SignedDistancePose = signedDistanceDrive.pose
        sdfUniforms[0] = Float(SignedDistanceScene.cap(quality))
        sdfUniforms[1] = quality.hitThreshold
        sdfUniforms[2] = pose.angle
        sdfUniforms[3] = pose.sphereRadius
        return pose
    }

    /// VIS-017 (tests): draws the step-count view of the current pose and quality into `target` with `state`.
    func encodeStepCounts(into target: MTLTexture, commandBuffer: MTLCommandBuffer, state: MTLRenderPipelineState) -> Bool {
        guard let settings = configuration.signedDistance else { return false }
        writeSignedDistanceUniforms(quality: settings.quality)
        writeUniforms(width: target.width, height: target.height, gain: 1)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(uniforms, length: Self.uniformFloats * MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentBytes(sdfUniforms, length: SignedDistanceShader.uniformFloats * MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func fillPalette() {
        let n: Int = NoiseFieldConfiguration.paletteColors
        let source: VisualPalette = configuration.effectivePalette   // VIS-018: the tessellation's own choice
        for k in 0..<n { palette[k] = source.color(bar: k, of: n).clamped }
        for k in 0..<min(n, FluidStepScheduler.paletteCount) {   // VIS-011: the splats' colours
            fluidScheduler.palette[k] = SIMD3<Float>(palette[k].red, palette[k].green, palette[k].blue)
        }
        let stops: Int = ReactionDiffusion.paletteStops   // VIS-012: 8 stops across the palette
        for k in 0..<stops {
            let c: LinearColor = palette[k * (n - 1) / (stops - 1)]
            reactionStops[k] = SIMD3<Float>(c.red, c.green, c.blue)
        }
    }

    /// The host's loop restart: drift and smoothing start over; the envelope's history is kept (FX-019-R11).
    public func restartLoop() {
        limiter.reset()
        drive.reset()
        tunnelDrive.reset()   // VIS-015
        waterfallHistory.clear()   // VIS-020: storage kept
        resetFluid()   // VIS-011
        reactionReloadPending = true   // VIS-012: re-seed
        signedDistanceDrive.reset()   // VIS-017: rest pose
        tessellationDrive.reset()   // VIS-018
    }

    /// VIS-011: queues an impulse for an ANL-004 onset at the frame's time. False when ignored or the queue is full.
    @discardableResult
    public func enqueueImpulse(atNanoseconds nanoseconds: UInt64, strength: Float, threshold: Float) -> Bool {
        fluidScheduler.enqueue(atNanoseconds: nanoseconds, strength: strength, threshold: threshold)
    }

    /// VIS-011: the field starts at rest, the clock and queue start over (storage kept).
    private func resetFluid() {
        fluidScheduler.reset()
        fluidBound.reset()
        fluidPass?.reset()
    }

    /// VIS-011: the fluid's frame (contracts/fluid-ink.md C2).
    private func encodeFluid(into target: MTLTexture, commandBuffer: MTLCommandBuffer, context: VisualFrameContext) -> Bool {
        if fluidPass == nil {
            guard let made = try? FluidInkPass(device: device, library: library, targetFormat: pixelFormat) else { return false }
            fluidPass = made
        }
        guard let pass = fluidPass else { return false }
        let c: NoiseFieldConfiguration = configuration
        if let last = lastMode, last != .fluid { resetFluid() }   // entering from another mode starts at rest
        let speedCap: Float = FluidInk.effectiveSpeedCap(reduceMotion: c.reduceMotion)
        if pass.pollHealth(speedCap: speedCap) {
            fluidHealthResets += 1
            fluidBound.reset()
            pass.reset()
        }
        fluidScheduler.reduceMotion = c.reduceMotion
        let steps: Int = fluidScheduler.advance(toNanoseconds: context.timeNanoseconds)
        for s in 0..<steps {
            var sum = SIMD3<Float>(0, 0, 0)
            for k in 0..<fluidScheduler.splatCount(step: s) {
                let splat: FluidSplat = fluidScheduler.splat(step: s, k)
                sum += SIMD3<Float>(splat.red, splat.green, splat.blue)
            }
            fluidBound.step(splatSum: sum)
        }
        let level: SIMD3<Float> = fluidBound.level
        flashAreas.loadUniform(LinearColor(red: level.x, green: level.y, blue: level.z, alpha: 1))
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: downstream, frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        } else {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        }
        lastGain = gain
        lastMode = .fluid
        let shown: Bool = target.width > 0 && target.height > 0   // size 0: the steps still run, nothing is drawn
        let encoded: Bool = pass.encode(scheduler: fluidScheduler, speedCap: speedCap, commandBuffer: commandBuffer,
                                        target: shown ? target : nil, gain: gain)
        return encoded && shown
    }

    /// VIS-012: the reaction's frame (contracts/reaction-diffusion.md C2).
    private func encodeReaction(into target: MTLTexture, commandBuffer: MTLCommandBuffer, bands: UnsafeBufferPointer<Float>,
                                context: VisualFrameContext) -> Bool {
        if reactionPass == nil {
            guard let made = try? ReactionDiffusionPass(device: device, library: library, targetFormat: pixelFormat) else { return false }
            reactionPass = made
        }
        guard let pass = reactionPass, let settings = configuration.reactionDiffusion else { return false }
        let now: UInt64 = context.timeNanoseconds
        if lastMode != .reaction { reactionReloadPending = true }   // entering the mode re-seeds
        if pass.pollHealth() {
            reactionHealthReloads += 1
            reactionReloadPending = true
        }
        if reactionReloadPending {
            reactionScheduler.reset()
            pass.requestSeed(pattern: settings.pattern, seed: settings.seed)
            reactionReloadNanoseconds = now
            reactionReloadPending = false
        }
        let scheduler: ReactionDiffusionScheduler = reactionScheduler
        scheduler.reduceMotion = configuration.reduceMotion
        scheduler.speed = settings.speed
        scheduler.seed = settings.seed
        scheduler.observeBass(MandalaBandGroups.from(bands).low, atNanoseconds: now)
        scheduler.advance(toNanoseconds: now)
        let ramp: Float = now >= reactionReloadNanoseconds
            ? ReactionDiffusion.ramp(elapsedNanoseconds: now - reactionReloadNanoseconds) : 0
        let level: SIMD3<Float> = ReactionDiffusionBound.level(stops: reactionStops, count: ReactionDiffusion.paletteStops, ramp: ramp)
        reactionBound = level
        flashAreas.loadUniform(LinearColor(red: level.x, green: level.y, blue: level.z, alpha: 1))
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: downstream, frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        } else {
            gain = flashAreas.gain(envelope: limiter.envelope, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                   configuration: context.flashConfiguration)
        }
        lastGain = gain
        lastMode = .reaction
        for k in 0..<ReactionDiffusion.paletteStops { pass.stops[k] = reactionStops[k] }
        let shown: Bool = target.width > 0 && target.height > 0   // size 0: the iterations still run, nothing is drawn
        let encoded: Bool = pass.encode(scheduler: scheduler, parameters: settings.preset.parameters, commandBuffer: commandBuffer,
                                        target: shown ? target : nil, scale: ramp * gain)
        return encoded && shown
    }

    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat else { return false }
        let c: NoiseFieldConfiguration = configuration
        let mode: Mode = Self.mode(c)
        if mode == .fluid { return encodeFluid(into: target, commandBuffer: commandBuffer, context: context) }   // VIS-011
        if mode == .reaction {   // VIS-012
            return encodeReaction(into: target, commandBuffer: commandBuffer, bands: bands, context: context)
        }
        guard let state = pipeline(mode) else { return false }
        if mode == .waterfall {   // VIS-020
            if lastMode != .waterfall { waterfallHistory.clear() }
            waterfallHistory.advance(bands: bands, timeNanoseconds: context.timeNanoseconds, reduceMotion: c.reduceMotion)
            uploadWaterfallRows(commandBuffer: commandBuffer)
            flashAreas.loadWaterfall(waterfallCells, history: waterfallHistory, brightness: Float(NoiseFieldConfiguration.maximumBrightness))
        } else if mode == .signedDistance, let settings = c.signedDistance {   // VIS-017
            if lastMode != .signedDistance { signedDistanceDrive.reset() }
            signedDistanceDrive.advance(groups: MandalaBandGroups.from(bands), timeNanoseconds: context.timeNanoseconds,
                                        reduceMotion: c.reduceMotion)
            let pose: SignedDistancePose = writeSignedDistanceUniforms(quality: settings.quality)
            flashAreas.sampleSignedDistance(pose: pose, quality: settings.quality, paletteStops: palette,
                                            width: target.width, height: target.height)
        } else if mode == .tessellation, let settings = c.tessellation {   // VIS-018
            if lastMode != .tessellation { tessellationDrive.reset() }
            tessellationDrive.advance(groups: MandalaBandGroups.from(bands), timeNanoseconds: context.timeNanoseconds,
                                      reduceMotion: c.reduceMotion)
            let frame: TessellationFrame = writeTessellationUniforms(settings)
            flashAreas.sampleTessellation(settings: settings, frame: frame, paletteStops: palette,
                                          width: target.width, height: target.height)
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
        if mode == .signedDistance {   // VIS-017
            encoder.setFragmentBytes(sdfUniforms, length: SignedDistanceShader.uniformFloats * MemoryLayout<Float>.stride, index: 1)
        }
        if mode == .tessellation {   // VIS-018
            encoder.setFragmentBytes(tessUniforms, length: TessellationShader.uniformFloats * MemoryLayout<Float>.stride, index: 1)
        }
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
        if c.signedDistance != nil {   // VIS-017: the drive's brightness in the same slot
            uniforms[3] = signedDistanceDrive.pose.brightness * gain
        }
        if c.tessellation != nil {   // VIS-018: the drive's brightness in the same slot
            uniforms[3] = tessellationDrive.frame.brightness * gain
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
        + TunnelShader.function + WaterfallShader.function + shaderBody + FluidInkShader.functions   // VIS-011: after the body
        + ReactionDiffusionShader.functions   // VIS-012: after the body
        + SignedDistanceShader.functions   // VIS-017: after the body
        + TessellationShader.functions   // VIS-018: after the body

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
