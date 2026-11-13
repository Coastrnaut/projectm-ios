// PostProcessEffect.swift — the post-processing effect contract (FX-001-R1; ADR-0010 decision 2;
// specs/020-fx-001-bloom/contracts/post-process-effect.md).
//
// An effect reads one input texture and writes one output texture of the same size and pixel
// format, in linear light with premultiplied alpha. Working textures are created by `prepare` only
// when the size changes; per frame nothing is created. The output may be a `framebufferOnly`
// drawable, so effects write it only from a render pass. Not Sendable: one thread drives an effect.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import VisualGenerators

public protocol PostProcessEffect: AnyObject {
    /// Stable identifier (`fx.bloom`); never reused for another effect.
    var identifier: EffectIdentifier { get }
    /// The only pixel format of `input` and `output`.
    var pixelFormat: MTLPixelFormat { get }
    /// True when `encode` would reproduce the input exactly; a chain then skips the effect.
    var isPassThrough: Bool { get }
    /// Creates or resizes working textures for an output of width × height (only when it changed).
    func prepare(width: Int, height: Int) throws(VisualGeneratorError)
    /// Encodes input → output into `commandBuffer` (the caller commits). Returns false, encoding
    /// nothing, when the sizes or formats do not match the prepared ones or input is output.
    func encode(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool
}

/// Shared runtime-compilation options for effect shaders (ADR-0009 decision 3): safe math, so
/// `isnan`/`isinf` work and results do not depend on fast-math reassociation (FX-001-R9).
enum EffectShaderCompiler {
    static func library(device: MTLDevice, source: String) throws(VisualGeneratorError) -> MTLLibrary {
        let options = MTLCompileOptions()
        options.mathMode = .safe
        do {
            return try device.makeLibrary(source: source, options: options)
        } catch {
            throw .pipelineUnavailable("shader compile: \(error.localizedDescription)")
        }
    }
}
#endif
