// PremultipliedSRGB.swift — straight-alpha sRGB bytes → premultiplied sRGB-encoded bytes, for the photo
// layer's mipmapped `rgba8Unorm_srgb` texture (fix for the dark fringe on soft alpha edges).
//
// The photo layer used to upload straight-alpha texels, build mips from them and premultiply after
// sampling, so the colour of fully transparent texels (stored as black) bled into soft edges whenever a
// picture was drawn below 1:1 or at fractional offsets. Now each colour byte c with alpha a becomes
// encode(decode(c) · a): the sRGB encoding of the premultiplied linear colour. The texture stays
// `rgba8Unorm_srgb`, so the sampler (and the mip builder) decode it to premultiplied linear light, and
// filtering mixes premultiplied values, which is correct.
//
// Memory: 4 bytes per texel as before (a 4096 × 4096 photo is 64 MB plus about a third for mips), half
// of what `rgba16Float` would take. Precision: the sRGB curve spends its codes near zero, so the dark,
// low-alpha values of a soft edge keep fine steps (the first step is 1/(255 · 12.92) in linear light).
// Opaque texels (a = 255) are unchanged byte for byte (`table` row 255 is the identity), so opaque photos
// upload exactly the bytes they did before. Plain Swift: builds and is tested on every platform.
import Foundation

public enum PremultipliedSRGB {
    /// sRGB code → linear light (IEC 61966-2-1).
    public static func decode(_ code: Int) -> Double {
        let c: Double = Double(code) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear light → nearest sRGB code.
    public static func encode(_ linear: Double) -> UInt8 {
        let l: Double = Swift.min(Swift.max(linear, 0), 1)
        let c: Double = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
        return UInt8((c * 255).rounded())
    }

    /// `table[a << 8 | c]` = encode(decode(c) · a / 255); row 0 is all zero, row 255 the identity.
    public static let table: [UInt8] = {
        var t = [UInt8](repeating: 0, count: 256 * 256)
        let linear: [Double] = (0..<256).map { (code: Int) -> Double in decode(code) }
        for a in 1..<256 {
            let alpha: Double = Double(a) / 255
            for c in 0..<256 { t[a << 8 | c] = a == 255 ? UInt8(c) : encode(linear[c] * alpha) }
        }
        return t
    }()

    /// RGBA8 straight-alpha sRGB → RGBA8 premultiplied sRGB-encoded; alpha bytes are kept. An image with
    /// no transparency is returned as is.
    public static func pixels(_ image: DecodedImage) -> [UInt8] {
        guard image.hasAlpha else { return image.pixels }
        var out: [UInt8] = image.pixels
        let t: [UInt8] = table
        t.withUnsafeBufferPointer { (lut: UnsafeBufferPointer<UInt8>) in
            out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<UInt8>) in
                var i = 0
                let count: Int = p.count - p.count % 4
                while i < count {
                    let a: Int = Int(p[i + 3])
                    if a != 255 {
                        let row: Int = a << 8
                        p[i] = lut[row | Int(p[i])]
                        p[i + 1] = lut[row | Int(p[i + 1])]
                        p[i + 2] = lut[row | Int(p[i + 2])]
                    }
                    i += 4
                }
            }
        }
        return out
    }
}
