// ProceduralMaterialLayer.swift — one catalog material as a CMP-001 layer (SHD-001-R3, R4, R5, R6,
// R10, R13; contracts/material-catalog.md "Layer").
//
// `prepare` compiles the module's constant shader source once per layer (kept across size changes)
// and builds the pipeline for the layer picture format. Each `render` advances the material's
// motion from the frame duration and the bands (music changes only speed), then one render pass
// clears the picture and draws a full-screen triangle with the uniforms passed by
// `setFragmentBytes`. The picture is opaque linear color (premultiplied = straight). A failure to
// prepare throws `.resourceUnavailable`; the compositor then shows the transparent fallback. Under
// the compositor, the composite flash guard (CMP-001-R10) applies on top of every material.
// SHD-004: a layer holds a selected variant (nil = default). `prepare` builds the pipelines of the default and
// every variant the GPU supports into a cache; `select(variant:)` only re-resolves which cached pipeline the
// next frame uses (no pipeline creation, allocation or lock in `render`), and never touches parameters,
// motion or the layer's identity. An unknown, unsupported or unbuildable variant draws the default with a
// notice (`resolution.notice`); the selection is kept.
// Not Sendable: the compositor's thread drives it (call `select` between frames on that thread).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import ParameterGraph
import ShaderParameterMetadata
import VisualGenerators

public final class ProceduralMaterialLayer: LayerSource {
    public let definition: MaterialDefinition
    public let fallback = LayerFallback.transparent
    public private(set) var parameters: MaterialParameterValues
    public private(set) var motion = MaterialMotion()
    /// SHD-004: the stored choice (nil = the default variant); kept even when it cannot be drawn here.
    public private(set) var selectedVariant: String?
    /// SHD-004: what is drawn and why; recomputed by `select` and `prepare`.
    public private(set) var resolution: MaterialVariantResolution
    /// The GPU families judged against; nil until `prepare` reads them from the device (unless injected).
    public private(set) var capabilities: MaterialGPUCapabilities?
    private var library: MTLLibrary?
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var pipeline: MTLRenderPipelineState?
    /// SHD-005: the multi-stop gradient the Gradient Field draws (nil = its two colours, unchanged); other materials
    /// ignore it.
    public private(set) var gradient: GradientRamp?
    private var rampUniforms = GradientRampUniforms.none
    private let speedSlot: Int
    private let reactivitySlot: Int

    /// `variant` nil (or the default's ID) draws the default; `capabilities` nil reads them from the device.
    public init(_ definition: MaterialDefinition, variant: String? = nil, capabilities: MaterialGPUCapabilities? = nil) {
        self.definition = definition
        parameters = MaterialParameterValues(definition)
        speedSlot = definition.slot(of: definition.speedParameter) ?? -1
        reactivitySlot = definition.slot(of: definition.reactivityParameter) ?? -1
        self.capabilities = capabilities
        selectedVariant = variant == definition.defaultVariantID ? nil : variant
        resolution = MaterialVariantResolution(drawn: definition.defaultVariantID)
        resolveVariant()
    }

    /// The catalog material with exactly this ID, or nil.
    public convenience init?(materialID: String, variant: String? = nil, capabilities: MaterialGPUCapabilities? = nil) {
        guard let definition = ProceduralMaterialCatalog.material(withID: materialID) else { return nil }
        self.init(definition, variant: variant, capabilities: capabilities)
    }

    /// SHD-004-R4: chooses the variant drawn from the next frame (nil or the default's ID = default). Values,
    /// motion and composite settings are untouched; no pipeline is built here.
    public func select(variant: String?) {
        selectedVariant = variant == definition.defaultVariantID ? nil : variant
        resolveVariant()
    }

    /// SHD-004: the variants whose pipelines `prepare` built (empty before it).
    public var preparedVariants: Set<String> { Set(pipelines.keys) }

    private func resolveVariant() {
        let built: Set<String>? = pipelines.isEmpty ? nil : Set(pipelines.keys)
        resolution = MaterialVariantResolution.resolve(selection: selectedVariant, variants: definition.variants,
                                                       capabilities: capabilities ?? .all, built: built)
        pipeline = pipelines[resolution.drawn]
    }

    public var layerName: String { definition.id }

    /// SHD-005-R6: sets (or clears) the gradient drawn from the next frame. Call between frames.
    public func setGradient(_ ramp: GradientRamp?) {
        gradient = ramp
        rampUniforms = GradientRampUniforms(ramp: ramp)
    }

    /// Sets one parameter, clamped (SHD-001-R6); takes effect from the next frame.
    @discardableResult
    public func set(_ value: ParameterValue, for id: ParameterID) throws(MaterialParameterError) -> ParameterValue {
        try parameters.set(value, for: id)
    }

    /// Copies the values `store` holds for this material's parameters (a store built from the
    /// catalog's registry holds all of them). Call outside `render`: the store locks.
    public func update(from store: ParameterStore) {
        for d in definition.parameters {
            if let value = store.value(for: d.id) { _ = try? parameters.set(value, for: d.id) }
        }
    }

    /// Phase and music level back to 0 (a new scene).
    public func resetMotion() { motion.reset() }

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        if !pipelines.isEmpty { return }
        let gpu: MaterialGPUCapabilities = capabilities ?? MaterialGPUCapabilities(device: device)
        capabilities = gpu
        let library: MTLLibrary
        if let compiled = self.library {
            library = compiled
        } else {
            library = try ProceduralMaterialShaders.makeLibrary(device: device)
            self.library = library
        }
        // The default variant must build (SHD-001: otherwise the layer is unavailable).
        let defaultID: String = definition.defaultVariantID
        pipelines[defaultID] = try makePipeline(variant: defaultID, library: library, device: device)
        // SHD-004-R4: every other supported variant is built now, so switching never builds at render time.
        for variant in definition.variants.dropFirst() where gpu.supports(variant) {
            if let built = try? makePipeline(variant: variant.id, library: library, device: device) { pipelines[variant.id] = built }
        }
        resolveVariant()
    }

    private func makePipeline(variant: String, library: MTLLibrary, device: MTLDevice) throws(LayerSourceError) -> MTLRenderPipelineState {
        let function: String = definition.fragmentFunction(for: variant)
        // SHD-003-R4, SHD-004-R2: the material's metadata must match the slots this variant's function reads.
        if let metadata = definition.metadata {
            do {
                try metadata.check(source: ProceduralMaterialShaders.source, function: function)
            } catch {
                throw .resourceUnavailable("material metadata \(definition.id) (\(variant)): \(error)")
            }
        }
        guard let vertex = library.makeFunction(name: ProceduralMaterialShaders.vertexFunction),
              let fragment = library.makeFunction(name: function) else {
            throw .resourceUnavailable("material functions for \(definition.id) (\(variant))")
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = "SHD-001 \(definition.id) \(variant)"
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
        do {
            return try device.makeRenderPipelineState(descriptor: d)
        } catch {
            throw .resourceUnavailable("material pipeline \(definition.id) (\(variant)): \(error.localizedDescription)")
        }
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        guard let pipeline else { throw .notReady }
        let speed = Double(parameters.slot(speedSlot).x)
        let reactivity = Double(parameters.slot(reactivitySlot).x)
        motion.advance(frameDuration: frame.frameDuration, bandLevel: MaterialMotion.bandLevel(audio.bands),
                       speed: speed, reactivity: reactivity)
        var uniforms = MaterialUniforms(width: picture.width, height: picture.height, phase: motion.phase,
                                        audio: motion.audioLevel, values: parameters)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        encoder.label = "SHD-001 \(definition.id)"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MaterialUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&rampUniforms, length: MemoryLayout<GradientRampUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

extension ProceduralMaterialCatalog {
    /// A new layer drawing `kind` at its documented defaults.
    public static func makeLayer(_ kind: MaterialKind) -> ProceduralMaterialLayer {
        ProceduralMaterialLayer(definition(kind))
    }
}
#endif
