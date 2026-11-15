// MonotoneCubic.swift — SHOW-009 Cubic keyframe curve (specs/283-show-009-keyframe-easing; R3, R4; research D2).
//
// A piecewise cubic Hermite with Fritsch–Butland tangents (the PCHIP rule): at an inner key the slope is the weighted
// harmonic mean of the two secants, or zero when they differ in sign (a peak or valley) or either is flat. That keeps
// |m| ≤ 3·min(|Δ0|, |Δ1|), the Fritsch–Carlson condition, so every segment is monotone and never leaves the range of
// its two keys. Zero slopes at both ends give the standard ease-in-out 3u² − 2u³. Pure Swift (Linux).

enum MonotoneCubic {
    /// The slope at a key between a segment of length `h0` rising by `d0` and one of length `h1` rising by `d1`
    /// (value per unit of h).
    static func tangent(h0: Double, d0: Double, h1: Double, d1: Double) -> Double {
        guard h0 > 0, h1 > 0 else { return 0 }
        let s0: Double = d0 / h0
        let s1: Double = d1 / h1
        guard s0 * s1 > 0 else { return 0 }   // unlike signs or a flat secant: flat key, no overshoot
        let w1: Double = 2 * h1 + h0
        let w2: Double = h1 + 2 * h0
        return (w1 + w2) / (w1 / s0 + w2 / s1)
    }

    /// The Hermite value at `u` (0…1) from `y0` to `y1`, with end slopes already scaled to the segment (m·h), clamped to
    /// the segment's key range (the clamp only absorbs floating rounding).
    static func value(y0: Double, y1: Double, m0: Double, m1: Double, u: Double) -> Double {
        let u2: Double = u * u
        let u3: Double = u2 * u
        let h00: Double = 2 * u3 - 3 * u2 + 1
        let h10: Double = u3 - 2 * u2 + u
        let h01: Double = -2 * u3 + 3 * u2
        let h11: Double = u3 - u2
        let y: Double = h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
        return min(max(y, min(y0, y1)), max(y0, y1))
    }
}
