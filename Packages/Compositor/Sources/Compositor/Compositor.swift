// Compositor.swift — the minimal Metal compositor (CMP-001-R6 to R10, R15; ADR-0013; research
// CMP-001-D2, D4, D6; contracts/layer-source.md "Compositor").
//
// Per frame: the frame clock → each layer, bottom to top, renders into its free picture (its
// outcome decides which picture, if any, is shown: `LayerSlots`) → one render pass accumulates the
// shown pictures with premultiplied "over" onto transparent in an `rgba16Float` composite → the
// composite flash guard (FX-019's envelope on the finished stack, GPU only) → the output pass
// writes composite × gain into the caller's texture, whose format does the encoding.
// FX-002 (contracts/tone-map.md in specs/122, ADR-0047): the output pass tone-maps the composite first
// (`cmp_tone_map`: NaN, ±Inf and negatives → 0, identity while the largest channel is ≤ 1, else luminance and hue
// kept, desaturated toward white), and the flash guard measures the same tone-mapped values, so its gain applies
// to what is shown. Every output (screen, REC-003 recording, REC-001 capture, CMP-014's bus) uses that pass; the
// screen pass counts non-finite composite pixels (`nonFiniteOutputPixels`).
// FX-003 (contracts/color-grade.md in specs/123, ADR-0050): before the tone map the output pass applies `colorGrade`
// (`cmp_grade`: temperature, lift, gamma, gain, saturation in linear light; neutral = bypass, bit for bit), and the
// flash guard measures the graded, tone-mapped values (`cmp_display`) with the same block.
//
// Ownership: the compositor creates every picture and the composite, before the first frame and
// once per output size change; layers are prepared at the same moments. At a steady size nothing
// is created per frame except Metal's own command objects; output pipelines are built the first
// time an output format appears. Not Sendable: one thread drives a compositor and its layers.
//
// CMP-002 (contracts/layer-stack.md in specs/040): the layer list is a `LayerStack` applied between
// frames with `apply(_:makeLayer:)`. Index 0 is the bottom. Kept IDs keep their pictures and state,
// new IDs are created and prepared at apply (the third allocation point), removed IDs are released.
//
// CMP-003 (contracts/layer-opacity.md in specs/043): each layer has an opacity animator; per frame it
// advances by the frame duration and the shown picture is drawn × its value (skipped at exactly 0,
// while the layer keeps rendering). `apply(_:opacityTransition:makeLayer:)` fades changed opacities.
//
// CMP-005 (contracts/layer-transform.md in specs/046): each layer has a `LayerTransform`. Identity
// layers keep the exact per-pixel "over"; the others are drawn by `cmp_over_transformed`, which
// samples the picture bilinearly through the inverse placement matrix in pixels (transparent
// outside). A transform change at apply is shown from the next frame; nothing is re-created.
//
// PERF-004 (contracts/texture-pool.md in specs/052): the composite and every picture come from a
// `TexturePool` (given, e.g. the app's shared pool, or private) and go back to it when a layer is
// removed, when the output size changes and when the compositor is released, each with the last command
// buffer this compositor encoded as its fence, so no picture is reused while a frame may still use it.
// The pool is ticked once per frame (idle-age eviction). `pictureAllocations` counts pictures taken;
// `texturePool.counters.misses` counts the ones Metal actually created.
//
// REC-001 (contracts/frame-capture.md in specs/055): `requestFrameCapture` asks for the next frame as
// shown. The next successful `composite` encodes the same output pipeline (composite × the flash
// guard's gain) a second time into a private `rgba16Float` texture and blits it into a shared buffer;
// the handler gets linear premultiplied half floats when the command buffer completes. Frames
// without a request are unchanged; the capture's texture and buffer are one-offs, not pooled.
//
// PERF-014 (contracts/render-health.md in specs/057): every call with a usable output is a frame tick.
// A layer whose prepare fails, whose pictures cannot be created or whose render throws a serious
// error (not "not ready" or "frame skipped") is a counted fault: it shows its fallback and is touched
// again only at its back-off ticks (`recoveryPolicy`: 30, 60, 120, 240), then stays on its fallback
// until `resetRenderHealth()`. The visual's own part covers GPU errors (the last three command
// buffers' `status`, polled at the start of each tick: no handler, no wait, no allocation) and a
// composite texture that cannot be created; while it backs off no layer renders and the frame is
// black. `health` is the visual's record. DEBUG builds can arm `faultInjection`, which makes creation
// or the status check fail (no faulty shader exists).
// CMP-006 (contracts/aspect-fitting.md in specs/101): a layer that adopts `LayerFitting` (photo,
// video) gets its stack entry's fit at creation and at every apply; it fits its content inside its
// own picture, so compositing (transform, opacity, blend) is unchanged.
// CMP-004 (contracts/blend-modes.md in specs/099, ADR-0037): each layer has a blend mode. Normal layers
// keep the fixed-function "over" in the open pass. A layer with another mode ends that pass and draws
// `cmp_blend` full screen into a second composite (pooled, created the first time a mode layer is drawn
// at a size), reading the composite so far as its backdrop; the two composites then swap and the "over"
// pass re-opens on the new one with load action load. A mode change at apply shows from the next frame.
// CMP-007 (contracts/shape-masks.md in specs/104): a layer with a mask is drawn with its coverage (a signed
// distance at the layer pixel, exactly 0 beyond the band) multiplied in: normal layers by `cmp_over_masked`
// in the open "over" pass (no extra pass), other modes by `cmp_blend` with the mask block. Unmasked layers
// keep their pipelines. The block is cached per record and size; a mask change at apply shows next frame.
// REC-003 (contracts/video-recording.md in specs/058): `encodeOutput(into:commandBuffer:)` encodes the
// output pass of the frame just composited once more into another target (a video recorder's pixel
// buffer texture), cropped to that target from the top left. Nothing changes for frames shown.
// CMP-011 (contracts/layer-groups.md in specs/109, ADR-0039): a grouped layer is drawn with G(a)·L(a), its
// group's placement after its own (its own path, bit for bit, while the group transform is the identity).
// A group is an isolated group: a disabled group or one at opacity 0 draws nothing (its layers still render);
// at opacity exactly 1 with only normal visible layers it is drawn flattened in the open pass (exact, since
// "over" is associative); otherwise its layers are drawn onto a cleared pooled group picture (with its own
// blend-mode partner) and that picture is drawn over the composite × the group's animated opacity.
// CMP-012 (contracts/solo-and-mute.md in specs/112): a `LayerSoloMute` overlay, kept beside the stack and
// never in it, is resolved into one flag per record at `apply` and `setSoloMute`. A hidden layer keeps
// rendering every frame; it is only left out of the composite (and so of its group's isolation decision).
// CMP-013 (contracts/render-caching.md in specs/113, ADR-0040): a layer that adopts `LayerRenderCaching` and
// declares no time, audio, modulation or external input is not rendered again while its key (generations,
// picture, content scale, Reduce flashing, cache epoch) equals the key of its last good picture (level 1). When
// no layer rendered and every draw input is unchanged, the previous composite is kept and only the layer passes
// are skipped (level 2); the flash guard, output, capture and recording run every frame. Global triggers bump
// the epoch. Output is bit-identical to `isRenderCachingEnabled = false`.
// CMP-014 (contracts/transition-bus.md in specs/116, ADR-0042): `encodeScene` runs only the stack phase and returns
// the composite, so a `SceneTransitionBus` can blend two scenes and run one flash guard on the shown frame;
// `composite(into:)` runs the same phase and then its own guard and output pass, unchanged.
// FX-009 (contracts/motion-feedback.md in specs/130, ADR-0051): while `motionFeedback` is active, one `cmp_trails` pass
// (MotionFeedbackPass.swift) turns the finished composite into the trails frame, max(composite, decay × previous), which
// the guard, every output and `encodeScene` receive; a reset (a new scene, size, output format, render-health reset,
// enabling, an unfinished frame) makes the next frame the composite only. CMP-013 never keeps the composite then.
// FX-020 (contracts/effect-chain.md in specs/142, ADR-0054): `outputEffectOrder` orders Trails and Color. Only when Color
// comes first, Trails are active and the grade is not neutral does `OutputGradePass` grade the composite before Trails
// (the guard and outputs then use the neutral block); otherwise the single-pass output above runs unchanged. The flash
// guard and the tone map always come after both. `encodeScene` never runs the grade pass (CMP-014's bus grades itself).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import FrameCapture
import FlashSafety
import Metal

public enum CompositorError: Error, Equatable, Sendable {
    /// Shaders, pipelines or the guard's buffers could not be created; the text is the system's.
    case pipelineUnavailable(String)
    /// The same layer object appears twice (at this index).
    case duplicateLayer(index: Int)
    /// The layer at this index asks for settings the compositor cannot draw. Not thrown since CMP-004
    /// (every mode is drawn); kept for source compatibility.
    case unsupportedCompositeSettings(index: Int)
    /// The factory could not create the layer of the stack entry at this index (CMP-002-R9).
    case layerCreationFailed(index: Int, LayerSourceError)
}

/// Turns a new stack entry into a live layer (CMP-002-R7). Called by `apply` only for IDs the
/// compositor does not hold yet, in index order.
public typealias LayerFactory = (LayerStackEntry) throws(LayerSourceError) -> any LayerSource

public final class Compositor {
    /// Output formats `composite` writes.
    public static let supportedOutputFormats: [MTLPixelFormat] = [.bgra8Unorm_srgb, .rgba16Float, .bgra8Unorm, .rgba8Unorm]

    /// One layer's live state (CMP-002: one record per layer, so a reorder is a permutation that
    /// keeps the pictures, the slots and the last good frame).
    private struct LayerRecord {
        /// nil for layers given to `init(device:layers:)`.
        let id: LayerInstanceID?
        let layer: any LayerSource
        var slots: LayerSlots
        var pictures: [MTLTexture] = []
        var outcome: LayerOutcome = .notRendered
        var prepareError: LayerSourceError?
        /// Picture shown this frame (−1: none).
        var shown = -1
        /// CMP-003: the shown opacity and its fade.
        var opacity: LayerOpacityAnimator
        /// CMP-005: the placement shown from the next frame.
        var transform: LayerTransform
        /// CMP-004: the blend mode shown from the next frame.
        var blendMode: LayerBlendMode
        /// CMP-007: the mask shown from the next frame, and its shader block for `maskBlockSize`.
        var mask: LayerMask?
        var maskBlock: CompositorShaders.MaskBlock?
        var maskBlockSize: LayerPictureDescriptor?
        /// PERF-014: the layer's back-off, and the render error shown while it holds.
        var retry = RenderRetryState()
        var heldError: LayerSourceError?
        /// CMP-011: the layer's group (nil: ungrouped).
        var group: LayerGroupID?
        /// CMP-012: hidden by the solo/mute overlay (resolved at `apply` and `setSoloMute`).
        var overlayHidden = false
        /// CMP-013: the layer's caching declaration (nil: unknown, rendered every frame), its cache entry,
        /// whether this frame reused its picture, and how it was drawn into the last good composite.
        let caching: (any LayerRenderCaching)?
        var cache = LayerRenderCacheEntry()
        var reusedThisFrame = false
        var drawn: LayerDrawInput?

        init(id: LayerInstanceID?, layer: any LayerSource, settings: LayerCompositeSettings, group: LayerGroupID? = nil) {
            self.id = id
            self.layer = layer
            caching = layer as? any LayerRenderCaching
            self.group = group
            slots = LayerSlots(fallback: layer.fallback)
            opacity = LayerOpacityAnimator(opacity: settings.opacity)
            transform = settings.transform
            blendMode = settings.blendMode
            mask = settings.mask
            // CMP-006: a stack entry's fit always reaches the layer (the stack is the source of
            // truth); a layer given to `init(device:layers:)` keeps its own fit unless its settings set one.
            if let fitting = layer as? any LayerFitting, id != nil || settings.fit != nil { fitting.fit = settings.fit }
        }
    }

    /// CMP-011: one group's live state: its shown opacity and fade, placement and enabled flag.
    private struct GroupRecord {
        let id: LayerGroupID
        var opacity: LayerOpacityAnimator
        var transform: LayerTransform
        var isEnabled: Bool
        /// CMP-013: the opacity drawn into the last good composite.
        var drawnOpacity: Double?
    }

    public let device: MTLDevice
    private var records: [LayerRecord]
    /// CMP-011: in stack order.
    private var groupRecords: [GroupRecord] = []
    /// CMP-011: the isolated groups' picture and its blend-mode partner (nil until first needed at a size).
    private var groupComposite: MTLTexture?
    private var groupAlternate: MTLTexture?
    private var composite: MTLTexture?
    /// CMP-004: the other composite of the blend-mode ping-pong (nil until a mode layer is drawn).
    private var compositeAlternate: MTLTexture?
    private var descriptor: LayerPictureDescriptor?
    private var clock = LayerFrameClock()
    private let library: MTLLibrary
    private let fullScreen: MTLFunction
    private let overPipeline: MTLRenderPipelineState
    private let transformedPipeline: MTLRenderPipelineState
    private let blendPipeline: MTLRenderPipelineState
    private let maskedPipeline: MTLRenderPipelineState
    private var outputPipelines: [(format: MTLPixelFormat, state: MTLRenderPipelineState)] = []
    private let flashGuard: CompositeFlashGuard
    /// FX-002-R7: where the output pass counts non-finite composite pixels.
    private let nonFiniteCounter: NonFiniteOutputCounter
    /// PERF-004: where pictures come from and go back to.
    public let texturePool: TexturePool
    /// PERF-004: the last command buffer this compositor encoded with (the fence of returned pictures).
    private var lastCommandBuffer: MTLCommandBuffer?

    /// Pictures (and composites) created so far (tests, diagnostics).
    public private(set) var pictureAllocations = 0
    /// Calls to layers' `prepare` so far (tests, diagnostics; CMP-002-S3).
    public private(set) var layerPreparations = 0
    /// Draws through the transformed path in the last frame (CMP-005; tests, diagnostics).
    public private(set) var transformedDraws = 0
    /// Draws through the blend-mode path in the last frame (CMP-004; tests, diagnostics).
    public private(set) var blendDraws = 0
    /// Normal-mode draws through the masked "over" path in the last frame (CMP-007; tests, diagnostics).
    public private(set) var maskedDraws = 0
    /// Groups drawn through their own picture in the last frame (CMP-011; tests, diagnostics).
    public private(set) var isolatedGroupDraws = 0
    /// The stack last applied (nil before the first `apply`, and for `init(device:layers:)`).
    public private(set) var appliedStack: LayerStack?
    /// CMP-012: the solo/mute overlay (never part of `appliedStack`).
    public private(set) var soloMute = LayerSoloMute()
    /// CMP-012: layers the overlay left out of the last frame (tests, diagnostics).
    public private(set) var soloMuteHiddenLayers = 0
    /// CMP-013-R8: render caching (level 1 pictures, level 2 composite); off behaves exactly as before CMP-013.
    public var isRenderCachingEnabled = true {
        didSet { if isRenderCachingEnabled != oldValue { invalidateRenderCache() } }
    }
    /// CMP-013: bumped by every global invalidation (part of every cache key).
    public private(set) var renderCacheEpoch: UInt64 = 0
    /// CMP-013-R13: layers whose picture was reused in the last frame (tests, diagnostics).
    public private(set) var renderCacheHits = 0
    /// CMP-013-R13: whether the last frame kept the previous composite, and how many frames did so far.
    public private(set) var compositeReused = false
    public private(set) var compositeReuses = 0
    /// CMP-013: the composite holds the last good frame's stack and nothing was applied or invalidated since.
    private var compositeValid = false
    /// CMP-013: the pool's purge count last seen (a memory-warning purge invalidates).
    private var seenPoolPurges: UInt64 = 0
    /// REC-001: the handler waiting for the next frame.
    private var pendingCapture: (@Sendable (CapturedPixels?) -> Void)?
    /// REC-003: the command buffer of the last frame whose output pass was encoded.
    private weak var outputCommandBuffer: MTLCommandBuffer?
    /// FX-003: the grade's shader block (built when `colorGrade` changes) and the block of the frame last shown, so
    /// `encodeOutput` repeats exactly that frame's output.
    private var gradeBlock = CompositorShaders.GradeBlock.neutral
    private var shownGradeBlock = CompositorShaders.GradeBlock.neutral
    /// FX-009: the trails pass and its pooled pair; the texture the last finished frame showed (the composite, or the
    /// trails frame), which `encodeOutput` repeats; the output format of the last `composite(into:)` (a change resets).
    private let trails: TrailsPass
    private var shownComposite: MTLTexture?
    private var lastOutputFormat: MTLPixelFormat?
    /// FX-020: the Color-first pass, the grade block the guard and outputs use this frame (neutral when the pass ran),
    /// and whether the last frame's trails history was graded (a change resets it).
    private let gradePass: OutputGradePass
    private var outputGradeBlock = CompositorShaders.GradeBlock.neutral
    private var trailsHistoryGraded = false

    /// FX-020 (ADR-0054): the order of Trails and Color, set between frames. The flash guard and the tone map always
    /// run after both. `.standard` (the default) renders exactly as before FX-020; a change resets the trails.
    public var outputEffectOrder: OutputEffectOrder = .standard {
        didSet { if outputEffectOrder != oldValue { trails.resetPending = true } }
    }

    /// FX-020: frames that ran the Color-first grade pass (tests, diagnostics).
    public var gradePassFrames: Int { gradePass.frames }

    /// FX-009 (ADR-0051): Trails, set between frames (the effective value after ACC-012's caps). Inactive (the default)
    /// adds no pass and holds no picture: output bit-identical to before FX-009. Turning it on starts clean; turning it
    /// off returns the pair to the pool.
    public var motionFeedback: MotionFeedback = .off {
        didSet {
            if !motionFeedback.isActive {
                trails.release(to: texturePool, after: lastCommandBuffer)
            } else if !oldValue.isActive {
                trails.resetPending = true
            }
        }
    }

    /// FX-009-R5: the next frame shows the composite only (a scene change); trails then build up from it.
    public func resetFeedback() { trails.resetPending = true }

    /// FX-009: frames drawn through the trails pass, reset frames among them, and whether the pair is held (tests).
    public var trailsFrames: Int { trails.frames }
    public var trailsResets: Int { trails.resets }
    public var holdsTrailsPictures: Bool { trails.holdsPictures }

    /// FX-003 (contracts/color-grade.md in specs/123, ADR-0050): the colour grade every output pass applies before the
    /// tone map, and the flash guard measures. Set between frames; neutral (the default) bypasses grading bit for bit.
    /// Never invalidates CMP-013's caches (grading runs after the composite).
    public var colorGrade: ColorGrade = .neutral {
        didSet { gradeBlock = CompositorShaders.GradeBlock(colorGrade.coefficients) }
    }

    /// PERF-014: the visual's render health record (PERF-014-R2).
    public private(set) var health = RenderHealth()
    /// PERF-014-R5: how often and how far apart failing parts are tried again.
    public var recoveryPolicy = RenderRecoveryPolicy.standard
    /// PERF-014-D1: `composite` calls with a usable output (the time base of every back-off).
    public private(set) var frameTicks: UInt64 = 0
    /// PERF-014: the visual's own part (GPU errors, a missing composite texture).
    private var visualRetry = RenderRetryState()
    /// PERF-014-D2: the last command buffers encoded and their tick; a fixed ring read on this thread.
    private struct WatchedBuffer {
        let buffer: MTLCommandBuffer
        let tick: UInt64
    }
    private var watched: [WatchedBuffer?] = [nil, nil, nil]
    private var watchCursor = 0
    #if DEBUG
    /// PERF-014-R15: faults to force (DEBUG builds only).
    public var faultInjection = RenderFaultInjection()
    #endif

    /// An empty compositor; give it layers with `apply(_:makeLayer:)` (CMP-002).
    /// PERF-004: `texturePool` nil gives the compositor a private pool.
    public convenience init(device: MTLDevice, texturePool: TexturePool? = nil) throws(CompositorError) {
        try self.init(device: device, layers: [], texturePool: texturePool)
    }

    /// A compositor with a fixed list of layers, bottom first (CMP-001). The layers have no stack
    /// ID; the first `apply` releases them.
    public init(device: MTLDevice, layers: [any LayerSource], texturePool: TexturePool? = nil) throws(CompositorError) {
        for (i, layer) in layers.enumerated() {
            if layers[..<i].contains(where: { $0 === layer }) { throw .duplicateLayer(index: i) }
            if !layer.compositeSettings.isSupportedByCompositor { throw .unsupportedCompositeSettings(index: i) }
        }
        self.device = device
        self.texturePool = texturePool ?? TexturePool(device: device)
        seenPoolPurges = self.texturePool.purgeCount
        records = layers.map { (layer: any LayerSource) -> LayerRecord in
            LayerRecord(id: nil, layer: layer, settings: layer.compositeSettings)
        }
        library = try CompositorShaders.library(device: device, source: CompositorShaders.source + TrailsPass.source
                                                + OutputGradePass.source)   // FX-009, FX-020
        fullScreen = try CompositorShaders.function(library, "cmp_fullscreen")
        trails = try TrailsPass(device: device, library: library, vertex: fullScreen)
        gradePass = try OutputGradePass(device: device, library: library, vertex: fullScreen)   // FX-020
        overPipeline = try CompositorShaders.pipeline(device: device, vertex: fullScreen,
                                                      fragment: try CompositorShaders.function(library, "cmp_over"),
                                                      format: LayerPictureDescriptor.metalPixelFormat, blendOver: true,
                                                      label: "CMP-001 over")
        transformedPipeline = try CompositorShaders.pipeline(device: device, vertex: fullScreen,
                                                             fragment: try CompositorShaders.function(library, "cmp_over_transformed"),
                                                             format: LayerPictureDescriptor.metalPixelFormat, blendOver: true,
                                                             label: "CMP-005 transformed over")
        blendPipeline = try CompositorShaders.pipeline(device: device, vertex: fullScreen,
                                                       fragment: try CompositorShaders.function(library, "cmp_blend"),
                                                       format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                       label: "CMP-004 blend")
        maskedPipeline = try CompositorShaders.pipeline(device: device, vertex: fullScreen,
                                                        fragment: try CompositorShaders.function(library, "cmp_over_masked"),
                                                        format: LayerPictureDescriptor.metalPixelFormat, blendOver: true,
                                                        label: "CMP-007 masked over")
        flashGuard = try CompositeFlashGuard(device: device)
        nonFiniteCounter = try NonFiniteOutputCounter(device: device)
    }

    /// PERF-004: every picture goes back to the pool, reusable once the last frame completed.
    deinit {
        if let composite { texturePool.recycle(composite, after: lastCommandBuffer) }
        if let compositeAlternate { texturePool.recycle(compositeAlternate, after: lastCommandBuffer) }
        if let groupComposite { texturePool.recycle(groupComposite, after: lastCommandBuffer) }   // CMP-011
        if let groupAlternate { texturePool.recycle(groupAlternate, after: lastCommandBuffer) }
        for record in records { texturePool.recycle(record.pictures, after: lastCommandBuffer) }
        trails.release(to: texturePool, after: lastCommandBuffer)   // FX-009
        gradePass.release(to: texturePool, after: lastCommandBuffer)   // FX-020
    }

    public var layerCount: Int { records.count }

    /// What happened to layer `index` (bottom first) in the last frame.
    public func outcome(ofLayer index: Int) -> LayerOutcome { records[index].outcome }

    /// The opacity layer `index` was drawn with in the last frame (CMP-003; tests, diagnostics).
    public func shownOpacity(ofLayer index: Int) -> Double { records[index].opacity.value }

    /// The blend mode layer `index` is drawn with (CMP-004; tests, diagnostics).
    public func shownBlendMode(ofLayer index: Int) -> LayerBlendMode { records[index].blendMode }

    /// The transform layer `index` is drawn with (CMP-005; tests, diagnostics).
    public func shownTransform(ofLayer index: Int) -> LayerTransform { records[index].transform }

    /// The mask layer `index` is drawn with (CMP-007; tests, diagnostics).
    public func shownMask(ofLayer index: Int) -> LayerMask? { records[index].mask }

    /// The opacity group `id` was drawn with in the last frame (CMP-011; nil for an unknown group).
    public func shownGroupOpacity(of id: LayerGroupID) -> Double? {
        groupRecords.first { (g: GroupRecord) -> Bool in g.id == id }?.opacity.value
    }

    /// The stack ID of layer `index` (nil for a layer given to `init(device:layers:)`).
    public func layerID(at index: Int) -> LayerInstanceID? { records[index].id }

    /// CMP-012: whether the solo/mute overlay hides layer `index` from the next frame.
    public func isHiddenBySoloMute(layer index: Int) -> Bool { records[index].overlayHidden }

    /// CMP-012-R1, R6, R11: sets the solo/mute overlay between frames, on the compositor's thread. Shown
    /// from the next frame without a fade; nothing is prepared, created or released, every layer keeps
    /// rendering, the flash guard's history is kept, and the applied stack is unchanged. A host loading a
    /// different scene passes `LayerSoloMute()` first (restored scenes reuse their instance IDs).
    public func setSoloMute(_ overlay: LayerSoloMute) {
        soloMute = overlay
        resolveSoloMute()
        compositeValid = false   // CMP-013: composite only; layer pictures stay valid
    }

    /// CMP-013: the layer pictures and the composite are drawn again from the next frame (all keys change).
    public func invalidateRenderCache() {
        renderCacheEpoch &+= 1
        compositeValid = false
    }

    /// CMP-013-R13: whether layer `index`'s picture was reused (not rendered) in the last frame.
    public func wasReused(layer index: Int) -> Bool { records[index].reusedThisFrame }

    /// One flag per record from the overlay and the applied stack; layers without a stack ID are never hidden.
    private func resolveSoloMute() {
        guard let stack = appliedStack, !soloMute.isEmpty else {
            for i in records.indices { records[i].overlayHidden = false }
            return
        }
        let active = soloMute.isSoloActive(in: stack)
        for i in records.indices {
            guard let id = records[i].id, let entry = stack.entry(id) else {
                records[i].overlayHidden = false
                continue
            }
            records[i].overlayHidden = !soloMute.lets(entry, soloActive: active)
        }
    }

    /// Applies a new stack between frames (CMP-002-R7 to R11, R14; contracts/layer-stack.md). Call it
    /// on the compositor's thread, never while encoding a frame. An equal stack changes nothing.
    /// Layers whose IDs are still present keep their object, pictures and state at their new index;
    /// `makeLayer` is called once per new ID and the new layers are prepared now if the output size
    /// is known (else with the first frame); layers whose IDs are gone are released (nothing is
    /// called on them). On any error the previous stack stays applied. The flash guard's history is
    /// kept: a stack edit is not a new scene.
    /// CMP-003: a kept layer whose entry opacity changed fades to it with `opacityTransition` (from
    /// the opacity shown last); a new layer starts at its entry's opacity.
    /// CMP-005: every layer is drawn with its entry's transform from the next frame (no animation).
    /// CMP-004: and with its entry's blend mode (no animation; a running opacity fade continues).
    /// CMP-011: groups as layers: a changed group opacity fades with `opacityTransition`, transform and
    /// enabled flag show from the next frame.
    public func apply(_ stack: LayerStack, opacityTransition: LayerOpacityTransition = .immediate,
                      makeLayer: LayerFactory) throws(CompositorError) {
        if let appliedStack, appliedStack == stack { return }
        let entries = stack.entries
        for (i, entry) in entries.enumerated() where !entry.settings.isSupportedByCompositor {
            throw .unsupportedCompositeSettings(index: i)
        }
        var next: [LayerRecord] = []
        next.reserveCapacity(entries.count)
        var created: [Int] = []
        for (i, entry) in entries.enumerated() {
            if var kept = records.first(where: { (r: LayerRecord) -> Bool in r.id == entry.id }) {
                if appliedStack?.entry(entry.id)?.settings.opacity != entry.settings.opacity {
                    kept.opacity.setOpacity(entry.settings.opacity, transition: opacityTransition)
                }
                kept.transform = entry.settings.transform
                kept.blendMode = entry.settings.blendMode
                if kept.mask != entry.settings.mask {   // CMP-007: rebuilt on the next draw
                    kept.mask = entry.settings.mask
                    kept.maskBlock = nil
                }
                if let fitting = kept.layer as? any LayerFitting { fitting.fit = entry.settings.fit }   // CMP-006
                kept.group = entry.group   // CMP-011
                next.append(kept)
                continue
            }
            let layer: any LayerSource
            do {
                layer = try makeLayer(entry)
            } catch {
                throw .layerCreationFailed(index: i, error)
            }
            next.append(LayerRecord(id: entry.id, layer: layer, settings: entry.settings, group: entry.group))
            created.append(i)
        }
        for i in next.indices where next[..<i].contains(where: { (r: LayerRecord) -> Bool in r.layer === next[i].layer }) {
            throw .duplicateLayer(index: i)
        }
        for old in records where !next.contains(where: { (r: LayerRecord) -> Bool in r.layer === old.layer }) {
            texturePool.recycle(old.pictures, after: lastCommandBuffer)   // PERF-004: back to the pool
        }
        var nextGroups: [GroupRecord] = []   // CMP-011
        nextGroups.reserveCapacity(stack.groups.count)
        for group in stack.groups {
            if var kept = groupRecords.first(where: { (g: GroupRecord) -> Bool in g.id == group.id }) {
                if appliedStack?.group(group.id)?.settings.opacity != group.settings.opacity {
                    kept.opacity.setOpacity(group.settings.opacity, transition: opacityTransition)
                }
                kept.transform = group.settings.transform
                kept.isEnabled = group.settings.isEnabled
                nextGroups.append(kept)
            } else {
                nextGroups.append(GroupRecord(id: group.id, opacity: LayerOpacityAnimator(opacity: group.settings.opacity),
                                              transform: group.settings.transform, isEnabled: group.settings.isEnabled))
            }
        }
        records = next   // records no longer listed are released here
        groupRecords = nextGroups
        appliedStack = stack
        resolveSoloMute()   // CMP-012: the overlay against the new stack
        compositeValid = false   // CMP-013: kept layers keep their cached pictures
        if let descriptor {
            for i in created { allocatePictures(i, descriptor) }
        }
    }

    /// Prepares every unavailable layer again at the current size (it reappears from the next frame
    /// if its `prepare` now succeeds). PERF-014: the same as `resetRenderHealth()`.
    public func retryUnavailableLayers() { resetRenderHealth() }

    /// PERF-014-R6: a fresh retry budget for every part; failed layers are prepared again now (at the
    /// current size), a held layer or GPU back-off runs again from the next frame. The counters are
    /// kept. Call between frames (the frame loop starting, the user changing or resuming the visual).
    public func resetRenderHealth() {
        let next = frameTicks &+ 1   // work from the next tick decides the retry
        invalidateRenderCache()   // CMP-013
        trails.resetPending = true   // FX-009-R5
        visualRetry.reset(atTick: next)
        for i in records.indices {
            records[i].retry.reset(atTick: next)
            records[i].heldError = nil
            if let descriptor, !records[i].slots.isAvailable { rebuildLayer(i, descriptor) }
        }
        updateHealthState()
    }

    /// The flash guard's gain of the last completed frame (read it after the command buffer completed;
    /// diagnostics and tests).
    public var lastFlashGain: Float { flashGuard.lastGain }

    /// Forgets the composite's flash history (a new scene; FX-019-R11). A pause must not call it.
    /// FX-009-R5: a new scene clears the trails too (every visual host calls this when its frame loop starts).
    public func resetFlashHistory() {
        flashGuard.reset()
        trails.resetPending = true
    }

    /// FX-002-R7: composite pixels with a NaN or infinite channel that the screen output pass tone-mapped to 0
    /// so far (cumulative; recording and capture passes do not count). Exact once the last frame completed.
    public var nonFiniteOutputPixels: UInt32 { nonFiniteCounter.count }
    /// ACC-012-R5: the sensory safety profile's envelope for the final flash guard when it differs from the
    /// Reduce flashing one (`SafetyClamp.flashLimitsOverride`); nil = `forReduceFlashing(reduceFlashing)`.
    /// From the next frame; the guard's history is kept (FX-019-R11).
    public var flashLimits: FlashEnvelopeConfiguration?
    /// PERF-001 (contracts/frame-stage-timer.md C4): when set, `composite(into:)` stamps
    /// `lastOutputPassStartNanoseconds` with this clock where the output pass (flash guard, grade, output)
    /// begins, so a host can split its time into composite and output. Nil (the default): nothing is read.
    public var stageClock: (() -> UInt64)?
    /// PERF-001: the stage clock's reading at the start of the last frame's output pass; 0 when the frame
    /// stopped before it (or without a stage clock).
    public private(set) var lastOutputPassStartNanoseconds: UInt64 = 0

    /// Encodes one frame into `output` (a render target of a `supportedOutputFormats` format) and
    /// `commandBuffer`, which the caller commits. Returns false, encoding nothing, for an empty
    /// output, an unsupported format or when Metal cannot create an encoder.
    public func composite(into output: MTLTexture, commandBuffer: MTLCommandBuffer, presentationTimeNanoseconds: UInt64,
                          contentScale: Double, reduceFlashing: Bool, audio: LayerAudioContext) -> Bool {
        guard let size = LayerPictureDescriptor(width: output.width, height: output.height),
              let outputPipeline = outputPipeline(for: output.pixelFormat) else { return false }
        if let last = lastOutputFormat, last != output.pixelFormat { trails.resetPending = true }   // FX-009-R5
        lastOutputFormat = output.pixelFormat
        lastOutputPassStartNanoseconds = 0
        return encodeFrame(size: size, commandBuffer: commandBuffer, presentationTimeNanoseconds: presentationTimeNanoseconds,
                           contentScale: contentScale, reduceFlashing: reduceFlashing, audio: audio,
                           allowGradePass: true) { (composite: MTLTexture, frame: LayerFrameContext) -> Bool in
            if let stageClock { lastOutputPassStartNanoseconds = stageClock() }   // PERF-001: the output pass starts
            let grade: CompositorShaders.GradeBlock = outputGradeBlock   // FX-003, FX-020: one block for the guard and outputs
            guard flashGuard.encode(composite: composite, commandBuffer: commandBuffer, frameDuration: frame.frameDuration,
                                    reduceFlashing: reduceFlashing, flashLimits: flashLimits, grade: grade) else { return false }
            shownGradeBlock = grade
            let out = MTLRenderPassDescriptor()
            out.colorAttachments[0].texture = output
            out.colorAttachments[0].loadAction = .dontCare
            out.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: out) else { return false }
            encoder.label = "CMP-001 output"
            encoder.setRenderPipelineState(outputPipeline)
            encoder.setFragmentTexture(composite, index: 0)
            encoder.setFragmentBuffer(flashGuard.gainBuffer, offset: 0, index: 0)
            encoder.setFragmentBuffer(nonFiniteCounter.counter, offset: 0, index: 1)   // FX-002: the screen pass counts
            Self.bindGrade(grade, encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            outputCommandBuffer = commandBuffer   // REC-003: `encodeOutput` may follow in this command buffer
            if let handler = pendingCapture {
                pendingCapture = nil
                encodeCapture(composite: composite, size: size, commandBuffer: commandBuffer, handler: handler)
            }
            return true
        }
    }

    /// CMP-014 (contracts/transition-bus.md in specs/116): the stack phase of one frame only, exactly as
    /// `composite(into:)` runs it (frame tick, render health, layer renders, CMP-013 reuse, pool tick,
    /// command-buffer watch). Returns the finished composite (`rgba16Float`, linear premultiplied, owned by
    /// this compositor and valid in `commandBuffer` until its next frame); no flash guard and no output pass
    /// run (a `SceneTransitionBus` runs its own). nil when nothing could be encoded.
    public func encodeScene(width: Int, height: Int, commandBuffer: MTLCommandBuffer, presentationTimeNanoseconds: UInt64,
                            contentScale: Double, reduceFlashing: Bool, audio: LayerAudioContext) -> MTLTexture? {
        guard let size = LayerPictureDescriptor(width: width, height: height) else { return nil }
        var finished: MTLTexture?
        let ok = encodeFrame(size: size, commandBuffer: commandBuffer, presentationTimeNanoseconds: presentationTimeNanoseconds,
                             contentScale: contentScale, reduceFlashing: reduceFlashing, audio: audio,
                             allowGradePass: false) { (composite: MTLTexture, _: LayerFrameContext) -> Bool in
            finished = composite
            return true
        }
        return ok ? finished : nil
    }

    /// One frame's stack phase, then `finish` on the finished composite (the guard and output, or nothing);
    /// a successful `finish` makes the frame finished (watched, its composite inputs noted for CMP-013).
    private func encodeFrame(size: LayerPictureDescriptor, commandBuffer: MTLCommandBuffer, presentationTimeNanoseconds: UInt64,
                             contentScale: Double, reduceFlashing: Bool, audio: LayerAudioContext, allowGradePass: Bool,
                             finish: (MTLTexture, LayerFrameContext) -> Bool) -> Bool {
        frameTicks &+= 1   // PERF-014-D1
        let tick = frameTicks
        defer { updateHealthState() }
        var finished = false
        defer {   // CMP-013: an unfinished frame may leave pictures undrawn; FX-009: and the trails history
            if !finished {
                invalidateRenderCache()
                trails.resetPending = true
            }
        }
        observeFinishedCommandBuffers()
        if visualRetry.isRetryDue(atTick: tick) { visualRetry.beginRetry(atTick: tick) }
        if size != descriptor {
            // PERF-014: a composite that could not be created is tried again only at its retry.
            if composite == nil, visualRetry.isHolding { return false }
            guard allocate(size) else {
                recordVisualFault(.missingTexture)
                return false
            }
        }
        guard var composite else { return false }
        let purges = texturePool.tick()
        if purges != seenPoolPurges {   // CMP-013: a memory-warning purge (PERF-006)
            seenPoolPurges = purges
            invalidateRenderCache()
        }
        lastCommandBuffer = commandBuffer   // PERF-004: from here on this frame may use every picture
        let frame = clock.next(presentationTimeNanoseconds: presentationTimeNanoseconds, outputWidth: size.width,
                               outputHeight: size.height, contentScale: contentScale, reduceFlashing: reduceFlashing)

        for g in groupRecords.indices { groupRecords[g].opacity.advance(by: frame.frameDuration) }   // CMP-011

        // PERF-014-D3: while the visual's own part backs off, no layer renders (a black frame).
        let visualHolds = visualRetry.isHolding
        renderCacheHits = 0
        for i in records.indices {
            records[i].shown = -1
            records[i].reusedThisFrame = false
            records[i].opacity.advance(by: frame.frameDuration)
            if visualHolds {
                records[i].outcome = .notRendered
                records[i].cache.drop()
                continue
            }
            if records[i].retry.isRetryDue(atTick: tick) {   // PERF-014-R3, R4: only at back-off ticks
                records[i].retry.beginRetry(atTick: tick)
                records[i].heldError = nil
                if let descriptor, !records[i].slots.isAvailable { rebuildLayer(i, descriptor) }
            }
            guard records[i].slots.isAvailable else {
                records[i].outcome = .unavailable(records[i].prepareError ?? .notReady)
                records[i].cache.drop()
                continue
            }
            if records[i].retry.isHolding {   // a held render failure: its fallback, no render call
                showFallback(i, records[i].heldError ?? .notReady)
                records[i].cache.drop()
                continue
            }
            // CMP-013 level 1: unchanged inputs show the last good picture without a render call.
            let key = renderCacheKey(i, frame: frame, size: size)
            if let good = records[i].slots.lastGoodIndex, records[i].cache.canReuse(key, hasGoodPicture: true) {
                records[i].shown = good
                records[i].outcome = .rendered
                records[i].reusedThisFrame = true
                renderCacheHits += 1
                records[i].caching?.renderReused(frame: frame)
                continue
            }
            records[i].cache.drop()   // the render may overwrite the picture
            let target = records[i].pictures[records[i].slots.renderIndex]
            do throws(LayerSourceError) {
                #if DEBUG
                if faultInjection.failingRender.contains(records[i].layer.layerName) { throw .engineFailure("injected") }
                #endif
                try records[i].layer.render(into: target, commandBuffer: commandBuffer, frame: frame, audio: audio)
                records[i].shown = records[i].slots.frameSucceeded()
                records[i].outcome = .rendered
                records[i].cache.rendered(key)   // CMP-013: only a successful render stores its key
                if records[i].retry.succeeded(encodedAtTick: tick) { health.recordRecovery() }
            } catch {
                showFallback(i, error)
                if error.isRenderFault {   // PERF-014-D4: routine errors keep CMP-001's per-frame behaviour
                    records[i].heldError = error
                    recordLayerFault(i, .layerRenderFailed)
                }
            }
        }

        soloMuteHiddenLayers = 0
        for i in records.indices where records[i].overlayHidden && records[i].shown >= 0 && records[i].opacity.value > 0 {   // CMP-012
            if let g = records[i].group, let group = groupRecords.first(where: { (r: GroupRecord) -> Bool in r.id == g }),
               !group.isEnabled || group.opacity.value <= 0 { continue }   // hidden by its group anyway
            soloMuteHiddenLayers += 1
        }
        // CMP-013 level 2: nothing the composite is made of changed, so the previous composite is the stack.
        compositeReused = canReuseComposite()
        if compositeReused {
            compositeReuses += 1
        } else {   // a reused composite keeps the draw counts it was drawn with (the same draws)
            compositeValid = false
            transformedDraws = 0
            blendDraws = 0
            maskedDraws = 0
            isolatedGroupDraws = 0
            guard let stacked = encodeStack(onto: composite, size: size, commandBuffer: commandBuffer) else { return false }
            composite = stacked
        }

        // FX-009: the trails frame replaces the composite for the guard and every output (research FX-009-D3).
        var shown: MTLTexture = composite
        outputGradeBlock = gradeBlock
        if motionFeedback.isActive {
            guard let trailsInput = gradeBeforeTrails(composite, allowed: allowGradePass, commandBuffer: commandBuffer) else {
                return false
            }
            let decay: Double = motionFeedback.decay(frameDuration: frame.frameDuration)
            let taken: Int = trails.allocations
            guard let trailed = trails.encode(composite: trailsInput, decay: decay, pool: texturePool, fence: lastCommandBuffer,
                                              commandBuffer: commandBuffer) else { return false }
            pictureAllocations += trails.allocations - taken   // PERF-004: the pair, at its allocation points
            shown = trailed
        } else if gradePass.holdsPicture {
            gradePass.release(to: texturePool, after: lastCommandBuffer)   // FX-020: not used while Trails are off
        }
        shownComposite = shown
        guard finish(shown, frame) else { return false }   // CMP-014: the guard and output, or the bus's
        watch(commandBuffer, tick: tick)
        noteCompositeInputs()   // CMP-013
        finished = true
        return true
    }

    /// FX-020: the Trails input. Color first with a non-neutral grade: the graded composite (and the neutral block for
    /// the guard and outputs); otherwise the composite. A change between the two resets the trails history.
    private func gradeBeforeTrails(_ composite: MTLTexture, allowed: Bool, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let graded: Bool = allowed && outputEffectOrder.gradeBeforeTrails && gradeBlock.flags != 0
        if graded != trailsHistoryGraded {
            trails.resetPending = true
            trailsHistoryGraded = graded
        }
        guard graded else {
            if gradePass.holdsPicture { gradePass.release(to: texturePool, after: lastCommandBuffer) }
            return composite
        }
        let taken: Int = gradePass.allocations
        guard let output = gradePass.encode(composite: composite, grade: gradeBlock, pool: texturePool, fence: lastCommandBuffer,
                                            commandBuffer: commandBuffer) else { return nil }
        pictureAllocations += gradePass.allocations - taken   // PERF-004
        outputGradeBlock = .neutral
        return output
    }

    // MARK: - Render caching (CMP-013)

    /// Layer `i`'s cache key this frame (nil: render): only for an adopter, with caching on, and never for a
    /// layer a DEBUG render fault targets (PERF-014's injected faults must reach `render`).
    private func renderCacheKey(_ i: Int, frame: LayerFrameContext, size: LayerPictureDescriptor) -> LayerRenderCacheKey? {
        guard isRenderCachingEnabled, let caching = records[i].caching else { return nil }
        #if DEBUG
        if faultInjection.failingRender.contains(records[i].layer.layerName) { return nil }
        #endif
        return LayerRenderCacheKey(dependencies: caching.renderDependencies, picture: size, contentScale: frame.contentScale,
                                   reduceFlashing: frame.reduceFlashing, epoch: renderCacheEpoch)
    }

    /// How layer `i` is drawn into this frame's composite (−1: not drawn).
    private func drawInput(_ i: Int) -> LayerDrawInput {
        LayerDrawInput(picture: isVisible(i) ? records[i].shown : -1, opacity: records[i].opacity.value,
                       reused: records[i].reusedThisFrame)
    }

    /// CMP-013-R6: the composite is valid and every layer and group contributes what it contributed to it.
    private func canReuseComposite() -> Bool {
        guard isRenderCachingEnabled, compositeValid, !motionFeedback.isActive else { return false }   // FX-009-R12
        for i in records.indices where !drawInput(i).isUnchanged(from: records[i].drawn) { return false }
        for g in groupRecords where g.drawnOpacity != g.opacity.value { return false }
        return true
    }

    /// A finished frame: remember what its composite is made of.
    private func noteCompositeInputs() {
        for i in records.indices { records[i].drawn = drawInput(i) }
        for g in groupRecords.indices { groupRecords[g].drawnOpacity = groupRecords[g].opacity.value }
        compositeValid = isRenderCachingEnabled
    }

    /// Draws every visible layer, bottom first, onto the cleared composite (CMP-001 to CMP-012). Returns the
    /// composite holding the stack (the blend-mode ping-pong may have swapped it), nil when Metal cannot
    /// create an encoder or a picture.
    private func encodeStack(onto composite: MTLTexture, size: LayerPictureDescriptor, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = composite
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let over = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        over.label = "CMP-001 composite"
        over.setRenderPipelineState(overPipeline)
        var surface = DrawSurface(texture: composite, partner: compositeAlternate, encoder: over, pipe: .plain,
                                  label: "CMP-001 composite", partnerLabel: "CMP-004 composite")
        defer {   // CMP-004: the two composites may have swapped (kept even when a frame fails half way)
            self.composite = surface.texture
            compositeAlternate = surface.partner
        }
        var i = 0
        while i < records.count {
            // CMP-011: an ungrouped layer (or one whose group is unknown) is drawn as before.
            guard let groupID = records[i].group,
                  let g = groupRecords.firstIndex(where: { (r: GroupRecord) -> Bool in r.id == groupID }) else {
                if isVisible(i), !drawLayer(i, on: &surface, size: size, commandBuffer: commandBuffer) { return nil }
                i += 1
                continue
            }
            var end = i + 1
            while end < records.count, records[end].group == groupID { end += 1 }
            let run = i..<end
            i = end
            let groupOpacity = groupRecords[g].opacity.value
            guard groupRecords[g].isEnabled, groupOpacity > 0 else { continue }   // hidden: its layers still rendered
            // The rule of `LayerGroupComposition.needsIsolation`, without building a sequence per frame.
            var anyVisible = false
            var isolate = groupOpacity < 1
            for k in run where isVisible(k) {
                anyVisible = true
                if records[k].blendMode != .normal { isolate = true }
            }
            guard anyVisible else { continue }
            if isolate {
                guard drawIsolatedGroup(run, opacity: groupOpacity, on: &surface, size: size, commandBuffer: commandBuffer) else { return nil }
            } else {
                for k in run where isVisible(k) {
                    guard drawLayer(k, on: &surface, size: size, commandBuffer: commandBuffer) else { return nil }
                }
            }
        }
        surface.encoder.endEncoding()
        return surface.texture
    }

    // MARK: - Blend modes (CMP-004)

    /// A pooled picture the size of `current`: `existing` when it matches, else a new one from the pool
    /// (an allocation point: the first blend-mode or isolated-group draw at a size).
    private func partnerTexture(like current: MTLTexture, existing: MTLTexture?, label: String) -> MTLTexture? {
        if let existing, existing.width == current.width, existing.height == current.height { return existing }
        if let existing { texturePool.recycle(existing, after: lastCommandBuffer) }
        guard let d = LayerPictureDescriptor(width: current.width, height: current.height),
              let made = texturePool.makeTexture(descriptor: d.textureDescriptor()) else { return nil }
        made.label = label
        pictureAllocations += 1
        return made
    }

    /// One full-screen `cmp_blend` pass: layer `i` with its mode over `backdrop`, written to `target`;
    /// `matrix` is its placement (nil: identity).
    private func encodeBlend(_ i: Int, matrix: LayerTransformMatrix?, backdrop: MTLTexture, into target: MTLTexture,
                             size: LayerPictureDescriptor, commandBuffer: MTLCommandBuffer) -> Bool {
        let opacity = records[i].opacity.value
        var draw: TransformedDraw
        if let matrix {
            guard let placed = Self.transformedDraw(matrix, size: size, opacity: opacity) else { return false }   // checked by the caller
            draw = placed
            draw.params.y = 1
        } else {
            draw = TransformedDraw(row0: .zero, row1: .zero, params: SIMD4<Float>(Float(opacity), 0, 0, 0))
        }
        draw.params.z = CompositorShaders.shaderIndex(records[i].blendMode)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "CMP-004 blend \(records[i].blendMode.rawValue)"
        encoder.setRenderPipelineState(blendPipeline)
        encoder.setFragmentTexture(records[i].pictures[records[i].shown], index: 0)
        encoder.setFragmentTexture(backdrop, index: 1)
        encoder.setFragmentBytes(&draw, length: MemoryLayout<TransformedDraw>.stride, index: 0)
        var block = maskBlock(i, size: size) ?? CompositorShaders.MaskBlock.none   // CMP-007
        encoder.setFragmentBytes(&block, length: MemoryLayout<CompositorShaders.MaskBlock>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        blendDraws += 1
        return true
    }

    // MARK: - Drawing layers (CMP-001 to CMP-007; CMP-011 surfaces)

    /// A picture being composited onto: the composite, or an isolated group's picture (CMP-011), with its
    /// blend-mode partner and the open "over" pass.
    private struct DrawSurface {
        var texture: MTLTexture
        var partner: MTLTexture?
        var encoder: MTLRenderCommandEncoder
        var pipe: OverPipe
        let label: String
        let partnerLabel: String
    }

    /// Whether layer `i` has a picture to composite this frame (CMP-012: and the solo/mute overlay lets it).
    private func isVisible(_ i: Int) -> Bool { records[i].shown >= 0 && records[i].opacity.value > 0 && !records[i].overlayHidden }

    /// CMP-011: the placement layer `i` is drawn with: nil for its own identity (the exact per-pixel paths),
    /// its own matrix while its group (if any) has the identity transform, else G(a)·L(a).
    private func placement(_ i: Int, size: LayerPictureDescriptor) -> LayerTransformMatrix? {
        let local = records[i].transform
        if let groupID = records[i].group,
           let group = groupRecords.first(where: { (g: GroupRecord) -> Bool in g.id == groupID }), !group.transform.isIdentity {
            return LayerGroupComposition.matrix(group: group.transform, local: local, outputWidth: size.width, outputHeight: size.height)
        }
        return local.isIdentity ? nil : local.matrix(outputWidth: size.width, outputHeight: size.height)
    }

    /// An "over" pass that keeps `texture`'s contents (after a blend-mode pass or a group).
    private func reopenOver(_ texture: MTLTexture, label: String, commandBuffer: MTLCommandBuffer) -> MTLRenderCommandEncoder? {
        let reopen = MTLRenderPassDescriptor()
        reopen.colorAttachments[0].texture = texture
        reopen.colorAttachments[0].loadAction = .load
        reopen.colorAttachments[0].storeAction = .store
        guard let next = commandBuffer.makeRenderCommandEncoder(descriptor: reopen) else { return nil }
        next.label = label
        next.setRenderPipelineState(overPipeline)
        return next
    }

    /// Draws visible layer `i` onto `surface`: normal layers in the open pass (identity, transformed or
    /// masked), other modes by ending the pass, blending into the partner, swapping and re-opening. False
    /// only when Metal cannot create an encoder or a picture (the frame fails; the pass may be ended).
    private func drawLayer(_ i: Int, on surface: inout DrawSurface, size: LayerPictureDescriptor,
                           commandBuffer: MTLCommandBuffer) -> Bool {
        let matrix = placement(i, size: size)
        if records[i].blendMode != .normal {
            if let matrix, matrix.inverse == nil { return true }   // not drawable (ruled out by the scale bounds)
            // CMP-004: end the "over" pass, blend into the partner, swap, re-open.
            surface.encoder.endEncoding()
            guard let target = partnerTexture(like: surface.texture, existing: surface.partner, label: surface.partnerLabel) else {
                return false
            }
            surface.partner = target
            guard encodeBlend(i, matrix: matrix, backdrop: surface.texture, into: target, size: size, commandBuffer: commandBuffer) else {
                return false
            }
            surface.partner = surface.texture
            surface.texture = target
            guard let next = reopenOver(target, label: surface.label, commandBuffer: commandBuffer) else { return false }
            surface.encoder = next
            surface.pipe = .plain
            return true
        }
        let over = surface.encoder
        over.setFragmentTexture(records[i].pictures[records[i].shown], index: 0)
        if var block = maskBlock(i, size: size) {   // CMP-007: same pass, coverage multiplied in
            var draw = TransformedDraw(row0: .zero, row1: .zero, params: SIMD4<Float>(Float(records[i].opacity.value), 0, 0, 0))
            if let matrix {
                guard let placed = Self.transformedDraw(matrix, size: size, opacity: records[i].opacity.value) else { return true }
                draw = placed
                draw.params.y = 1
            }
            if surface.pipe != .masked { over.setRenderPipelineState(maskedPipeline); surface.pipe = .masked }
            over.setFragmentBytes(&draw, length: MemoryLayout<TransformedDraw>.stride, index: 0)
            over.setFragmentBytes(&block, length: MemoryLayout<CompositorShaders.MaskBlock>.stride, index: 1)
            maskedDraws += 1
        } else if let matrix {
            guard var draw = Self.transformedDraw(matrix, size: size, opacity: records[i].opacity.value) else { return true }
            if surface.pipe != .transformed { over.setRenderPipelineState(transformedPipeline); surface.pipe = .transformed }
            over.setFragmentBytes(&draw, length: MemoryLayout<TransformedDraw>.stride, index: 0)
            transformedDraws += 1
        } else {
            if surface.pipe != .plain { over.setRenderPipelineState(overPipeline); surface.pipe = .plain }
            var opacity = Float(records[i].opacity.value)
            over.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
        }
        over.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        return true
    }

    /// CMP-011: the visible layers of `run` drawn in order onto the cleared group picture, which is then
    /// drawn over `surface` with premultiplied "over" × `opacity` (ADR-0039).
    private func drawIsolatedGroup(_ run: Range<Int>, opacity: Double, on surface: inout DrawSurface,
                                   size: LayerPictureDescriptor, commandBuffer: MTLCommandBuffer) -> Bool {
        surface.encoder.endEncoding()
        guard let picture = partnerTexture(like: surface.texture, existing: groupComposite, label: "CMP-011 group composite") else {
            return false
        }
        groupComposite = picture
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "CMP-011 group"
        encoder.setRenderPipelineState(overPipeline)
        var inner = DrawSurface(texture: picture, partner: groupAlternate, encoder: encoder, pipe: .plain,
                                label: "CMP-011 group", partnerLabel: "CMP-011 group composite")
        defer {   // the group's two pictures may have swapped
            groupComposite = inner.texture
            groupAlternate = inner.partner
        }
        for k in run where isVisible(k) {
            guard drawLayer(k, on: &inner, size: size, commandBuffer: commandBuffer) else { return false }
        }
        inner.encoder.endEncoding()
        guard let outer = reopenOver(surface.texture, label: surface.label, commandBuffer: commandBuffer) else { return false }
        surface.encoder = outer
        surface.pipe = .plain
        outer.setFragmentTexture(inner.texture, index: 0)
        var groupOpacity = Float(opacity)
        outer.setFragmentBytes(&groupOpacity, length: MemoryLayout<Float>.size, index: 0)
        outer.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        isolatedGroupDraws += 1
        return true
    }

    // MARK: - Masks (CMP-007)

    /// Which pipeline the open "over" pass has set.
    private enum OverPipe { case plain, transformed, masked }

    /// Layer `i`'s mask block for `size` (nil: unmasked); built from `LayerMaskGeometry` only when the
    /// mask or the size changed, so a steady frame creates nothing.
    private func maskBlock(_ i: Int, size: LayerPictureDescriptor) -> CompositorShaders.MaskBlock? {
        guard let mask = records[i].mask else { return nil }
        if let block = records[i].maskBlock, records[i].maskBlockSize == size { return block }
        let block = CompositorShaders.MaskBlock(mask.geometry(width: size.width, height: size.height))
        records[i].maskBlock = block
        records[i].maskBlockSize = size
        return block
    }

    // MARK: - Render health (PERF-014)

    private func showFallback(_ i: Int, _ error: LayerSourceError) {
        if let good = records[i].slots.frameFailed() { records[i].shown = good }
        records[i].outcome = records[i].slots.fallback == .lastGoodFrame ? .fallbackLastGood(error) : .fallbackTransparent(error)
    }

    private func recordLayerFault(_ i: Int, _ reason: RenderFaultReason) {
        if records[i].retry.fault(atTick: frameTicks, policy: recoveryPolicy) { health.recordFault(reason, atTick: frameTicks) }
    }

    private func recordVisualFault(_ reason: RenderFaultReason) {
        invalidateRenderCache()   // CMP-013
        if visualRetry.fault(atTick: frameTicks, policy: recoveryPolicy) { health.recordFault(reason, atTick: frameTicks) }
    }

    private func updateHealthState() {
        health.setState(RenderHealth.state(layers: records.lazy.map { (r: LayerRecord) -> RenderRetryState in r.retry },
                                           visual: visualRetry))
    }

    /// Remembers this tick's command buffer: a free slot, else the oldest (dropped unobserved).
    private func watch(_ buffer: MTLCommandBuffer, tick: UInt64) {
        var slot = watched.firstIndex { (entry: WatchedBuffer?) -> Bool in entry == nil }
        if slot == nil {
            slot = watchCursor
            watchCursor = (watchCursor + 1) % watched.count
        }
        if let slot { watched[slot] = WatchedBuffer(buffer: buffer, tick: tick) }
    }

    /// PERF-014-D2: reads the finished command buffers (completed or failed) and forgets them.
    private func observeFinishedCommandBuffers() {
        for k in watched.indices {
            guard let entry = watched[k] else { continue }
            let status = entry.buffer.status
            guard status == .completed || status == .error else { continue }
            watched[k] = nil
            if status == .error { invalidateRenderCache() }   // CMP-013: its pictures may be undrawn
            var reason: RenderFaultReason? = status == .error ? Self.renderFaultReason(for: entry.buffer.error) : nil
            #if DEBUG
            if let injected = faultInjection.gpuFault { reason = injected }
            #endif
            if visualRetry.isStale(encodedAtTick: entry.tick) { continue }   // encoded before the running retry
            if let reason {
                recordVisualFault(reason)
            } else if visualRetry.succeeded(encodedAtTick: entry.tick) {
                health.recordRecovery()
            }
        }
    }

    /// `MTLCommandBufferError` codes → reasons (PERF-014-R1).
    public static func renderFaultReason(for error: (any Error)?) -> RenderFaultReason {
        guard let error = error as? MTLCommandBufferError else { return .gpuError }
        switch error.code {
        case .timeout: return .gpuTimeout
        case .pageFault: return .gpuPageFault
        case .notPermitted: return .gpuNotPermitted
        case .outOfMemory: return .gpuOutOfMemory
        default: return .gpuError
        }
    }

    // MARK: - Recording output (REC-003)

    /// Encodes the output pass of the frame `composite` just encoded into `commandBuffer` (composite ×
    /// the flash guard's gain, as shown) once more into `target`, cropped to its size from the top
    /// left. Returns false, encoding nothing, when no frame was composited into this command buffer,
    /// the target is larger than the output, or its format is not in `supportedOutputFormats`.
    public func encodeOutput(into target: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let composite = shownComposite, let shown = outputCommandBuffer, shown === commandBuffer,   // FX-009: as shown
              target.width <= composite.width, target.height <= composite.height,
              let pipeline = outputPipeline(for: target.pixelFormat) else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "REC-003 recording output"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.setFragmentBuffer(flashGuard.gainBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(nonFiniteCounter.sink, offset: 0, index: 1)   // FX-002: not counted twice
        Self.bindGrade(shownGradeBlock, encoder)   // FX-003: the shown frame's grade
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    /// FX-003: `cmp_output`'s grade block at fragment buffer 2 (copied; no buffer).
    static func bindGrade(_ grade: CompositorShaders.GradeBlock, _ encoder: MTLRenderCommandEncoder) {
        var block = grade
        encoder.setFragmentBytes(&block, length: MemoryLayout<CompositorShaders.GradeBlock>.size, index: 2)
    }

    // MARK: - Frame capture (REC-001)

    /// True while a capture waits for the next frame.
    public var hasPendingFrameCapture: Bool { pendingCapture != nil }

    /// Captures the next frame `composite` encodes, as shown (after the flash guard): `handler` runs
    /// once, on Metal's completion thread, with linear premultiplied half-float RGBA at the output's
    /// size, or nil if the GPU work failed. A newer request or `cancelFrameCapture` gives an older
    /// pending handler nil. Call on the compositor's thread.
    public func requestFrameCapture(_ handler: @escaping @Sendable (CapturedPixels?) -> Void) {
        pendingCapture?(nil)
        pendingCapture = handler
    }

    /// Drops a pending capture (its handler gets nil).
    public func cancelFrameCapture() {
        let handler = pendingCapture
        pendingCapture = nil
        handler?(nil)
    }

    private func encodeCapture(composite: MTLTexture, size: LayerPictureDescriptor, commandBuffer: MTLCommandBuffer,
                               handler: @escaping @Sendable (CapturedPixels?) -> Void) {
        let width = size.width, height = size.height
        let rowBytes = width * 8
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        guard let pipeline = outputPipeline(for: .rgba16Float), let target = device.makeTexture(descriptor: d),
              let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared) else {
            handler(nil)
            return
        }
        target.label = "REC-001 capture"
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { handler(nil); return }
        encoder.label = "REC-001 capture output"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.setFragmentBuffer(flashGuard.gainBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(nonFiniteCounter.sink, offset: 0, index: 1)   // FX-002: not counted twice
        Self.bindGrade(shownGradeBlock, encoder)   // FX-003
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { handler(nil); return }
        blit.label = "REC-001 capture read-back"
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        // The buffer is read only here, after the GPU finished with it; nothing else holds it.
        nonisolated(unsafe) let readBack = buffer
        commandBuffer.addCompletedHandler { (completed: MTLCommandBuffer) in
            guard completed.status == .completed else { handler(nil); return }
            let count = width * height * 4
            let halves = readBack.contents().bindMemory(to: UInt16.self, capacity: count)
            let values = Array(UnsafeBufferPointer(start: halves, count: count))
            handler(CapturedPixels(width: width, height: height, layout: .linearPremultipliedHalfRGBA(values)))
        }
    }

    // MARK: - Transforms (CMP-005)

    /// `CMPTransformedDraw` in the shader: the inverse placement matrix in pixels (rows, xyz) and the
    /// opacity (`params.x`). 48 bytes, copied by `setFragmentBytes` (no buffer per frame).
    private struct TransformedDraw {
        var row0: SIMD4<Float>
        var row1: SIMD4<Float>
        var params: SIMD4<Float>
    }

    /// Output pixel → layer pixel: `D·M⁻¹·D⁻¹` with `D = diag(W, H)` (pictures are output-sized).
    /// nil only for a non-invertible matrix, which the scale bounds rule out. CMP-011: any placement matrix
    /// (a group's composed one included).
    private static func transformedDraw(_ matrix: LayerTransformMatrix, size: LayerPictureDescriptor,
                                        opacity: Double) -> TransformedDraw? {
        guard let inv = matrix.inverse else { return nil }
        let w = Double(size.width), h = Double(size.height)
        return TransformedDraw(row0: SIMD4<Float>(Float(inv.m00), Float(inv.m01 * w / h), Float(inv.m02 * w), 0),
                               row1: SIMD4<Float>(Float(inv.m10 * h / w), Float(inv.m11), Float(inv.m12 * h), 0),
                               params: SIMD4<Float>(Float(opacity), 0, 0, 0))
    }

    // MARK: - Resources

    /// Creates the composite and every picture for `size`, and prepares every layer (once per size).
    private func allocate(_ size: LayerPictureDescriptor) -> Bool {
        let d = size.textureDescriptor()
        if let composite { texturePool.recycle(composite, after: lastCommandBuffer) }   // PERF-004
        composite = nil
        if let compositeAlternate { texturePool.recycle(compositeAlternate, after: lastCommandBuffer) }   // CMP-004
        compositeAlternate = nil
        if let groupComposite { texturePool.recycle(groupComposite, after: lastCommandBuffer) }   // CMP-011
        groupComposite = nil
        if let groupAlternate { texturePool.recycle(groupAlternate, after: lastCommandBuffer) }
        groupAlternate = nil
        invalidateRenderCache()   // CMP-013: a new size (the key holds it too)
        trails.release(to: texturePool, after: lastCommandBuffer)   // FX-009-R5: a new size starts clean
        var starved = false
        #if DEBUG
        starved = faultInjection.missingPictures.contains("composite")
        #endif
        guard !starved, let newComposite = texturePool.makeTexture(descriptor: d) else { return false }
        newComposite.label = "CMP-001 composite"
        composite = newComposite
        pictureAllocations += 1
        for i in records.indices {
            records[i].retry.reset(atTick: frameTicks)   // PERF-014-R6: a new size is a fresh start
            records[i].heldError = nil
            allocatePictures(i, size)
        }
        descriptor = size
        return true
    }

    /// Creates layer `i`'s pictures for `size` and prepares it (an allocation point: a size change or
    /// a new layer applied).
    private func allocatePictures(_ i: Int, _ size: LayerPictureDescriptor) {
        let d = size.textureDescriptor()
        texturePool.recycle(records[i].pictures, after: lastCommandBuffer)   // PERF-004: the old size's pictures
        records[i].pictures = []
        records[i].cache.drop()   // CMP-013
        var created: [MTLTexture] = []
        var starved = false
        #if DEBUG
        starved = faultInjection.missingPictures.contains(records[i].layer.layerName)
        #endif
        for k in 0..<records[i].slots.pictureCount {
            guard !starved, let t = texturePool.makeTexture(descriptor: d) else { break }
            t.label = "CMP-001 \(records[i].layer.layerName) picture \(k)"
            created.append(t)
            pictureAllocations += 1
        }
        records[i].pictures = created
        if created.count == records[i].slots.pictureCount {
            prepareLayer(i, size)
        } else {
            records[i].slots.prepared(ok: false)
            records[i].prepareError = .resourceUnavailable("layer picture \(size.width)×\(size.height)")
            recordLayerFault(i, .missingTexture)
        }
    }

    /// PERF-014: a failed layer's retry: its pictures again if they are missing, else `prepare` again.
    private func rebuildLayer(_ i: Int, _ size: LayerPictureDescriptor) {
        if records[i].pictures.count == records[i].slots.pictureCount {
            prepareLayer(i, size)
        } else {
            allocatePictures(i, size)
        }
    }

    private func prepareLayer(_ i: Int, _ size: LayerPictureDescriptor) {
        guard records[i].pictures.count == records[i].slots.pictureCount else { return }
        records[i].cache.drop()   // CMP-013: prepared pictures hold nothing good
        layerPreparations += 1
        do throws(LayerSourceError) {
            #if DEBUG
            if faultInjection.failingPrepare.contains(records[i].layer.layerName) {
                throw .resourceUnavailable("injected pipeline failure")
            }
            #endif
            try records[i].layer.prepare(picture: size, device: device)
            records[i].slots.prepared(ok: true)
            records[i].prepareError = nil
        } catch {
            records[i].slots.prepared(ok: false)
            records[i].prepareError = error
            recordLayerFault(i, .layerPrepareFailed)
        }
    }

    private func outputPipeline(for format: MTLPixelFormat) -> MTLRenderPipelineState? {
        for entry in outputPipelines where entry.format == format { return entry.state }
        guard Self.supportedOutputFormats.contains(format),
              let fragment = library.makeFunction(name: "cmp_output"),
              let state = try? CompositorShaders.pipeline(device: device, vertex: fullScreen, fragment: fragment, format: format,
                                                          blendOver: false, label: "CMP-001 output \(format.rawValue)") else {
            return nil
        }
        outputPipelines.append((format, state))
        return state
    }
}
#endif
