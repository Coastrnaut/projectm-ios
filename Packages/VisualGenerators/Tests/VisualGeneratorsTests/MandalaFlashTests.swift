// MandalaFlashTests.swift — VIS-007-T08: the mandala feeds FX-019's strobe safety envelope like the other native
// visuals (VIS-007-R8, S4; FX-019-R4, R9). The flash test pattern: bands alternating silence and full scale on
// every frame at 60 Hz for 1.5 s (the petal's length, width, curl and brightness all jump each frame), white
// petals, through the Reduce-flashing slew and the limiter as `MandalaGenerator` applies them, with and without
// the strongest glow's luminance model, measured with FlashSafety's independent `FlashAnalysis` (as VIS-006's
// test). The clock is injected; constant frame times. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class MandalaFlashTests: XCTestCase {
    private func levels<T: FrameLuminanceTransfer>(_ layout: MandalaLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            layout.meanLevels(gain: gain, transfer: transfer, into: b)
        }
        return out
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, mirror: Bool,
                                                            width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let layout = MandalaLayout(configuration: MandalaConfiguration(symmetry: 12, mirror: mirror, petalStyle: .round,
                                                                       palette: .mono))
        let dt = 1.0 / 60
        let loud = [Float](repeating: 1, count: 64), quiet = [Float](repeating: 0, count: 64)
        var shown: [[FlashLevels]] = []
        for f in 0..<90 {
            let now = UInt64((Double(f) * dt * 1e9).rounded())
            (f % 2 == 0 ? loud : quiet).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                let slewed = limiter.limitValues(b, frameTime: dt, enabled: enabled)
                layout.layout(bands: slewed, atNanoseconds: now, width: width, height: height)
            }
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

    func testAlternatingBandsObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-007 mandala (CPU, 12-fold white petals, silence/full scale alternating every frame for 1.5 s): worst transitions per window:"]
        for enabled in [true, false] {
            let budget = FlashEnvelopeConfiguration.forReduceFlashing(enabled).transitionBudget
            let plain = worstTransitions(transfer: IdentityLuminanceTransfer(), enabled: enabled, mirror: false, width: 390, height: 844)
            let glowing = worstTransitions(transfer: glow, enabled: enabled, mirror: true, width: 844, height: 390)
            XCTAssertLessThanOrEqual(plain, budget, "Reduce flashing \(enabled), portrait")
            XCTAssertLessThanOrEqual(glowing, budget, "Reduce flashing \(enabled), landscape mirrored with glow")
            report.append("Reduce flashing \(enabled ? "on" : "off"): \(plain) portrait, \(glowing) landscape mirrored with glow (limit \(budget))")
        }
        print(report.joined(separator: "\n"))
    }
}
