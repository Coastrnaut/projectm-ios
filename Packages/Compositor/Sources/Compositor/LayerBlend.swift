// LayerBlend.swift — the plain-Swift reference of the CMP-004 blend modes (CMP-004-R2 to R5, R10;
// specs/099-cmp-004-blend-mode-library/contracts/blend-modes.md; ADR-0037). CPU only, builds on
// Linux. The compositor's `cmp_blend` shader follows the same steps in float; tests compare the two.
//
// Steps per pixel (linear premultiplied in and out):
//   1. straight colours Cb = cb / αb, Cs = cs / αs (0 when the alpha is 0);
//   2. clamp to 0…1 and sRGB-encode;
//   3. B(Eb, Es) per channel (the mode);
//   4. decode B to linear light;
//   5. co = cs·(1 − αb) + cb·(1 − αs) + αs·αb·D(B), αo = αs + αb·(1 − αs).
// Every expression is split into typed steps (the type checker on Linux and Xcode 26).
#if canImport(Foundation)
import Foundation
#endif

public enum LayerBlend {
    /// Linear premultiplied RGBA.
    public typealias Pixel = SIMD4<Double>

    /// sRGB encoding of a linear value in 0…1 (IEC 61966-2-1 piecewise curve).
    public static func encode(_ linear: Double) -> Double {
        let x: Double = min(max(linear, 0), 1)
        if x <= 0.0031308 { return x * 12.92 }
        let curved: Double = pow(x, 1.0 / 2.4)
        return 1.055 * curved - 0.055
    }

    /// sRGB decoding of an encoded value in 0…1.
    public static func decode(_ encoded: Double) -> Double {
        let y: Double = min(max(encoded, 0), 1)
        if y <= 0.04045 { return y / 12.92 }
        let base: Double = (y + 0.055) / 1.055
        return pow(base, 2.4)
    }

    /// B(Cb, Cs) on encoded straight values in 0…1 (step 3).
    public static func function(_ mode: LayerBlendMode, backdrop cb: Double, source cs: Double) -> Double {
        switch mode {
        case .normal:
            return cs
        case .add:
            let sum: Double = cb + cs
            return min(sum, 1)
        case .screen:
            return screen(cb, cs)
        case .multiply:
            return cb * cs
        case .overlay:
            // HardLight(Cs, Cb): the backdrop decides.
            if cb <= 0.5 {
                let doubled: Double = 2 * cb
                return doubled * cs
            }
            let lifted: Double = 2 * cb - 1
            return screen(cs, lifted)
        case .difference:
            let d: Double = cb - cs
            return Swift.abs(d)
        }
    }

    private static func screen(_ a: Double, _ b: Double) -> Double {
        let product: Double = a * b
        let sum: Double = a + b
        return sum - product
    }

    /// One premultiplied channel's straight value: c / α, or 0 for α = 0 (step 1).
    public static func straight(_ c: Double, alpha: Double) -> Double {
        alpha > 0 ? c / alpha : 0
    }

    /// Sanitizes one picture pixel as the compositor does: non-finite → 0, colour ≥ 0, alpha 0…1.
    public static func sanitized(_ p: Pixel) -> Pixel {
        var out = Pixel.zero
        for i in 0..<4 {
            let v: Double = p[i].isFinite ? p[i] : 0
            out[i] = i == 3 ? min(max(v, 0), 1) : max(v, 0)
        }
        return out
    }

    /// The composite of `source` (a layer picture pixel, sanitized here, then × `opacity`) over
    /// `backdrop` with `mode` (steps 1-5). Both linear premultiplied.
    public static func composite(_ mode: LayerBlendMode, backdrop: Pixel, source: Pixel, opacity: Double = 1) -> Pixel {
        let o: Double = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        let s: Pixel = sanitized(source) * o
        let b: Pixel = backdrop
        let alphaS: Double = s[3]
        let alphaB: Double = b[3]
        let both: Double = alphaS * alphaB
        let keepS: Double = 1 - alphaB
        let keepB: Double = 1 - alphaS
        var out = Pixel.zero
        for i in 0..<3 {
            let encodedB: Double = encode(straight(b[i], alpha: alphaB))
            let encodedS: Double = encode(straight(s[i], alpha: alphaS))
            let blended: Double = decode(function(mode, backdrop: encodedB, source: encodedS))
            let fromS: Double = s[i] * keepS
            let fromB: Double = b[i] * keepB
            let mixed: Double = both * blended
            out[i] = fromS + fromB + mixed
        }
        let alphaKept: Double = alphaB * keepB
        out[3] = alphaS + alphaKept
        return out
    }

    /// A straight sRGB-encoded colour (r, g, b in 0…1) with alpha as a linear premultiplied pixel.
    public static func premultipliedLinear(encoded r: Double, _ g: Double, _ b: Double, alpha: Double) -> Pixel {
        let lr: Double = decode(r) * alpha
        let lg: Double = decode(g) * alpha
        let lb: Double = decode(b) * alpha
        return Pixel(lr, lg, lb, alpha)
    }
}
