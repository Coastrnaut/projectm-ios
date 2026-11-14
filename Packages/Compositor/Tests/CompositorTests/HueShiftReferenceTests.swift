// FX-004-T03: the plain-Swift reference of the hue step (FX-004-R2 to R5, R8, S3; research FX-004-D1 to D6). CPU only;
// runs on Linux and on the Mac in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE).
import Compositor
import Foundation
import XCTest

final class HueShiftReferenceTests: XCTestCase {
    private typealias P = ToneMap.Pixel

    private static let weights: SIMD3<Double> = ColorGrade.luminanceWeights

    private static func luminance(_ v: SIMD3<Double>) -> Double {
        let w: SIMD3<Double> = weights
        let r: Double = w.x * v.x
        let g: Double = w.y * v.y
        let b: Double = w.z * v.z
        return r + g + b
    }

    private static func rgb(_ p: P) -> SIMD3<Double> { SIMD3<Double>(p.x, p.y, p.z) }

    private static func shifted(_ p: P, _ degrees: Double) -> P {
        ColorGrade(hue: degrees).apply(p)
    }

    private static func assertClose(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ tolerance: Double, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        for c in 0..<3 { XCTAssertEqual(a[c], b[c], accuracy: tolerance, "\(message) channel \(c)", file: file, line: line) }
    }

    // MARK: - The acceptance on the reference: red patch (D6) and greys (D2)

    func testRedPatchReferenceTable() {
        let red = P(1, 0, 0, 1)
        let table: [(degrees: Double, expected: SIMD3<Double>)] = [
            (0, SIMD3(1, 0, 0)),
            (30, SIMD3(0.372852, 0.186426, 0)),
            (90, SIMD3(0.129397, 0.258795, 0)),
            (120, SIMD3(0, 0.2126 / 0.7152, 0)),
            (180, SIMD3(0, 0.270003, 0.270003)),
            (-120, SIMD3(0.1404, 0.1404, 1.1404)),   // = 240° (the range is −180…180)
        ]
        for (degrees, expected) in table {
            let out: P = Self.shifted(red, degrees)
            Self.assertClose(Self.rgb(out), expected, 1e-6, "red at \(degrees)°")
            XCTAssertEqual(Self.luminance(Self.rgb(out)), 0.2126, accuracy: 1e-12, "red's luminance kept at \(degrees)°")
            XCTAssertEqual(out.w, 1)
        }
        // 240° is −120° (T has period 360°; a stored 240 clamps to 180, so the setting uses −120).
        let t240: SIMD4<Double> = ColorGradeCoefficients.hueMatrix(degrees: 240)
        let tMinus120: SIMD4<Double> = ColorGradeCoefficients.hueMatrix(degrees: -120)
        for c in 0..<4 { XCTAssertEqual(t240[c], tMinus120[c], accuracy: 1e-12) }
        XCTAssertEqual(ColorGrade(hue: 240).clamped.hue, 180)
        // 120°: pure green (red and blue 0 to rounding); 240°: its blue tint, displayed (0.15133, 0.15133, 1).
        let green: P = Self.shifted(red, 120)
        XCTAssertEqual(green.x, 0, accuracy: 1e-12)
        XCTAssertEqual(green.z, 0, accuracy: 1e-12)
        let shown: P = ToneMap.map(Self.shifted(red, -120))
        Self.assertClose(Self.rgb(shown), SIMD3(0.151328, 0.151328, 1), 1e-5, "240° displayed")
        // Green → blue and blue → red at +120 (hue only: the differences point at the next primary).
        let blueish: P = Self.shifted(P(0, 1, 0, 1), 120)
        XCTAssertGreaterThan(blueish.z, blueish.x)
        XCTAssertEqual(blueish.x, blueish.y, accuracy: 1e-12, "a tint of blue")
        let reddish: P = Self.shifted(P(0, 0, 1, 1), 120)
        XCTAssertGreaterThan(reddish.x, 0)
        XCTAssertEqual(reddish.y, 0, accuracy: 1e-12)
        XCTAssertEqual(reddish.z, 0, accuracy: 1e-12)
    }

    func testGreysAreFixedPointsBitForBit() {
        let greys: [Double] = [0, 1e-6, 0.01, 0.18, 0.214, 0.5, 0.75, 0.999, 1, 1.5, 2, 4, 1000]
        let angles: [Double] = [-180, -120, -90, -30, -1, 1, 30, 90, 120, 179, 180]
        for degrees in angles {
            let k: ColorGradeCoefficients = ColorGrade(hue: degrees).coefficients
            for x in greys {
                let v = SIMD3<Double>(x, x, x)
                let out: SIMD3<Double> = ColorGradeCoefficients.rotateHue(v, matrix: k.hueMatrix)
                XCTAssertEqual(out.x.bitPattern, x.bitPattern, "grey \(x) at \(degrees)°")
                XCTAssertEqual(out.y.bitPattern, x.bitPattern, "grey \(x) at \(degrees)°")
                XCTAssertEqual(out.z.bitPattern, x.bitPattern, "grey \(x) at \(degrees)°")
                let pixel: P = k.apply(P(x, x, x, 1))
                XCTAssertEqual(pixel, P(x, x, x, 1), "through apply")
            }
        }
    }

    func testGreysAreFixedPointsInFloatToo() {
        // The shader's arithmetic in Float: differences are exactly 0, so y = g and every channel equals g.
        let angles: [Double] = [30, 90, 180, -120]
        for degrees in angles {
            let t: SIMD4<Double> = ColorGradeCoefficients.hueMatrix(degrees: degrees)
            let tf = SIMD4<Float>(Float(t.x), Float(t.y), Float(t.z), Float(t.w))
            for i in 0...64 {
                let x: Float = Float(i) / 16
                let d1: Float = x - x
                let d2: Float = x - x
                let y: Float = x + 0.2126 * d1 + 0.0722 * d2
                let e1: Float = tf.x * d1 + tf.y * d2
                let e2: Float = tf.z * d1 + tf.w * d2
                let g: Float = y - 0.2126 * e1 - 0.0722 * e2
                XCTAssertEqual((g + e1).bitPattern, x.bitPattern)
                XCTAssertEqual(g.bitPattern, x.bitPattern)
                XCTAssertEqual((g + e2).bitPattern, x.bitPattern)
            }
        }
    }

    // MARK: - Luminance (R3, S3) and the matrix (D1)

    func testLuminanceKeptOverSampledColoursAndAngles() {
        var random = GradeTestRandom(seed: 0xF4_0004)
        var worst: Double = 0
        var greysExact: Int = 0
        for i in 0..<10_000 {
            let degrees: Double = random.uniform(-180...180)
            let k: ColorGradeCoefficients = ColorGrade(hue: degrees).coefficients
            let v: SIMD3<Double>
            if i % 10 == 0 {
                let x: Double = random.uniform(0...4)
                v = SIMD3(x, x, x)
            } else {
                v = SIMD3(random.uniform(0...2), random.uniform(0...2), random.uniform(0...2))
            }
            let out: SIMD3<Double> = ColorGradeCoefficients.rotateHue(v, matrix: k.hueMatrix)
            let error: Double = Swift.abs(Self.luminance(out) - Self.luminance(v))
            worst = max(worst, error)
            XCTAssertGreaterThanOrEqual(min(out.x, min(out.y, out.z)), 0, "never negative")
            if v.x == v.y && v.y == v.z {
                XCTAssertEqual(out, v, "grey \(v) at \(degrees)°")
                greysExact += 1
            }
        }
        XCTAssertLessThanOrEqual(worst, 1e-9, "luminance kept (FX-004-S3)")
        XCTAssertEqual(greysExact, 1000)
    }

    func testMatrixRowsSumToOneAndKeepLuminance() {
        for degrees in [17.0, 90, 120, 240, -45] {
            let k: SIMD4<Double> = ColorGradeCoefficients.hueMatrix(degrees: degrees)
            XCTAssertEqual(k.x * k.w - k.y * k.z, 1, accuracy: 1e-12, "det T = 1")
            // Columns of M before the gamut step: the (linear) image of each primary, computed without clamping.
            var columns: [SIMD3<Double>] = []
            for e in [SIMD3<Double>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
                let w: SIMD3<Double> = Self.weights
                let d1: Double = e.x - e.y
                let d2: Double = e.z - e.y
                let y: Double = e.y + w.x * d1 + w.z * d2
                let e1: Double = k.x * d1 + k.y * d2
                let e2: Double = k.z * d1 + k.w * d2
                let g: Double = y - w.x * e1 - w.z * e2
                columns.append(SIMD3(g + e1, g, g + e2))
            }
            for row in 0..<3 {
                let sum: Double = columns[0][row] + columns[1][row] + columns[2][row]
                XCTAssertEqual(sum, 1, accuracy: 1e-12, "row \(row) at \(degrees)°")
            }
            for col in 0..<3 {
                XCTAssertEqual(Self.luminance(columns[col]), Self.weights[col], accuracy: 1e-12, "wᵀM = wᵀ, column \(col)")
            }
        }
        // M(120°)'s first column (red's image) as documented in research D1: (−0.5026, 0.4974, −0.5026).
        let k120: SIMD4<Double> = ColorGradeCoefficients.hueMatrix(degrees: 120)
        Self.assertClose(SIMD3(k120.x, k120.y, k120.z), SIMD3(-1, 1, -1), 1e-12, "T(120°)")
        XCTAssertEqual(k120.w, 0, accuracy: 1e-12)
    }

    func testPlusAndMinus180AreTheSame() {
        let colours: [P] = [P(1, 0, 0, 1), P(0.2, 0.6, 0.1, 1), P(0.9, 0.3, 0.7, 1)]
        for p in colours {
            Self.assertClose(Self.rgb(Self.shifted(p, 180)), Self.rgb(Self.shifted(p, -180)), 1e-12, "\(p)")
        }
    }

    // MARK: - Hue 0 is FX-003 (R5) and composition (D4)

    func testHueZeroLeavesTheFlagOffAndFX003Unchanged() {
        XCTAssertEqual(ColorGrade(hue: 0).coefficients.flags, 0)
        XCTAssertTrue(ColorGrade(hue: 0).isNeutral)
        XCTAssertEqual(ColorGrade(hue: 30).coefficients.flags, ColorGradeCoefficients.hueFlag)
        XCTAssertFalse(ColorGrade(hue: 0.5).isNeutral)
        let fx003 = ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5)
        XCTAssertEqual(fx003.coefficients.flags, 31)
        XCTAssertEqual(fx003.coefficients.hueMatrix, SIMD4<Double>(1, 0, 0, 1))
        // FX-003's hand-checked value (ColorGradeReferenceTests): gain 2 on (0.25, 0.5, 0.75) is (0.5, 1, 1.5).
        XCTAssertEqual(ColorGrade(gain: 2, hue: 0).apply(P(0.25, 0.5, 0.75, 1)), P(0.5, 1, 1.5, 1))
    }

    func testHueCommutesWithSaturationAwayFromTheClamps() {
        // In-gamut colours and a moderate saturation: hue then saturation equals saturation then hue (D4).
        let colours: [P] = [P(0.5, 0.4, 0.45, 1), P(0.3, 0.35, 0.32, 1), P(0.6, 0.55, 0.5, 1)]
        for p in colours {
            let both: P = ColorGrade(saturation: 1.3, hue: 40).apply(p)
            let saturated: P = ColorGrade(saturation: 1.3).apply(p)
            let thenHue: P = Self.shifted(saturated, 40)
            Self.assertClose(Self.rgb(both), Self.rgb(thenHue), 1e-12, "grade order")
            let hueFirst: P = Self.shifted(p, 40)
            let thenSaturation: P = ColorGrade(saturation: 1.3).apply(hueFirst)
            Self.assertClose(Self.rgb(both), Self.rgb(thenSaturation), 1e-12, "commutes for \(p)")
        }
    }

    func testCompositionWithEveryOperator() {
        let grade = ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5, hue: 60)
        XCTAssertEqual(grade.coefficients.flags, 63)
        let p = P(0.3, 0.2, 0.1, 0.8)
        let firstFive = ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5)
        let expected: P = Self.shifted(firstFive.apply(p), 60)
        XCTAssertEqual(grade.apply(p), expected, "hue runs last, after the five FX-003 operators")
        XCTAssertEqual(grade.apply(p).w, 0.8, "alpha unchanged")
        XCTAssertEqual(Self.luminance(Self.rgb(grade.apply(p))), Self.luminance(Self.rgb(firstFive.apply(p))), accuracy: 1e-12)
        // Saturation 0 makes grey, which the hue step leaves untouched.
        let grey: P = ColorGrade(saturation: 0, hue: 120).apply(P(0.8, 0.1, 0.3, 1))
        XCTAssertEqual(grey.x, grey.y)
        XCTAssertEqual(grey.y, grey.z)
        // Non-finite input is sanitised before the hue step.
        let nan: P = Self.shifted(P(.nan, 0.5, 0.5, 1), 90)
        XCTAssertEqual(nan, Self.shifted(P(0, 0.5, 0.5, 1), 90), "NaN → 0 first")
        XCTAssertTrue(nan.x.isFinite && nan.y.isFinite && nan.z.isFinite)
    }

    // MARK: - Value rules (R8)

    func testClampingAndDecoding() throws {
        XCTAssertEqual(ColorGrade(hue: 400).clamped.hue, 180)
        XCTAssertEqual(ColorGrade(hue: -.infinity).clamped.hue, -180)
        XCTAssertEqual(ColorGrade(hue: .nan).clamped.hue, 0)
        XCTAssertEqual(ColorGrade.neutral.hue, 0)
        let old: Data = Data(#"{"temperature":0.1,"lift":0,"gamma":1,"gain":1,"saturation":1}"#.utf8)
        let decoded: ColorGrade = try JSONDecoder().decode(ColorGrade.self, from: old)
        XCTAssertEqual(decoded, ColorGrade(temperature: 0.1), "a grade from before FX-004 decodes with hue 0")
        let round: ColorGrade = try JSONDecoder().decode(ColorGrade.self, from: try JSONEncoder().encode(ColorGrade(hue: -42)))
        XCTAssertEqual(round.hue, -42)
    }
}
