// SignedDistanceHostSupport.swift — VIS-017-R8, R11: what the native host needs for the SDF shapes, kept out of
// NativeSpectrumHost.swift so the shared host gains only one-line hooks (style case, build, in-place update, accessibility
// value). Palette and Reduce Motion reach the generator through the host's existing noise-field paths.
import Metal
import VisualGenerators

extension NoiseFieldGenerator {
    /// The generator in its SDF mode for the app's quality (pipeline built here, off the frame loop).
    nonisolated static func makeSignedDistance(device: MTLDevice, quality: SignedDistanceQuality,
                                               barCount: SpectrumBarCount) throws -> NoiseFieldGenerator {
        let generator = try NoiseFieldGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                configuration: .signedDistance(SignedDistanceSettings(quality: quality)))
        generator.barCount = barCount
        return generator
    }

    /// VIS-017: the SDF mode at `quality`, in place from the next frame (from another noise-field mode the pose starts at
    /// rest; a quality change keeps it turning).
    func applySignedDistance(quality: SignedDistanceQuality) {
        configuration = .signedDistance(SignedDistanceSettings(quality: quality), reduceMotion: configuration.reduceMotion,
                                        palette: configuration.palette)
    }
}
