// MotionFeedback.swift — FX-009 "Trails": the value, its decay model, the ACC-012 caps and the CPU reference of the
// blend (specs/130-fx-009-motion-feedback, contracts/motion-feedback.md, research FX-009-D1, D2, D4, D6; ADR-0051).
//
// Plain Swift (builds on Linux). The compositor's `cmp_trails` pass does the same per pixel on the GPU:
//   reset frame:   out = current (bit for bit, so the first frame after a scene change has no prior-scene content);
//   current non-finite (any channel NaN/±Inf): out = current (FX-002's output pass maps it to 0 and counts it);
//   otherwise:     out = max(current, decay × sanitize(previous)) per channel, premultiplied alpha included.
// Decay per frame = min(0.5^(Δt / halfLife), 0.99), Δt the frame clock's duration (0…0.1 s), so the fade per second
// is the same at any frame rate. The sensory safety profile caps the half-life (limit × 0.5 s; ≤ 0.25 s with Reduce
// flashing); a cap of 0 turns Trails off.
import FlashSafety
import Foundation

public struct MotionFeedback: Sendable, Equatable, Codable {
    /// User half-lives (seconds); an effective (capped) half-life may be shorter.
    public static let halfLifeRange: ClosedRange<Double> = 0.05...0.50
    public static let halfLifeStep = 0.01
    public static let defaultHalfLife = 0.20
    /// The longest half-life; ACC-012's intensity limit scales it.
    public static let longestHalfLife = 0.50
    /// The cap while Reduce flashing is effective (research FX-009-D6).
    public static let reduceFlashingHalfLife = 0.25
    /// The per-frame decay never exceeds this (binds only above 120 fps at the longest half-life, or on a 0 s frame).
    public static let maximumDecay = 0.99

    /// Trails off (the default; output bit-identical to before FX-009).
    public static let off = MotionFeedback()

    public var isEnabled: Bool
    public var halfLifeSeconds: Double

    public init(isEnabled: Bool = false, halfLifeSeconds: Double = MotionFeedback.defaultHalfLife) {
        self.isEnabled = isEnabled
        self.halfLifeSeconds = halfLifeSeconds
    }

    /// Enabled with a positive, finite half-life: the compositor runs the trails pass.
    public var isActive: Bool { isEnabled && halfLifeSeconds.isFinite && halfLifeSeconds > 0 }

    /// A user value made valid: NaN → the default half-life, out of range (±Inf) → the nearest bound.
    public var clamped: MotionFeedback {
        MotionFeedback(isEnabled: isEnabled, halfLifeSeconds: Self.clampHalfLife(halfLifeSeconds))
    }

    public static func clampHalfLife(_ value: Double) -> Double {
        if value.isNaN { return defaultHalfLife }
        return min(max(value, halfLifeRange.lowerBound), halfLifeRange.upperBound)
    }

    /// The per-frame decay for a frame lasting `frameDuration` seconds (research FX-009-D2): 0.5^(Δt / h), at most
    /// `maximumDecay`; 0 when inactive. A NaN or negative duration counts as 0 s.
    public func decay(frameDuration: Double) -> Double {
        guard isActive else { return 0 }
        let seconds: Double = frameDuration.isFinite && frameDuration > 0 ? frameDuration : 0
        let exponent: Double = seconds / halfLifeSeconds
        let raw: Double = Self.halfPower(exponent)
        return min(raw, Self.maximumDecay)
    }

    /// 0.5^x for x ≥ 0.
    static func halfPower(_ x: Double) -> Double {
        guard x > 0 else { return 1 }
        return pow(0.5, x)
    }

    /// What the compositors use under `clamp` (ACC-012; research FX-009-D6): the half-life at most limit × 0.5 s when
    /// the profile caps intensity and at most 0.25 s while Reduce flashing is effective; a cap of 0 turns Trails off.
    /// Standard with Reduce flashing off returns `self` unchanged.
    public func limited(by clamp: SafetyClamp) -> MotionFeedback {
        guard isEnabled else { return self }
        var cap: Double = .infinity
        if clamp.capsIntensity { cap = Self.longestHalfLife * clamp.limits.intensityLimit }
        if clamp.reducesFlashing { cap = min(cap, Self.reduceFlashingHalfLife) }
        guard cap < halfLifeSeconds else { return self }
        if !(cap > 0) { return MotionFeedback(isEnabled: false, halfLifeSeconds: halfLifeSeconds) }
        return MotionFeedback(isEnabled: true, halfLifeSeconds: cap)
    }

    /// The CPU reference of one `cmp_trails` pixel (linear premultiplied RGBA).
    public static func blend(current: SIMD4<Float>, previous: SIMD4<Float>, decay: Float, reset: Bool) -> SIMD4<Float> {
        if reset { return current }
        for c in 0..<4 where !current[c].isFinite { return current }
        var p: SIMD4<Float> = previous
        for c in 0..<4 {
            let v: Float = p[c].isFinite ? p[c] : 0
            p[c] = max(v, 0)
        }
        p.w = min(p.w, 1)
        let d: Float = min(max(decay.isFinite ? decay : 0, 0), 1)
        var out: SIMD4<Float> = current
        for c in 0..<4 { out[c] = max(current[c], d * p[c]) }
        return out
    }
}
