// PremultipliedLinear.swift — straight-alpha sRGB bytes → premultiplied linear-light half floats
// (MED-010-R4; research MED-010-D2; contracts/logo-overlay.md C2).
//
// The MED-001 photo layer filters straight-alpha texels and premultiplies after sampling, which pulls
// the colour of fully transparent texels (stored as black) into soft edges when a picture is scaled
// down: a dark fringe. The logo layer instead converts on the CPU before upload: each colour byte goes
// through the exact sRGB decoding curve to linear light and is multiplied by alpha, so every texel —
// and every mip level built from them — is already premultiplied, and bilinear or mip filtering is
// correct. Values are IEEE 754 half floats (`rgba16Float`), bit patterns built here so the conversion
// is plain Swift and testable on every platform (no `Float16` type needed).
import Foundation

public enum PremultipliedLinear {
    /// sRGB byte → linear light (IEC 61966-2-1), as a 256-entry table.
    public static let table: [Float] = (0..<256).map { (code: Int) -> Float in
        let c: Double = Double(code) / 255
        let linear: Double = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        return Float(linear)
    }

    public static func linear(_ srgbByte: UInt8) -> Float { table[Int(srgbByte)] }

    /// Float → half bits, round to nearest even; overflow → ±infinity, NaN → quiet NaN.
    public static func halfBits(_ value: Float) -> UInt16 {
        let bits: UInt32 = value.bitPattern
        let sign: UInt16 = UInt16((bits >> 16) & 0x8000)
        let exponent: Int = Int((bits >> 23) & 0xFF)
        let mantissa: UInt32 = bits & 0x7F_FFFF
        if exponent == 0xFF {
            return sign | 0x7C00 | (mantissa != 0 ? 0x0200 : 0)
        }
        let halfExponent: Int = exponent - 127 + 15
        if halfExponent >= 0x1F { return sign | 0x7C00 }
        if halfExponent <= 0 {
            // Subnormal half (or zero): shift the full mantissa (with its implicit 1) into place.
            if halfExponent < -10 { return sign }
            let full: UInt32 = mantissa | 0x80_0000
            let shift: UInt32 = UInt32(14 - halfExponent)
            var half: UInt32 = full >> shift
            let remainder: UInt32 = full & ((1 << shift) - 1)
            let halfway: UInt32 = 1 << (shift - 1)
            if remainder > halfway || (remainder == halfway && (half & 1) == 1) { half += 1 }
            return sign | UInt16(half)
        }
        var half: UInt32 = (UInt32(halfExponent) << 10) | (mantissa >> 13)
        let remainder: UInt32 = mantissa & 0x1FFF
        if remainder > 0x1000 || (remainder == 0x1000 && (half & 1) == 1) { half += 1 }   // may carry into the exponent (correct)
        return sign | UInt16(half)
    }

    /// Half bits → float (exact).
    public static func float(halfBits h: UInt16) -> Float {
        let sign: Float = (h & 0x8000) != 0 ? -1 : 1
        let exponent: Int = Int((h >> 10) & 0x1F)
        let mantissa: Float = Float(h & 0x3FF)
        if exponent == 0 { return sign * mantissa * 0x1p-24 }
        if exponent == 0x1F { return mantissa == 0 ? sign * Float.infinity : Float.nan }
        let scale: Float = Float(sign: .plus, exponent: exponent - 15, significand: 1)
        return sign * scale * (1 + mantissa / 1024)
    }

    /// RGBA half bits per pixel: (linear(r)·a, linear(g)·a, linear(b)·a, a); alpha 0 → all zero.
    public static func texels(_ image: DecodedImage) -> [UInt16] {
        let count: Int = image.width * image.height * 4
        guard image.pixels.count == count else { return [] }
        var out = [UInt16](repeating: 0, count: count)
        let alphaHalves: [UInt16] = (0..<256).map { (code: Int) -> UInt16 in halfBits(Float(code) / 255) }
        image.pixels.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) in
            out.withUnsafeMutableBufferPointer { (dst: inout UnsafeMutableBufferPointer<UInt16>) in
                var i = 0
                while i < count {
                    let a: UInt8 = src[i + 3]
                    if a != 0 {
                        let alpha: Float = Float(a) / 255
                        dst[i] = halfBits(table[Int(src[i])] * alpha)
                        dst[i + 1] = halfBits(table[Int(src[i + 1])] * alpha)
                        dst[i + 2] = halfBits(table[Int(src[i + 2])] * alpha)
                        dst[i + 3] = alphaHalves[Int(a)]
                    }
                    i += 4
                }
            }
        }
        return out
    }
}
