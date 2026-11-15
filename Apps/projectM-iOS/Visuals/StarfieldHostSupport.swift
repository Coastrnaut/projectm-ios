// StarfieldHostSupport.swift — VIS-016-R8, R11: what the native host needs for the starfield, kept out of
// NativeSpectrumHost.swift so the shared host gains only one-line hooks (style case, build, in-place update, palette,
// Reduce Motion, accessibility value).
import Metal
import VisualGenerators

extension StarfieldGenerator {
    /// The generator for the app's choices (pipeline built here, off the frame loop).
    nonisolated static func make(device: MTLDevice, speed: StarfieldSpeed, density: Int,
                                 barCount: SpectrumBarCount) throws -> StarfieldGenerator {
        let generator = try StarfieldGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                               configuration: StarfieldConfiguration(density: density, speed: speed))
        generator.barCount = barCount
        return generator
    }

    /// VIS-016: speed and density in place, from the next frame (no restart: the stars keep flying).
    func apply(speed: StarfieldSpeed, density: Int) {
        var configuration = self.configuration
        configuration.speed = speed
        configuration.density = density
        self.configuration = configuration
    }

    /// ACC-003-R13: the palette, from the next frame.
    func apply(palette: VisualPalette) {
        guard configuration.palette != palette else { return }
        var configuration = self.configuration
        configuration.palette = palette
        self.configuration = configuration
    }

    /// ACC-001: half speed, from the next step.
    func apply(reduceMotion: Bool) {
        guard configuration.reduceMotion != reduceMotion else { return }
        var configuration = self.configuration
        configuration.reduceMotion = reduceMotion
        self.configuration = configuration
    }
}

enum StarfieldDescription {
    /// VIS-016-R11: "Medium speed, 600 stars, Glow off" (the density as the model draws it, capped).
    static func accessibilityValue(speed: StarfieldSpeed, density: Int, glow: String) -> String {
        "\(speed.title) speed, \(StarfieldConfiguration.activeCount(requested: density)) stars, \(glow)"
    }
}
