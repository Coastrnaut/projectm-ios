// ParticleFountainFlashTests.swift — VIS-008-T09: the particle fountain feeds FX-019's strobe safety envelope like
// the other native visuals (VIS-008-R8, S5; FX-019-R4, R9). Full-strength bursts of large white particles on
// every other 0.1 s window (bursts alternating with silence) at 60 Hz for 3 s, through the limiter as
// `ParticleFountainGenerator` applies it, with and without the strongest glow's luminance model, measured with
// FlashSafety's independent `FlashAnalysis` (as VIS-006's test). The clock is injected; constant frame times.
// Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class ParticleFountainFlashTests: XCTestCase {
    private func levels<T: FrameLuminanceTransfer>(_ layout: ParticleFountainLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            layout.meanLevels(gain: gain, transfer: transfer, into: b)
        }
        return out
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let simulation = ParticleFountainSimulation(configuration: ParticleFountainConfiguration(life: 0.5, particleSize: 0.1,
                                                                                                 palette: .mono))
        let layout = ParticleFountainLayout()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<180 {
            let now = UInt64((Double(f) * dt * 1e9).rounded())
            if (f / 6) % 2 == 0 {   // an onset on every frame of every other 0.1 s window
                simulation.enqueueOnset(atNanoseconds: now, strength: 1, threshold: 0.06)
            }
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

    func testBurstsAlternatingWithSilenceObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-008 particle fountain (CPU, large white particles, bursts alternating with silence for 3 s): worst transitions per window:"]
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
