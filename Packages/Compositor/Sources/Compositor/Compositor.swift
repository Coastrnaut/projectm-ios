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
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

public enum CompositorError: Error, Equatable, Sendable {
    /// Shaders, pipelines or the guard's buffers could not be created; the text is the system's.
    case pipelineUnavailable(String)
    /// The same layer object appears twice (at this index).
    case duplicateLayer(index: Int)
    /// The layer at this index asks for opacity, blend or transform values CMP-001 does not support.
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

        init(id: LayerInstanceID?, layer: any LayerSource) {
            self.id = id
            self.layer = layer
            slots = LayerSlots(fallback: layer.fallback)
        }
    }

    public let device: MTLDevice
    private var records: [LayerRecord]
    private var composite: MTLTexture?
    private var descriptor: LayerPictureDescriptor?
    private var clock = LayerFrameClock()
    private let library: MTLLibrary
    private let fullScreen: MTLFunction
    private let overPipeline: MTLRenderPipelineState
    private var outputPipelines: [(format: MTLPixelFormat, state: MTLRenderPipelineState)] = []
    private let flashGuard: CompositeFlashGuard

    /// Pictures (and composites) created so far (tests, diagnostics).
    public private(set) var pictureAllocations = 0
    /// Calls to layers' `prepare` so far (tests, diagnostics; CMP-002-S3).
    public private(set) var layerPreparations = 0
    /// The stack last applied (nil before the first `apply`, and for `init(device:layers:)`).
    public private(set) var appliedStack: LayerStack?

    /// An empty compositor; give it layers with `apply(_:makeLayer:)` (CMP-002).
    public convenience init(device: MTLDevice) throws(CompositorError) {
        try self.init(device: device, layers: [])
    }

    /// A compositor with a fixed list of layers, bottom first (CMP-001). The layers have no stack
    /// ID; the first `apply` releases them.
    public init(device: MTLDevice, layers: [any LayerSource]) throws(CompositorError) {
        for (i, layer) in layers.enumerated() {
            if layers[..<i].contains(where: { $0 === layer }) { throw .duplicateLayer(index: i) }
            if !layer.compositeSettings.isSupportedByCMP001 { throw .unsupportedCompositeSettings(index: i) }
        }
        self.device = device
        records = layers.map { (layer: any LayerSource) -> LayerRecord in LayerRecord(id: nil, layer: layer) }
        library = try CompositorShaders.library(device: device, source: CompositorShaders.source)
        fullScreen = try CompositorShaders.function(library, "cmp_fullscreen")
        overPipeline = try CompositorShaders.pipeline(device: device, vertex: fullScreen,
                                                      fragment: try CompositorShaders.function(library, "cmp_over"),
                                                      format: LayerPictureDescriptor.metalPixelFormat, blendOver: true,
                                                      label: "CMP-001 over")
        flashGuard = try CompositeFlashGuard(device: device)
    }

    public var layerCount: Int { records.count }

    /// What happened to layer `index` (bottom first) in the last frame.
    public func outcome(ofLayer index: Int) -> LayerOutcome { records[index].outcome }

    /// The stack ID of layer `index` (nil for a layer given to `init(device:layers:)`).
    public func layerID(at index: Int) -> LayerInstanceID? { records[index].id }

    /// Applies a new stack between frames (CMP-002-R7 to R11, R14; contracts/layer-stack.md). Call it
    /// on the compositor's thread, never while encoding a frame. An equal stack changes nothing.
    /// Layers whose IDs are still present keep their object, pictures and state at their new index;
    /// `makeLayer` is called once per new ID and the new layers are prepared now if the output size
    /// is known (else with the first frame); layers whose IDs are gone are released (nothing is
    /// called on them). On any error the previous stack stays applied. The flash guard's history is
    /// kept: a stack edit is not a new scene.
    public func apply(_ stack: LayerStack, makeLayer: LayerFactory) throws(CompositorError) {
        if let appliedStack, appliedStack == stack { return }
        let entries = stack.entries
        for (i, entry) in entries.enumerated() where !entry.settings.isSupportedByCMP001 {
            throw .unsupportedCompositeSettings(index: i)
        }
        var next: [LayerRecord] = []
        next.reserveCapacity(entries.count)
        var created: [Int] = []
        for (i, entry) in entries.enumerated() {
            if let kept = records.first(where: { (r: LayerRecord) -> Bool in r.id == entry.id }) {
                next.append(kept)
                continue
            }
            let layer: any LayerSource
            do {
                layer = try makeLayer(entry)
            } catch {
                throw .layerCreationFailed(index: i, error)
            }
            next.append(LayerRecord(id: entry.id, layer: layer))
            created.append(i)
        }
        for i in next.indices where next[..<i].contains(where: { (r: LayerRecord) -> Bool in r.layer === next[i].layer }) {
            throw .duplicateLayer(index: i)
        }
        records = next   // records no longer listed are released here
        appliedStack = stack
        if let descriptor {
            for i in created { allocatePictures(i, descriptor) }
        }
    }

    /// Prepares every unavailable layer again at the current size (it reappears from the next frame
    /// if its `prepare` now succeeds).
    public func retryUnavailableLayers() {
        guard let descriptor else { return }
        for i in records.indices where !records[i].slots.isAvailable { prepareLayer(i, descriptor) }
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
        if size != descriptor {
            guard allocate(size) else { return false }
        }
        guard let composite else { return false }
        let frame = clock.next(presentationTimeNanoseconds: presentationTimeNanoseconds, outputWidth: size.width,
                               outputHeight: size.height, contentScale: contentScale, reduceFlashing: reduceFlashing)

        for i in records.indices {
            records[i].shown = -1
            guard records[i].slots.isAvailable else {
                records[i].outcome = .unavailable(records[i].prepareError ?? .notReady)
                continue
            }
            let target = records[i].pictures[records[i].slots.renderIndex]
            do {
                try records[i].layer.render(into: target, commandBuffer: commandBuffer, frame: frame, audio: audio)
                records[i].shown = records[i].slots.frameSucceeded()
                records[i].outcome = .rendered
            } catch {
                if let good = records[i].slots.frameFailed() { records[i].shown = good }
                records[i].outcome = records[i].slots.fallback == .lastGoodFrame ? .fallbackLastGood(error) : .fallbackTransparent(error)
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = composite
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let over = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        over.label = "CMP-001 composite"
        over.setRenderPipelineState(overPipeline)
        for i in records.indices where records[i].shown >= 0 {
            over.setFragmentTexture(records[i].pictures[records[i].shown], index: 0)
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
        return true
    }

    // MARK: - Resources

    /// Creates the composite and every picture for `size`, and prepares every layer (once per size).
    private func allocate(_ size: LayerPictureDescriptor) -> Bool {
        let d = size.textureDescriptor()
        guard let newComposite = device.makeTexture(descriptor: d) else { return false }
        newComposite.label = "CMP-001 composite"
        composite = newComposite
        pictureAllocations += 1
        for i in records.indices { allocatePictures(i, size) }
        descriptor = size
        return true
    }

    /// Creates layer `i`'s pictures for `size` and prepares it (an allocation point: a size change or
    /// a new layer applied).
    private func allocatePictures(_ i: Int, _ size: LayerPictureDescriptor) {
        let d = size.textureDescriptor()
        var created: [MTLTexture] = []
        for k in 0..<records[i].slots.pictureCount {
            guard let t = device.makeTexture(descriptor: d) else { break }
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
        }
    }

    private func prepareLayer(_ i: Int, _ size: LayerPictureDescriptor) {
        guard records[i].pictures.count == records[i].slots.pictureCount else { return }
        layerPreparations += 1
        do {
            try records[i].layer.prepare(picture: size, device: device)
            records[i].slots.prepared(ok: true)
            records[i].prepareError = nil
        } catch {
            records[i].slots.prepared(ok: false)
            records[i].prepareError = error
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
