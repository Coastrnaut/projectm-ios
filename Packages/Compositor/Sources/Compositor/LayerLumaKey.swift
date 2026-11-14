// LayerLumaKey.swift — a per-layer luma key: a luminance range made transparent (CMP-009-R1 to R5; research
// CMP-009-D1, D2; specs/220-cmp-009-luma-key/contracts/luma-key.md K1).
//
// CPU only (builds on Linux). The key reads the layer's own colour at the shown pixel (premultiplied linear, as the
// compositor holds it), before opacity:
//
//     straight c = a > 0 ? rgb / a : 0, each clamped to 0…1;  c′ = sRGB encode (as `LayerBlend.encode`)
//     Y′ = 0.2126·r′ + 0.7152·g′ + 0.0722·b′                    (Rec. 709 luma of the displayed values)
//     k = 1 for low ≤ Y′ ≤ high; outside, k = max(0, 1 − d / softness) (d: distance to the nearer end; 0 if softness 0)
//     keep = inverted ? k : 1 − k
//
// `keep` multiplies the premultiplied colour and alpha (with CMP-007's shape coverage and CMP-008's gradient alpha),
// so a kept pixel's colour and alpha are unchanged. `CompositorShaders` runs the same steps (`cmp_luma_keep`) from
// the same numbers (`MaskBlock.luma`). Every intermediate is a named, typed value (type-checker budgets).
import Foundation

/// A layer's luma key (CMP-009). nil in `LayerCompositeSettings.lumaKey` draws without one.
public struct LayerLumaKey: Sendable, Hashable {
    public static let rangeLimits: ClosedRange<Double> = 0...1
    public static let softnessLimits: ClosedRange<Double> = 0...0.5
    /// Rec. 709 luma weights.
    public static let weights: (red: Double, green: Double, blue: Double) = (0.2126, 0.7152, 0.0722)

    /// 0…1, at most `high`.
    public let low: Double
    /// 0…1, at least `low`.
    public let high: Double
    /// 0…0.5: the width of the linear ramp on each side of the range (0: a hard cut).
    public let softness: Double
    /// false: the range is made transparent; true: only the range is kept.
    public let inverted: Bool

    /// Clamps each value (non-finite: low 0, high 0.1, softness 0; −0 is stored as 0) and swaps a reversed range.
    public init(low: Double, high: Double, softness: Double = 0, inverted: Bool = false) {
        let a: Double = Self.clamp(low, Self.rangeLimits, 0)
        let b: Double = Self.clamp(high, Self.rangeLimits, 0.1)
        self.low = min(a, b)
        self.high = max(a, b)
        self.softness = Self.clamp(softness, Self.softnessLimits, 0)
        self.inverted = inverted
    }

    /// The inspector's default: key out the darkest tenth with a small ramp.
    public static let blackKey = LayerLumaKey(low: 0, high: 0.1, softness: 0.05)

    /// Rec. 709 luma (0…1) of the displayed straight colour of a premultiplied linear pixel (contract K1 steps 1-3).
    /// Non-finite channels read 0; alpha ≤ 0 gives 0.
    public static func luma(red: Double, green: Double, blue: Double, alpha: Double) -> Double {
        let a: Double = alpha.isFinite ? min(max(alpha, 0), 1) : 0
        guard a > 0 else { return 0 }
        let r: Double = encodedStraight(red, alpha: a)
        let g: Double = encodedStraight(green, alpha: a)
        let b: Double = encodedStraight(blue, alpha: a)
        let wr: Double = weights.red * r
        let wg: Double = weights.green * g
        let wb: Double = weights.blue * b
        return wr + wg + wb
    }

    private static func encodedStraight(_ c: Double, alpha: Double) -> Double {
        let premultiplied: Double = c.isFinite ? max(c, 0) : 0
        let straight: Double = min(premultiplied / alpha, 1)
        return LayerBlend.encode(straight)
    }

    /// The keyed amount: 1 inside the range, a linear ramp to 0 over `softness` outside it.
    public func keyed(luma y: Double) -> Double {
        if y >= low && y <= high { return 1 }
        let distance: Double = y < low ? low - y : y - high
        guard softness > 0 else { return 0 }
        let k: Double = 1 - distance / softness
        return max(k, 0)
    }

    /// The factor that multiplies the pixel (contract K1 steps 4-5).
    public func keep(luma y: Double) -> Double {
        let k: Double = keyed(luma: y)
        return inverted ? k : 1 - k
    }

    /// The factor for a premultiplied linear pixel.
    public func keep(red: Double, green: Double, blue: Double, alpha: Double) -> Double {
        keep(luma: Self.luma(red: red, green: green, blue: blue, alpha: alpha))
    }

    static func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        let c: Double = min(max(v, range.lowerBound), range.upperBound)
        return c == 0 ? 0 : c
    }
}
