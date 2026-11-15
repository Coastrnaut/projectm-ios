// FluidInkFlashTests.swift — VIS-011-T08 (VIS-011-R10, R11; S5): the strobe safety envelope and fluid ink. The CPU ink
// bound is never below the ink the GPU holds or draws; the drawn picture is the ink × the envelope's gain and never
// above 0.8; bursts of impulses after silence stay within the envelope's transition budget and rise rate with Reduce
// flashing on and off; Reduce Motion halves the speed the GPU reaches. Without Metal the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal
import XCTest
@testable import VisualGenerators

final class FluidInkFlashTests: XCTestCase {
    private static let format: MTLPixelFormat = .rgba16Float

    private func frame(_ generator: NoiseFieldGenerator, _ target: MTLTexture, _ commands: MTLCommandBuffer, m: UInt64,
                       reduceFlashing: Bool) -> Bool {
        let context = VisualFrameContext(timeNanoseconds: 1_000_000_000 + m * 1_000_000_000 / 60, frameDuration: 1.0 / 60,
                                         reduceFlashing: reduceFlashing)
        let bands = [Float](repeating: 0, count: 64)
        return bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
        }
    }

    /// The bound covers the GPU's ink and the drawn pixels (ink × gain ≤ bound × gain ≤ 0.8).
    func testBoundCoversTheInkTheGPUHoldsAndDraws() throws {
        let rig = try RenderRig()
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .fluidInk(palette: .spectrum))
        }
        let target = try rig.makeTexture(width: 24, height: 24, format: Self.format)
        for m: UInt64 in 0..<60 {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            if m < 30, m % 4 == 0 {
                generator.enqueueImpulse(atNanoseconds: 1_000_000_000 + m * 1_000_000_000 / 60, strength: 1, threshold: 0)
            }
            XCTAssertTrue(frame(generator, target, commands, m: m, reduceFlashing: false))
            guard m % 10 == 9 else { commands.commit(); commands.waitUntilCompleted(); continue }   // each frame's health copy has a slot
            let image = try rig.encodeReadBack(target, commands: commands)
            commands.commit()
            commands.waitUntilCompleted()
            let pass = try XCTUnwrap(generator.fluidPass)
            pass.pollHealth(speedCap: FluidInk.speedCap)
            let bound: Float = generator.fluidBound.level.max()
            XCTAssertGreaterThanOrEqual(bound + 1e-5, try XCTUnwrap(pass.lastHealth).maxInk, "frame \(m)")
            let pixels = rig.decode(RenderRig.bytes(of: image), width: 24, height: 24, format: Self.format).pixels
            let brightest: Float = pixels.map { (p: Pixel) -> Float in max(p.x, max(p.y, p.z)) }.max() ?? 0
            XCTAssertLessThanOrEqual(brightest, bound * generator.lastGain + 2e-3, "frame \(m)")
            XCTAssertLessThanOrEqual(brightest, FluidInk.inkCap + 1e-3)
        }
        XCTAssertGreaterThan(generator.fluidBound.level.max(), 0.05)
    }

    /// Bursts after silence: the shown levels (the estimate at the frame's gain) obey the envelope.
    private func worstTransitions(reduceFlashing: Bool) throws -> Int {
        let rig = try RenderRig()
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .fluidInk(palette: .mono))
        }
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(reduceFlashing)
        var shown: [[FlashLevels]] = []
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0..<240 {   // 1 s silence, then 3 s of bursts: 6 frames of impulses, 6 frames of none
            if m >= 60, (m / 6) % 2 == 0 {
                generator.enqueueImpulse(atNanoseconds: 1_000_000_000 + m * 1_000_000_000 / 60, strength: 1, threshold: 0)
            }
            XCTAssertTrue(frame(generator, target, commands, m: m, reduceFlashing: reduceFlashing))
            var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
            out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
                generator.flashAreas.levels(gain: generator.lastGain, transfer: IdentityLuminanceTransfer(), into: b)
            }
            shown.append(out)
        }
        commands.commit()
        commands.waitUntilCompleted()
        let dt = 1.0 / 60
        let times = [Double](repeating: dt, count: shown.count)
        var worst = 0
        for z in 0..<FlashZones.count {
            for s in FlashSignal.allCases {
                let out = FlashAnalysis.analyze(shown.map { (l: [FlashLevels]) -> Double in l[z][s] }, frameTimes: times,
                                                threshold: configuration.threshold(for: s))
                worst = max(worst, out.maxTransitionsPerWindow)
                if let rate = configuration.riseRatePerSecond {
                    XCTAssertLessThanOrEqual(out.maxRise, rate * dt + 1e-9, "area \(z) \(s)")
                }
            }
        }
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.05)
        return worst
    }

    func testBurstsAfterSilenceObeyTheEnvelope() throws {
        var report = ["VIS-011 fluid ink (bound estimate, mono, bursts after 1 s of silence): worst transitions per window:"]
        for enabled in [true, false] {
            let budget = FlashEnvelopeConfiguration.forReduceFlashing(enabled).transitionBudget
            let worst = try worstTransitions(reduceFlashing: enabled)
            XCTAssertLessThanOrEqual(worst, budget, "Reduce flashing \(enabled)")
            report.append("Reduce flashing \(enabled ? "on" : "off"): \(worst) (limit \(budget))")
        }
        print(report.joined(separator: "\n"))
    }

    /// ACC-001: Reduce Motion halves the speed the GPU reaches and spaces the impulses.
    func testReduceMotionSlowsTheFlow() throws {
        let rig = try RenderRig()
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .fluidInk(reduceMotion: true))
        }
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        for m: UInt64 in 0...60 {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            generator.enqueueImpulse(atNanoseconds: 1_000_000_000 + m * 1_000_000_000 / 60, strength: 1, threshold: 0)
            XCTAssertTrue(frame(generator, target, commands, m: m, reduceFlashing: false))
            commands.commit()
            commands.waitUntilCompleted()
        }
        let pass = try XCTUnwrap(generator.fluidPass)
        pass.pollHealth(speedCap: FluidInk.effectiveSpeedCap(reduceMotion: true))
        let health = try XCTUnwrap(pass.lastHealth)
        XCTAssertGreaterThan(health.maxSpeed, 0.01)
        XCTAssertLessThanOrEqual(health.maxSpeed, FluidInk.speedCap * FluidInk.reduceMotionScale * 1.001)
        XCTAssertEqual(generator.fluidScheduler.appliedImpulses, 2, "one impulse per 0.5 s")
        XCTAssertEqual(generator.fluidHealthResets, 0)
    }
}
#endif
