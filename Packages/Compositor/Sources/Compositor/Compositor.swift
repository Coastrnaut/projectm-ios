// Compositor.swift — the minimal Metal compositor (CMP-001-R6 to R10, R15; ADR-0013; research
// CMP-001-D2, D4, D6; contracts/layer-source.md "Compositor").
//
// Per frame: the frame clock → each layer, bottom to top, renders into its free picture (its
// outcome decides which picture, if any, is shown: `LayerSlots`) → one render pass accumulates the
// shown pictures with premultiplied "over" onto transparent in an `rgba16Float` composite → the
// composite flash guard (FX-019's envelope on the finished stack, GPU only) → the output pass
// writes composite × gain into the caller's texture, whose format does the encoding.
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
// REC-003 (contracts/video-recording.md in specs/058): `encodeOutput(into:commandBuffer:)` encodes the
// output pass of the frame just composited once more into another target (a video recorder's pixel
// buffer texture), cropped to that target from the top left. Nothing changes for frames shown.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import FrameCapture
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
        /// PERF-014: the layer's back-off, and the render error shown while it holds.
        var retry = RenderRetryState()
        var heldError: LayerSourceError?

        init(id: LayerInstanceID?, layer: any LayerSource, settings: LayerCompositeSettings) {
            self.id = id
            self.layer = layer
            slots = LayerSlots(fallback: layer.fallback)
            opacity = LayerOpacityAnimator(opacity: settings.opacity)
            transform = settings.transform
            blendMode = settings.blendMode
            // CMP-006: a stack entry's fit always reaches the layer (the stack is the source of
            // truth); a layer given to `init(device:layers:)` keeps its own fit unless its settings set one.
            if let fitting = layer as? any LayerFitting, id != nil || settings.fit != nil { fitting.fit = settings.fit }
        }
    }

    public let device: MTLDevice
    private var records: [LayerRecord]
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
    private var outputPipelines: [(format: MTLPixelFormat, state: MTLRenderPipelineState)] = []
    private let flashGuard: CompositeFlashGuard
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
    /// The stack last applied (nil before the first `apply`, and for `init(device:layers:)`).
    public private(set) var appliedStack: LayerStack?
    /// REC-001: the handler waiting for the next frame.
    private var pendingCapture: (@Sendable (CapturedPixels?) -> Void)?
    /// REC-003: the command buffer of the last frame whose output pass was encoded.
    private weak var outputCommandBuffer: MTLCommandBuffer?

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
        records = layers.map { (layer: any LayerSource) -> LayerRecord in
            LayerRecord(id: nil, layer: layer, settings: layer.compositeSettings)
        }
        library = try CompositorShaders.library(device: device, source: CompositorShaders.source)
        fullScreen = try CompositorShaders.function(library, "cmp_fullscreen")
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
        flashGuard = try CompositeFlashGuard(device: device)
    }

    /// PERF-004: every picture goes back to the pool, reusable once the last frame completed.
    deinit {
        if let composite { texturePool.recycle(composite, after: lastCommandBuffer) }
        if let compositeAlternate { texturePool.recycle(compositeAlternate, after: lastCommandBuffer) }
        for record in records { texturePool.recycle(record.pictures, after: lastCommandBuffer) }
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

    /// The stack ID of layer `index` (nil for a layer given to `init(device:layers:)`).
    public func layerID(at index: Int) -> LayerInstanceID? { records[index].id }

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
                if let fitting = kept.layer as? any LayerFitting { fitting.fit = entry.settings.fit }   // CMP-006
                next.append(kept)
                continue
            }
            let layer: any LayerSource
            do {
                layer = try makeLayer(entry)
            } catch {
                throw .layerCreationFailed(index: i, error)
            }
            next.append(LayerRecord(id: entry.id, layer: layer, settings: entry.settings))
            created.append(i)
        }
        for i in next.indices where next[..<i].contains(where: { (r: LayerRecord) -> Bool in r.layer === next[i].layer }) {
            throw .duplicateLayer(index: i)
        }
        for old in records where !next.contains(where: { (r: LayerRecord) -> Bool in r.layer === old.layer }) {
            texturePool.recycle(old.pictures, after: lastCommandBuffer)   // PERF-004: back to the pool
        }
        records = next   // records no longer listed are released here
        appliedStack = stack
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
    public func resetFlashHistory() { flashGuard.reset() }

    /// Encodes one frame into `output` (a render target of a `supportedOutputFormats` format) and
    /// `commandBuffer`, which the caller commits. Returns false, encoding nothing, for an empty
    /// output, an unsupported format or when Metal cannot create an encoder.
    public func composite(into output: MTLTexture, commandBuffer: MTLCommandBuffer, presentationTimeNanoseconds: UInt64,
                          contentScale: Double, reduceFlashing: Bool, audio: LayerAudioContext) -> Bool {
        guard let size = LayerPictureDescriptor(width: output.width, height: output.height),
              let outputPipeline = outputPipeline(for: output.pixelFormat) else { return false }
        frameTicks &+= 1   // PERF-014-D1
        let tick = frameTicks
        defer { updateHealthState() }
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
        texturePool.tick()
        lastCommandBuffer = commandBuffer   // PERF-004: from here on this frame may use every picture
        let frame = clock.next(presentationTimeNanoseconds: presentationTimeNanoseconds, outputWidth: size.width,
                               outputHeight: size.height, contentScale: contentScale, reduceFlashing: reduceFlashing)

        // PERF-014-D3: while the visual's own part backs off, no layer renders (a black frame).
        let visualHolds = visualRetry.isHolding
        for i in records.indices {
            records[i].shown = -1
            records[i].opacity.advance(by: frame.frameDuration)
            if visualHolds {
                records[i].outcome = .notRendered
                continue
            }
            if records[i].retry.isRetryDue(atTick: tick) {   // PERF-014-R3, R4: only at back-off ticks
                records[i].retry.beginRetry(atTick: tick)
                records[i].heldError = nil
                if let descriptor, !records[i].slots.isAvailable { rebuildLayer(i, descriptor) }
            }
            guard records[i].slots.isAvailable else {
                records[i].outcome = .unavailable(records[i].prepareError ?? .notReady)
                continue
            }
            if records[i].retry.isHolding {   // a held render failure: its fallback, no render call
                showFallback(i, records[i].heldError ?? .notReady)
                continue
            }
            let target = records[i].pictures[records[i].slots.renderIndex]
            do throws(LayerSourceError) {
                #if DEBUG
                if faultInjection.failingRender.contains(records[i].layer.layerName) { throw .engineFailure("injected") }
                #endif
                try records[i].layer.render(into: target, commandBuffer: commandBuffer, frame: frame, audio: audio)
                records[i].shown = records[i].slots.frameSucceeded()
                records[i].outcome = .rendered
                if records[i].retry.succeeded(encodedAtTick: tick) { health.recordRecovery() }
            } catch {
                showFallback(i, error)
                if error.isRenderFault {   // PERF-014-D4: routine errors keep CMP-001's per-frame behaviour
                    records[i].heldError = error
                    recordLayerFault(i, .layerRenderFailed)
                }
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = composite
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard var over = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        over.label = "CMP-001 composite"
        var plain = true
        over.setRenderPipelineState(overPipeline)
        transformedDraws = 0
        blendDraws = 0
        for i in records.indices where records[i].shown >= 0 && records[i].opacity.value > 0 {
            let transform = records[i].transform
            if records[i].blendMode != .normal {
                if !transform.isIdentity, case .none = Self.transformedDraw(transform, size: size, opacity: 1) { continue }
                // CMP-004: end the "over" pass, blend into the other composite, swap, re-open.
                over.endEncoding()
                guard let target = alternateComposite(like: composite),
                      encodeBlend(i, backdrop: composite, into: target, size: size, commandBuffer: commandBuffer) else { return false }
                compositeAlternate = composite
                composite = target
                self.composite = target
                let reopen = MTLRenderPassDescriptor()
                reopen.colorAttachments[0].texture = composite
                reopen.colorAttachments[0].loadAction = .load
                reopen.colorAttachments[0].storeAction = .store
                guard let next = commandBuffer.makeRenderCommandEncoder(descriptor: reopen) else { return false }
                next.label = "CMP-001 composite"
                next.setRenderPipelineState(overPipeline)
                over = next
                plain = true
                continue
            }
            over.setFragmentTexture(records[i].pictures[records[i].shown], index: 0)
            if transform.isIdentity {
                if !plain { over.setRenderPipelineState(overPipeline); plain = true }
                var opacity = Float(records[i].opacity.value)
                over.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            } else {
                guard var draw = Self.transformedDraw(transform, size: size, opacity: records[i].opacity.value) else { continue }
                if plain { over.setRenderPipelineState(transformedPipeline); plain = false }
                over.setFragmentBytes(&draw, length: MemoryLayout<TransformedDraw>.stride, index: 0)
                transformedDraws += 1
            }
            over.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        over.endEncoding()

        guard flashGuard.encode(composite: composite, commandBuffer: commandBuffer, frameDuration: frame.frameDuration,
                                reduceFlashing: reduceFlashing) else { return false }

        let out = MTLRenderPassDescriptor()
        out.colorAttachments[0].texture = output
        out.colorAttachments[0].loadAction = .dontCare
        out.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: out) else { return false }
        encoder.label = "CMP-001 output"
        encoder.setRenderPipelineState(outputPipeline)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.setFragmentBuffer(flashGuard.gainBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        outputCommandBuffer = commandBuffer   // REC-003: `encodeOutput` may follow in this command buffer
        if let handler = pendingCapture {
            pendingCapture = nil
            encodeCapture(composite: composite, size: size, commandBuffer: commandBuffer, handler: handler)
        }
        watch(commandBuffer, tick: tick)
        return true
    }

    // MARK: - Blend modes (CMP-004)

    /// The ping-pong partner of `current` (taken from the pool the first time; an allocation point).
    private func alternateComposite(like current: MTLTexture) -> MTLTexture? {
        if let compositeAlternate, compositeAlternate.width == current.width, compositeAlternate.height == current.height {
            return compositeAlternate
        }
        if let compositeAlternate { texturePool.recycle(compositeAlternate, after: lastCommandBuffer) }
        compositeAlternate = nil
        guard let d = LayerPictureDescriptor(width: current.width, height: current.height),
              let made = texturePool.makeTexture(descriptor: d.textureDescriptor()) else { return nil }
        made.label = "CMP-004 composite"
        pictureAllocations += 1
        compositeAlternate = made
        return made
    }

    /// One full-screen `cmp_blend` pass: layer `i` with its mode over `backdrop`, written to `target`.
    private func encodeBlend(_ i: Int, backdrop: MTLTexture, into target: MTLTexture, size: LayerPictureDescriptor,
                             commandBuffer: MTLCommandBuffer) -> Bool {
        let opacity = records[i].opacity.value
        var draw: TransformedDraw
        if records[i].transform.isIdentity {
            draw = TransformedDraw(row0: .zero, row1: .zero, params: SIMD4<Float>(Float(opacity), 0, 0, 0))
        } else {
            guard let placed = Self.transformedDraw(records[i].transform, size: size, opacity: opacity) else { return false }   // checked by the caller
            draw = placed
            draw.params.y = 1
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
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        blendDraws += 1
        return true
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
        guard let composite, let shown = outputCommandBuffer, shown === commandBuffer,
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
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
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
    /// nil only for a non-invertible matrix, which the scale bounds rule out.
    private static func transformedDraw(_ transform: LayerTransform, size: LayerPictureDescriptor,
                                        opacity: Double) -> TransformedDraw? {
        guard let inv = transform.matrix(outputWidth: size.width, outputHeight: size.height).inverse else { return nil }
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
