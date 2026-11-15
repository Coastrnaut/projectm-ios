// ParticleTrailFlashTests.swift — VIS-010-T09: trails under FX-019's strobe safety envelope (VIS-010-R7).
// * CPU: bursts of large white particles alternating with silence, with Long trails, through the same gain step the
//   generators use (`ParticleTrailFlashBound.gain` and `.record`); the frames the envelope passes (particles plus the
//   gain-scaled trail bound) stay within the transition budget with Reduce flashing on and off, measured with
//   FlashSafety's independent `FlashAnalysis`; the trail can only lower the gain.
// * GPU: the bound is never below the mean of the accumulation texture actually drawn.
// Injected clock, constant frame times.
import FlashSafety
import XCTest
@testable import VisualGenerators

final class ParticleTrailFlashTests: XCTestCase {
    private func worstTransitions(enabled: Bool) -> (worst: Int, trailLowersGain: Bool) {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let bound = ParticleTrailFlashBound()
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(life: 0.5, particleSize: 0.1, palette: .mono))
        let layout = ParticleFountainLayout()
        let transfer = IdentityLuminanceTransfer()
        let dt = 1.0 / 60
        let d = ParticleTrails.decay(frameDuration: dt, halfLife: ParticleTrails.halfLife(.long, reduceMotion: false, reduceFlashing: enabled))
        var shown: [[FlashLevels]] = []
        var lowers = true
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        for f in 0..<180 {
            let now = UInt64((Double(f) * dt * 1e9).rounded())
            if (f / 6) % 2 == 0 { simulation.enqueueOnset(atNanoseconds: now, strength: 1, threshold: 0.06) }
            simulation.advance(toNanoseconds: now)
            layout.layout(simulation: simulation, width: 390, height: 844)
            let gain = bound.gain(layout: layout, transfer: transfer, limiter: limiter, decay: d, showsTrail: f > 0,
                                  frameTime: dt, configuration: configuration)
            out.withUnsafeMutableBufferPointer { (o: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
                layout.meanLevels(gain: gain, transfer: transfer, into: o)
                if f > 0 { bound.add(gain: gain, decay: d, into: o) }
            }
            if f > 0, bound.shown(FlashZones.wholeFrame, decay: d).luminance > 0 {
                // With the trail's light added, the levels at any gain are at least the particles' alone.
                var plain = [FlashLevels](repeating: .zero, count: FlashZones.count)
                plain.withUnsafeMutableBufferPointer { (o: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
                    layout.meanLevels(gain: gain, transfer: transfer, into: o)
                }
                lowers = lowers && out[FlashZones.wholeFrame].luminance >= plain[FlashZones.wholeFrame].luminance
            }
            shown.append(out)
            bound.record(layout: layout, transfer: transfer, gain: gain, background: layout.background, decay: d)
        }
        let times = [Double](repeating: dt, count: shown.count)
        var worst = 0
        for z in 0..<FlashZones.count {
            for s in FlashSignal.allCases {
                let result = FlashAnalysis.analyze(shown.map { (l: [FlashLevels]) -> Double in l[z][s] }, frameTimes: times,
                                                   threshold: configuration.threshold(for: s))
                worst = max(worst, result.maxTransitionsPerWindow)
                if let rate = configuration.riseRatePerSecond {
                    XCTAssertLessThanOrEqual(result.maxRise, rate * dt + 1e-9, "area \(z) \(s)")
                }
            }
        }
        XCTAssertGreaterThan(bound.accumulated[FlashZones.wholeFrame].luminance, 0, "the trail added light")
        return (worst, lowers)
    }

    func testTrailedBurstsStayWithinTheEnvelope() {
        for enabled in [true, false] {
            let budget = FlashEnvelopeConfiguration.forReduceFlashing(enabled).transitionBudget
            let result = worstTransitions(enabled: enabled)
            XCTAssertLessThanOrEqual(result.worst, budget, "Reduce flashing \(enabled)")
            XCTAssertTrue(result.trailLowersGain, "the trail's light is counted")
            print("VIS-010 trails, bursts alternating with silence: Reduce flashing \(enabled ? "on" : "off"): worst \(result.worst) (limit \(budget))")
        }
    }
}

#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

final class ParticleTrailBoundRenderTests: XCTestCase {
    /// The bound's whole-frame luminance is never below the mean luminance of the accumulation drawn on the GPU.
    func testBoundIsNotBelowTheDrawnAccumulation() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try ParticleFountainGenerator(device: rig.device, pixelFormat: .rgba16Float,
                                                                      configuration: ParticleFountainConfiguration(particleSize: 0.08)) }
        generator.trails = .long
        let target = try rig.makeTexture(width: 64, height: 48, format: .rgba16Float)
        for f in 0..<45 {
            if f % 10 == 0 { generator.enqueueOnset(atNanoseconds: UInt64(f) * 16_666_667, strength: 1, threshold: 0.1) }
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 16_666_667, frameDuration: 1.0 / 60, reduceFlashing: false)
            let drawn = [Float]().withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
            commands.commit()
            commands.waitUntilCompleted()
        }
        let pass = try XCTUnwrap(generator.trailPass)
        let side = ParticleTrails.textureSide
        let image = rig.decode(try rig.readBack(pass.textures[pass.newest]), width: side, height: side, format: .rgba16Float)
        let mean = image.pixels.reduce(0.0) { (sum: Double, p: Pixel) -> Double in sum + luminance(p) } / Double(side * side)
        XCTAssertGreaterThan(mean, 0.0005, "the accumulation holds a trail")
        XCTAssertGreaterThanOrEqual(pass.flashBound.accumulated[FlashZones.wholeFrame].luminance, mean * 0.98,
                                    "bound \(pass.flashBound.accumulated[FlashZones.wholeFrame].luminance) ≥ drawn mean \(mean)")
    }
}
#endif
