// FX-004-T05, T10, T12: the hue step on the GPU (FX-004-S1, S2, S4, S5). The roadmap acceptance: "Gray ramp stays
// neutral and red test patch rotates predictably". Composites go through the real `cmp_output` (`OutputPassRig`) in
// both output formats (half float and the sRGB screen format) and are compared with the plain-Swift reference
// (`ColorGrade.apply` then `ToneMap.map`) and with the hue-0 output. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class HueShiftOutputTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667
    private static let formats: [MTLPixelFormat] = [.rgba16Float, .bgra8Unorm_srgb]

    private static func tolerance(_ format: MTLPixelFormat) -> Double {
        format == .rgba16Float ? 0.002 : 1.0 / 255 + 1e-6
    }

    /// The grey ramp: 0…1 in 33 steps, then over-range greys 1.25, 1.5, 2, 4.
    static func greyRamp() -> [SIMD4<Float>] {
        var pixels: [SIMD4<Float>] = []
        for i in 0...32 {
            let x: Float = Float(i) / 32
            pixels.append(SIMD4<Float>(x, x, x, 1))
        }
        for x: Float in [1.25, 1.5, 2, 4] { pixels.append(SIMD4<Float>(x, x, x, 1)) }
        return pixels
    }

    private static func halfRounded(_ p: SIMD4<Float>) -> SIMD4<Double> {
        SIMD4<Double>(Double(Float(Float16(p.x))), Double(Float(Float16(p.y))), Double(Float(Float16(p.z))), Double(Float(Float16(p.w))))
    }

    /// The reference displayed value in the target's encoding (linear for half float, sRGB-encoded for the screen).
    private static func expected(_ p: SIMD4<Float>, _ grade: ColorGrade, _ format: MTLPixelFormat) -> SIMD4<Double> {
        let linear: SIMD4<Double> = ToneMap.map(grade.apply(halfRounded(p)))
        if format == .rgba16Float { return linear }
        return SIMD4<Double>(LayerBlend.encode(linear.x), LayerBlend.encode(linear.y), LayerBlend.encode(linear.z), linear.w)
    }

    private static func worst(_ gpu: SIMD4<Float>, _ reference: SIMD4<Double>) -> Double {
        var worst: Double = 0
        for c in 0..<4 {
            let d: Double = Swift.abs(Double(gpu[c]) - reference[c])
            worst = d.isNaN ? .infinity : max(worst, d)
        }
        return worst
    }

    // MARK: - US1: the acceptance (T05)

    func testGreyRampStaysNeutralAtEveryAngle() throws {
        let passes = try OutputPassRig()
        let ramp: [SIMD4<Float>] = Self.greyRamp()
        let composite: MTLTexture = try passes.composite(ramp)
        var report: [String] = []
        for format in Self.formats {
            let unshifted: [SIMD4<Float>] = try passes.output(composite, format: format, grade: .neutral)
            for degrees in [30.0, 90, 180, -120] {
                let out: [SIMD4<Float>] = try passes.output(composite, format: format, grade: ColorGrade(hue: degrees))
                var maxSpread: Float = 0
                var maxDrift: Float = 0
                var identical: Int = 0
                for i in ramp.indices {
                    let p: SIMD4<Float> = out[i]
                    let spread: Float = max(p.x, max(p.y, p.z)) - min(p.x, min(p.y, p.z))
                    maxSpread = max(maxSpread, spread)
                    XCTAssertEqual(p.x.bitPattern, p.y.bitPattern, "format \(format.rawValue), \(degrees)°, grey \(ramp[i].x): \(p)")
                    XCTAssertEqual(p.y.bitPattern, p.z.bitPattern, "format \(format.rawValue), \(degrees)°, grey \(ramp[i].x): \(p)")
                    let drift: Float = Swift.abs(p.y - unshifted[i].y)
                    maxDrift = max(maxDrift, drift)
                    if p == unshifted[i] { identical += 1 }
                }
                XCTAssertEqual(maxSpread, 0, "neutral: spread exactly 0 (FX-004-S1)")
                XCTAssertLessThanOrEqual(Double(maxDrift), Self.tolerance(format), "grey value kept")
                report.append("format \(format.rawValue) \(degrees)°: max spread \(maxSpread), max drift vs hue 0 \(maxDrift), "
                              + "\(identical)/\(ramp.count) bit-identical to hue 0")
            }
        }
        print("FX-004 grey ramp (\(ramp.count) greys incl. over-range):\n  " + report.joined(separator: "\n  "))
    }

    func testRedPatchRotatesPredictably() throws {
        let passes = try OutputPassRig()
        let red: [SIMD4<Float>] = [SIMD4<Float>(1, 0, 0, 1)]
        let composite: MTLTexture = try passes.composite(red)
        // Research FX-004-D6 (linear, displayed): 0° red; 120° (0, wR/wG, 0); 240° = −120° (0.15133, 0.15133, 1).
        let documented: [(degrees: Double, linear: SIMD3<Double>)] = [
            (0, SIMD3(1, 0, 0)), (120, SIMD3(0, 0.2126 / 0.7152, 0)), (-120, SIMD3(0.151328, 0.151328, 1)),
        ]
        var report: [String] = []
        for (degrees, linear) in documented {
            let grade = ColorGrade(hue: degrees)
            let reference: SIMD4<Double> = Self.expected(red[0], grade, .rgba16Float)
            for c in 0..<3 { XCTAssertEqual(reference[c], linear[c], accuracy: 1e-5, "reference = D6 at \(degrees)°") }
            for format in Self.formats {
                let gpu: SIMD4<Float> = try passes.output(composite, format: format, grade: grade)[0]
                let error: Double = Self.worst(gpu, Self.expected(red[0], grade, format))
                XCTAssertLessThanOrEqual(error, Self.tolerance(format), "red at \(degrees)°, format \(format.rawValue): \(gpu)")
                report.append(String(format: "%.0f° format %lu: GPU (%.5f, %.5f, %.5f), error %.6f", degrees, format.rawValue,
                                     gpu.x, gpu.y, gpu.z, error))
            }
        }
        print("FX-004 red patch:\n  " + report.joined(separator: "\n  "))
    }

    func testMixedImageMatchesTheReferenceWithOtherOperators() throws {
        let passes = try OutputPassRig()
        let image: [SIMD4<Float>] = ColorGradeOutputTests.referenceImage()
        let composite: MTLTexture = try passes.composite(image)
        let grades: [ColorGrade] = [ColorGrade(hue: 30), ColorGrade(hue: -150),
                                    ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5, hue: 30)]
        for grade in grades {
            for format in Self.formats {
                let gpu: [SIMD4<Float>] = try passes.output(composite, format: format, grade: grade)
                var worst: Double = 0
                for i in image.indices { worst = max(worst, Self.worst(gpu[i], Self.expected(image[i], grade, format))) }
                XCTAssertLessThanOrEqual(worst, Self.tolerance(format), "\(grade), format \(format.rawValue)")
            }
        }
    }

    // MARK: - US2: hue 0 is FX-003 (T10)

    func testHueZeroIsBitIdenticalToFX003() throws {
        let passes = try OutputPassRig()
        let image: [SIMD4<Float>] = ColorGradeOutputTests.referenceImage()
        let composite: MTLTexture = try passes.composite(image)
        let fx003 = ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5)
        for format in Self.formats {
            let withHueZero: [SIMD4<Float>] = try passes.output(composite, format: format, grade: ColorGrade(hue: 0))
            let neutral: [SIMD4<Float>] = try passes.output(composite, format: format, grade: .neutral)
            XCTAssertEqual(withHueZero.map(\.bitPatterns), neutral.map(\.bitPatterns), "hue 0 alone = bypass")
            var grade: ColorGrade = fx003
            grade.hue = 0
            let a: [SIMD4<Float>] = try passes.output(composite, format: format, grade: grade)
            let b: [SIMD4<Float>] = try passes.output(composite, format: format, grade: fx003)
            XCTAssertEqual(a.map(\.bitPatterns), b.map(\.bitPatterns), "hue 0 with other controls = FX-003's grade")
            XCTAssertEqual(CompositorShaders.GradeBlock(grade.coefficients), CompositorShaders.GradeBlock(fx003.coefficients))
        }
    }

    // MARK: - US3: the limiter measures the shifted colour (T12)

    private func minimumGain(low: Pixel, high: Pixel, grade: ColorGrade) throws -> Float {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let layer = StrobeLayer()
        layer.color = { (i: Int) -> Pixel in i % 2 == 0 ? high : low }
        let compositor = try Compositor(device: rig.device, layers: [layer])
        compositor.colorGrade = grade
        let output: MTLTexture = try passes.target(.rgba16Float, width: 16, height: 16)
        var minimum: Float = 1
        for i in 0..<60 {
            try rig.frame(compositor, into: output, time: 1_000_000_000 + UInt64(i) * Self.frameNanoseconds)
            minimum = min(minimum, compositor.lastFlashGain)
        }
        return minimum
    }

    func testFlashLimiterMeasuresTheShiftedColour() throws {
        let black = Pixel(0, 0, 0, 1)
        // A black ↔ white strobe: the shift keeps greys, so it is limited exactly as without it.
        let white = Pixel(1, 1, 1, 1)
        let greyPlain: Float = try minimumGain(low: black, high: white, grade: .neutral)
        let greyShifted: Float = try minimumGain(low: black, high: white, grade: ColorGrade(hue: 120))
        XCTAssertLessThan(greyShifted, 1)
        XCTAssertEqual(greyShifted, greyPlain, "greys are unchanged, so the limiter acts identically")
        // A black ↔ blue flicker: luminance step 0.0722 (under 0.1) and no redness, so never limited. Turned by +120°
        // (blue → red) it keeps its luminance but becomes pure red (wB/wR, 0, 0) = (0.3396, 0, 0), a red flash
        // (redness 0.34 against the 0.0625 threshold) that the limiter must catch.
        let blue = Pixel(0, 0, 1, 1)
        let bluePlain: Float = try minimumGain(low: black, high: blue, grade: .neutral)
        XCTAssertEqual(bluePlain, 1, "a sub-threshold blue flicker is not limited")
        let blueToRed: Float = try minimumGain(low: black, high: blue, grade: ColorGrade(hue: 120))
        XCTAssertLessThan(blueToRed, 1, "the shifted flicker is a red flash and is limited")
        print("FX-004 limiter: black↔white plain \(greyPlain), hue 120° \(greyShifted); black↔blue plain \(bluePlain), "
              + "hue 120° (red) \(blueToRed)")
    }
}

private extension SIMD4 where Scalar == Float {
    var bitPatterns: SIMD4<UInt32> { SIMD4<UInt32>(x.bitPattern, y.bitPattern, z.bitPattern, w.bitPattern) }
}
#endif
