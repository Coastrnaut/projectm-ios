// CymaticHostSupport.swift — VIS-019-R10, R13: what the native host needs for the cymatic lines, kept out of
// NativeSpectrumHost.swift so the shared host gains only one-line hooks (style case, build, in-place update, accessibility
// value). Palette and Reduce Motion reach the generator through the host's existing noise-field paths.
import Metal
import VisualGenerators

extension NoiseFieldGenerator {
    /// The generator in its cymatic mode for the app's band range (pipeline built here, off the frame loop).
    nonisolated static func makeCymatic(device: MTLDevice, bands: CymaticBandRange, barCount: SpectrumBarCount) throws -> NoiseFieldGenerator {
        let generator = try NoiseFieldGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                configuration: .cymatic(CymaticSettings(bands: bands)))
        generator.barCount = barCount
        return generator
    }

    /// VIS-019: the cymatic mode with `bands`, in place from the next frame (from another noise-field mode it starts at
    /// rest; a range change keeps the blend going).
    func applyCymatic(bands: CymaticBandRange) {
        configuration = .cymatic(CymaticSettings(bands: bands), reduceMotion: configuration.reduceMotion,
                                 palette: configuration.palette)
    }
}
