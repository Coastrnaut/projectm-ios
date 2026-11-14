// ParticleOrbitFlashTests.swift — VIS-009-T11: the particle orbit feeds FX-019's strobe safety envelope like the other
// native visuals (VIS-009-R8, S5; FX-019-R4, R9). Large white particles at the largest count, beats on every frame of
// every other 0.1 s window and full bass alternating with silence at 60 Hz for 3 s, through the limiter as
// `ParticleOrbitGenerator` applies it, with and without the strongest glow's luminance model, measured with
// FlashSafety's independent `FlashAnalysis` (as VIS-008's test). The clock is injected. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class ParticleOrbitFlashTests: XCTestCase {
    private func levels<T: FrameLuminanceTransfer>(_ layout: ParticleOrbitLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            layout.meanLevels(gain: gain, transfer: transfer, into: b)
        }
        return out
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let simulation = ParticleOrbitSimulation(configuration: ParticleOrbitConfiguration(particleCount: 256, bassDepth: 1,
                                                                                           particleSize: 0.1, palette: .mono))
        let layout = ParticleOrbitLayout()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<180 {
            let now = UInt64(f) * 1_000_000_000 / 60
            let loud = (f / 6) % 2 == 0
            if loud { simulation.enqueueBeat(atNanoseconds: now) }
            simulation.setTarget(base: 0.8, bass: loud ? 1 : 0)
            simulation.advance(toNanoseconds: now)
            layout.layout(simulation: simulation, width: width, height: height)
            let gain = limiter.gain(for: layout, transfer: transfer, frameTime: dt, configuration: configuration)
            shown.append(levels(layout, gain: gain, transfer))
        }
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
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.002,
                             "frames were not blank")
        return worst
    }

    func testBeatsAndBassAlternatingWithSilenceObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-009 particle orbit (CPU, 256 large white particles, beats and bass alternating with silence for 3 s): worst transitions per window:"]
        for enabled in [true, false] {
            let budget = FlashEnvelopeConfiguration.forReduceFlashing(enabled).transitionBudget
            let plain = worstTransitions(transfer: IdentityLuminanceTransfer(), enabled: enabled, width: 390, height: 844)
            let glowing = worstTransitions(transfer: glow, enabled: enabled, width: 844, height: 390)
            XCTAssertLessThanOrEqual(plain, budget, "Reduce flashing \(enabled), portrait")
            XCTAssertLessThanOrEqual(glowing, budget, "Reduce flashing \(enabled), landscape with glow")
            report.append("Reduce flashing \(enabled ? "on" : "off"): \(plain) portrait, \(glowing) landscape with glow (limit \(budget))")
        }
        print(report.joined(separator: "\n"))
    }
}
