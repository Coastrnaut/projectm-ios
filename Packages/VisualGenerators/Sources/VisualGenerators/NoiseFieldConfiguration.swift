// NoiseFieldConfiguration.swift — the noise field's settings and constants (VIS-013-R3 to R5, R8; data-model.md;
// research VIS-013-D2, D3).
//
// `init` clamps; properties set later are clamped by `clamped()`, which every consumer applies. Non-finite values
// take their defaults. Pure Swift (every platform).

public struct NoiseFieldConfiguration: Sendable, Equatable {
    public static let frequencyRange: ClosedRange<Double> = 1...16
    public static let octaveRange: ClosedRange<Int> = 1...6
    public static let seedRange: ClosedRange<Int> = 0...65535
    public static let defaultFrequency = 4.0
    public static let defaultOctaves = 4
    public static let defaultSeed = 1301

    /// SHD-006's defaults, fixed (VIS-013 Clarifications Q2).
    public static let lacunarity: Float = 2.03
    public static let gain: Float = 0.5
    /// Domain warp: base cells plus up to `bandWarp` cells × the low group (× 0.5 under Reduce Motion).
    public static let baseWarp = 0.5
    public static let bandWarp = 1.0
    /// Brightness from the overall energy; never above `maximumBrightness` (ACC-012: below full white).
    public static let baseBrightness = 0.5
    public static let bandBrightness = 0.3
    public static let maximumBrightness = 0.8
    /// One-pole smoothing of warp and brightness, seconds of frame time; frame times clamp to 0…`maxFrameTime`.
    public static let smoothingTimeConstant = 0.25
    public static let maxFrameTime = 0.1
    /// Drift, cells per second along (1, 0.5); the most one frame advances.
    public static let driftSpeed = 0.12
    public static let maxDriftStep = 1.0
    /// ACC-001: drift and band warp depth factor.
    public static let reduceMotionScale = 0.5
    /// Palette colours the shader interpolates; the noise value maps to t = (n − 0.2) / 0.6.
    public static let paletteColors = 16
    public static let paletteLow: Float = 0.2
    public static let paletteSpan: Float = 0.6

    /// Noise cells across the shorter side.
    public var frequency: Double
    public var octaves: Int
    public var seed: Int
    public var reduceMotion: Bool
    public var palette: VisualPalette
    /// VIS-014: kaleidoscope wedges; 0 draws the plain field, 2…24 fold it (`KaleidoscopeFold`).
    public var wedges: Int
    /// VIS-015: tunnel rings per beat (`TunnelPace`); 0 draws the field or kaleidoscope, 0.5/1/2 the tunnel (wedges 0).
    public var tunnelPace: Double
    /// VIS-020: the spectrum waterfall (the bands' 60 s history); on forces `wedges` and `tunnelPace` to 0.
    public var waterfall: Bool

    public init(frequency: Double = NoiseFieldConfiguration.defaultFrequency, octaves: Int = NoiseFieldConfiguration.defaultOctaves,
                seed: Int = NoiseFieldConfiguration.defaultSeed, reduceMotion: Bool = false, palette: VisualPalette = .spectrum,
                wedges: Int = 0, tunnelPace: Double = 0, waterfall: Bool = false) {
        self.frequency = frequency
        self.octaves = octaves
        self.seed = seed
        self.reduceMotion = reduceMotion
        self.palette = palette
        self.wedges = wedges
        self.tunnelPace = tunnelPace
        self.waterfall = waterfall
        self = clamped()
    }

    /// VIS-014: the kaleidoscope, the default field (4 cells, 4 octaves, seed 1301) folded into `wedges` (2…24).
    public static func kaleidoscope(wedges: Int = KaleidoscopeFold.defaultWedges, reduceMotion: Bool = false,
                                    palette: VisualPalette = .spectrum) -> NoiseFieldConfiguration {
        let n: Int = min(max(wedges, KaleidoscopeFold.wedgeRange.lowerBound), KaleidoscopeFold.wedgeRange.upperBound)
        return NoiseFieldConfiguration(reduceMotion: reduceMotion, palette: palette, wedges: n)
    }

    /// VIS-015: the tunnel at `pace`, from the default field's seed (1301).
    public static func tunnel(pace: TunnelPace = .defaultPace, reduceMotion: Bool = false,
                              palette: VisualPalette = .spectrum) -> NoiseFieldConfiguration {
        NoiseFieldConfiguration(reduceMotion: reduceMotion, palette: palette, tunnelPace: pace.ringsPerBeat)
    }

    /// VIS-020: the spectrum waterfall from the default field's settings (only the palette and Reduce Motion apply).
    public static func waterfall(reduceMotion: Bool = false, palette: VisualPalette = .spectrum) -> NoiseFieldConfiguration {
        NoiseFieldConfiguration(reduceMotion: reduceMotion, palette: palette, waterfall: true)
    }

    /// VIS-015: the tunnel is on.
    public var isTunnel: Bool { tunnelPace > 0 }

    /// VIS-015: the tunnel's pace (nil when not a tunnel).
    public var pace: TunnelPace? { TunnelPace(ringsPerBeat: tunnelPace) }

    /// VIS-014: the fold is on.
    public var isKaleidoscope: Bool { wedges >= KaleidoscopeFold.wedgeRange.lowerBound }

    /// Every value in its documented range.
    public func clamped() -> NoiseFieldConfiguration {
        var c = self
        c.frequency = frequency.isFinite ? min(max(frequency, Self.frequencyRange.lowerBound), Self.frequencyRange.upperBound)
            : Self.defaultFrequency
        c.octaves = min(max(octaves, Self.octaveRange.lowerBound), Self.octaveRange.upperBound)
        c.seed = Self.seedRange.contains(seed) ? seed : Self.defaultSeed
        c.wedges = wedges < KaleidoscopeFold.wedgeRange.lowerBound ? 0 : min(wedges, KaleidoscopeFold.wedgeRange.upperBound)
        c.tunnelPace = TunnelPace(ringsPerBeat: tunnelPace)?.ringsPerBeat ?? 0   // VIS-015: 0, 0.5, 1 or 2
        if c.tunnelPace > 0 { c.wedges = 0 }
        if c.waterfall { c.wedges = 0; c.tunnelPace = 0 }   // VIS-020
        return c
    }

    /// Drift speed in effect (cells/s).
    public var effectiveDriftSpeed: Double { reduceMotion ? Self.driftSpeed * Self.reduceMotionScale : Self.driftSpeed }
    /// Band warp depth in effect (cells at a full low group).
    public var effectiveBandWarp: Double { reduceMotion ? Self.bandWarp * Self.reduceMotionScale : Self.bandWarp }

    /// The palette position of noise value `n`.
    @inlinable
    public static func paletteT(_ n: Float) -> Float { min(max((n - paletteLow) / paletteSpan, 0), 1) }
}
