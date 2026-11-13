// FrameColorConversion.swift — REC-001-R7 (research REC-001-D3). Plain Swift: builds on Linux.
//
// Linear premultiplied half floats → clamp → (unpremultiply for straight alpha) → sRGB transfer →
// round to 8 bits. 8-bit sources are already display-encoded: swizzle, flip, alpha 255.
import Foundation

public enum FrameColorConversion {
    /// IEEE 754 binary16 → Float, by bits (no `Float16`, which some hosts lack).
    public static func halfToFloat(_ bits: UInt16) -> Float {
        let sign: UInt32 = UInt32(bits & 0x8000) << 16
        let exponent = Int((bits >> 10) & 0x1F)
        let mantissa = UInt32(bits & 0x3FF)
        if exponent == 0 {
            // Zero or subnormal: mantissa × 2^-24.
            let value = Float(mantissa) * Float(sign: .plus, exponent: -24, significand: 1)
            return sign != 0 ? -value : value
        }
        if exponent == 31 {
            return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))   // inf or NaN
        }
        return Float(bitPattern: sign | (UInt32(exponent - 15 + 127) << 23) | (mantissa << 13))
    }

    /// The sRGB transfer function for a linear value, clamped to 0…1 (NaN → 0).
    public static func linearToSRGB(_ linear: Float) -> Float {
        let c = clamp01(linear)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * powf(c, 1 / 2.4) - 0.055
    }

    /// Nearest 8-bit value of an encoded 0…1 value (clamped; NaN → 0).
    public static func encode8(_ encoded: Float) -> UInt8 {
        UInt8((clamp01(encoded) * 255).rounded())
    }

    static func clamp01(_ v: Float) -> Float {
        guard v == v else { return 0 }   // NaN
        return min(max(v, 0), 1)
    }

    /// The frame as 8-bit sRGB per `policy` (REC-001-R5 to R7).
    public static func rgba8(_ pixels: CapturedPixels, policy: FrameAlphaPolicy) -> RGBA8Image {
        let w = pixels.width, h = pixels.height
        var out = [UInt8](repeating: 255, count: w * h * 4)
        switch pixels.layout {
        case .linearPremultipliedHalfRGBA(let half):
            var anyCoverage = false
            if policy == .preserveCoverage {
                for i in stride(from: 0, to: half.count, by: 4) {
                    let a = clamp01(halfToFloat(half[i + 3]))
                    let a8 = encode8(a)
                    out[i + 3] = a8
                    if a8 < 255 { anyCoverage = true }
                    if a8 == 0 {
                        out[i] = 0; out[i + 1] = 0; out[i + 2] = 0
                        continue
                    }
                    for c in 0..<3 {
                        let premultiplied = min(clamp01(halfToFloat(half[i + c])), a)
                        out[i + c] = encode8(linearToSRGB(min(premultiplied / a, 1)))
                    }
                }
                if anyCoverage { return RGBA8Image(width: w, height: h, rgba: out, hasAlpha: true) }
                // No coverage below 1: the opaque rule gives the same color (rgb / 1) without alpha.
                for i in stride(from: 3, to: out.count, by: 4) { out[i] = 255 }
                return RGBA8Image(width: w, height: h, rgba: out, hasAlpha: false)
            }
            for i in stride(from: 0, to: half.count, by: 4) {
                let a = clamp01(halfToFloat(half[i + 3]))
                for c in 0..<3 {
                    out[i + c] = encode8(linearToSRGB(min(clamp01(halfToFloat(half[i + c])), a)))
                }
            }
            return RGBA8Image(width: w, height: h, rgba: out, hasAlpha: false)
        case .sRGBBGRA8TopDown(let bgra):
            for i in stride(from: 0, to: bgra.count, by: 4) {
                out[i] = bgra[i + 2]; out[i + 1] = bgra[i + 1]; out[i + 2] = bgra[i]
            }
            return RGBA8Image(width: w, height: h, rgba: out, hasAlpha: false)
        case .sRGBRGBA8BottomUp(let rgba):
            let row = w * 4
            for y in 0..<h {
                let src = (h - 1 - y) * row, dst = y * row
                for x in stride(from: 0, to: row, by: 4) {
                    out[dst + x] = rgba[src + x]; out[dst + x + 1] = rgba[src + x + 1]; out[dst + x + 2] = rgba[src + x + 2]
                }
            }
            return RGBA8Image(width: w, height: h, rgba: out, hasAlpha: false)
        }
    }
}
