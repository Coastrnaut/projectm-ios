// ReactionDiffusionFlashTests.swift — VIS-012-T08 (VIS-012-R11, R12; S6): the strobe safety envelope and reaction
// diffusion. Drawn pixels never exceed the bound × the envelope's gain or 0.8; rapid reloads (a new seed every 0.1 s)
// and bass bursts stay within the envelope's transition budget and rise rate with Reduce flashing on and off; Reduce
// Motion halves the iterations and spaces the injections. Without Metal the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal
import XCTest
@testable import VisualGenerators

final class ReactionDiffusionFlashTests: XCTestCase {
    private static let format: MTLPixelFormat = .rgba16Float

    private func frame(_ generator: NoiseFieldGenerator, _ target: MTLTexture, _ commands: MTLCommandBuffer, m: UInt64,
                       reduceFlashing: Bool, bass: Float) -> Bool {
        let context = VisualFrameContext(timeNanoseconds: 1_000_000_000 + m * 1_000_000_000 / 60, frameDuration: 1.0 / 60,
                                         reduceFlashing: reduceFlashing)
        let bands = [Float](repeating: bass, count: 64)
        return bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
        }
    }

    /// Drawn pixels ≤ bound × gain ≤ 0.8 while the pattern fades in and grows.
    func testDrawnPixelsStayUnderTheBound() throws {
        let rig = try RenderRig()
        let settings = ReactionDiffusionSettings(preset: .coral, pattern: .spots, seed: 11, speed: 16)
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format,
                                    configuration: .reactionDiffusion(settings, palette: .spectrum))
        }
        let target = try rig.makeTexture(width: 32, height: 32, format: Self.format)
        var brightestSeen: Float = 0
        for m: UInt64 in 0..<90 {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            XCTAssertTrue(frame(generator, target, commands, m: m, reduceFlashing: false, bass: m % 20 == 0 ? 1 : 0))
            guard m % 15 == 14 else { commands.commit(); continue }
            let image = try rig.encodeReadBack(target, commands: commands)
            commands.commit()
            commands.waitUntilCompleted()
            let pixels = rig.decode(RenderRig.bytes(of: image), width: 32, height: 32, format: Self.format).pixels
            let brightest: Float = pixels.map { (p: Pixel) -> Float in max(p.x, max(p.y, p.z)) }.max() ?? 0
            XCTAssertLessThanOrEqual(brightest, generator.reactionBound.max() * generator.lastGain + 2e-3, "frame \(m)")
            XCTAssertLessThanOrEqual(brightest, ReactionDiffusion.displayCap + 1e-3)
            XCTAssertTrue(pixels.allSatisfy { (p: Pixel) -> Bool in p.w == 1 })
            brightestSeen = max(brightestSeen, brightest)
        }
        XCTAssertGreaterThan(brightestSeen, 0.05, "something was drawn")
        XCTAssertEqual(generator.reactionBound.max(), min(generator.reactionBound.max(), ReactionDiffusion.displayCap))
    }

    /// Reloads every 0.1 s for 1.5 s, then 1.5 s of bass bursts: the shown levels obey the envelope.
    private func worstTransitions(reduceFlashing: Bool) throws -> Int {
        let rig = try RenderRig()
        var settings = ReactionDiffusionSettings(preset: .mitosis, pattern: .square, seed: 1, speed: 16)
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .reactionDiffusion(settings, palette: .mono))
        }
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(reduceFlashing)
        var shown: [[FlashLevels]] = []
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0..<180 {
            if m < 90, m % 6 == 5 {
                settings.seed += 1
                generator.configuration = .reactionDiffusion(settings, palette: .mono)
            }
            let bass: Float = m >= 90 && (m / 4) % 2 == 0 ? 1 : 0
            XCTAssertTrue(frame(generator, target, commands, m: m, reduceFlashing: reduceFlashing, bass: bass))
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
        XCTAssertGreaterThanOrEqual(generator.reactionPass?.reloads ?? 0, 15)
        return worst
    }

    func testRapidReloadsAndBassBurstsObeyTheEnvelope() throws {
        var report = ["VIS-012 reaction diffusion (bound estimate, mono, reloads every 0.1 s then bass bursts): worst transitions per window:"]
        for enabled in [true, false] {
            let budget = FlashEnvelopeConfiguration.forReduceFlashing(enabled).transitionBudget
            let worst = try worstTransitions(reduceFlashing: enabled)
            XCTAssertLessThanOrEqual(worst, budget, "Reduce flashing \(enabled)")
            report.append("Reduce flashing \(enabled ? "on" : "off"): \(worst) (limit \(budget))")
        }
        print(report.joined(separator: "\n"))
    }

    /// ACC-001: Reduce Motion runs half the iterations and at most one injection per second.
    func testReduceMotionHalvesIterationsAndSpacesInjections() throws {
        let rig = try RenderRig()
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format,
                                    configuration: .reactionDiffusion(ReactionDiffusionSettings(speed: 16), reduceMotion: true))
        }
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0...120 {
            XCTAssertTrue(frame(generator, target, commands, m: m, reduceFlashing: false, bass: m % 2 == 0 ? 1 : 0))
        }
        commands.commit()
        commands.waitUntilCompleted()
        let scheduler = generator.reactionScheduler
        XCTAssertEqual(scheduler.totalSteps, 120)
        XCTAssertEqual(scheduler.totalIterations, 120 * 8, "half of Speed 16")
        XCTAssertEqual(scheduler.kicks, 3, "one per second")
        XCTAssertEqual(generator.reactionHealthReloads, 0)
    }
}
#endif
