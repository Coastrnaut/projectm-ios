// StarfieldConfiguration.swift — the starfield's parameters, speed choices and constants (VIS-016-R2, R5, R6;
// specs/287-vis-016-starfield-flight, data-model.md, contract S1).
//
// Depth z runs from the far plane (1) to the near plane (0.05); x and y are lateral, −2…2. `init` clamps; properties
// set later are clamped by `clamped()`, which every consumer applies. Pure Swift (every platform).

/// How fast the flight goes (VIS-016-R6); stored by the app as the raw value.
public enum StarfieldSpeed: String, CaseIterable, Sendable {
    case slow
    case medium
    case fast

    public static let defaultSpeed = StarfieldSpeed.medium

    /// Depth units per second before the bass boost.
    public var depthPerSecond: Double {
        switch self {
        case .slow: 0.1
        case .medium: 0.2
        case .fast: 0.4
        }
    }

    public var title: String {
        switch self {
        case .slow: "Slow"
        case .medium: "Medium"
        case .fast: "Fast"
        }
    }
}

public struct StarfieldConfiguration: Sendable, Equatable {
    /// VIS-016-R2: the fixed pool (and the density limit) on every device class and power profile.
    public static let capacity = 2000
    public static let densityRange: ClosedRange<Int> = 1...2000
    /// The app's stepper: 100…2000 in steps of 100.
    public static let settingsDensityRange: ClosedRange<Int> = 100...2000
    public static let settingsDensityStep = 100
    public static let defaultDensity = 600
    /// "VIS-016" in hex-speak.
    public static let defaultSeed: UInt64 = 0x5EED_0016

    /// VIS-008's fixed step and the most steps one advance runs.
    public static let stepsPerSecond = 240
    public static let maximumStepsPerAdvance = 240
    /// Depth planes and the lateral spread (x, y uniform in −spread…spread).
    public static let near = 0.05
    public static let far = 1.0
    public static let lateralSpread = 2.0
    /// Screen offset = (x, −y) · focal · R / z (R = half the shorter side): the far plane spans ±1 R.
    public static let focal = 0.5
    /// Bass boost: speed × (1 + bassBoost · low), low smoothed with τ = bassTimeConstant (s); capped at maximumSpeed.
    public static let bassBoost = 0.5
    public static let bassTimeConstant = 0.2
    public static let maximumSpeed = 0.6
    public static let reduceMotionScale = 0.5
    /// Side = baseSide · R / z, at least minimumSidePixels and at most maximumSide · R.
    public static let baseSide = 0.004
    public static let maximumSide = 0.04
    public static let minimumSidePixels = 1.0
    /// Alpha = min(brightness / z, maximumAlpha) × fades (ACC-012: below 0.8).
    public static let brightness = 0.12
    public static let maximumAlpha = 0.8
    public static let fadeInDepth = 0.15
    public static let fadeOutDepth = 0.05
    /// VIS-016-R7: the frame's mean light (relative luminance × coverage) never exceeds this.
    public static let lightBound = 0.05
    public static let paletteColors = 16
    /// Share of white in a star's colour (the rest is the palette's).
    public static let whiteShare: Float = 0.5

    /// Requested stars; the first `activeCount` of the pool are drawn.
    public var density: Int
    public var speed: StarfieldSpeed
    /// Restored at every reset; a change resets the stars.
    public var seed: UInt64
    /// ACC-001: half speed.
    public var reduceMotion: Bool
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(density: Int = StarfieldConfiguration.defaultDensity, speed: StarfieldSpeed = .defaultSpeed,
                seed: UInt64 = StarfieldConfiguration.defaultSeed, reduceMotion: Bool = false,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.density = density
        self.speed = speed
        self.seed = seed
        self.reduceMotion = reduceMotion
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// VIS-016-R2: the density limit; any request is clamped to 1…2000.
    public static func activeCount(requested: Int) -> Int {
        min(max(requested, densityRange.lowerBound), densityRange.upperBound)
    }

    /// Stars drawn.
    public var activeCount: Int { Self.activeCount(requested: density) }

    /// Every value in its documented range.
    public func clamped() -> StarfieldConfiguration {
        var c = self
        c.density = Self.activeCount(requested: density)
        c.background = background.clamped
        return c
    }

    /// The flight speed (depth/s) for a smoothed low group `bass` (0…1; not finite → 0): boosted, capped, then halved
    /// with Reduce Motion.
    public func effectiveSpeed(bass: Double) -> Double {
        let b: Double = bass.isFinite ? min(max(bass, 0), 1) : 0
        let boosted: Double = min(speed.depthPerSecond * (1 + Self.bassBoost * b), Self.maximumSpeed)
        return reduceMotion ? boosted * Self.reduceMotionScale : boosted
    }
}
