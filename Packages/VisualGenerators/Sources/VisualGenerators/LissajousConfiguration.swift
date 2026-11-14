// LissajousConfiguration.swift — the Lissajous scope's parameters (VIS-004-R3 to R5, R8, R9; data-model.md;
// research VIS-004-D2, D6).
//
// `init` clamps; properties set later are clamped by `clamped()`, which every consumer applies.
// Non-finite values take their defaults. The persistence half-life follows FX-009 Trails' ACC-012 caps
// (`persistenceHalfLife(enabled:clamp:)`), so every afterglow in the app obeys one rule.
import FlashSafety

/// How the stereo pair is plotted (VIS-004-R3). Stored as the raw value.
public enum LissajousMode: String, CaseIterable, Sendable {
    /// x = left, y = right: mono is the 45° diagonal (the roadmap's "X/Y"; the default).
    case xy
    /// The goniometer view, X/Y rotated 45°: x = (R − L)/√2, y = (L + R)/√2; mono is vertical.
    case midSide

    /// The plotted point of one stereo frame (samples already sanitized).
    @inline(__always)
    public func map(left: Double, right: Double) -> (x: Double, y: Double) {
        switch self {
        case .xy:
            return (left, right)
        case .midSide:
            let k: Double = 0.707_106_781_186_547_6   // 1/√2
            return ((right - left) * k, (left + right) * k)
        }
    }
}

public struct LissajousConfiguration: Sendable, Equatable {
    /// FX-009's default half-life, the persistence's nominal one (seconds).
    public static let nominalHalfLife = 0.2
    /// The longest half-life; ACC-012's intensity limit scales it (as FX-009 Trails).
    public static let longestHalfLife = 0.5
    /// The cap while Reduce flashing is effective (FX-009-D6).
    public static let reduceFlashingHalfLife = 0.25
    public static let thicknessRange: ClosedRange<Double> = 0.001...0.05
    public static let defaultLineThickness = 0.006

    public var mode: LissajousMode
    /// Seconds; 0 = persistence off. Clamped to 0…0.5 (non-finite or negative → 0).
    public var persistenceHalfLife: Double
    /// Fraction of the output's shorter side (at least 1 px drawn).
    public var lineThickness: Double
    public var palette: VisualPalette
    /// Premultiplied, linear.
    public var background: LinearColor

    public init(mode: LissajousMode = .xy, persistenceHalfLife: Double = 0,
                lineThickness: Double = LissajousConfiguration.defaultLineThickness,
                palette: VisualPalette = .spectrum, background: LinearColor = .opaqueBlack) {
        self.mode = mode
        self.persistenceHalfLife = persistenceHalfLife
        self.lineThickness = lineThickness
        self.palette = palette
        self.background = background
        self = clamped()
    }

    public var persistenceEnabled: Bool { persistenceHalfLife > 0 }

    /// Every value in its documented range.
    public func clamped() -> LissajousConfiguration {
        var c = self
        if persistenceHalfLife.isFinite, persistenceHalfLife > 0 {
            c.persistenceHalfLife = min(persistenceHalfLife, Self.longestHalfLife)
        } else {
            c.persistenceHalfLife = 0
        }
        if lineThickness.isFinite {
            c.lineThickness = min(max(lineThickness, Self.thicknessRange.lowerBound), Self.thicknessRange.upperBound)
        } else {
            c.lineThickness = Self.defaultLineThickness
        }
        c.background = background.clamped
        return c
    }

    /// The half-life the visual uses (VIS-004-R9): 0 when persistence is off; otherwise the nominal 0.2 s
    /// capped exactly like FX-009 Trails under ACC-012: at most intensity limit × 0.5 s when the profile caps
    /// intensity, at most 0.25 s while Reduce flashing is effective; a cap of 0 turns persistence off.
    public static func persistenceHalfLife(enabled: Bool, clamp: SafetyClamp) -> Double {
        guard enabled else { return 0 }
        var cap: Double = .infinity
        if clamp.capsIntensity { cap = longestHalfLife * clamp.limits.intensityLimit }
        if clamp.reducesFlashing { cap = min(cap, reduceFlashingHalfLife) }
        let h: Double = min(nominalHalfLife, cap)
        return h > 0 ? h : 0
    }
}
