// CapturedPixelSample.swift — UIX-012-R6 (specs/300-uix-012-touch-color-sampler, contract C2; research
// UIX-012-D4). Plain Swift: builds on Linux.
//
// One pixel of a REC-001 capture as straight linear RGBA in 0…1, with the same clamps as the PNG path:
// half floats are clamped, a pixel without coverage is black, colour = min(c, a) / a; 8-bit sources are
// sRGB-encoded and opaque, decoded with the inverse sRGB transfer (bottom-up rows flipped).
import Foundation

/// A sampled colour: straight (not premultiplied) linear RGBA, each component 0…1.
public struct SampledColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func unit(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }
        self.red = unit(red)
        self.green = unit(green)
        self.blue = unit(blue)
        self.alpha = unit(alpha)
    }

    /// Red, green and blue sRGB-encoded (0…1).
    public var sRGB: (red: Double, green: Double, blue: Double) {
        (Self.encode(red), Self.encode(green), Self.encode(blue))
    }

    /// "red 20%, green 40%, blue 60%" — whole sRGB-encoded percents (UIX-012-R8).
    public var spoken: String { Self.spoken(sRGBRed: sRGB.red, green: sRGB.green, blue: sRGB.blue) }

    /// The spoken form of sRGB-encoded components.
    public static func spoken(sRGBRed red: Double, green: Double, blue: Double) -> String {
        func percent(_ v: Double) -> Int { Int((min(max(v.isFinite ? v : 0, 0), 1) * 100).rounded()) }
        return "red \(percent(red))%, green \(percent(green))%, blue \(percent(blue))%"
    }

    public static func encode(_ linear: Double) -> Double { Double(FrameColorConversion.linearToSRGB(Float(linear))) }

    /// The inverse sRGB transfer, clamped to 0…1.
    public static func decode(_ encoded: Double) -> Double {
        let c: Double = encoded.isFinite ? min(max(encoded, 0), 1) : 0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}

extension CapturedPixels {
    /// The pixel at (x, y), top-left origin, as straight linear RGBA; nil outside the frame.
    public func sampledColor(x: Int, y: Int) -> SampledColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        switch layout {
        case .linearPremultipliedHalfRGBA(let half):
            let i: Int = (y * width + x) * 4
            let a: Float = FrameColorConversion.clamp01(FrameColorConversion.halfToFloat(half[i + 3]))
            guard a > 0 else { return SampledColor(red: 0, green: 0, blue: 0, alpha: 0) }
            func straight(_ k: Int) -> Double {
                Double(min(FrameColorConversion.clamp01(FrameColorConversion.halfToFloat(half[i + k])), a) / a)
            }
            return SampledColor(red: straight(0), green: straight(1), blue: straight(2), alpha: Double(a))
        case .sRGBBGRA8TopDown(let bgra):
            let i: Int = (y * width + x) * 4
            return Self.decoded(r: bgra[i + 2], g: bgra[i + 1], b: bgra[i])
        case .sRGBRGBA8BottomUp(let rgba):
            let i: Int = ((height - 1 - y) * width + x) * 4
            return Self.decoded(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
        }
    }

    private static func decoded(r: UInt8, g: UInt8, b: UInt8) -> SampledColor {
        SampledColor(red: SampledColor.decode(Double(r) / 255), green: SampledColor.decode(Double(g) / 255),
                     blue: SampledColor.decode(Double(b) / 255), alpha: 1)
    }
}
