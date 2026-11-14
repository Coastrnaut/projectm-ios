// PresetMotionScore.swift — roadmap PRE-005: a deterministic motion score from a preset's thumbnail
// frame samples (spec PRE-005-R1, R2; research PRE-005-D1, D3; contract C2). Plain Swift integer maths
// on RGBA8 bytes, so the same samples give the bit-identical score on every platform, Linux included.
//
// * Brightness Y = (77 R + 150 G + 29 B) >> 8 at the centres of a fixed 32 × 18 grid (any picture size).
// * Score = 1000 × Σ|ΔY| over consecutive sample pairs / (pairs × 576), integer division: the mean
//   brightness change per grid point and pair, in thousandths of a level (0 ... 255,000).
// * Classes (PresetEnergy): Calm below 4 levels, Moderate below 16, Energetic from 16 (provisional
//   until a device sweep, PRE-005-T17; only the score is stored, so retuning migrates nothing).
import Foundation

public enum PresetMotionScore {
    /// Bumped whenever the score computation (not the thresholds) changes; the PNG field and the
    /// index carry it, and another version is ignored or rebuilt.
    public static let version = 1
    public static let gridColumns = 32
    public static let gridRows = 18
    public static let moderateThreshold = 4_000
    public static let energeticThreshold = 16_000
    /// The thumbnail drawing's sample frames (0-based within PRE-001's 45 frames; the last is the
    /// thumbnail itself).
    public static let sampleFrames: [Int] = [36, 40, 44]

    /// The score of RGBA8 samples (top row first, all of one size) in drawing order; nil for fewer than
    /// two samples or a size that does not match the bytes.
    public static func score(samples: [[UInt8]], width: Int, height: Int) -> Int? {
        guard samples.count >= 2, width > 0, height > 0 else { return nil }
        let needed: Int = width * height * 4
        guard samples.allSatisfy({ (sample: [UInt8]) -> Bool in sample.count >= needed }) else { return nil }
        let grids: [[Int]] = samples.map { (sample: [UInt8]) -> [Int] in luma(sample, width: width, height: height) }
        var total = 0
        for pair in 1..<grids.count {
            let previous: [Int] = grids[pair - 1], current: [Int] = grids[pair]
            for index in 0..<current.count { total += abs(current[index] - previous[index]) }
        }
        let points: Int = (grids.count - 1) * gridColumns * gridRows
        return total * 1000 / points
    }

    /// The class of the samples' score; nil when they cannot be scored.
    public static func energy(samples: [[UInt8]], width: Int, height: Int) -> PresetEnergy? {
        score(samples: samples, width: width, height: height).map { (value: Int) -> PresetEnergy in PresetEnergy.of(score: value) }
    }

    /// Brightness at the grid's cell centres, row by row.
    static func luma(_ rgba: [UInt8], width: Int, height: Int) -> [Int] {
        var values: [Int] = []
        values.reserveCapacity(gridColumns * gridRows)
        for row in 0..<gridRows {
            let y: Int = (2 * row + 1) * height / (2 * gridRows)
            for column in 0..<gridColumns {
                let x: Int = (2 * column + 1) * width / (2 * gridColumns)
                let offset: Int = (y * width + x) * 4
                let weighted: Int = 77 * Int(rgba[offset]) + 150 * Int(rgba[offset + 1]) + 29 * Int(rgba[offset + 2])
                values.append(weighted >> 8)
            }
        }
        return values
    }
}
