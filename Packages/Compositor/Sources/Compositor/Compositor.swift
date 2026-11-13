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
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

public enum CompositorError: Error, Equatable, Sendable {
    /// Shaders, pipelines or the guard's buffers could not be created; the text is the system's.
    case pipelineUnavailable(String)
    /// The same layer object appears twice (at this index).
    case duplicateLayer(index: Int)
    /// The layer at this index asks for opacity, blend or transform values CMP-001 does not support.
    case unsupportedCompositeSettings(index: Int)
}

public final class Compositor {
    /// Output formats `composite` writes.
    public static let supportedOutputFormats: [MTLPixelFormat] = [.bgra8Unorm_srgb, .rgba16Float, .bgra8Unorm, .rgba8Unorm]

    public let device: MTLDevice
    private let layers: [any LayerSource]
    private var slots: [LayerSlots]
    private var pictures: [[MTLTexture]]
    private var outcomes: [LayerOutcome]
    private var prepareErrors: [LayerSourceError?]
    /// Picture shown per layer this frame (−1: none). Preallocated.
    private var shown: [Int]
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

    public init(device: MTLDevice, layers: [any LayerSource]) throws(CompositorError) {
        for (i, layer) in layers.enumerated() {
            if layers[..<i].contains(where: { $0 === layer }) { throw .duplicateLayer(index: i) }
            if !layer.compositeSettings.isSupportedByCMP001 { throw .unsupportedCompositeSettings(index: i) }
        }
        self.device = device
        self.layers = layers
        slots = layers.map { LayerSlots(fallback: $0.fallback) }
        pictures = Array(repeating: [], count: layers.count)
        outcomes = Array(repeating: .notRendered, count: layers.count)
        prepareErrors = Array(repeating: nil, count: layers.count)
        shown = Array(repeating: -1, count: layers.count)
        library = try CompositorShaders.library(device: device, source: CompositorShaders.source)
        fullScreen = try CompositorShaders.function(library, "cmp_fullscreen")
        overPipeline = try CompositorShaders.pipeline(device: device, vertex: fullScreen,
                                                      fragment: try CompositorShaders.function(library, "cmp_over"),
                                                      format: LayerPictureDescriptor.metalPixelFormat, blendOver: true,
                                                      label: "CMP-001 over")
        flashGuard = try CompositeFlashGuard(device: device)
    }

    public var layerCount: Int { layers.count }

    /// What happened to layer `index` in the last frame.
    public func outcome(ofLayer index: Int) -> LayerOutcome { outcomes[index] }

    /// Prepares every unavailable layer again at the current size (it reappears from the next frame
    /// if its `prepare` now succeeds).
    public func retryUnavailableLayers() {
        guard let descriptor else { return }
        for i in layers.indices where !slots[i].isAvailable { prepareLayer(i, descriptor) }
    }

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

        for i in layers.indices {
            shown[i] = -1
            guard slots[i].isAvailable else {
                outcomes[i] = .unavailable(prepareErrors[i] ?? .notReady)
                continue
            }
            let target = pictures[i][slots[i].renderIndex]
            do {
                try layers[i].render(into: target, commandBuffer: commandBuffer, frame: frame, audio: audio)
                shown[i] = slots[i].frameSucceeded()
                outcomes[i] = .rendered
            } catch {
                if let good = slots[i].frameFailed() { shown[i] = good }
                outcomes[i] = slots[i].fallback == .lastGoodFrame ? .fallbackLastGood(error) : .fallbackTransparent(error)
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
        for i in layers.indices where shown[i] >= 0 {
            over.setFragmentTexture(pictures[i][shown[i]], index: 0)
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
        for i in layers.indices {
            var created: [MTLTexture] = []
            for k in 0..<slots[i].pictureCount {
                guard let t = device.makeTexture(descriptor: d) else { break }
                t.label = "CMP-001 \(layers[i].layerName) picture \(k)"
                created.append(t)
                pictureAllocations += 1
            }
            pictures[i] = created
            if created.count == slots[i].pictureCount {
                prepareLayer(i, size)
            } else {
                slots[i].prepared(ok: false)
                prepareErrors[i] = .resourceUnavailable("layer picture \(size.width)×\(size.height)")
            }
        }
        descriptor = size
        return true
    }

    private func prepareLayer(_ i: Int, _ size: LayerPictureDescriptor) {
        guard pictures[i].count == slots[i].pictureCount else { return }
        do {
            try layers[i].prepare(picture: size, device: device)
            slots[i].prepared(ok: true)
            prepareErrors[i] = nil
        } catch {
            slots[i].prepared(ok: false)
            prepareErrors[i] = error
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
