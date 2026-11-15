// FX-005-T05, T11, T12: the plain-Swift reference of the contrast curves (FX-005-R2 to R5, S1 to S3; research
// FX-005-D1 to D5). The roadmap acceptance: "Neutral curve is identity and extreme values stay bounded." CPU only;
// runs on Linux and on the Mac in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE).
import Compositor
import Foundation
import XCTest

final class ContrastCurveReferenceTests: XCTestCase {
    private typealias P = ToneMap.Pixel
    private static let curves: [ContrastCurve] = [.sCurve, .filmic]
    private static let strengths: [Double] = [0.25, 0.5, 1]

    /// 0…1 in 4,096 steps (4,097 values).
    private static func sweep() -> [Double] {
        (0...4096).map { (i: Int) -> Double in Double(i) / 4096 }
    }

    /// Deterministic random colours (a fixed LCG; no wall clock): channels −0.5…4, alpha 0…1.
    private static func randomColours(_ count: Int) -> [P] {
        var state: UInt64 = 0x5EED_F0F5
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

    // MARK: - US2: Linear is identity (S1)

    func testLinearAndStrengthZeroAreBitIdentical() {
        for x in Self.sweep() {
            XCTAssertEqual(ContrastCurve.value(x, curve: .linear, strength: 1).bitPattern, x.bitPattern)
            for curve in Self.curves {
                XCTAssertEqual(ContrastCurve.value(x, curve: curve, strength: 0).bitPattern, x.bitPattern, "\(curve) at 0")
            }
        }
        let neutralGrades: [ColorGrade] = [ColorGrade(contrast: .linear, contrastStrength: 1),
                                           ColorGrade(contrast: .sCurve, contrastStrength: 0),
                                           ColorGrade(contrast: .filmic, contrastStrength: 0)]
        let colours: [P] = Self.randomColours(1000) + [P(.nan, 1, .infinity, 1), P(-1, 1e6, 0.5, 2)]
        for grade in neutralGrades {
            XCTAssertTrue(grade.isNeutral, "\(grade) sets no flag")
            for p in colours { XCTAssertEqual(Self.bits(grade.apply(p)), Self.bits(p), "bypass, bit for bit") }
        }
        // With other controls active, Linear equals the grade before FX-005 (same flags, same pixels).
        let fx004 = ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5, hue: 30)
        var withLinear: ColorGrade = fx004
        withLinear.contrast = .sCurve
        withLinear.contrastStrength = 0
        XCTAssertEqual(withLinear.coefficients.flags, fx004.coefficients.flags)
        for p in colours { XCTAssertEqual(Self.bits(withLinear.apply(p)), Self.bits(fx004.apply(p))) }
    }

    // MARK: - US1: shape (S2)

    func testEveryPresetIsMonotoneBoundedAndKeepsTheEnds() {
        let xs: [Double] = Self.sweep()
        for curve in Self.curves {
            for s in Self.strengths {
                XCTAssertEqual(ContrastCurve.value(0, curve: curve, strength: s), 0, "\(curve) \(s): 0 → 0 exactly")
                XCTAssertEqual(ContrastCurve.value(1, curve: curve, strength: s), 1, "\(curve) \(s): 1 → 1 exactly")
                var previous: Double = 0
                var reversals: Int = 0
                for x in xs {
                    let y: Double = ContrastCurve.value(x, curve: curve, strength: s)
                    XCTAssertTrue(y >= 0 && y <= 1, "\(curve) \(s) at \(x): \(y)")
                    if y < previous { reversals += 1 }
                    previous = y
                }
                XCTAssertEqual(reversals, 0, "\(curve) at strength \(s) is monotone over \(xs.count) values")
            }
        }
    }

    func testSCurveAddsContrastAroundMidGreyAndFilmicDiffers() {
        let p: Double = ContrastCurve.pivot
        for s in Self.strengths {
            XCTAssertEqual(ContrastCurve.value(p, curve: .sCurve, strength: s), p, accuracy: 1e-15, "pivot kept")
            XCTAssertLessThan(ContrastCurve.value(0.09, curve: .sCurve, strength: s), 0.09, "shadows darker")
            XCTAssertGreaterThan(ContrastCurve.value(0.5, curve: .sCurve, strength: s), 0.5, "highlights brighter")
            XCTAssertLessThan(ContrastCurve.value(0.02, curve: .filmic, strength: s), 0.02, "filmic toe")
            XCTAssertLessThan(ContrastCurve.value(0.99, curve: .filmic, strength: s), 1, "filmic shoulder below white")
        }
        // Documented values at full strength (research FX-005-D3, D4).
        XCTAssertEqual(ContrastCurve.value(0.09, curve: .sCurve, strength: 1), 0.045, accuracy: 1e-12)
        XCTAssertEqual(ContrastCurve.value(0.5, curve: .sCurve, strength: 1), 1 - 0.82 * pow(0.5 / 0.82, 2), accuracy: 1e-12)
        XCTAssertEqual(ContrastCurve.value(0.18, curve: .filmic, strength: 1), 0.304, accuracy: 0.001)
        let differs: Bool = Self.sweep().contains { (x: Double) -> Bool in
            Swift.abs(ContrastCurve.value(x, curve: .sCurve, strength: 1) - ContrastCurve.value(x, curve: .filmic, strength: 1)) > 0.05
        }
        XCTAssertTrue(differs, "Filmic is distinct from S-curve")
    }

    func testGreysStayGreyThroughTheGrade() {
        for curve in Self.curves {
            let grade = ColorGrade(contrast: curve, contrastStrength: 1)
            for g in [0.0, 0.01, 0.18, 0.5, 0.9, 1, 1.5, 4] {
                let out: P = grade.apply(P(g, g, g, 1))
                XCTAssertEqual(out.x.bitPattern, out.y.bitPattern, "\(curve) grey \(g)")
                XCTAssertEqual(out.y.bitPattern, out.z.bitPattern, "\(curve) grey \(g)")
                XCTAssertEqual(out.y, ContrastCurve.value(min(g, 1), curve: curve, strength: 1), accuracy: 1e-15)
            }
        }
    }

    // MARK: - US3: extremes stay bounded (S3)

    func testExtremeInputsGiveFiniteBoundedOutputs() {
        let extremes: [Double] = [1e6, -1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude, -0.0]
        for curve in ContrastCurve.allCases {
            for s in [0.0, 0.5, 1, .nan, 7, -3] {
                for x in extremes {
                    let y: Double = ContrastCurve.value(x, curve: curve, strength: s)
                    XCTAssertTrue(y.isFinite && y >= 0 && y <= 1, "\(curve) s \(s) x \(x): \(y)")
                }
            }
            let grade = ColorGrade(gain: 2, contrast: curve, contrastStrength: 1)
            let pixels: [P] = [P(1e6, -1, .nan, 1), P(.infinity, -.infinity, 0.5, .nan), P(1e6, 1e6, 1e6, 2)]
            for p in pixels {
                let display: P = ToneMap.map(grade.apply(p))
                for c in 0..<4 { XCTAssertTrue(display[c].isFinite && display[c] >= 0 && display[c] <= 1, "\(curve) \(p): \(display)") }
                if curve != .linear {
                    let graded: P = grade.apply(p)
                    for c in 0..<3 { XCTAssertTrue(graded[c] >= 0 && graded[c] <= 1, "the curve's own output is bounded: \(graded)") }
                    XCTAssertEqual(Self.bits(ToneMap.map(graded)), Self.bits(graded), "the tone map after the curve is identity")
                }
            }
        }
    }

    // MARK: - Values, clamping and decoding

    func testClampingFlagsAndDecoding() throws {
        XCTAssertEqual(ColorGrade.neutral.contrast, .linear)
        XCTAssertEqual(ColorGrade.neutral.contrastStrength, 0.5)
        XCTAssertEqual(ColorGrade(contrastStrength: .nan).clamped.contrastStrength, 0.5)
        XCTAssertEqual(ColorGrade(contrastStrength: 9).clamped.contrastStrength, 1)
        XCTAssertEqual(ColorGrade(contrastStrength: -.infinity).clamped.contrastStrength, 0)
        XCTAssertEqual(ColorGrade(contrast: .sCurve).coefficients.flags, ColorGradeCoefficients.sCurveFlag)
        XCTAssertEqual(ColorGrade(contrast: .filmic, contrastStrength: 9).coefficients.flags, ColorGradeCoefficients.filmicFlag)
        XCTAssertEqual(ColorGrade(contrast: .filmic, contrastStrength: 0.3).coefficients.contrast,
                       SIMD4<Double>(1.3, 0.3, 0.1, 0.5))
        XCTAssertEqual(ContrastCurve(storedName: "sCurve"), .sCurve)
        XCTAssertEqual(ContrastCurve(storedName: "posterize"), .linear)
        XCTAssertEqual(ContrastCurve(storedName: nil), .linear)
        let old: Data = Data(#"{"temperature":0,"lift":0,"gamma":1,"gain":1.2,"saturation":1,"hue":10}"#.utf8)
        let decoded: ColorGrade = try JSONDecoder().decode(ColorGrade.self, from: old)
        XCTAssertEqual(decoded, ColorGrade(gain: 1.2, hue: 10), "a grade saved before FX-005 reads as Linear")
        let graded = ColorGrade(gamma: 1.2, contrast: .filmic, contrastStrength: 0.75)
        XCTAssertEqual(try JSONDecoder().decode(ColorGrade.self, from: try JSONEncoder().encode(graded)), graded)
        let unknown: Data = Data(#"{"temperature":0,"lift":0,"gamma":1,"gain":1,"saturation":1,"contrast":"sepia"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ColorGrade.self, from: unknown).contrast, .linear)
    }
}
