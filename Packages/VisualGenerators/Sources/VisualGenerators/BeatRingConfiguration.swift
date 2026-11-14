// BeatRingConfiguration.swift — the beat rings' parameters and their fixed curves and caps (VIS-006-R3 to R5,
// R7; data-model.md; research VIS-006-D3, D5).
//
// `init` clamps; properties set later are clamped by `clamped()`, which every consumer applies. Non-finite
// values take their defaults. Radii are fractions of half the output's shorter side.
import FlashSafety

public struct BeatRingConfiguration: Sendable, Equatable {
    public static let lifeRange: ClosedRange<Double> = 0.5...5
    public static let thicknessRange: ClosedRange<Double> = 0.001...0.05
    public static let defaultLife = 1.5
    public static let defaultLineThickness = 0.015

    /// r₀ and r₁: a ring's radius at birth and at the end of its life (fractions of half the shorter side).
    public static let startRadius = 0.05
    public static let endRadius = 0.95
    /// α_peak: a ring's brightest alpha (ACC-012: below full white).
    public static let peakAlpha = 0.8
    /// a_attack: the fade-in after birth, seconds (a ramp instead of a step).
    public static let attackSeconds = 0.05
    /// The most rings drawn at once (VIS-006-R4).
    public static let maximumRings = 16
    /// Flat segments per ring (VIS-006-R7).
    public static let segmentsPerRing = 64
    /// Palette colors cycled by ring sequence.
    public static let paletteColors = 16
    /// The shortest interval between accepted rings, seconds: normally (≤ 6 per second) and while the envelope
    /// limits rises (Reduce flashing or a stricter ACC-012 profile; ≤ 3 per second) (VIS-006-R5).
    public static let minimumInterval = 1.0 / 6
    public static let reducedInterval = 1.0 / 3

    /// L: seconds from birth to removal.
    public var life: Double
    /// Fraction of the output's shorter side (at least 1 px drawn).
    public var lineThickness: Double
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(life: Double = BeatRingConfiguration.defaultLife,
                lineThickness: Double = BeatRingConfiguration.defaultLineThickness,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.life = life
        self.lineThickness = lineThickness
        self.palette = palette
        self.background = background
        self = clamped()
    }

    /// Every value in its documented range.
    public func clamped() -> BeatRingConfiguration {
        var c = self
        c.life = Self.clamp(life, Self.lifeRange, Self.defaultLife)
        c.lineThickness = Self.clamp(lineThickness, Self.thicknessRange, Self.defaultLineThickness)
        c.background = background.clamped
        return c
    }

    /// The rate cap's interval for a frame drawn under `envelope` (VIS-006-R5).
    public static func minimumInterval(for envelope: FlashEnvelopeConfiguration) -> Double {
        envelope.riseRatePerSecond != nil ? reducedInterval : minimumInterval
    }

    /// r(a): eased out from r₀ to r₁ over the life (VIS-006-R3).
    public static func radius(age: Double, life: Double) -> Double {
        let p: Double = min(max(age / life, 0), 1)
        let q: Double = 1 - p
        return startRadius + (endRadius - startRadius) * (1 - q * q)
    }

    /// α(a): the attack ramp times a squared fade to 0 at the end of the life (VIS-006-R3).
    public static func alpha(age: Double, life: Double) -> Double {
        guard age >= 0, age < life else { return 0 }
        let q: Double = 1 - age / life
        let ramp: Double = min(1, age / attackSeconds)
        return peakAlpha * ramp * q * q
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
