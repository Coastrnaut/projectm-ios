// TextRendering.swift — a drawn message (MED-009-R8, S1, S5; data-model "TextRendering"; research
// MED-009-D2, D3). Plain Swift, every platform.
//
// `pixels` are RGBA, 8 bits, premultiplied, sRGB-encoded, row 0 at the top, exactly what the
// rasterizer drew. `checksum` is FNV-1a 64 over the picture size, the canvas rectangle and the
// pixels: equal renderings have equal checksums, and any changed byte changes it (with
// overwhelming likelihood). `linearHalfPixels()` is the layer picture's format (CMP-001-R2): linear
// light, premultiplied, IEEE half floats.
import Foundation

public struct TextPixelBounds: Equatable, Sendable {
    public let minX: Int
    public let minY: Int
    public let maxX: Int
    public let maxY: Int

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

public struct TextRendering: Equatable, Sendable {
    public let pictureWidth: Int
    public let pictureHeight: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(pictureWidth: Int, pictureHeight: Int, x: Int, y: Int, width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "RGBA pixels")
        self.pictureWidth = pictureWidth
        self.pictureHeight = pictureHeight
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The smallest rectangle (canvas pixels, inclusive) whose pixels have alpha > 0; nil when blank.
    public var inkBounds: TextPixelBounds? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        pixels.withUnsafeBufferPointer { (p: UnsafeBufferPointer<UInt8>) in
            for row in 0..<height {
                let base = row * width * 4
                for column in 0..<width where p[base + column * 4 + 3] != 0 {
                    if column < minX { minX = column }
                    if column > maxX { maxX = column }
                    if row < minY { minY = row }
                    if row > maxY { maxY = row }
                }
            }
        }
        return maxX < 0 ? nil : TextPixelBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// FNV-1a 64 over the sizes, the rectangle and the pixels.
    public var checksum: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for value in [pictureWidth, pictureHeight, x, y, width, height] {
            var v = UInt64(truncatingIfNeeded: value)
            for _ in 0..<8 {
                hash = (hash ^ (v & 0xff)) &* prime
                v >>= 8
            }
        }
        pixels.withUnsafeBufferPointer { (p: UnsafeBufferPointer<UInt8>) in
            for byte in p { hash = (hash ^ UInt64(byte)) &* prime }
        }
        return hash
    }

    /// 16 hex digits.
    public var checksumText: String {
        let hex = String(checksum, radix: 16)
        return String(repeating: "0", count: max(16 - hex.count, 0)) + hex
    }

    /// The pixels as linear premultiplied half floats (bit patterns), RGBA.
    public func linearHalfPixels() -> [UInt16] {
        var out = [UInt16](repeating: 0, count: pixels.count)
        let table = SRGBTable.linear
        pixels.withUnsafeBufferPointer { (p: UnsafeBufferPointer<UInt8>) in
            out.withUnsafeMutableBufferPointer { (o: inout UnsafeMutableBufferPointer<UInt16>) in
                var i = 0
                while i < p.count {
                    let a = p[i + 3]
                    if a != 0 {
                        let alpha = Float(a) / 255
                        for c in 0..<3 {
                            // Un-premultiply to the sRGB code, to linear, premultiply again.
                            let straight = min((Float(p[i + c]) / alpha).rounded(), 255)
                            o[i + c] = HalfFloat.bits(table[Int(straight)] * alpha)
                        }
                        o[i + 3] = HalfFloat.bits(alpha)
                    }
                    i += 4
                }
            }
        }
        return out
    }
}

/// sRGB code (0…255) → linear light.
enum SRGBTable {
    static let linear: [Float] = (0...255).map { (code: Int) -> Float in
        let c = Double(code) / 255
        return Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
    }
}

/// IEEE 754 binary16 from Float (round to nearest even), plain Swift (no `Float16`, which is not
/// available on every host).
public enum HalfFloat {
    public static func bits(_ value: Float) -> UInt16 {
        let f = value.bitPattern
        let sign = UInt16((f >> 16) & 0x8000)
        let exponent = Int((f >> 23) & 0xff)
        var mantissa = f & 0x7f_ffff
        if exponent == 0xff { return sign | 0x7c00 | (mantissa != 0 ? 0x200 : 0) }   // inf / NaN
        let e = exponent - 127 + 15
        if e >= 0x1f { return sign | 0x7c00 }   // overflow → inf
        if e <= 0 {
            if e < -10 { return sign }   // underflow → 0
            mantissa |= 0x80_0000
            let shift = UInt32(14 - e)
            var half = mantissa >> shift
            let remainder = mantissa & ((1 << shift) - 1), halfway = UInt32(1) << (shift - 1)
            if remainder > halfway || (remainder == halfway && (half & 1) == 1) { half += 1 }
            return sign | UInt16(half)
        }
        var half = UInt32(e) << 10 | (mantissa >> 13)
        let remainder = mantissa & 0x1fff
        if remainder > 0x1000 || (remainder == 0x1000 && (half & 1) == 1) { half += 1 }   // may carry into the exponent: correct
        return sign | UInt16(half)
    }

    public static func float(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = Int((bits >> 10) & 0x1f)
        let mantissa = UInt32(bits & 0x3ff)
        if exponent == 0 {
            let v = Float(mantissa) / 1024 / 16384   // 2^-14 × m/1024
            return sign != 0 ? -v : v
        }
        if exponent == 0x1f { return Float(bitPattern: sign | 0x7f80_0000 | (mantissa << 13)) }
        return Float(bitPattern: sign | UInt32(exponent - 15 + 127) << 23 | (mantissa << 13))
    }
}
