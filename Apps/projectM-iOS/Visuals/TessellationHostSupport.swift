// TessellationHostSupport.swift — VIS-018-R10, R13: what the app needs for the tessellation, kept out of the shared files
// so they gain only one-line hooks (style case, build, in-place update, accessibility value, settings keys). Palette and
// Reduce Motion reach the generator through the host's existing noise-field paths; the tessellation's own palette choice
// is resolved in the generator (the colour-blind-safe palette wins).
import Foundation
import Metal
import VisualGenerators

extension NoiseFieldGenerator {
    /// The generator in its tessellation mode (pipeline built here, off the frame loop).
    nonisolated static func makeTessellation(device: MTLDevice, settings: TessellationSettings,
                                             barCount: SpectrumBarCount) throws -> NoiseFieldGenerator {
        let generator = try NoiseFieldGenerator(device: device, pixelFormat: .bgra8Unorm_srgb, configuration: .tessellation(settings))
        generator.barCount = barCount
        return generator
    }

    /// VIS-018: the tessellation with `settings`, in place from the next frame (from another noise-field mode the drive
    /// starts at rest; a settings change keeps it going).
    func applyTessellation(_ settings: TessellationSettings) {
        configuration = .tessellation(settings, reduceMotion: configuration.reduceMotion, palette: configuration.palette)
    }
}

extension TessellationSettings {
    /// "Hexagons, 6 tiles, 6-fold symmetry, Spectrum palette, Glow off" (VIS-018-R13).
    func accessibilityValue(glow: String) -> String {
        let parts: [String] = [tiling.title, "\(tiles) tiles", symmetryDescription, "\(palette.title) palette", glow]
        return parts.joined(separator: ", ")
    }
}

/// VIS-018-R10: the five `settings.tessellation.*` keys; out-of-range or wrongly typed values read as the defaults.
enum TessellationSettingsKeys {
    static let tiling = "settings.tessellation.tiling"
    static let tiles = "settings.tessellation.tiles"
    static let symmetry = "settings.tessellation.symmetry"
    static let mirror = "settings.tessellation.mirror"
    static let palette = "settings.tessellation.palette"
    static let all: [String] = [tiling, tiles, symmetry, mirror, palette]

    static func load(from defaults: UserDefaults) -> TessellationSettings {
        let tilingValue: TessellationTiling = defaults.string(forKey: tiling).flatMap(TessellationTiling.init(rawValue:)) ?? .defaultTiling
        let tileCount: Int = (defaults.object(forKey: tiles) as? Int).flatMap { (n: Int) -> Int? in
            TessellationSettings.tileRange.contains(n) ? n : nil
        } ?? TessellationSettings.defaultTiles
        let order: Int = (defaults.object(forKey: symmetry) as? Int).flatMap { (k: Int) -> Int? in
            TessellationSettings.symmetries.contains(k) ? k : nil
        } ?? TessellationSettings.defaultSymmetry
        let mirrored: Bool = defaults.object(forKey: mirror) as? Bool ?? false
        let colours: TessellationPalette = defaults.string(forKey: palette).flatMap(TessellationPalette.init(rawValue:)) ?? .defaultPalette
        return TessellationSettings(tiling: tilingValue, tiles: tileCount, symmetry: order, mirror: mirrored, palette: colours)
    }

    static func store(_ settings: TessellationSettings, in defaults: UserDefaults) {
        defaults.set(settings.tiling.rawValue, forKey: tiling)
        defaults.set(settings.tiles, forKey: tiles)
        defaults.set(settings.symmetry, forKey: symmetry)
        defaults.set(settings.mirror, forKey: mirror)
        defaults.set(settings.palette.rawValue, forKey: palette)
    }
}
