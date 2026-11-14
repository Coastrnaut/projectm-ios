// FX-003-T03: the plain-Swift reference of the colour grade (FX-003-R3 to R5, R8, S3). CPU only; runs on Linux
// and on the Mac in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE).
import Compositor
import XCTest

/// A small deterministic generator (SplitMix64), so sampled tests are reproducible.
struct GradeTestRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `range`.
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        let unit: Double = Double(next() >> 11) / Double(UInt64(1) << 53)
        let span: Double = range.upperBound - range.lowerBound
        return range.lowerBound + unit * span
    }
}

final class ColorGradeReferenceTests: XCTestCase {
    private typealias P = ToneMap.Pixel

    private static func luminance(_ p: P) -> Double { ToneMap.luminance(p) }

    private static let samples: [P] = [P(0, 0, 0, 0), P(1, 1, 1, 1), P(0.25, 0.5, 0.75, 1), P(1, 0, 0, 0.5),
                                       P(0.18, 0.18, 0.18, 1), P(3, 0.2, 0.1, 1), P(.nan, 0.5, 0.5, 1),
                                       P(.infinity, -1, 0.5, 0.7), P(0.5, 0.5, 0.5, .nan)]

    func testNeutralIsBypassBitForBit() {
        XCTAssertTrue(ColorGrade.neutral.isNeutral)
        XCTAssertEqual(ColorGrade.neutral.coefficients.flags, 0)
        for p in Self.samples {
            let out: P = ColorGrade.neutral.apply(p)
            for c in 0..<4 { XCTAssertEqual(out[c].bitPattern, p[c].bitPattern, "\(p) channel \(c)") }
        }
    }

    func testEachNeutralControlIsAnExactIdentityWhileOthersAreActive() {
        // Saturation alone vs saturation with every other control at neutral: identical by construction; and each
        // flag appears only for its non-neutral control.
        let cases: [(ColorGrade, UInt32)] = [
            (ColorGrade(temperature: 0.5), ColorGradeCoefficients.temperatureFlag),
            (ColorGrade(lift: 0.05), ColorGradeCoefficients.liftFlag),
            (ColorGrade(gamma: 1.5), ColorGradeCoefficients.gammaFlag),
            (ColorGrade(gain: 1.5), ColorGradeCoefficients.gainFlag),
            (ColorGrade(saturation: 0.5), ColorGradeCoefficients.saturationFlag),
        ]
        for (grade, flag) in cases { XCTAssertEqual(grade.coefficients.flags, flag, "\(grade)") }
        let gainOnly = ColorGrade(gain: 1.25)
        let p = P(0.3, 0.6, 0.1, 1)
        let out: P = gainOnly.apply(p)
        for c in 0..<3 { XCTAssertEqual(out[c], p[c] * 1.25, accuracy: 1e-15, "gain only, channel \(c)") }
        XCTAssertEqual(ColorGrade(temperature: 0, lift: 0, gamma: 1, gain: 1.25, saturation: 1).apply(p), out)
    }

    func testTemperatureIsIdentityAtNeutralAndKeepsGreyLuminance() {
        XCTAssertEqual(ColorGrade(temperature: 0).coefficients.balance, SIMD3<Double>(1, 1, 1))
        for t in [-1.0, -0.4, 0.3, 1.0] {
            let grade = ColorGrade(temperature: t)
            for level in [0.0, 0.05, 0.18, 0.5, 1.0, 2.5] {
                let out: P = grade.apply(P(level, level, level, 1))
                XCTAssertEqual(Self.luminance(out), level, accuracy: 1e-12, "T \(t), grey \(level)")
            }
            let grey: P = grade.apply(P(0.5, 0.5, 0.5, 1))
            if t > 0 {
                XCTAssertGreaterThan(grey.x, grey.z, "warm: more red than blue")
            } else {
                XCTAssertLessThan(grey.x, grey.z, "cool: more blue than red")
            }
        }
        // Hand-checked: T = 1 → r = 2^0.3, b = 2^-0.3, n = 0.2126 r + 0.7152 + 0.0722 b.
        let r: Double = 1.231_144_413_344_916
        let b: Double = 0.812_252_396_356_740_4
        let n: Double = 0.2126 * r + 0.7152 + 0.0722 * b
        let gains: SIMD3<Double> = ColorGrade(temperature: 1).coefficients.balance
        XCTAssertEqual(gains.x, r / n, accuracy: 1e-12)
        XCTAssertEqual(gains.y, 1 / n, accuracy: 1e-12)
        XCTAssertEqual(gains.z, b / n, accuracy: 1e-12)
    }

    func testSaturationZeroGivesGreyOfEqualLuminance() {
        let grade = ColorGrade(saturation: 0)
        for p in [P(1, 0, 0, 1), P(0.2, 0.7, 0.1, 1), P(0.9, 0.9, 0.2, 0.5), P(3, 0.5, 0.25, 1)] {
            let out: P = grade.apply(p)
            let y: Double = Self.luminance(p)
            XCTAssertEqual(out.x, y, accuracy: 1e-15)
            XCTAssertEqual(out.y, y, accuracy: 1e-15)
            XCTAssertEqual(out.z, y, accuracy: 1e-15)
            XCTAssertEqual(Self.luminance(out), y, accuracy: 1e-12, "\(p)")
            XCTAssertEqual(out.w, p.w)
        }
    }

    func testHandCheckedLiftGammaGainAndSaturation() {
        let lift = ColorGrade(lift: 0.1)
        XCTAssertEqual(lift.apply(P(0, 0, 0, 1)).x, 0.1, accuracy: 1e-15, "black → lift")
        XCTAssertEqual(lift.apply(P(1, 1, 1, 1)).x, 1, accuracy: 1e-15, "white stays")
        XCTAssertEqual(ColorGrade(lift: -0.1).apply(P(0.05, 0, 0, 1)).x, 0, "clamped at black")
        XCTAssertEqual(ColorGrade(gamma: 2).apply(P(0.25, 0, 1, 1)).x, 0.5, accuracy: 1e-15, "0.25^(1/2)")
        XCTAssertEqual(ColorGrade(gamma: 2).apply(P(0.25, 0, 1, 1)).z, 1, accuracy: 1e-15, "1 fixed")
        XCTAssertEqual(ColorGrade(gain: 2).apply(P(0.25, 0, 1, 1)).z, 2, accuracy: 1e-15, "over range before the tone map")
        let sat: P = ColorGrade(saturation: 2).apply(P(0.5, 0.25, 0.25, 1))
        let y: Double = 0.2126 * 0.5 + 0.7152 * 0.25 + 0.0722 * 0.25
        XCTAssertEqual(sat.x, y + 2 * (0.5 - y), accuracy: 1e-15)
        XCTAssertEqual(ColorGrade(saturation: 2).apply(P(1, 0, 0, 1)).y, 0, "a pushed channel stops at 0")
    }

    func testLuminanceOrderingUnderLiftGammaGain() {
        // FX-003-R4, S3: ≥ 10,000 sampled settings × input pairs; brightening an input never darkens the output.
        var random = GradeTestRandom(seed: 0xF3_003)
        var checks: Int = 0
        for _ in 0..<2_500 {
            let grade = ColorGrade(lift: random.uniform(ColorGrade.liftRange), gamma: random.uniform(ColorGrade.gammaRange),
                                   gain: random.uniform(ColorGrade.gainRange))
            let base = P(random.uniform(0...2), random.uniform(0...2), random.uniform(0...2), 1)
            let lower: Double = Self.luminance(grade.apply(base))
            for c in 0..<3 {
                var brighter: P = base
                brighter[c] += random.uniform(0...0.5)
                let upper: Double = Self.luminance(grade.apply(brighter))
                XCTAssertGreaterThanOrEqual(upper, lower - 1e-12, "\(grade) \(base) channel \(c)")
                checks += 1
            }
            let g0: Double = random.uniform(0...1.5)
            let g1: Double = g0 + random.uniform(0...0.5)
            let y0: Double = Self.luminance(grade.apply(P(g0, g0, g0, 1)))
            let y1: Double = Self.luminance(grade.apply(P(g1, g1, g1, 1)))
            XCTAssertGreaterThanOrEqual(y1, y0 - 1e-12, "grey ramp \(grade)")
            checks += 1
        }
        XCTAssertGreaterThanOrEqual(checks, 10_000)
    }

    func testSampledGradesStayFiniteAndNonNegative() {
        var random = GradeTestRandom(seed: 42)
        for _ in 0..<5_000 {
            let grade = ColorGrade(temperature: random.uniform(ColorGrade.temperatureRange), lift: random.uniform(ColorGrade.liftRange),
                                   gamma: random.uniform(ColorGrade.gammaRange), gain: random.uniform(ColorGrade.gainRange),
                                   saturation: random.uniform(ColorGrade.saturationRange))
            let p = P(random.uniform(0...4), random.uniform(0...4), random.uniform(0...4), random.uniform(0...1))
            let out: P = grade.apply(p)
            for c in 0..<4 {
                XCTAssertTrue(out[c].isFinite && out[c] >= 0, "\(grade) \(p) → \(out)")
            }
            let shown: P = ToneMap.map(out)
            for c in 0..<3 { XCTAssertLessThanOrEqual(shown[c], 1) }
        }
    }

    func testClampingAndNeutralDetection() {
        let wild = ColorGrade(temperature: 9, lift: -.infinity, gamma: .nan, gain: 0, saturation: 7).clamped
        XCTAssertEqual(wild, ColorGrade(temperature: 1, lift: -0.1, gamma: 1, gain: 0.5, saturation: 2))
        XCTAssertTrue(ColorGrade(temperature: .nan, lift: .nan, gamma: .nan, gain: .nan, saturation: .nan).isNeutral)
        XCTAssertFalse(ColorGrade(gain: 1.01).isNeutral)
        XCTAssertEqual(ColorGrade(gain: 5).coefficients.gain, 2, "coefficients use the clamped values")
    }
}
