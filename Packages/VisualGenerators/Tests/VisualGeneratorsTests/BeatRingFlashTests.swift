// BeatRingFlashTests.swift — VIS-006-T08: beat rings feed FX-019's strobe safety envelope like the other native
// visuals (VIS-006-R5, R8, S4; FX-019-R4, R9). A beat on every frame at 60 Hz for 1.5 s with thick white rings,
// through the rate cap and the limiter as `BeatRingGenerator` applies them, with and without the strongest
// glow's luminance model, measured with FlashSafety's independent `FlashAnalysis` (as VIS-005's test). The
// clock is injected; constant frame times. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class BeatRingFlashTests: XCTestCase {
    private func levels<T: FrameLuminanceTransfer>(_ layout: BeatRingLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            layout.meanLevels(gain: gain, transfer: transfer, into: b)
        }
        return out
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> (worst: Int, rings: Int) {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let field = BeatRingField()
        let layout = BeatRingLayout(configuration: BeatRingConfiguration(life: 1.0, lineThickness: 0.05, palette: .mono))
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<90 {
            let now = UInt64((Double(f) * dt * 1e9).rounded())
            field.emit(atNanoseconds: now, minimumInterval: BeatRingConfiguration.minimumInterval(for: configuration))   // a beat every frame
            layout.layout(field: field, atNanoseconds: now, width: width, height: height)
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
        return (worst, field.accepted)
    }

    func testBeatOnEveryFrameObeysTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-006 beat rings (CPU, thick white rings, a beat every frame for 1.5 s): worst transitions per window:"]
        for enabled in [true, false] {
            let budget = FlashEnvelopeConfiguration.forReduceFlashing(enabled).transitionBudget
            let plain = worstTransitions(transfer: IdentityLuminanceTransfer(), enabled: enabled, width: 390, height: 844)
            let glowing = worstTransitions(transfer: glow, enabled: enabled, width: 844, height: 390)
            XCTAssertLessThanOrEqual(plain.worst, budget, "Reduce flashing \(enabled), portrait")
            XCTAssertLessThanOrEqual(glowing.worst, budget, "Reduce flashing \(enabled), landscape with glow")
            XCTAssertLessThanOrEqual(plain.rings, enabled ? 5 : 9, "the rate cap bounds 90 beats in 1.5 s")
            report.append("Reduce flashing \(enabled ? "on" : "off"): \(plain.worst) portrait, \(glowing.worst) landscape with glow "
                          + "(limit \(budget)); \(plain.rings) of 90 beats became rings")
        }
        print(report.joined(separator: "\n"))
    }
}
