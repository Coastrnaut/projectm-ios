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
// Not Sendable: the compositor's thread drives it.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import ParameterGraph

public final class ProceduralMaterialLayer: LayerSource {
    public let definition: MaterialDefinition
    public let fallback = LayerFallback.transparent
    public private(set) var parameters: MaterialParameterValues
    public private(set) var motion = MaterialMotion()
    private var library: MTLLibrary?
    private var pipeline: MTLRenderPipelineState?
    private let speedSlot: Int
    private let reactivitySlot: Int

    public init(_ definition: MaterialDefinition) {
        self.definition = definition
        parameters = MaterialParameterValues(definition)
        speedSlot = definition.slot(of: definition.speedParameter) ?? -1
        reactivitySlot = definition.slot(of: definition.reactivityParameter) ?? -1
    }

    /// The catalog material with exactly this ID, or nil.
    public convenience init?(materialID: String) {
        guard let definition = ProceduralMaterialCatalog.material(withID: materialID) else { return nil }
        self.init(definition)
    }

    public var layerName: String { definition.id }

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
        if pipeline != nil { return }
        let library: MTLLibrary
        if let compiled = self.library {
            library = compiled
        } else {
            library = try ProceduralMaterialShaders.makeLibrary(device: device)
            self.library = library
        }
        guard let vertex = library.makeFunction(name: ProceduralMaterialShaders.vertexFunction),
              let fragment = library.makeFunction(name: definition.fragmentFunction) else {
            throw .resourceUnavailable("material functions for \(definition.id)")
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = "SHD-001 \(definition.id)"
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            throw .resourceUnavailable("material pipeline \(definition.id): \(error.localizedDescription)")
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
