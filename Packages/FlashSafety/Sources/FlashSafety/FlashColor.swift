// FlashColor.swift — WCAG relative luminance and redness (FX-019-R3; research FX-019-D1), and the
// area levels of an RGBA8 image (tests that read back rendered frames; ACC-002 later).

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum FlashColor {
    /// sRGB-encoded 0…1 → linear (WCAG's relative-luminance definition).
    public static func decodeSRGB(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear 0…1 → sRGB-encoded.
    public static func encodeSRGB(_ l: Double) -> Double {
        l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    /// Relative luminance of linear channels.
    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// max(R − G − B, 0) of linear channels (WCAG red flash: (R − G − B) × 320, negatives as 0).
    public static func redness(red: Double, green: Double, blue: Double) -> Double {
        max(red - green - blue, 0)
    }

    /// Mean levels of the 16 tiles and the whole frame of an sRGB-encoded RGBA8 image.
    /// `bottomRowFirst` for OpenGL read-backs (tile rows are numbered from the top of the picture).
    public static func tileLevels(rgba: [UInt8], width: Int, height: Int, bottomRowFirst: Bool) -> [FlashLevels] {
        var table = [Double](repeating: 0, count: 256)
        for i in 0..<256 { table[i] = decodeSRGB(Double(i) / 255) }
        let side = FlashZones.gridSide
        var sums = [FlashLevels](repeating: .zero, count: FlashZones.count)
        var counts = [Int](repeating: 0, count: FlashZones.tileCount)
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return sums }
        for row in 0..<height {
            let pictureRow = bottomRowFirst ? height - 1 - row : row
            let tileRow = pictureRow * side / height
            for x in 0..<width {
                let p = (row * width + x) * 4
                let r = table[Int(rgba[p])], g = table[Int(rgba[p + 1])], b = table[Int(rgba[p + 2])]
                let tile = tileRow * side + x * side / width
                sums[tile].luminance += relativeLuminance(red: r, green: g, blue: b)
                sums[tile].redness += redness(red: r, green: g, blue: b)
                counts[tile] += 1
            }
        }
        var whole = FlashLevels.zero
        for t in 0..<FlashZones.tileCount {
            whole.luminance += sums[t].luminance
            whole.redness += sums[t].redness
            if counts[t] > 0 {
                sums[t].luminance /= Double(counts[t])
                sums[t].redness /= Double(counts[t])
            }
        }
        let n = Double(width * height)
        sums[FlashZones.wholeFrame] = FlashLevels(luminance: whole.luminance / n, redness: whole.redness / n)
        return sums
    }
}
