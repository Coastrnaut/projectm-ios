// BloomRenderTests.swift — FX-001-T09: the roadmap acceptance on a GPU ("Black pixels remain black
// and bright test patch gains bounded halo"; FX-001-R5 to R9, S1 to S3; research FX-001-D3).
// Synthetic inputs go through the real `BloomEffect`; pixels are read back and compared with the
// documented bounds. Runs on the Mac host GPU and the simulator; skips where no Metal device exists.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators
@testable import VisualEffects

final class BloomRenderTests: XCTestCase {
    private func render(_ rig: RenderRig, _ input: PixelImage, format: MTLPixelFormat,
                        parameters: BloomParameters) throws -> (bytes: [UInt8], image: PixelImage, plan: BloomPlan) {
        let effect = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: parameters) }
        try effect.prepare(width: input.width, height: input.height)
        let source = try rig.upload(input, format: format)
        let output = try rig.makeTexture(width: input.width, height: input.height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(effect.encode(input: source, output: output, commandBuffer: commands))
        let buffer = try rig.encodeReadBack(output, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        let bytes = RenderRig.bytes(of: buffer)
        return (bytes, rig.decode(bytes, width: input.width, height: input.height, format: format), try XCTUnwrap(effect.plan))
    }

    private let formats: [MTLPixelFormat] = [.rgba16Float, .bgra8Unorm_srgb]

    // (a) FX-001-S1: an all-black frame stays exactly black at every parameter corner.
    func testAllBlackStaysExactlyBlackAtEveryCorner() throws {
        let rig = try RenderRig()
        for format in formats {
            for fill in [Pixel(0, 0, 0, 0), Pixel(0, 0, 0, 1)] {
                let input = PixelImage(width: 97, height: 61, fill: fill)
                let expected = rig.bytes(of: input, format: format)
                for intensity: Float in [0.01, 1] { for radius: Float in [0.005, 0.06] {
                    for threshold: Float in [0.1, 1] { for knee: Float in [0, 1] {
                        let p = BloomParameters(enabled: true, intensity: intensity, radius: radius, threshold: threshold, knee: knee)
                        let out = try render(rig, input, format: format, parameters: p)
                        XCTAssertEqual(out.bytes, expected, "\(format.rawValue) \(p)")
                    } }
                } }
            }
        }
    }

    private struct PatchCase {
        var width: Int, height: Int, x0: Int, y0: Int, size: Int
        var radius: Float, color: Pixel, threshold: Float
    }

    // (b) FX-001-S2: the halo around a bright patch is non-zero next to it, zero beyond E, never
    // brighter than the patch, non-increasing outward, and bounded in energy.
    func testBrightPatchGainsABoundedHalo() throws {
        let rig = try RenderRig()
        let white = Pixel(1, 1, 1, 1), orange = Pixel(1, 0.3, 0.05, 1)
        let cases = [
            PatchCase(width: 160, height: 128, x0: 70, y0: 58, size: 12, radius: 0.02, color: white, threshold: 0.7),
            PatchCase(width: 160, height: 128, x0: 67, y0: 53, size: 12, radius: 0.06, color: white, threshold: 0.7),
            PatchCase(width: 160, height: 128, x0: 67, y0: 53, size: 12, radius: 0.06, color: orange, threshold: 0.5),
            PatchCase(width: 600, height: 600, x0: 293, y0: 290, size: 12, radius: 0.06, color: white, threshold: 0.7),  // D = 4
            PatchCase(width: 600, height: 600, x0: 296, y0: 296, size: 16, radius: 0.06, color: orange, threshold: 0.1), // aligned
            PatchCase(width: 1200, height: 1100, x0: 597, y0: 541, size: 12, radius: 0.06, color: white, threshold: 0.7), // D = 8
        ]
        var report: [String] = []
        for c in cases {
            for intensity: Float in [0.5, 1] {
                let p = BloomParameters(enabled: true, intensity: intensity, radius: c.radius, threshold: c.threshold, knee: 0.5)
                let input = PixelImage.patch(width: c.width, height: c.height, x0: c.x0, y0: c.y0, size: c.size, color: c.color)
                let out = try render(rig, input, format: .rgba16Float, parameters: p)
                let plan = out.plan
                let e = plan.haloExtent
                let x1 = c.x0 + c.size, y1 = c.y0 + c.size   // exclusive
                func distance(_ x: Int, _ y: Int) -> Int {
                    max(max(c.x0 - x, x - (x1 - 1), 0), max(c.y0 - y, y - (y1 - 1), 0))
                }
                var farthest = 0
                var maxHalo: Float = 0
                var addedEnergy = SIMD4<Double>.zero
                for y in 0..<c.height {
                    for x in 0..<c.width {
                        let o = out.image[x, y]
                        let i = input[x, y]
                        addedEnergy += SIMD4<Double>(Double(o.x - i.x), Double(o.y - i.y), Double(o.z - i.z), Double(o.w - i.w))
                        let d = distance(x, y)
                        guard d > 0 else { continue }
                        if o != .zero { farthest = max(farthest, d) }
                        if d >= e, o != .zero {
                            XCTFail("beyond E=\(e) at (\(x),\(y)) d=\(d): \(o)")
                        }
                        if o.x > c.color.x + 1e-3 || o.y > c.color.y + 1e-3 || o.z > c.color.z + 1e-3 {
                            XCTFail("halo brighter than the patch at (\(x),\(y)): \(o)")
                        }
                        maxHalo = max(maxHalo, o.x, o.y, o.z)
                    }
                }
                // Non-zero right next to every edge (mid row / mid column).
                let midX = c.x0 + c.size / 2, midY = c.y0 + c.size / 2
                for (x, y) in [(x1, midY), (c.x0 - 1, midY), (midX, y1), (midX, c.y0 - 1)] {
                    XCTAssertGreaterThan(luminance(out.image[x, y]), 0, "halo next to the patch at (\(x),\(y))")
                }
                // Non-increasing moving away along the centre row and column.
                func checkRay(_ points: [(Int, Int)]) {
                    for j in 1..<points.count {
                        let a = luminance(out.image[points[j - 1].0, points[j - 1].1])
                        let b = luminance(out.image[points[j].0, points[j].1])
                        XCTAssertLessThanOrEqual(b, a + 1e-3, "halo increases at \(points[j])")
                    }
                }
                checkRay((x1..<c.width).map { ($0, midY) })
                checkRay(stride(from: c.x0 - 1, through: 0, by: -1).map { ($0, midY) })
                checkRay((y1..<c.height).map { (midX, $0) })
                checkRay(stride(from: c.y0 - 1, through: 0, by: -1).map { (midX, $0) })
                // Energy: Σ(out − in) ≤ k · Σ P(in) per channel (+ half-float rounding).
                let pc = p.thresholded(LinearColor(red: c.color.x, green: c.color.y, blue: c.color.z, alpha: c.color.w))
                let count = Double(c.size * c.size)
                let bound = SIMD4<Double>(Double(pc.red), Double(pc.green), Double(pc.blue), Double(pc.alpha)) * count * Double(p.intensity)
                for k in 0..<4 {
                    XCTAssertLessThanOrEqual(addedEnergy[k], bound[k] * 1.002 + 0.05, "energy channel \(k)")
                }
                XCTAssertLessThan(farthest, e)
                report.append("\(c.width)x\(c.height) patch \(c.size)@(\(c.x0),\(c.y0)) radius=\(c.radius) k=\(intensity): D=\(plan.downsample) R=\(plan.blurRadius) E=\(e) farthest non-zero=\(farthest) max halo=\(String(format: "%.4f", maxHalo)) added=\(String(format: "%.2f", addedEnergy.x)) bound=\(String(format: "%.2f", bound.x))")
            }
        }
        // 8-bit sRGB target: beyond E exactly black as well.
        let input = PixelImage.patch(width: 160, height: 128, x0: 67, y0: 53, size: 12, color: white)
        let p = BloomParameters(enabled: true, intensity: 1, radius: 0.06)
        let out = try render(rig, input, format: .bgra8Unorm_srgb, parameters: p)
        let e = out.plan.haloExtent
        for y in 0..<128 { for x in 0..<160 {
            let d = max(max(67 - x, x - 78, 0), max(53 - y, y - 64, 0))
            if d >= e, out.image[x, y] != .zero { XCTFail("sRGB beyond E at (\(x),\(y))") }
        } }
        XCTAssertGreaterThan(luminance(out.image[79, 59]), 0, "sRGB halo next to the patch")
        print("FX-001 halo:\n" + report.joined(separator: "\n"))
    }

    // (c) FX-001-R6: a patch below T − K is unchanged.
    func testBelowThresholdPatchIsUnchanged() throws {
        let rig = try RenderRig()
        let input = PixelImage.patch(width: 96, height: 64, x0: 40, y0: 20, size: 14, color: Pixel(0.3, 0.3, 0.3, 1))
        let p = BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.7, knee: 0.5)   // T − K = 0.35
        let half = try render(rig, input, format: .rgba16Float, parameters: p)
        XCTAssertEqual(half.bytes, rig.bytes(of: input, format: .rgba16Float), "exact on rgba16Float")
        let srgb = try render(rig, input, format: .bgra8Unorm_srgb, parameters: p)
        let expected = rig.bytes(of: input, format: .bgra8Unorm_srgb)
        XCTAssertEqual(srgb.bytes.count, expected.count)
        let worst = zip(srgb.bytes, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(worst, 1, "within 1/255 on bgra8Unorm_srgb")
    }

    // (d) A horizontal 0…1 ramp: the glow only adds, stays finite, and leaves pixels farther than E
    // from every contributing pixel unchanged.
    func testGradientOnlyGainsAndStaysFinite() throws {
        let rig = try RenderRig()
        var input = PixelImage(width: 256, height: 48)
        for y in 0..<48 { for x in 0..<256 { let v = Float(x) / 255; input[x, y] = Pixel(v, v, v, 1) } }
        let p = BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.7, knee: 0.5)
        let out = try render(rig, input, format: .rgba16Float, parameters: p)
        // Compare with the input as stored in the texture (rounded to half floats).
        let stored = rig.decode(rig.bytes(of: input, format: .rgba16Float), width: 256, height: 48, format: .rgba16Float)
        let firstContributing = (0..<256).first { Float($0) / 255 > p.threshold - p.kneeWidth } ?? 256
        for y in 0..<48 { for x in 0..<256 {
            let o = out.image[x, y], i = stored[x, y]
            for k in 0..<4 where !o[k].isFinite || o[k] < i[k] - 1e-3 {
                XCTFail("glow must only add and stay finite at (\(x),\(y)): \(o) vs \(i)")
            }
            if x <= firstContributing - out.plan.haloExtent - 1, o != i {
                XCTFail("unchanged beyond E at (\(x),\(y)): \(o) vs \(i)")
            }
        } }
        XCTAssertGreaterThan(luminance(out.image[200, 24]), luminance(input[200, 24]), "bright end glows")
    }

    // (e) FX-001-R8: intensity 0 or disabled is bit for bit the input.
    func testIntensityZeroAndDisabledAreExactPassThrough() throws {
        let rig = try RenderRig()
        let input = PixelImage.patch(width: 80, height: 60, x0: 30, y0: 20, size: 10, color: Pixel(1, 0.8, 0.2, 1))
        for format in formats {
            for p in [BloomParameters(enabled: true, intensity: 0, radius: 0.06, threshold: 0.1),
                      BloomParameters(enabled: false, intensity: 1, radius: 0.06, threshold: 0.1)] {
                let out = try render(rig, input, format: format, parameters: p)
                XCTAssertEqual(out.bytes, rig.bytes(of: input, format: format), "\(format.rawValue) \(p)")
            }
        }
    }

    // (f) FX-001-R9: identical input and parameters give identical bits.
    func testRepeatedRunsAreBitIdentical() throws {
        let rig = try RenderRig()
        let input = PixelImage.patch(width: 150, height: 110, x0: 61, y0: 47, size: 13, color: Pixel(0.9, 0.6, 1, 1))
        for format in formats {
            let p = BloomParameters(enabled: true, intensity: 0.8, radius: 0.04, threshold: 0.3, knee: 0.7)
            let a = try render(rig, input, format: format, parameters: p)
            let b = try render(rig, input, format: format, parameters: p)
            XCTAssertEqual(a.bytes, b.bytes, "\(format.rawValue)")
            XCTAssertNotEqual(a.bytes, rig.bytes(of: input, format: format), "the glow changed something")
        }
    }

    // MOD-002-T09 (research MOD-002-D6): a modulated intensity changes only the uniforms. The plan
    // is not rebuilt (no allocation per frame), and the result equals a bloom built at that intensity.
    func testIntensityOnlyChangeKeepsThePlanAndRendersTheNewIntensity() throws {
        let rig = try RenderRig()
        let input = PixelImage.patch(width: 96, height: 72, x0: 40, y0: 30, size: 12, color: Pixel(1, 1, 1, 1))
        let format = MTLPixelFormat.rgba16Float
        let start = BloomParameters(enabled: true, intensity: 0.5, radius: 0.03, threshold: 0.5)
        let effect = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: start) }
        try effect.prepare(width: input.width, height: input.height)
        let builds = effect.planBuildCount
        effect.parameters.intensity = 0.9
        XCTAssertEqual(effect.planBuildCount, builds, "an intensity-only change does not rebuild the plan")
        let source = try rig.upload(input, format: format)
        let output = try rig.makeTexture(width: input.width, height: input.height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(effect.encode(input: source, output: output, commandBuffer: commands))
        let buffer = try rig.encodeReadBack(output, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        var fresh = start
        fresh.intensity = 0.9
        XCTAssertEqual(RenderRig.bytes(of: buffer), try render(rig, input, format: format, parameters: fresh).bytes)
        effect.parameters.radius = 0.05
        XCTAssertEqual(effect.planBuildCount, builds + 1, "another field still rebuilds the plan")
    }

    // (g) Contract: unsupported formats throw; mismatched sizes or formats encode nothing.
    func testContractViolationsAreRefused() throws {
        let rig = try RenderRig()
        XCTAssertThrowsError(try BloomEffect(device: rig.device, pixelFormat: .r8Unorm))
        let effect = try rig.build { try BloomEffect(device: rig.device, pixelFormat: .rgba16Float,
                                                     parameters: BloomParameters(enabled: true, intensity: 1)) }
        let a = try rig.makeTexture(width: 32, height: 32, format: .rgba16Float)
        let b = try rig.makeTexture(width: 32, height: 32, format: .rgba16Float)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertFalse(effect.encode(input: a, output: b, commandBuffer: commands), "not prepared")
        try effect.prepare(width: 64, height: 48)
        XCTAssertFalse(effect.encode(input: a, output: b, commandBuffer: commands), "size mismatch")
        try effect.prepare(width: 32, height: 32)
        XCTAssertFalse(effect.encode(input: a, output: a, commandBuffer: commands), "input and output must differ")
        let srgb = try rig.makeTexture(width: 32, height: 32, format: .bgra8Unorm_srgb)
        XCTAssertFalse(effect.encode(input: a, output: srgb, commandBuffer: commands), "format mismatch")
        XCTAssertTrue(effect.encode(input: a, output: b, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(effect.identifier, .bloom)
    }
}
#endif
