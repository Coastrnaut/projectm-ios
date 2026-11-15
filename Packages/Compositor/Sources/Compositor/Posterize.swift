// Posterize.swift — FX-013's posterization (FX-013-R1 to R5; specs/301-fx-013-posterization, contracts/posterize.md,
// research FX-013-D2 to D4). CPU only, builds on Linux. The plain-Swift reference of the quantiser the compositor's
// `cmp_posterize` shader applies in float as step 8 of FX-003's grade; tests compare the two.
//
// One display-range value x, L levels (n = L − 1), threshold t:
//   x' = 0 if NaN else clamp(x, 0, 1); e = sRGB-encode(x'); k = clamp(⌊e·n + t⌋, 0, n); output sRGB-decode(k/n).
//   t = 0.5 without dithering (nearest level, half way up); with dithering t = (B[y mod 4][x mod 4] + 0.5)/16 from the
//   4 × 4 Bayer matrix B (output pixel position). The output is always one of the L values decode(k/n).
// Every expression is split into typed steps.
import Foundation

public enum Posterize {
    public static let levelsRange: ClosedRange<Int> = 2...32
    public static let defaultLevels: Int = 6
    /// The nearest-level threshold (dithering off).
    public static let roundingThreshold: Double = 0.5

    /// The ordered-dither matrix, row by row (research FX-013-D4).
    public static let bayer: [Int] = [0, 8, 2, 10,
                                      12, 4, 14, 6,
                                      3, 11, 1, 9,
                                      15, 7, 13, 5]

    /// Levels clamped to 2…32.
    public static func clampLevels(_ levels: Int) -> Int {
        min(max(levels, levelsRange.lowerBound), levelsRange.upperBound)
    }

    /// A stored number as a level count: NaN or ±Inf → the default, else rounded and clamped.
    public static func levels(from value: Double) -> Int {
        guard value.isFinite else { return defaultLevels }
        let bounded: Double = min(max(value.rounded(), Double(levelsRange.lowerBound)), Double(levelsRange.upperBound))
        return Int(bounded)
    }

    /// The dither threshold at an output pixel (0 < t < 1).
    public static func threshold(x: Int, y: Int) -> Double {
        let column: Int = ((x % 4) + 4) % 4
        let row: Int = ((y % 4) + 4) % 4
        let index: Int = bayer[row * 4 + column]
        return (Double(index) + 0.5) / 16
    }

    /// The level index 0…n of one value (contract C1).
    public static func levelIndex(_ x: Double, levels: Int, threshold t: Double) -> Int {
        let input: Double = x.isNaN ? 0 : min(max(x, 0), 1)
        let n: Int = clampLevels(levels) - 1
        let e: Double = LayerBlend.encode(input)
        let scaled: Double = e * Double(n) + t
        let k: Double = floor(scaled)
        let bounded: Double = min(max(k, 0), Double(n))
        return Int(bounded)
    }

    /// The linear value of level `k` of `levels`.
    public static func level(_ k: Int, levels: Int) -> Double {
        let n: Int = clampLevels(levels) - 1
        let encoded: Double = Double(k) / Double(n)
        return LayerBlend.decode(encoded)
    }

    /// The quantised linear value (one of the L levels).
    public static func quantize(_ x: Double, levels: Int, threshold t: Double = roundingThreshold) -> Double {
        level(levelIndex(x, levels: levels, threshold: t), levels: levels)
    }
}
