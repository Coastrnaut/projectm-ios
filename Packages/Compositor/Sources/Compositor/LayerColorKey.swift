// LayerColorKey.swift — a per-layer colour key: colours near a chosen key colour made transparent (CMP-010-R1 to R5;
// research CMP-010-D1, D2; specs/230-cmp-010-color-key/contracts/color-key.md C1).
//
// CPU only (builds on Linux). The key reads the layer's own colour at the shown pixel (premultiplied linear, as the
// compositor holds it), before opacity:
//
//     straight c = a > 0 ? rgb / a : 0, each clamped to 0…1;  c′ = sRGB encode (as `LayerBlend.encode`)
//     Y′ = 0.2126·r′ + 0.7152·g′ + 0.0722·b′;  Cb = (b′ − Y′) / 1.8556;  Cr = (r′ − Y′) / 1.5748   (Rec. 709)
//     d = distance in the (Cb, Cr) plane to the key colour's chroma (the key is stored as displayed sRGB)
//     k = 1 for d ≤ tolerance; beyond, k = max(0, 1 − (d − tolerance) / feather) (0 if feather 0)
//     keep = 1 − k
//
// `keep` multiplies the premultiplied colour and alpha (with the masks' coverage and the luma key's keep), so a kept
// pixel's colour and alpha are unchanged. `CompositorShaders` runs the same steps (`cmp_color_keep`) from the same
// numbers (`MaskBlock.chroma`). Spill suppression is out of scope (spec Clarifications). Every intermediate is a
// named, typed value (type-checker budgets).
import Foundation

/// A layer's colour key (CMP-010). nil in `LayerCompositeSettings.colorKey` draws without one.
public struct LayerColorKey: Sendable, Hashable {
    public static let componentLimits: ClosedRange<Double> = 0...1
    public static let toleranceLimits: ClosedRange<Double> = 0...1
    public static let featherLimits: ClosedRange<Double> = 0...0.5
    /// Rec. 709 colour-difference scales: Cb = (B′ − Y′) / 1.8556, Cr = (R′ − Y′) / 1.5748.
    public static let blueScale: Double = 1.8556
    public static let redScale: Double = 1.5748

    /// The key colour as displayed (sRGB-encoded), each 0…1.
    public let red: Double
    public let green: Double
    public let blue: Double
    /// 0…1: the chroma distance keyed out fully.
    public let tolerance: Double
    /// 0…0.5: the width of the linear ramp beyond the tolerance (0: a hard cut).
    public let feather: Double

    /// Clamps each value; non-finite values read `greenKey`'s; −0 is stored as 0.
    public init(red: Double, green: Double, blue: Double, tolerance: Double = 0.2, feather: Double = 0.1) {
        self.red = LayerLumaKey.clamp(red, Self.componentLimits, 0)
        self.green = LayerLumaKey.clamp(green, Self.componentLimits, 1)
        self.blue = LayerLumaKey.clamp(blue, Self.componentLimits, 0)
        self.tolerance = LayerLumaKey.clamp(tolerance, Self.toleranceLimits, 0.2)
        self.feather = LayerLumaKey.clamp(feather, Self.featherLimits, 0.1)
    }

    /// The inspector's default: pure green, tolerance 0.2, feather 0.1.
    public static let greenKey = LayerColorKey(red: 0, green: 1, blue: 0, tolerance: 0.2, feather: 0.1)

    /// (Cb, Cr) of displayed (sRGB-encoded) values, each clamped to 0…1.
    public static func chroma(encodedRed r: Double, green g: Double, blue b: Double) -> (cb: Double, cr: Double) {
        let rr: Double = min(max(r, 0), 1)
        let gg: Double = min(max(g, 0), 1)
        let bb: Double = min(max(b, 0), 1)
        let wr: Double = LayerLumaKey.weights.red * rr
        let wg: Double = LayerLumaKey.weights.green * gg
        let wb: Double = LayerLumaKey.weights.blue * bb
        let y: Double = wr + wg + wb
        let cb: Double = (bb - y) / blueScale
        let cr: Double = (rr - y) / redScale
        return (cb, cr)
    }

    /// (Cb, Cr) of a premultiplied linear pixel (contract C1 steps 1-3). Non-finite channels read 0; alpha ≤ 0 gives (0, 0).
    public static func chroma(red: Double, green: Double, blue: Double, alpha: Double) -> (cb: Double, cr: Double) {
        let a: Double = alpha.isFinite ? min(max(alpha, 0), 1) : 0
        guard a > 0 else { return (0, 0) }
        let r: Double = encodedStraight(red, alpha: a)
        let g: Double = encodedStraight(green, alpha: a)
        let b: Double = encodedStraight(blue, alpha: a)
        return chroma(encodedRed: r, green: g, blue: b)
    }

    private static func encodedStraight(_ c: Double, alpha: Double) -> Double {
        let premultiplied: Double = c.isFinite ? max(c, 0) : 0
        let straight: Double = min(premultiplied / alpha, 1)
        return LayerBlend.encode(straight)
    }

    /// The key colour's (Cb, Cr) (contract C1 step 4).
    public var keyChroma: (cb: Double, cr: Double) { Self.chroma(encodedRed: red, green: green, blue: blue) }

    /// The chroma distance of a premultiplied linear pixel to the key colour (contract C1 step 5).
    public func distance(red r: Double, green g: Double, blue b: Double, alpha a: Double) -> Double {
        let p: (cb: Double, cr: Double) = Self.chroma(red: r, green: g, blue: b, alpha: a)
        let k: (cb: Double, cr: Double) = keyChroma
        let dcb: Double = p.cb - k.cb
        let dcr: Double = p.cr - k.cr
        return (dcb * dcb + dcr * dcr).squareRoot()
    }

    /// The keyed amount: 1 within the tolerance, a linear ramp to 0 over `feather` beyond it.
    public func keyed(distance d: Double) -> Double {
        if d <= tolerance { return 1 }
        guard feather > 0 else { return 0 }
        let k: Double = 1 - (d - tolerance) / feather
        return max(k, 0)
    }

    /// The factor that multiplies the pixel (contract C1 steps 6-7).
    public func keep(distance d: Double) -> Double { 1 - keyed(distance: d) }

    /// The factor for a premultiplied linear pixel.
    public func keep(red: Double, green: Double, blue: Double, alpha: Double) -> Double {
        keep(distance: distance(red: red, green: green, blue: blue, alpha: alpha))
    }
}
