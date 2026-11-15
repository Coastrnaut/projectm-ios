// FX-013-T05, T08: the plain-Swift reference of posterization (FX-013-R2 to R6, S1 to S4; research FX-013-D1 to D4).
// The roadmap acceptance: "Known gradient contains at most configured levels without dithering." CPU only; runs on
// Linux and on the Mac in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE).
import Compositor
import Foundation
import XCTest

final class PosterizeReferenceTests: XCTestCase {
    private typealias P = ToneMap.Pixel
    private static let levelCounts: [Int] = [2, 3, 6, 16, 32]

    /// 0…1 in 4,096 steps (4,097 values).
    private static func sweep() -> [Double] {
        (0...4096).map { (i: Int) -> Double in Double(i) / 4096 }
    }

    /// Deterministic random colours (a fixed LCG): channels −0.5…4, alpha 0…1.
    private static func randomColours(_ count: Int) -> [P] {
        var state: UInt64 = 0xF0_013
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let top: UInt64 = state >> 11
            return Double(top) / Double(UInt64(1) << 53)
        }
        return (0..<count).map { (_: Int) -> P in
            let r: Double = next() * 4.5 - 0.5
            let g: Double = next() * 4.5 - 0.5
            let b: Double = next() * 4.5 - 0.5
            return P(r, g, b, next())
        }
    }

    private static func bits(_ p: P) -> SIMD4<UInt64> {
        SIMD4<UInt64>(p.x.bitPattern, p.y.bitPattern, p.z.bitPattern, p.w.bitPattern)
    }

    /// The gradient as pixels: grey ramp, or a ramp on one channel with the others at fixed values.
    private static func ramp(channel: Int?) -> [P] {
        sweep().map { (v: Double) -> P in
            guard let channel else { return P(v, v, v, 1) }
            var p = P(0.3, 0.6, 0.05, 1)
            p[channel] = v
            return p
        }
    }

    private static func distinct(_ pixels: [P], channel: Int) -> Set<UInt64> {
        Set(pixels.map { (p: P) -> UInt64 in p[channel].bitPattern })
    }

    // MARK: - US1: the acceptance — at most L levels per channel without dithering (S1)

    func testKnownGradientHasAtMostTheConfiguredLevelsWithoutDithering() {
        for levels in Self.levelCounts {
            let grade = ColorGrade(posterize: true, posterizeLevels: levels)
            for channel in [nil, 0, 1, 2] as [Int?] {
                let out: [P] = Self.ramp(channel: channel).enumerated().map { (i: Int, p: P) -> P in
                    grade.apply(p, x: i, y: 0)
                }
                for c in 0..<3 {
                    let count: Int = Self.distinct(out, channel: c).count
                    XCTAssertLessThanOrEqual(count, levels, "L \(levels), ramp \(String(describing: channel)), channel \(c)")
                    if channel == nil || channel == c {
                        XCTAssertEqual(count, levels, "the full ramp reaches every level (L \(levels))")
                    }
                }
                let allowed = Set((0..<levels).map { (k: Int) -> UInt64 in Posterize.level(k, levels: levels).bitPattern })
                for p in out { for c in 0..<3 { XCTAssertTrue(allowed.contains(p[c].bitPattern)) } }
            }
            XCTAssertEqual(grade.apply(P(0, 0, 0, 1)), P(0, 0, 0, 1), "black stays black")
            XCTAssertEqual(grade.apply(P(1, 1, 1, 1)), P(1, 1, 1, 1), "white stays white")
        }
    }

    func testLevelsAreEvenOnTheEncodedScaleAndRoundToNearest() {
        XCTAssertEqual(Posterize.levelIndex(0.2140, levels: 3, threshold: 0.5), 1, "sRGB 0.5 is level 1 of 3")
        XCTAssertEqual(LayerBlend.encode(Posterize.level(1, levels: 3)), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Posterize.levelIndex(LayerBlend.decode(0.24), levels: 3, threshold: 0.5), 0)
        XCTAssertEqual(Posterize.levelIndex(LayerBlend.decode(0.26), levels: 3, threshold: 0.5), 1)
        XCTAssertEqual(Posterize.clampLevels(1), 2)
        XCTAssertEqual(Posterize.clampLevels(99), 32)
        XCTAssertEqual(Posterize.levels(from: .nan), 6)
        XCTAssertEqual(Posterize.levels(from: 7.6), 8)
        XCTAssertEqual(ColorGrade(posterize: true, posterizeLevels: 400).clamped.posterizeLevels, 32)
    }

    // MARK: - US3: off is identity (S2), extremes are bounded (S3)

    func testOffIsBitIdenticalWhateverTheLevelsAndDither() {
        let off = ColorGrade(posterize: false, posterizeLevels: 2, posterizeDither: true)
        XCTAssertTrue(off.isNeutral)
        XCTAssertEqual(off.coefficients.flags, 0)
        let inputs: [P] = Self.sweep().map { (v: Double) -> P in P(v, v * 0.5, 1 - v, 1) } + Self.randomColours(1_000)
        for p in inputs { XCTAssertEqual(Self.bits(off.apply(p, x: 3, y: 1)), Self.bits(p)) }
        let others = ColorGrade(temperature: 0.4, gamma: 1.3, hue: 30, contrast: .filmic, contrastStrength: 0.5)
        var withOff: ColorGrade = others
        withOff.posterizeLevels = 3
        withOff.posterizeDither = true
        for p in inputs {
            XCTAssertEqual(Self.bits(withOff.apply(p, x: 1, y: 2)), Self.bits(others.apply(p, x: 1, y: 2)))
        }
    }

    func testExtremesAreFiniteAndOnALevel() {
        let extremes: [Double] = [1e6, -1, .nan, .infinity, -.infinity]
        for levels in [2, 6, 32] {
            for dither in [false, true] {
                let grade = ColorGrade(posterize: true, posterizeLevels: levels, posterizeDither: dither)
                let allowed = Set((0..<levels).map { (k: Int) -> UInt64 in Posterize.level(k, levels: levels).bitPattern })
                for e in extremes {
                    let out: P = grade.apply(P(e, 0.5, e, e), x: 2, y: 3)
                    for c in 0..<4 { XCTAssertTrue(out[c].isFinite, "\(e) → \(out)") }
                    for c in 0..<3 { XCTAssertTrue(allowed.contains(out[c].bitPattern), "\(e) → \(out)") }
                    XCTAssertTrue((0...1).contains(out.w))
                }
            }
        }
    }

    func testPosterizeRunsAfterTheContrastCurve() {
        let grade = ColorGrade(gain: 1.4, contrast: .sCurve, contrastStrength: 1, posterize: true, posterizeLevels: 6)
        let curvedOnly = ColorGrade(gain: 1.4, contrast: .sCurve, contrastStrength: 1)
        for v in stride(from: 0.0, through: 3.0, by: 0.05) {
            let p = P(v, v * 0.4, 0.1, 1)
            let curved: P = curvedOnly.apply(p)
            let expected = P(Posterize.quantize(curved.x, levels: 6), Posterize.quantize(curved.y, levels: 6),
                             Posterize.quantize(curved.z, levels: 6), curved.w)
            XCTAssertEqual(grade.apply(p), expected)
            XCTAssertEqual(ToneMap.map(grade.apply(p)), grade.apply(p), "the tone map after it is an identity")
        }
    }

    // MARK: - US2: dithering (S4)

    func testDitherKeepsTheLevelsIsDeterministicAndMixesNeighbours() {
        for levels in [2, 6, 32] {
            let grade = ColorGrade(posterize: true, posterizeLevels: levels, posterizeDither: true)
            XCTAssertEqual(grade.coefficients.flags, ColorGradeCoefficients.posterizeFlag | ColorGradeCoefficients.ditherFlag)
            let ramp: [P] = Self.ramp(channel: nil)
            let first: [P] = ramp.enumerated().map { (i: Int, p: P) -> P in grade.apply(p, x: i, y: i / 7) }
            let second: [P] = ramp.enumerated().map { (i: Int, p: P) -> P in grade.apply(p, x: i, y: i / 7) }
            XCTAssertEqual(first.map(Self.bits), second.map(Self.bits), "deterministic")
            for c in 0..<3 { XCTAssertLessThanOrEqual(Self.distinct(first, channel: c).count, levels) }
        }
        // A flat value 30% of the way from level 1 to level 2 of 3: a 4 × 4 tile shows both, mean within 1/32 level.
        let levels = 3
        let encoded: Double = 0.5 + 0.3 * 0.5
        let flat: Double = LayerBlend.decode(encoded)
        let grade = ColorGrade(posterize: true, posterizeLevels: levels, posterizeDither: true)
        var indices: [Int] = []
        for y in 0..<4 {
            for x in 0..<4 {
                let out: Double = grade.apply(P(flat, flat, flat, 1), x: x, y: y).x
                indices.append(Posterize.levelIndex(out, levels: levels, threshold: 0.5))
            }
        }
        XCTAssertEqual(Set(indices), [1, 2], "both neighbouring levels appear")
        let mean: Double = Double(indices.reduce(0, +)) / 16
        XCTAssertEqual(mean, encoded * Double(levels - 1), accuracy: 1.0 / 32 + 1e-9)
        XCTAssertEqual(Set(Posterize.bayer), Set(0..<16))
    }
}
