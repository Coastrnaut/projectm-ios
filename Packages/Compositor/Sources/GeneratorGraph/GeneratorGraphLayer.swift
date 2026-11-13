// GeneratorGraphLayer.swift — draws a compiled generator graph as a CMP-001 layer (SHD-002-R8, R9,
// R11; contracts/generator-graph.md "Layer").
//
// `GeneratorGraphPipeline` compiles the module's one interpreter constant and builds the pipeline
// for the layer picture format; it can be shared by every graph layer on a device, so showing a new
// graph never compiles a shader. `prepare` makes the plan buffer once (the instructions are fixed
// for the layer's life). Each `render` advances the motion from the frame duration and the bands,
// writes the 64 per-instruction time terms in double precision into a preallocated array, and draws
// one full-screen triangle (frame uniforms and terms by `setFragmentBytes`, the plan by buffer). The
// picture is opaque linear color (premultiplied = straight); a failure to prepare throws
// `.resourceUnavailable` and the compositor shows the transparent fallback. Under the compositor
// the composite flash guard (CMP-001-R10) applies on top. Not Sendable: the compositor's thread
// drives it.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal

/// The interpreter's pipeline for one device; share it between graph layers.
public final class GeneratorGraphPipeline {
    public let device: MTLDevice
    let state: MTLRenderPipelineState

    public init(device: MTLDevice) throws(LayerSourceError) {
        self.device = device
        let library = try GeneratorGraphShaders.makeLibrary(device: device)
        guard let vertex = library.makeFunction(name: GeneratorGraphShaders.vertexFunction),
              let fragment = library.makeFunction(name: GeneratorGraphShaders.fragmentFunction) else {
            throw .resourceUnavailable("generator graph functions")
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = "SHD-002 graph interpreter"
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
        do {
            state = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            throw .resourceUnavailable("generator graph pipeline: \(error.localizedDescription)")
        }
    }
}

public final class GeneratorGraphLayer: LayerSource {
    public static let maxTerms = GeneratorGraphLimits.nodes

    public let compiled: CompiledGeneratorGraph
    public let fallback = LayerFallback.transparent
    public private(set) var motion = GraphMotion()
    /// Phase cycles per second, clamped to ±`compiled.speedCap`.
    public private(set) var speed: Double
    private var pipeline: GeneratorGraphPipeline?
    private var planBuffer: MTLBuffer?
    private var terms: [SIMD4<Float>]

    public init(compiled: CompiledGeneratorGraph, pipeline: GeneratorGraphPipeline? = nil) {
        self.compiled = compiled
        self.pipeline = pipeline
        speed = compiled.defaultSpeed
        terms = [SIMD4<Float>](repeating: .zero, count: Self.maxTerms)
    }

    /// Compiles `document` and makes its layer.
    public convenience init(document: GeneratorGraphDocument, pipeline: GeneratorGraphPipeline? = nil) throws(GeneratorGraphValidationError) {
        self.init(compiled: try GeneratorGraphCompiler.compile(document), pipeline: pipeline)
    }

    public var layerName: String { "graph:\(compiled.name)" }

    /// Sets the speed, clamped to the graph's cap; returns the stored value.
    @discardableResult
    public func setSpeed(_ value: Double) -> Double {
        speed = compiled.clampSpeed(value)
        return speed
    }

    /// Phase and music level back to 0 (a new scene).
    public func resetMotion() { motion.reset() }

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        if pipeline == nil || pipeline?.device !== device {
            pipeline = try GeneratorGraphPipeline(device: device)
            planBuffer = nil
        }
        if planBuffer == nil {
            let bytes = compiled.instructionBytes
            guard !bytes.isEmpty,
                  let buffer = bytes.withUnsafeBytes({ (raw: UnsafeRawBufferPointer) -> MTLBuffer? in
                      guard let base = raw.baseAddress else { return nil }
                      return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
                  }) else {
                throw .resourceUnavailable("generator graph plan buffer")
            }
            buffer.label = "SHD-002 plan \(compiled.name)"
            planBuffer = buffer
        }
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        guard let pipeline, let planBuffer else { throw .notReady }
        motion.advance(frameDuration: frame.frameDuration, bandLevel: GraphMotion.bandLevel(audio.bands),
                       speed: speed, musicRate: compiled.musicRate)
        compiled.writeTimeTerms(phase: motion.phase, into: &terms)
        var uniforms = GraphFrameUniforms(size: SIMD2(Float(max(picture.width, 1)), Float(max(picture.height, 1))),
                                          music: Float(motion.musicLevel), count: UInt32(compiled.instructions.count))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        encoder.label = "SHD-002 \(compiled.name)"
        encoder.setRenderPipelineState(pipeline.state)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GraphFrameUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(planBuffer, offset: 0, index: 1)
        terms.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.baseAddress { encoder.setFragmentBytes(base, length: raw.count, index: 2) }
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
#endif
