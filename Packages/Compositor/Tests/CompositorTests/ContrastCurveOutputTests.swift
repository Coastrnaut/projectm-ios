// FX-005-T06, T11, T12: the contrast curves on the GPU (FX-005-S2 to S4; R6). Composites go through the real
// `cmp_output` (`OutputPassRig`) in both output formats (half float and the sRGB screen format) and are compared with
// the plain-Swift reference (`ColorGrade.apply` then `ToneMap.map`), with the output without the curve (Linear must be
// bit-identical), and through the compositor in FX-020's Color-before-Trails order (the curve applies once). Skipped
// without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class ContrastCurveOutputTests: XCTestCase {
    private static let formats: [MTLPixelFormat] = [.rgba16Float, .bgra8Unorm_srgb]
    private static let frameNanoseconds: UInt64 = 16_666_667

    private static func tolerance(_ format: MTLPixelFormat) -> Double {
        format == .rgba16Float ? 0.002 : 1.0 / 255 + 1e-6
    }

    private static func halfRounded(_ p: SIMD4<Float>) -> SIMD4<Double> {
        SIMD4<Double>(Double(Float(Float16(p.x))), Double(Float(Float16(p.y))), Double(Float(Float16(p.z))), Double(Float(Float16(p.w))))
    }

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

    // MARK: - US1: each preset matches the reference (S4)

    func testPresetsMatchTheReferenceOnRampsColoursAndExtremes() throws {
        let passes = try OutputPassRig()
        let image: [SIMD4<Float>] = ColorGradeOutputTests.referenceImage()   // ramps, swatches, greys, HDR, NaN/Inf
        let composite: MTLTexture = try passes.composite(image)
        let grades: [ColorGrade] = [ColorGrade(contrast: .sCurve, contrastStrength: 1),
                                    ColorGrade(contrast: .sCurve, contrastStrength: 0.25),
                                    ColorGrade(contrast: .filmic, contrastStrength: 1),
                                    ColorGrade(temperature: 0.4, gamma: 1.3, gain: 1.4, hue: 30, contrast: .filmic, contrastStrength: 0.5)]
        var report: [String] = []
        for grade in grades {
            for format in Self.formats {
                let gpu: [SIMD4<Float>] = try passes.output(composite, format: format, grade: grade)
                var worst: Double = 0
                for i in image.indices {
                    let p: SIMD4<Float> = gpu[i]
                    XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite && p.w.isFinite, "finite: \(image[i]) → \(p)")
                    worst = max(worst, Self.worst(p, Self.expected(image[i], grade, format)))
                }
                XCTAssertLessThanOrEqual(worst, Self.tolerance(format), "\(grade.contrast) \(grade.contrastStrength), format \(format.rawValue)")
                report.append("\(grade.contrast) s \(grade.contrastStrength) format \(format.rawValue): worst \(worst)")
            }
        }
        print("FX-005 GPU vs reference (\(image.count) pixels):\n  " + report.joined(separator: "\n  "))
    }

    // MARK: - US2: Linear is bit-identical (S4)

    func testLinearIsBitIdenticalToTheOutputWithoutTheCurve() throws {
        let passes = try OutputPassRig()
        let composite: MTLTexture = try passes.composite(ColorGradeOutputTests.referenceImage())
        let fx004 = ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5, hue: 30)
        for format in Self.formats {
            let neutral: [SIMD4<Float>] = try passes.output(composite, format: format, grade: .neutral)
            for linear in [ColorGrade(contrast: .linear, contrastStrength: 1), ColorGrade(contrast: .filmic, contrastStrength: 0)] {
                let out: [SIMD4<Float>] = try passes.output(composite, format: format, grade: linear)
                XCTAssertEqual(out.map(\.bitPatterns), neutral.map(\.bitPatterns), "Linear alone = bypass")
            }
            var graded: ColorGrade = fx004
            graded.contrast = .sCurve
            graded.contrastStrength = 0
            let a: [SIMD4<Float>] = try passes.output(composite, format: format, grade: graded)
            let b: [SIMD4<Float>] = try passes.output(composite, format: format, grade: fx004)
            XCTAssertEqual(a.map(\.bitPatterns), b.map(\.bitPatterns), "strength 0 with other controls = the grade without FX-005")
        }
    }

    // MARK: - R6: the curve applies once in FX-020's Color-before-Trails order

    private func steadyFrame(order: OutputEffectOrder, grade: ColorGrade) throws -> [Pixel] {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("scene", color: Pixel(0.6, 0.3, 0.1, 1))])
        compositor.outputEffectOrder = order
        compositor.motionFeedback = MotionFeedback(isEnabled: true, halfLifeSeconds: 0.3)
        compositor.colorGrade = grade
        let output = try rig.output(.rgba16Float, width: 16, height: 8)
        for k in 0..<3 {
            XCTAssertTrue(try rig.frame(compositor, into: output, time: 1_000_000_000 + UInt64(k) * Self.frameNanoseconds))
        }
        XCTAssertEqual(compositor.gradePassFrames, order.gradeBeforeTrails ? 3 : 0)
        return try rig.read(output)
    }

    func testColorBeforeTrailsAppliesTheCurveOnce() throws {
        let grade = ColorGrade(contrast: .sCurve, contrastStrength: 1)
        let standard: [Pixel] = try steadyFrame(order: .standard, grade: grade)
        let colorFirst: [Pixel] = try steadyFrame(order: OutputEffectOrder([.grade, .trails]), grade: grade)
        let reference: SIMD4<Double> = ToneMap.map(grade.apply(Self.halfRounded(Pixel(0.6, 0.3, 0.1, 1))))
        for p in [standard[0], colorFirst[0]] {
            XCTAssertLessThanOrEqual(Self.worst(p, reference), 0.002, "a steady colour shows the curve once: \(p) vs \(reference)")
        }
    }

    // MARK: - US3: the limiter measures the curved picture

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

    func testFlashLimiterStillActsWithACurve() throws {
        let black = Pixel(0, 0, 0, 1)
        let white = Pixel(1, 1, 1, 1)
        let plain: Float = try minimumGain(low: black, high: white, grade: .neutral)
        for curve in [ContrastCurve.sCurve, .filmic] {
            let curved: Float = try minimumGain(low: black, high: white, grade: ColorGrade(contrast: curve, contrastStrength: 1))
            XCTAssertLessThan(curved, 1, "\(curve): a black ↔ white strobe is still limited")
            XCTAssertEqual(curved, plain, accuracy: 1e-6, "\(curve) keeps black and white, so the limiter acts as without it")
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var bitPatterns: SIMD4<UInt32> { SIMD4<UInt32>(x.bitPattern, y.bitPattern, z.bitPattern, w.bitPattern) }
}
#endif
