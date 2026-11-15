// FX-013-T06, T08: posterization on the GPU (FX-013-S4, S5; R2, R4 to R6). A known horizontal gradient goes through
// the real `cmp_output` (`OutputPassRig`) in both output formats (half float and the sRGB screen format); the distinct
// values per channel are counted (the roadmap acceptance: "Known gradient contains at most configured levels without
// dithering") and the level of every pixel is compared with the plain-Swift reference (`ColorGrade.apply(_:x:y:)`).
// Off is bit-identical; the external-display calibration (OUT-009) and the flash guard are covered. Skipped without
// a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class PosterizeOutputTests: XCTestCase {
    private static let formats: [MTLPixelFormat] = [.rgba16Float, .bgra8Unorm_srgb]
    private static let width: Int = 1024
    private static let frameNanoseconds: UInt64 = 16_666_667

    /// The known gradient: red 0…1.05 left to right (a little above white at the right end), green x², blue 1 − x, so
    /// each channel sweeps its own ramp.
    private static func gradient() -> [SIMD4<Float>] {
        (0..<width).map { (i: Int) -> SIMD4<Float> in
            let x: Float = Float(i) / Float(width - 1)
            let r: Float = x * 1.05
            let g: Float = x * x
            let b: Float = 1 - x
            return SIMD4<Float>(r, g, b, 1)
        }
    }

    private static func halfRounded(_ p: SIMD4<Float>) -> SIMD4<Double> {
        SIMD4<Double>(Double(Float(Float16(p.x))), Double(Float(Float16(p.y))), Double(Float(Float16(p.z))), Double(Float(Float16(p.w))))
    }

    /// The level index of one output channel: half floats are linear, 8-bit values are already sRGB-encoded.
    private static func level(_ value: Float, format: MTLPixelFormat, levels: Int) -> Int {
        let n: Double = Double(levels - 1)
        if format == .rgba16Float { return Posterize.levelIndex(Double(value), levels: levels, threshold: 0.5) }
        let scaled: Double = Double(value) * n
        return Int(scaled.rounded())
    }

    private static func distinctCounts(_ pixels: [SIMD4<Float>]) -> [Int] {
        (0..<3).map { (c: Int) -> Int in Set(pixels.map { (p: SIMD4<Float>) -> UInt32 in p[c].bitPattern }).count }
    }

    /// Compares GPU levels with the reference at each pixel: returns (matching channels, total channels, worst gap).
    private static func compare(_ gpu: [SIMD4<Float>], _ image: [SIMD4<Float>], grade: ColorGrade,
                                format: MTLPixelFormat) -> (Int, Int, Int) {
        var same = 0
        var total = 0
        var worst = 0
        for i in image.indices {
            let reference: SIMD4<Double> = grade.apply(halfRounded(image[i]), x: i, y: 0)
            for c in 0..<3 {
                let expected: Int = Posterize.levelIndex(reference[c], levels: grade.posterizeLevels, threshold: 0.5)
                let actual: Int = level(gpu[i][c], format: format, levels: grade.posterizeLevels)
                total += 1
                if expected == actual { same += 1 }
                worst = max(worst, abs(expected - actual))
            }
        }
        return (same, total, worst)
    }

    // MARK: - US1: the acceptance on the GPU (S5)

    func testKnownGradientHasAtMostTheConfiguredLevelsAndMatchesTheReference() throws {
        let passes = try OutputPassRig()
        let image: [SIMD4<Float>] = Self.gradient()
        let composite: MTLTexture = try passes.composite(image)
        var report: [String] = []
        for levels in [2, 6, 32] {
            for dither in [false, true] {
                let grade = ColorGrade(posterize: true, posterizeLevels: levels, posterizeDither: dither)
                for format in Self.formats {
                    let gpu: [SIMD4<Float>] = try passes.output(composite, format: format, grade: grade)
                    let counts: [Int] = Self.distinctCounts(gpu)
                    for count in counts { XCTAssertLessThanOrEqual(count, levels, "L \(levels) dither \(dither) format \(format.rawValue)") }
                    // Red and green sweep 0…1 completely; blue's dark end is lifted by FX-002's step where red > 1.
                    if !dither { XCTAssertEqual(Array(counts.prefix(2)), [levels, levels], "the full ramps reach every level") }
                    let (same, total, worst) = Self.compare(gpu, image, grade: grade, format: format)
                    XCTAssertLessThanOrEqual(worst, 1, "within one level everywhere")
                    XCTAssertGreaterThanOrEqual(Double(same), 0.99 * Double(total), "GPU levels = reference levels")
                    report.append("L \(levels) dither \(dither) format \(format.rawValue): counts \(counts), same \(same)/\(total)")
                }
            }
        }
        print("FX-013 GPU gradient (\(image.count) pixels):\n  " + report.joined(separator: "\n  "))
    }

    // MARK: - US3: off is bit-identical (S2 on the GPU)

    func testOffIsBitIdenticalToTheOutputWithoutPosterize() throws {
        let passes = try OutputPassRig()
        let composite: MTLTexture = try passes.composite(ColorGradeOutputTests.referenceImage())
        let others = ColorGrade(temperature: 0.4, gamma: 1.3, hue: 30, contrast: .sCurve, contrastStrength: 0.5)
        var off: ColorGrade = others
        off.posterizeLevels = 2
        off.posterizeDither = true
        for format in Self.formats {
            let plain: [SIMD4<Float>] = try passes.output(composite, format: format, grade: .neutral)
            let neutralOff: [SIMD4<Float>] = try passes.output(composite, format: format,
                                                               grade: ColorGrade(posterizeLevels: 3, posterizeDither: true))
            XCTAssertEqual(neutralOff.map(\.posterBits), plain.map(\.posterBits), "off alone = bypass")
            let a: [SIMD4<Float>] = try passes.output(composite, format: format, grade: off)
            let b: [SIMD4<Float>] = try passes.output(composite, format: format, grade: others)
            XCTAssertEqual(a.map(\.posterBits), b.map(\.posterBits), "off with other controls = the grade without FX-013")
        }
    }

    // MARK: - Edge case: OUT-009's calibration after the grade keeps at most L values

    func testCalibratedOutputKeepsAtMostTheConfiguredLevels() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let library: MTLLibrary = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source)
        let vertex: MTLFunction = try CompositorShaders.function(library, "cmp_fullscreen")
        let fragment: MTLFunction = try CompositorShaders.function(library, "cmp_output_calibrated")
        let pipeline = try CompositorShaders.pipeline(device: rig.device, vertex: vertex, fragment: fragment,
                                                      format: .rgba16Float, blendOver: false, label: "FX-013 test calibrated")
        let composite: MTLTexture = try passes.composite(Self.gradient())
        let target: MTLTexture = try passes.target(.rgba16Float, width: composite.width, height: 1)
        var gain: Float = 1
        var zero: UInt32 = 0
        let gainBuffer = try XCTUnwrap(rig.device.makeBuffer(bytes: &gain, length: 4, options: .storageModeShared))
        let counter = try XCTUnwrap(rig.device.makeBuffer(bytes: &zero, length: 4, options: .storageModeShared))
        var calibration = CompositorShaders.CalibrationBlock(DisplayCalibration(gamma: 1.4, red: 0.9, green: 1.1, blue: 1))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.setFragmentBuffer(gainBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(counter, offset: 0, index: 1)
        Compositor.bindGrade(CompositorShaders.GradeBlock(ColorGrade(posterize: true, posterizeLevels: 4).coefficients), encoder)
        encoder.setFragmentBytes(&calibration, length: MemoryLayout<CompositorShaders.CalibrationBlock>.size, index: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
        for count in Self.distinctCounts(passes.readRaw(target)) { XCTAssertLessThanOrEqual(count, 4) }
    }

    // MARK: - US3: the limiter measures the posterized picture

    func testFlashLimiterStillActsWithPosterize() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        for dither in [false, true] {
            let layer = StrobeLayer()
            layer.color = { (i: Int) -> Pixel in i % 2 == 0 ? Pixel(1, 1, 1, 1) : Pixel(0, 0, 0, 1) }
            let compositor = try Compositor(device: rig.device, layers: [layer])
            compositor.colorGrade = ColorGrade(posterize: true, posterizeLevels: 2, posterizeDither: dither)
            let output: MTLTexture = try passes.target(.rgba16Float, width: 16, height: 16)
            var minimum: Float = 1
            for i in 0..<60 {
                try rig.frame(compositor, into: output, time: 1_000_000_000 + UInt64(i) * Self.frameNanoseconds)
                minimum = min(minimum, compositor.lastFlashGain)
            }
            XCTAssertLessThan(minimum, 1, "a black ↔ white strobe is still limited (dither \(dither))")
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var posterBits: SIMD4<UInt32> { SIMD4<UInt32>(x.bitPattern, y.bitPattern, z.bitPattern, w.bitPattern) }
}
#endif
