// EffectQualityBloomTests.swift — PERF-003-T06: the glow's cost actually falls with the level (PERF-003-R6, S2,
// S5; research PERF-003-D2). Plan arithmetic runs everywhere; the encode counts and the bit-identity check run on
// a Metal device (the Mac host GPU or the simulator) and skip elsewhere.
import XCTest
@testable import VisualGenerators
@testable import VisualEffects

final class EffectQualityBloomPlanTests: XCTestCase {
    private let sizes: [(Int, Int)] = [(1179, 2556), (2048, 1536), (320, 240)]
    private let radii: [Float] = [0.005, 0.01, 0.02, 0.035, 0.06]

    /// The reference plan before PERF-003 (FX-001-R14): D the first of 2, 4, 8 with ⌈r/D⌉ ≤ 16, R = clamp(round(r/D), 1, 16).
    private func legacy(_ radius: Float, _ w: Int, _ h: Int) -> (Int, Int) {
        let pixels = Double(radius) * Double(min(w, h))
        var d = 2
        while d < 8 && Int((pixels / Double(d)).rounded(.up)) > 16 { d *= 2 }
        return (d, min(max(Int((pixels / Double(d)).rounded()), 1), 16))
    }

    func testFullAndMinimalPlansAreTodaysPlan() {
        for (w, h) in sizes {
            for radius in radii {
                let p = BloomParameters(enabled: true, radius: radius)
                let today = BloomPlan(parameters: p, width: w, height: h)
                XCTAssertEqual(BloomPlan(parameters: p, width: w, height: h, quality: .full), today)
                XCTAssertEqual(BloomPlan(parameters: p, width: w, height: h, quality: .minimal), today)
                let (d, r) = legacy(radius, w, h)
                XCTAssertEqual(today.downsample, d)
                XCTAssertEqual(today.blurRadius, r)
            }
        }
    }

    /// S2: Reduced takes at most ⌈R/2⌉ taps, does less blur work and never widens the halo (the safety models'
    /// extent stays an upper bound).
    func testReducedHalvesTapsAndNeverWidensTheHalo() {
        var coarser = 0
        for (w, h) in sizes {
            var radius: Float = 0.005
            while radius <= 0.06 {
                let p = BloomParameters(enabled: true, radius: radius)
                let full = BloomPlan(parameters: p, width: w, height: h)
                let reduced = BloomPlan(parameters: p, width: w, height: h, quality: .reduced)
                XCTAssertLessThanOrEqual(reduced.blurRadius, (full.blurRadius + 1) / 2, "\(w)x\(h) r=\(radius)")
                XCTAssertLessThanOrEqual(reduced.haloExtent, full.haloExtent, "\(w)x\(h) r=\(radius)")
                XCTAssertLessThanOrEqual(reduced.reducedWidth * reduced.reducedHeight, full.reducedWidth * full.reducedHeight)
                if full.blurRadius > 1 { XCTAssertLessThan(reduced.blurWork, full.blurWork, "\(w)x\(h) r=\(radius)") }
                XCTAssertEqual(reduced.weights.count, reduced.blurRadius + 1)
                let sum = reduced.weights[0] + 2 * reduced.weights.dropFirst().reduce(0, +)
                XCTAssertEqual(sum, 1, accuracy: 1e-5, "the kernel still sums to one")
                if reduced.downsample > full.downsample { coarser += 1 }
                radius += 0.0025
            }
        }
        XCTAssertGreaterThan(coarser, 0, "some radii also get a coarser glow image")
    }
}

#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

final class EffectQualityBloomRenderTests: XCTestCase {
    private let format: MTLPixelFormat = .rgba16Float
    private let glow = BloomParameters(enabled: true, intensity: 0.8, radius: 0.04, threshold: 0.5, knee: 0.5)

    private func frame(_ rig: RenderRig, _ chain: EffectChain, _ input: MTLTexture, _ output: MTLTexture) throws -> [UInt8] {
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let encoded = chain.encode(output: output, commandBuffer: commands) { (target: MTLTexture) -> Bool in
            guard let blit = commands.makeBlitCommandEncoder() else { return false }
            blit.copy(from: input, to: target)
            blit.endEncoding()
            return true
        }
        XCTAssertTrue(encoded)
        let buffer = try rig.encodeReadBack(output, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return RenderRig.bytes(of: buffer)
    }

    /// S2: 4 glow passes per frame at Full and Reduced (with a smaller plan), none at Minimal; S5: Full after a round
    /// trip through the other levels renders exactly what a bloom that never changed level renders.
    func testEncodeCountsAndFullIdentity() throws {
        let rig = try RenderRig()
        let w = 160, h = 128
        let input = try rig.upload(PixelImage.patch(width: w, height: h, x0: 70, y0: 58, size: 12, color: Pixel(1, 1, 1, 1)), format: format)
        let output = try rig.makeTexture(width: w, height: h, format: format)
        let reference = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: glow) }
        let referenceChain = try rig.build { try EffectChain(device: rig.device, pixelFormat: format, effects: [reference]) }
        try referenceChain.prepare(width: w, height: h)
        let expected = try frame(rig, referenceChain, input, output)

        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: glow) }
        let chain = try rig.build { try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom]) }
        try chain.prepare(width: w, height: h)
        let fullPlan = try XCTUnwrap(bloom.plan)
        _ = try frame(rig, chain, input, output)
        XCTAssertEqual(bloom.encodedPassCount, 4)

        let builds = bloom.planBuildCount
        bloom.quality = .reduced
        bloom.quality = .reduced   // unchanged: no rebuild
        XCTAssertEqual(bloom.planBuildCount, builds + 1)
        let reducedPlan = try XCTUnwrap(bloom.plan)
        XCTAssertLessThan(reducedPlan.blurWork, fullPlan.blurWork)
        XCTAssertLessThanOrEqual(reducedPlan.blurRadius, (fullPlan.blurRadius + 1) / 2)
        let reducedBytes = try frame(rig, chain, input, output)
        XCTAssertEqual(bloom.encodedPassCount, 8)
        XCTAssertNotEqual(reducedBytes, expected, "Reduced draws a different (cheaper) glow")

        bloom.quality = .minimal
        XCTAssertTrue(bloom.isPassThrough)
        XCTAssertEqual(chain.activeEffectCount, 0)
        _ = try frame(rig, chain, input, output)
        XCTAssertEqual(bloom.encodedPassCount, 8, "Minimal encodes no glow pass")

        bloom.quality = .full
        XCTAssertEqual(bloom.plan, fullPlan)
        XCTAssertEqual(try frame(rig, chain, input, output), expected, "Full is bit-identical")
        XCTAssertEqual(bloom.resourceGeneration, 1, "level changes create no texture")
    }
}
#endif
