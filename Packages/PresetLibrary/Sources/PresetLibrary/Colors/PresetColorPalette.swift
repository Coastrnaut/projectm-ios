// PresetColorPalette.swift — roadmap PRE-004: a thumbnail's dominant colour families (spec
// PRE-004-R1, R2; research PRE-004-D2, D3; contract C1). Plain Swift on RGBA8 bytes, so the same
// picture gives the same families on every platform, Linux included.
//
// * A fixed 32 × 18 grid of samples at cell centres, whatever the picture's size (576 samples).
// * Each sample falls into exactly one family by integer lightness/chroma thresholds and its hue.
// * Families with at least 12% of the samples are dominant, largest first (ties in family order),
//   at most three; a picture where none reaches 12% keeps its single largest family.
import Foundation

public enum PresetColorPalette {
    /// Bumped whenever a rule below changes; opening an index of another version rebuilds it.
    public static let version = 1
    public static let gridColumns = 32
    public static let gridRows = 18
    public static let minimumShare = 0.12
    public static let maximumFamilies = 3

    /// The family of one 8-bit sRGB pixel (research D2).
    public static func family(r: UInt8, g: UInt8, b: UInt8) -> PresetColorFamily {
        let red = Int(r), green = Int(g), blue = Int(b)
        let high: Int = max(red, max(green, blue))
        let low: Int = min(red, min(green, blue))
        let chroma: Int = high - low
        let sum: Int = high + low
        if high < 48 { return .black }
        if low > 215 { return .white }
        if chroma < 32 {
            if sum >= 420 { return .white }
            if sum < 120 { return .black }
            return .grey
        }
        return hueFamily(hue(red: red, green: green, blue: blue, high: high, chroma: chroma))
    }

    /// Dominant families of RGBA8 rows (top first); `[]` when the size does not match the bytes.
    public static func dominantFamilies(rgba: [UInt8], width: Int, height: Int) -> [PresetColorFamily] {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return [] }
        var counts: [Int] = Array(repeating: 0, count: PresetColorFamily.allCases.count)
        for row in 0..<gridRows {
            let y: Int = (2 * row + 1) * height / (2 * gridRows)
            for column in 0..<gridColumns {
                let x: Int = (2 * column + 1) * width / (2 * gridColumns)
                let offset: Int = (y * width + x) * 4
                let family: PresetColorFamily = Self.family(r: rgba[offset], g: rgba[offset + 1], b: rgba[offset + 2])
                counts[family.order] += 1
            }
        }
        return rank(counts)
    }

    /// Families by count (descending, then family order), keeping those at or above the share.
    static func rank(_ counts: [Int]) -> [PresetColorFamily] {
        let total: Int = counts.reduce(0, +)
        guard total > 0 else { return [] }
        let threshold: Int = Int((Double(total) * minimumShare).rounded(.up))
        let families: [PresetColorFamily] = PresetColorFamily.allCases
        let ordered: [PresetColorFamily] = families.sorted { (a: PresetColorFamily, b: PresetColorFamily) -> Bool in
            let left: Int = counts[a.order], right: Int = counts[b.order]
            return left != right ? left > right : a.order < b.order
        }
        let dominant: [PresetColorFamily] = ordered.filter { (f: PresetColorFamily) -> Bool in counts[f.order] >= threshold }
        if dominant.isEmpty { return [ordered[0]] }
        return Array(dominant.prefix(maximumFamilies))
    }

    private static func hue(red: Int, green: Int, blue: Int, high: Int, chroma: Int) -> Double {
        let c = Double(chroma)
        var degrees: Double
        if high == red {
            degrees = 60.0 * (Double(green - blue) / c)
        } else if high == green {
            degrees = 60.0 * (Double(blue - red) / c) + 120.0
        } else {
            degrees = 60.0 * (Double(red - green) / c) + 240.0
        }
        if degrees < 0 { degrees += 360.0 }
        return degrees
    }

    private static func hueFamily(_ hue: Double) -> PresetColorFamily {
        switch hue {
        case ..<15: .red
        case ..<45: .orange
        case ..<70: .yellow
        case ..<165: .green
        case ..<195: .cyan
        case ..<255: .blue
        case ..<285: .purple
        case ..<340: .pink
        default: .red
        }
    }
}
