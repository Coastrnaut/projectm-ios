// SpectrumLayerSource.swift — the native spectra as layers (CMP-001-R12; contracts/layer-source.md
// "Adapters"; VIS-001, VIS-002, FX-001 glow).
//
// Wraps any `SpectrumTextureGenerator` built for the layer format (`rgba16Float`). Per frame the
// bands come from the audio context, the frame time and Reduce flashing from the frame context; the
// generator keeps its own Reduce-flashing slew and strobe envelope (VIS-001-R10, VIS-002-R9). With
// the glow on, an FX-001 `BloomEffect` runs in an `EffectChain` after the generator, and the
// generator's `downstreamLuminance` is the bloom's luminance model (FX-001-R10), exactly as the app
// host does. A skipped frame (no vertex buffer free) throws `.frameSkipped`; the fallback is the last
// good frame, so a skip never flickers. A glow whose textures cannot be created is dropped (the
// layer keeps drawing without it, FX-001-R13). Per frame nothing is allocated: the effect chain's
// closure is non-escaping. Not Sendable: the compositor's thread drives it.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import VisualEffects
import VisualGenerators

public final class SpectrumLayerSource: LayerSource {
    public let layerName: String
    public let fallback = LayerFallback.lastGoodFrame
    public let generator: any SpectrumTextureGenerator
    private let bloom: BloomEffect?
    private var chain: EffectChain?

    /// The glow settings, applied from the next frame.
    public var glow: BloomParameters {
        didSet { applyGlow() }
    }

    /// The bloom runs (available and not pass-through).
    public var glowActive: Bool { chain != nil && !glow.isPassThrough }

    /// Throws `VisualGeneratorError.unsupportedPixelFormat` when the generator does not draw the
    /// layer format. A glow that cannot be built leaves the layer without glow (FX-001-R13).
    public init(device: MTLDevice, generator: any SpectrumTextureGenerator, glow: BloomParameters = BloomParameters(),
                name: String = "spectrum") throws(VisualGeneratorError) {
        guard generator.pixelFormat == LayerPictureDescriptor.metalPixelFormat else {
            throw .unsupportedPixelFormat(generator.pixelFormat.rawValue)
        }
        layerName = name
        self.generator = generator
        self.glow = glow
        if let effect = try? BloomEffect(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat, parameters: glow),
           let effects = try? EffectChain(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat, effects: [effect]) {
            bloom = effect
            chain = effects
        } else {
            bloom = nil
            chain = nil
        }
        applyGlow()
    }

    private func applyGlow() {
        bloom?.parameters = glow
        generator.downstreamLuminance = glowActive ? BloomLuminanceModel(parameters: glow) : nil
    }

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        generator.restartLoop()
        guard let chain else { return }
        do {
            try chain.prepare(width: picture.width, height: picture.height)
        } catch {
            self.chain = nil   // FX-001-R13: continue without the glow
            applyGlow()
        }
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        let context = VisualFrameContext(timeNanoseconds: frame.presentationTimeNanoseconds, frameDuration: frame.frameDuration,
                                         reduceFlashing: frame.reduceFlashing)
        let bands = audio.bands
        let drawn: Bool
        if let chain, glowActive {
            drawn = chain.encode(output: picture, commandBuffer: commandBuffer) { image in
                generator.encode(into: image, commandBuffer: commandBuffer, bands: bands, context: context)
            }
        } else {
            drawn = generator.encode(into: picture, commandBuffer: commandBuffer, bands: bands, context: context)
        }
        if !drawn { throw .frameSkipped }
    }
}
#endif
