// FX-003-T06, T07, T09, T18, T19: the colour grade on the GPU (FX-003-S1, S2, S4, S7). The research D8 reference image
// goes through the real `cmp_output` on a hand-filled composite (`OutputPassRig`); results are compared with the
// FX-002 output pass without grading (bypass) and with `ColorGrade.apply` then `ToneMap.map` (the plain-Swift
// references). Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import Metal
import XCTest

final class ColorGradeOutputTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667
    private static let width = 64
    private static let rows = 8

    /// FX-003-D8: rows 0–3 ramps 0…1 (grey, red, green, blue); 4 primaries, secondaries, black, white; 5 fixed greys;
    /// 6 an over-range grey ramp 0…4; 7 NaN, ±Inf, negatives and alpha edge values. One row of 64 × 8 pixels.
    static func referenceImage() -> [SIMD4<Float>] {
        var pixels: [SIMD4<Float>] = []
        let w: Int = width
        let ramps: [SIMD3<Float>] = [SIMD3(1, 1, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        for hue in ramps {
            for x in 0..<w {
                let t: Float = Float(x) / Float(w - 1)
                pixels.append(SIMD4<Float>(t * hue.x, t * hue.y, t * hue.z, 1))
            }
        }
        let swatches: [SIMD4<Float>] = [SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1), SIMD4(0, 0, 1, 1), SIMD4(0, 1, 1, 1),
                                        SIMD4(1, 0, 1, 1), SIMD4(1, 1, 0, 1), SIMD4(0, 0, 0, 1), SIMD4(1, 1, 1, 1)]
        for x in 0..<w { pixels.append(swatches[x % swatches.count]) }
        let greys: [Float] = [0, 0.01, 0.05, 0.18, 0.214, 0.5, 0.75, 0.9]
        for x in 0..<w {
            let g: Float = greys[x % greys.count]
            pixels.append(SIMD4<Float>(g, g, g, 1))
        }
        for x in 0..<w {
            let t: Float = 4 * Float(x) / Float(w - 1)
            pixels.append(SIMD4<Float>(t, t * 0.6, t * 0.3, 1))
        }
        let specials: [SIMD4<Float>] = [SIMD4(.nan, 0.5, 0.5, 1), SIMD4(.infinity, 0.5, 0.5, 1), SIMD4(-.infinity, 0.2, 0.1, 1),
                                        SIMD4(-0.5, 0.5, 0.5, 1), SIMD4(0.5, 0.5, 0.5, .nan), SIMD4(0.5, 0.5, 0.5, 2),
                                        SIMD4(0.3, 0.2, 0.1, 0.5), SIMD4(0, 0, 0, 0)]
        for x in 0..<w { pixels.append(specials[x % specials.count]) }
        return pixels
    }

    /// The FX-002 output pass as it was before FX-003 (no grade), compiled beside the real source for the bypass.
    private static let bypassSource = """

    fragment float4 cmp_output_bypass(FullScreenOut in [[stage_in]], texture2d<float, access::read> composite [[texture(0)]],
                                      device const float *gain [[buffer(0)]], device atomic_uint *nonFinite [[buffer(1)]]) {
        float4 c = composite.read(uint2(in.position.xy));
        if (any(isnan(c) || isinf(c))) atomic_fetch_add_explicit(nonFinite, 1u, memory_order_relaxed);
        float4 t = cmp_tone_map(c);
        float g = clamp(gain[0], 0.0, 1.0);
        return float4(t.rgb * g, t.a);
    }
    """

    private static func halfRounded(_ p: SIMD4<Float>) -> SIMD4<Double> {
        SIMD4<Double>(Double(Float(Float16(p.x))), Double(Float(Float16(p.y))), Double(Float(Float16(p.z))), Double(Float(Float16(p.w))))
    }

    /// The reference display value (linear) of a composite pixel under `grade`.
    private static func expected(_ p: SIMD4<Float>, _ grade: ColorGrade) -> SIMD4<Double> {
        ToneMap.map(grade.apply(halfRounded(p)))
    }

    private static func encoded(_ linear: SIMD4<Double>) -> SIMD4<Double> {
        SIMD4<Double>(LayerBlend.encode(linear.x), LayerBlend.encode(linear.y), LayerBlend.encode(linear.z), linear.w)
    }

    private static func isInRange(_ p: SIMD4<Float>) -> Bool {
        for c in 0..<4 where !(p[c] >= 0 && p[c] <= 1) { return false }
        return true
    }

    private static func worstDifference(_ gpu: [SIMD4<Float>], _ expected: [SIMD4<Double>]) -> Double {
        var worst: Double = 0
        for (g, e) in zip(gpu, expected) {
            for c in 0..<4 {
                let d: Double = Swift.abs(Double(g[c]) - e[c])
                worst = d.isNaN ? .infinity : max(worst, d)
            }
        }
        return worst
    }

    // MARK: - US2: neutral is bypass (T06, the acceptance)

    func testNeutralGradeIsPixelEquivalentToBypass() throws {
        let passes = try OutputPassRig()
        let library: MTLLibrary = try CompositorShaders.library(device: passes.rig.device,
                                                                source: CompositorShaders.source + Self.bypassSource)
        let image: [SIMD4<Float>] = Self.referenceImage()
        let composite: MTLTexture = try passes.composite(image)
        for format in [MTLPixelFormat.bgra8Unorm_srgb, .rgba16Float] {
            let graded: [SIMD4<Float>] = try passes.output(composite, format: format, grade: .neutral)
            let bypass: [SIMD4<Float>] = try passes.output(composite, format: format, shader: "cmp_output_bypass", library: library)
            var inRange: Int = 0
            var identical: Int = 0
            var worst: Float = 0
            for i in image.indices {
                let a: SIMD4<Float> = graded[i], b: SIMD4<Float> = bypass[i]
                var same = true
                for c in 0..<4 {
                    if a[c].bitPattern != b[c].bitPattern { same = false }
                    let d: Float = Swift.abs(a[c] - b[c])
                    worst = d.isNaN ? .infinity : max(worst, d)
                }
                if same { identical += 1 }
                if Self.isInRange(image[i]) {
                    inRange += 1
                    XCTAssertTrue(same, "format \(format.rawValue), pixel \(i) \(image[i]): \(a) vs \(b)")
                }
            }
            let tolerance: Float = format == .rgba16Float ? 0.002 : 1.0 / 255
            XCTAssertLessThanOrEqual(worst, tolerance, "format \(format.rawValue): every pixel within tolerance")
            print("FX-003 neutral vs bypass, format \(format.rawValue): \(identical)/\(image.count) pixels bit-identical "
                  + "(\(inRange) in range, all identical), worst difference \(worst)")
        }
    }

    // MARK: - US1: each operator against the reference (T09)

    static let representativeGrades: [(name: String, grade: ColorGrade)] = [
        ("temperature +0.6", ColorGrade(temperature: 0.6)),
        ("temperature -1", ColorGrade(temperature: -1)),
        ("lift +0.05", ColorGrade(lift: 0.05)),
        ("lift -0.1", ColorGrade(lift: -0.1)),
        ("gamma 0.5", ColorGrade(gamma: 0.5)),
        ("gamma 1.8", ColorGrade(gamma: 1.8)),
        ("gain 0.5", ColorGrade(gain: 0.5)),
        ("gain 2", ColorGrade(gain: 2)),
        ("saturation 0", ColorGrade(saturation: 0)),
        ("saturation 2", ColorGrade(saturation: 2)),
        ("all", ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5)),
    ]

    func testEachOperatorMatchesTheReference() throws {
        let passes = try OutputPassRig()
        let image: [SIMD4<Float>] = Self.referenceImage()
        let composite: MTLTexture = try passes.composite(image)
        var table: [String] = []
        for (name, grade) in Self.representativeGrades {
            let linear: [SIMD4<Double>] = image.map { (p: SIMD4<Float>) -> SIMD4<Double> in Self.expected(p, grade) }
            let half: [SIMD4<Float>] = try passes.output(composite, format: .rgba16Float, grade: grade)
            let screen: [SIMD4<Float>] = try passes.output(composite, format: .bgra8Unorm_srgb, grade: grade)
            let halfWorst: Double = Self.worstDifference(half, linear)
            let screenWorst: Double = Self.worstDifference(screen, linear.map(Self.encoded))
            XCTAssertLessThanOrEqual(halfWorst, 0.002, "\(name): half float within 0.002")
            XCTAssertLessThanOrEqual(screenWorst, 1.0 / 255 + 1e-6, "\(name): screen within one 8-bit step")
            table.append(String(format: "%@: half %.5f, screen %.5f (%.2f steps)", name, halfWorst, screenWorst, screenWorst * 255))
        }
        print("FX-003 operator error table (worst |GPU − reference|):\n  " + table.joined(separator: "\n  "))
    }

    func testOutputLuminanceIsOrderedAlongTheGreyRampUnderLiftGammaGain() throws {
        let passes = try OutputPassRig()
        let ramp: [SIMD4<Float>] = (0..<128).map { (x: Int) -> SIMD4<Float> in
            let t: Float = 2 * Float(x) / 127
            return SIMD4<Float>(t, t, t, 1)
        }
        let composite: MTLTexture = try passes.composite(ramp)
        let grades: [ColorGrade] = [ColorGrade(lift: -0.1, gamma: 0.5, gain: 2), ColorGrade(lift: 0.1, gamma: 2, gain: 0.5),
                                    ColorGrade(lift: 0.03, gamma: 1.2, gain: 1.7)]
        for grade in grades {
            let out: [SIMD4<Float>] = try passes.output(composite, format: .rgba16Float, grade: grade)
            for i in 1..<out.count {
                XCTAssertGreaterThanOrEqual(out[i].x, out[i - 1].x, "\(grade) at \(i)")
                XCTAssertLessThanOrEqual(out[i].x, 1)
            }
        }
    }

    // MARK: - The compositor applies the grade to every output, without touching the caches (T07)

    func testCompositorAppliesTheGradeAndKeepsItsCompositeCache() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let layer = StillLayer("grey", color: Pixel(0.18, 0.18, 0.18, 1))
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output: MTLTexture = try passes.target(.rgba16Float, width: 8, height: 8)
        var time: UInt64 = 1_000_000_000
        for _ in 0..<3 {
            XCTAssertTrue(try rig.frame(compositor, into: output, time: time))
            time += Self.frameNanoseconds
        }
        let neutral: SIMD4<Float> = passes.readRaw(output)[0]
        XCTAssertEqual(neutral.x, Float(Float16(Float(0.18))), "neutral shows the composite unchanged")
        XCTAssertTrue(compositor.compositeReused)
        let reusesBefore: Int = compositor.compositeReuses
        let grade = ColorGrade(temperature: 0.5, gain: 1.5, saturation: 0.5)
        compositor.colorGrade = grade
        XCTAssertTrue(try rig.frame(compositor, into: output, time: time))
        XCTAssertTrue(compositor.compositeReused, "a grade change keeps CMP-013's composite")
        XCTAssertEqual(compositor.compositeReuses, reusesBefore + 1)
        let graded: SIMD4<Float> = passes.readRaw(output)[0]
        let expected: SIMD4<Double> = Self.expected(Pixel(0.18, 0.18, 0.18, 1), grade)
        for c in 0..<4 { XCTAssertEqual(Double(graded[c]), expected[c], accuracy: 0.002, "channel \(c)") }
        XCTAssertGreaterThan(graded.x, graded.z, "warm")
        // The recording pass of the same frame equals the screen.
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let screen: MTLTexture = try passes.target(.rgba16Float, width: 8, height: 8)
        let recording: MTLTexture = try passes.target(.rgba16Float, width: 8, height: 8)
        XCTAssertTrue(compositor.composite(into: screen, commandBuffer: commands, presentationTimeNanoseconds: time + Self.frameNanoseconds,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        compositor.colorGrade = .neutral   // set after the frame: the recording repeats the shown frame's grade
        XCTAssertTrue(compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(passes.readRaw(recording)[0], passes.readRaw(screen)[0], "recording = screen")
        XCTAssertEqual(passes.readRaw(screen)[0], graded)
    }

    // MARK: - US3: the limiter measures the graded colour (T18)

    private func minimumGain(low: Float, high: Float, grade: ColorGrade) throws -> Float {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let layer = StrobeLayer()
        layer.color = { (i: Int) -> Pixel in i % 2 == 0 ? Pixel(high, high, high, 1) : Pixel(low, low, low, 1) }
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

    func testFlashLimiterMeasuresTheGradedFrame() throws {
        // 0.02 ↔ 0.06: a luminance step of 0.04, under the 0.1 threshold: never limited ungraded.
        let ungraded: Float = try minimumGain(low: 0.02, high: 0.06, grade: .neutral)
        XCTAssertEqual(ungraded, 1, "a sub-threshold flicker is not limited")
        // Gamma 2 and gain 2 show 0.28 ↔ 0.49: a visible flash; the limiter must engage.
        let graded: Float = try minimumGain(low: 0.02, high: 0.06, grade: ColorGrade(gamma: 2, gain: 2))
        XCTAssertLessThan(graded, 1, "the graded flicker is a visible flash and is limited")
        // And grading cannot hide a flash: saturation 0 on a black ↔ white strobe is still limited.
        let hidden: Float = try minimumGain(low: 0, high: 1, grade: ColorGrade(saturation: 0))
        XCTAssertLessThan(hidden, 1)
        print("FX-003 limiter: 0.02↔0.06 ungraded minimum gain \(ungraded), graded (γ 2, gain 2) \(graded), 0↔1 sat 0 \(hidden)")
    }

    // MARK: - Polish: GPU time (T19, recorded only)

    func testOutputPassGPUTimeIsRecorded() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let w = 1920, h = 1080
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        d.storageMode = .private
        let composite: MTLTexture = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        let fill = try XCTUnwrap(rig.queue.makeCommandBuffer())
        SolidLayer.clear(composite, to: Pixel(0.6, 0.35, 0.2, 1), commandBuffer: fill)
        fill.commit()
        let library: MTLLibrary = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source)
        let pipeline = try CompositorShaders.pipeline(device: rig.device, vertex: try CompositorShaders.function(library, "cmp_fullscreen"),
                                                      fragment: try CompositorShaders.function(library, "cmp_output"),
                                                      format: .bgra8Unorm_srgb, blendOver: false, label: "FX-003 timing")
        let target: MTLTexture = try rig.output(.bgra8Unorm_srgb, width: w, height: h)
        var one: Float = 1
        let gain: MTLBuffer = try XCTUnwrap(rig.device.makeBuffer(bytes: &one, length: 4, options: .storageModeShared))
        let counter: MTLBuffer = try XCTUnwrap(rig.device.makeBuffer(length: 4, options: .storageModeShared))
        let active = CompositorShaders.GradeBlock(ColorGrade(temperature: 0.4, lift: 0.02, gamma: 1.3, gain: 1.4, saturation: 1.5).coefficients)
        XCTAssertEqual(active.flags, 31, "every operator active")
        func milliseconds(_ grade: CompositorShaders.GradeBlock) throws -> Double {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(composite, index: 0)
            encoder.setFragmentBuffer(gain, offset: 0, index: 0)
            encoder.setFragmentBuffer(counter, offset: 0, index: 1)
            Compositor.bindGrade(grade, encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            return (commands.gpuEndTime - commands.gpuStartTime) * 1000
        }
        for _ in 0..<5 { _ = try milliseconds(.neutral); _ = try milliseconds(active) }   // warm-up
        var neutral: [Double] = []
        var graded: [Double] = []
        for _ in 0..<30 {
            neutral.append(try milliseconds(.neutral))
            graded.append(try milliseconds(active))
        }
        let median = { (values: [Double]) -> Double in values.sorted()[values.count / 2] }
        print(String(format: "FX-003 GPU output pass 1920x1080 (Mac): neutral median %.3f ms, all operators median %.3f ms (30 frames each)",
                     median(neutral), median(graded)))
    }

    func testGradeBlockLayoutMatchesTheShader() {
        XCTAssertEqual(MemoryLayout<CompositorShaders.GradeBlock>.size, 64)   // FX-004: + float4 hue
        XCTAssertEqual(MemoryLayout<CompositorShaders.GradeBlock>.offset(of: \.hue), 32)
        XCTAssertEqual(MemoryLayout<CompositorShaders.GradeBlock>.offset(of: \.saturation), 48)
        XCTAssertEqual(MemoryLayout<CompositorShaders.GradeBlock>.offset(of: \.flags), 52)
        XCTAssertEqual(CompositorShaders.GradeBlock.neutral.flags, 0)
    }
}
#endif
