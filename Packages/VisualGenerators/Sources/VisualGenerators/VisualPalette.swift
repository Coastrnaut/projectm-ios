// VisualPalette.swift — colors of native visuals (VIS-001-R6; research VIS-001-D4, D7).
//
// Colors are stored linear (light intensity), not sRGB-encoded: blending, dimming and the
// Reduce-flashing luminance are computed in linear light, and a `bgra8Unorm_srgb` target encodes on
// write. Palettes are defined in sRGB (as designers specify them) and decoded once per
// configuration. A bar's color depends only on its index and the palette, never on the band value,
// so loudness changes geometry, not color. Full palette editing is UIX-011.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The sRGB transfer function (IEC 61966-2-1).
public enum SRGB {
    /// Encoded 0…1 → linear 0…1.
    @inlinable
    public static func decode(_ v: Float) -> Float {
        let c = min(max(v, 0), 1)
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// Linear 0…1 → encoded 0…1.
    @inlinable
    public static func encode(_ v: Float) -> Float {
        let c = min(max(v, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
    }
}

/// A linear-light RGBA color. Used premultiplied where the contract says so (backgrounds, vertices).
public struct LinearColor: Sendable, Equatable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let opaqueBlack = LinearColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// From 8-bit sRGB components.
    public static func fromSRGB(red: Int, green: Int, blue: Int, alpha: Float = 1) -> LinearColor {
        LinearColor(red: SRGB.decode(Float(red) / 255), green: SRGB.decode(Float(green) / 255),
                    blue: SRGB.decode(Float(blue) / 255), alpha: alpha)
    }

    /// Relative luminance Y of the linear color (Rec. 709 / sRGB primaries).
    public var relativeLuminance: Float { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    /// max(R − G − B, 0): WCAG's red-flash quantity on linear channels (FX-019-R3).
    public var redness: Float { max(red - green - blue, 0) }

    /// Every component clamped to 0…1 (NaN → 0).
    public var clamped: LinearColor {
        func c(_ v: Float) -> Float { v.isNaN ? 0 : min(max(v, 0), 1) }
        return LinearColor(red: c(red), green: c(green), blue: c(blue), alpha: c(alpha))
    }
}

/// The minimal palette set of VIS-001 (data-model.md).
public enum VisualPalette: String, CaseIterable, Sendable {
    /// Hue 0° (red) at bar 0 to 270° (violet) at the last bar, full saturation and value. Default.
    case spectrum
    /// `#2EC4FF` to `#E8F7FF`, interpolated in linear light.
    case ice
    /// White.
    case mono

    /// The linear color of bar `k` of `count`.
    public func color(bar k: Int, of count: Int) -> LinearColor {
        let t = count > 1 ? Float(min(max(k, 0), count - 1)) / Float(count - 1) : 0
        switch self {
        case .spectrum:
            return VisualPalette.hue(270 * t)
        case .ice:
            let a = LinearColor.fromSRGB(red: 0x2E, green: 0xC4, blue: 0xFF)
            let b = LinearColor.fromSRGB(red: 0xE8, green: 0xF7, blue: 0xFF)
            return LinearColor(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t,
                               blue: a.blue + (b.blue - a.blue) * t, alpha: 1)
        case .mono:
            return LinearColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    /// HSV(hue, 1, 1) in sRGB, decoded to linear.
    static func hue(_ degrees: Float) -> LinearColor {
        let h = degrees / 60
        let sector = Int(h.rounded(.down))
        let f = h - Float(sector)
        let (r, g, b): (Float, Float, Float)
        switch sector {
        case 0: (r, g, b) = (1, f, 0)
        case 1: (r, g, b) = (1 - f, 1, 0)
        case 2: (r, g, b) = (0, 1, f)
        case 3: (r, g, b) = (0, 1 - f, 1)
        case 4: (r, g, b) = (f, 0, 1)
        default: (r, g, b) = (1, 0, 1 - f)
        }
        return LinearColor(red: SRGB.decode(r), green: SRGB.decode(g), blue: SRGB.decode(b), alpha: 1)
    }
}
