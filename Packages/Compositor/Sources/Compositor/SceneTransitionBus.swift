// SceneTransitionBus.swift — blends whole scene outputs on one transition clock (CMP-014-R2 to R9;
// ADR-0042; specs/116-cmp-014-compositor-transition-bus/contracts/transition-bus.md).
//
// A scene output is one CMP-001 compositor with its CMP-002 stack. The bus shows the live scene and,
// during a transition, the outgoing scene too (at most two). Per frame:
//   1. the transition clock advances to the frame's presentation time (one clock: the frame timeline);
//      at progress ≥ 1 the outgoing scene and the blend target are released before anything is encoded;
//   2. each held scene runs its stack phase (`Compositor.encodeScene`) for the same presentation time;
//   3. the shown texture is the outgoing scene's composite at progress 0, the live scene's composite with
//      no transition or from progress 1, and otherwise one full-screen mix pass into a pooled
//      `rgba16Float` blend target (crossfade or dip to black at the eased progress);
//   4. the bus's one composite flash guard (FX-019) runs on the shown texture and the output pass
//      (`cmp_output`, the compositor's own shader source) writes it × the gain into the caller's texture
//      (FX-002, ADR-0047: both through the output tone map, as `Compositor.composite(into:)`).
// Steps 3–4 at progress 0 and ≥ 1 are the scene's own composite through the same guard and output code as
// `Compositor.composite(into:)`, so those frames are byte-identical to the scene alone given the same guard
// history. The blend target is the only texture the bus takes from the pool; it goes back (fenced by the last
// command buffer) at the end, on cancel, on interruption, on a size change and in `deinit`. A released scene
// returns its own pictures in its `deinit`. Nothing is cached: every blended frame is mixed again (CMP-013's
// reuse stays inside each scene). Not Sendable: one thread drives the bus and its scenes.
// FX-009 (ADR-0051): each scene's `encodeScene` returns its trails frame while its Trails are active; a cut to another
// scene and a transition start reset the trails of the scenes involved, so no trail crosses a scene change.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import FlashSafety
import Metal

public final class SceneTransitionBus {
    public let device: MTLDevice
    /// Where the blend target comes from (share the scenes' pool).
    public let texturePool: TexturePool
    private let fullScreen: MTLFunction
    private let library: MTLLibrary
    private let mixPipeline: MTLRenderPipelineState
    private var outputPipelines: [(format: MTLPixelFormat, state: MTLRenderPipelineState)] = []
    private let flashGuard: CompositeFlashGuard
    /// FX-002-R7: where the output pass counts non-finite pixels of the shown texture.
    private let nonFiniteCounter: NonFiniteOutputCounter
    private var frameClock = LayerFrameClock()

    /// The scene shown (the incoming one during a transition).
    public private(set) var liveScene: Compositor?
    /// The scene being left during a transition.
    public private(set) var outgoingScene: Compositor?
    /// The running transition's clock and spec (nil: none).
    public private(set) var clock: SceneTransitionClock?
    public private(set) var activeSpec: SceneTransitionSpec?
    private var blendTarget: MTLTexture?
    private var lastCommandBuffer: MTLCommandBuffer?
    private var shownTexture: MTLTexture?
    private weak var outputCommandBuffer: MTLCommandBuffer?
    /// FX-003: the grade's block and the block of the frame last shown (`encodeOutput` repeats it).
    private var gradeBlock = CompositorShaders.GradeBlock.neutral
    private var shownGradeBlock = CompositorShaders.GradeBlock.neutral

    /// FX-003 (ADR-0050): the colour grade of the bus's output pass and flash guard (as `Compositor.colorGrade`; the
    /// scenes' own `colorGrade` is not used here, since the bus runs its own output pass).
    public var colorGrade: ColorGrade = .neutral {
        didSet { gradeBlock = CompositorShaders.GradeBlock(colorGrade.coefficients) }
    }

    /// Frames drawn through the mix pass so far (tests, diagnostics).
    public private(set) var blendedFrames = 0
    /// The raw clock progress of the last encoded frame (1 with no transition).
    public private(set) var lastProgress = 1.0

    public init(device: MTLDevice, texturePool: TexturePool? = nil) throws(CompositorError) {
        self.device = device
        self.texturePool = texturePool ?? TexturePool(device: device)
        library = try CompositorShaders.library(device: device, source: CompositorShaders.source + Self.mixSource)
        fullScreen = try CompositorShaders.function(library, "cmp_fullscreen")
        mixPipeline = try CompositorShaders.pipeline(device: device, vertex: fullScreen,
                                                     fragment: try CompositorShaders.function(library, "cmp_transition_mix"),
                                                     format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                     label: "CMP-014 transition mix")
        flashGuard = try CompositeFlashGuard(device: device)
        nonFiniteCounter = try NonFiniteOutputCounter(device: device)
    }

    deinit {
        if let blendTarget { texturePool.recycle(blendTarget, after: lastCommandBuffer) }
    }

    /// Weighted sum of two premultiplied composites (`w.x` outgoing, `w.y` incoming).
    static let mixSource = """

    fragment float4 cmp_transition_mix(FullScreenOut in [[stage_in]], texture2d<float, access::read> outgoing [[texture(0)]],
                                       texture2d<float, access::read> incoming [[texture(1)]], constant float2 &w [[buffer(0)]]) {
        uint2 p = uint2(in.position.xy);
        return outgoing.read(p) * w.x + incoming.read(p) * w.y;
    }
    """

    // MARK: - Scenes

    public var isTransitioning: Bool { outgoingScene != nil }

    /// True while the bus holds a blend target from the pool (tests, diagnostics).
    public var holdsBlendTarget: Bool { blendTarget != nil }

    /// A cut: `scene` is shown from the next frame; any transition ends and its outgoing scene is released.
    /// FX-009-R5: a cut is a scene change, so the shown scene's trails start clean.
    public func show(_ scene: Compositor) {
        endTransition()
        if liveScene !== scene { scene.resetFeedback() }
        liveScene = scene
    }

    /// Starts a transition from the live scene to `scene` (CMP-014-R2, R6, R10). The spec is resolved with
    /// Reduce Motion first (a cut when on); an instant spec, or no live scene, is a cut. A running transition
    /// snaps to its end first (its incoming scene becomes the one left). Progress is 0 on the next frame.
    public func transition(to scene: Compositor, spec: SceneTransitionSpec, reduceMotion: Bool) {
        let resolved = spec.resolved(reduceMotion: reduceMotion)
        guard let current = liveScene, current !== scene, !resolved.isInstant else {
            show(scene)
            return
        }
        if isTransitioning { finishNow() }   // interruption: snap, then start from there
        guard let from = liveScene, from !== scene else { return }
        outgoingScene = from
        liveScene = scene
        from.resetFeedback()   // FX-009-R5: a transition start clears both scenes' trails
        scene.resetFeedback()
        clock = SceneTransitionClock(spec: resolved)
        activeSpec = resolved
    }

    /// Back to the outgoing scene at once; the incoming scene and the blend target are released.
    public func cancel() {
        guard let outgoing = outgoingScene else { return }
        endTransition()
        liveScene = outgoing
    }

    /// The incoming scene stays, at once; the outgoing scene and the blend target are released.
    public func finishNow() { endTransition() }

    /// The visualizer paused: the next frame adds no transition time (progress holds across any gap).
    public func pause() { clock?.pause() }

    private func endTransition() {
        outgoingScene = nil
        clock = nil
        activeSpec = nil
        if let blendTarget { texturePool.recycle(blendTarget, after: lastCommandBuffer) }
        blendTarget = nil
    }

    // MARK: - Frames

    /// The flash guard's gain of the last completed frame (read after its command buffer completed).
    public var lastFlashGain: Float { flashGuard.lastGain }

    /// Forgets the flash history (FX-019-R11); a transition does not call it.
    public func resetFlashHistory() { flashGuard.reset() }

    /// FX-002-R7: shown pixels with a NaN or infinite channel that the screen output pass tone-mapped to 0 so far
    /// (cumulative; `encodeOutput` passes do not count). Exact once the last frame completed.
    public var nonFiniteOutputPixels: UInt32 { nonFiniteCounter.count }
    /// ACC-012-R5: the sensory safety profile's envelope for the final flash guard when it differs from the
    /// Reduce flashing one (`SafetyClamp.flashLimitsOverride`); nil = `forReduceFlashing(reduceFlashing)`.
    /// From the next frame; the guard's history is kept (FX-019-R11).
    public var flashLimits: FlashEnvelopeConfiguration?

    /// Encodes one shown frame into `output` (a `Compositor.supportedOutputFormats` render target). Returns
    /// false for no live scene, an empty output, an unsupported format or an encoding failure.
    public func encodeFrame(into output: MTLTexture, commandBuffer: MTLCommandBuffer, presentationTimeNanoseconds: UInt64,
                            contentScale: Double, reduceFlashing: Bool, audio: LayerAudioContext) -> Bool {
        guard let live = liveScene, let size = LayerPictureDescriptor(width: output.width, height: output.height),
              let pipeline = outputPipeline(for: output.pixelFormat) else { return false }
        let frame = frameClock.next(presentationTimeNanoseconds: presentationTimeNanoseconds, outputWidth: size.width,
                                    outputHeight: size.height, contentScale: contentScale, reduceFlashing: reduceFlashing)
        var progress = 1.0
        if var running = clock {
            progress = running.advance(presentationTimeNanoseconds: presentationTimeNanoseconds)
            clock = running
            if progress >= 1 { endTransition() }   // the end: B alone from this frame, A released
        }
        lastProgress = progress
        let shown: MTLTexture
        if let outgoing = outgoingScene, let running = clock, let spec = activeSpec {
            guard let a = outgoing.encodeScene(width: size.width, height: size.height, commandBuffer: commandBuffer,
                                               presentationTimeNanoseconds: presentationTimeNanoseconds, contentScale: contentScale,
                                               reduceFlashing: reduceFlashing, audio: audio),
                  let b = live.encodeScene(width: size.width, height: size.height, commandBuffer: commandBuffer,
                                           presentationTimeNanoseconds: presentationTimeNanoseconds, contentScale: contentScale,
                                           reduceFlashing: reduceFlashing, audio: audio) else { return false }
            if progress <= 0 {
                shown = a   // the exact start: the outgoing scene alone
            } else {
                let weights = SceneTransitionMix.weights(style: spec.style, eased: running.easedProgress)
                guard let mixed = encodeMix(a, b, weights: weights, size: size, commandBuffer: commandBuffer) else { return false }
                shown = mixed
                blendedFrames += 1
            }
        } else {
            guard let b = live.encodeScene(width: size.width, height: size.height, commandBuffer: commandBuffer,
                                           presentationTimeNanoseconds: presentationTimeNanoseconds, contentScale: contentScale,
                                           reduceFlashing: reduceFlashing, audio: audio) else { return false }
            shown = b
        }
        lastCommandBuffer = commandBuffer
        shownGradeBlock = gradeBlock
        guard flashGuard.encode(composite: shown, commandBuffer: commandBuffer, frameDuration: frame.frameDuration,
                                reduceFlashing: reduceFlashing, flashLimits: flashLimits, grade: shownGradeBlock) else { return false }
        guard encodeOutputPass(shown, into: output, pipeline: pipeline, label: "CMP-014 output", counts: true,
                               commandBuffer: commandBuffer) else {
            return false
        }
        shownTexture = shown
        outputCommandBuffer = commandBuffer
        return true
    }

    /// CMP-014-R9: the output pass of the frame just encoded into `commandBuffer`, again into `target`
    /// (recording, a second display), cropped from the top left. False when no frame was encoded into this
    /// command buffer, the target is larger, or its format is unsupported.
    public func encodeOutput(into target: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let shown = shownTexture, let encoded = outputCommandBuffer, encoded === commandBuffer,
              target.width <= shown.width, target.height <= shown.height,
              let pipeline = outputPipeline(for: target.pixelFormat) else { return false }
        return encodeOutputPass(shown, into: target, pipeline: pipeline, label: "CMP-014 extra output", counts: false,
                                commandBuffer: commandBuffer)
    }

    private func encodeMix(_ a: MTLTexture, _ b: MTLTexture, weights: SceneTransitionWeights, size: LayerPictureDescriptor,
                           commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let existing = blendTarget, existing.width != size.width || existing.height != size.height {
            texturePool.recycle(existing, after: lastCommandBuffer)   // a size change mid-transition
            blendTarget = nil
        }
        if blendTarget == nil {
            guard let made = texturePool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
            made.label = "CMP-014 blend target"
            blendTarget = made
        }
        guard let target = blendTarget else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "CMP-014 transition mix"
        encoder.setRenderPipelineState(mixPipeline)
        encoder.setFragmentTexture(a, index: 0)
        encoder.setFragmentTexture(b, index: 1)
        var w = SIMD2<Float>(weights.outgoing, weights.incoming)
        encoder.setFragmentBytes(&w, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return target
    }

    /// `counts`: the screen pass binds the non-finite counter, any other output the sink (FX-002-R7).
    private func encodeOutputPass(_ shown: MTLTexture, into target: MTLTexture, pipeline: MTLRenderPipelineState, label: String,
                                  counts: Bool, commandBuffer: MTLCommandBuffer) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = label
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(shown, index: 0)
        encoder.setFragmentBuffer(flashGuard.gainBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(counts ? nonFiniteCounter.counter : nonFiniteCounter.sink, offset: 0, index: 1)
        Compositor.bindGrade(shownGradeBlock, encoder)   // FX-003
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func outputPipeline(for format: MTLPixelFormat) -> MTLRenderPipelineState? {
        for entry in outputPipelines where entry.format == format { return entry.state }
        guard Compositor.supportedOutputFormats.contains(format),
              let fragment = library.makeFunction(name: "cmp_output"),
              let state = try? CompositorShaders.pipeline(device: device, vertex: fullScreen, fragment: fragment, format: format,
                                                          blendOver: false, label: "CMP-014 output \(format.rawValue)") else {
            return nil
        }
        outputPipelines.append((format, state))
        return state
    }
}
#endif
