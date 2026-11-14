// RadialWaveformFlashTests.swift — VIS-005-T07: the radial waveform feeds FX-019's strobe safety envelope like
// the oscilloscope (VIS-005-R8, S4; FX-019-R4, R9). A 60 Hz alternation of a full-scale 97 Hz sine and silence
// (a thick white ring jumping between a wobble and the base circle) for 1.5 s through the limiter, as
// `RadialWaveformGenerator` applies it, with and without the strongest glow's luminance model, measured with
// FlashSafety's independent `FlashAnalysis`. Constant frame times; no clock. Pure Swift. Also the gain's
// reset (the loop restart; VIS-005-R5).
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class RadialWaveformFlashTests: XCTestCase {
    private func levels<T: FrameLuminanceTransfer>(_ layout: RadialWaveformLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            layout.meanLevels(gain: gain, transfer: transfer, into: b)
        }
        return out
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let layout = RadialWaveformLayout(configuration: RadialWaveformConfiguration(baseRadius: 0.5, amplitude: 0.25,
                                                                                     lineThickness: 0.05, palette: .mono))
        let loud = RadialFixture.sine(97, amplitude: 1, endingAt: 40_000)
        let silent = RadialFixture.silence()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<90 {
            layout.layout(f % 2 == 0 ? loud : silent, frameDuration: dt, width: width, height: height)
            let gain = limiter.gain(for: layout, transfer: transfer, frameTime: dt, enabled: enabled)
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
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.005,
                             "frames were not blank")
        return worst
    }

    func testSixtyHertzAlternationObeysTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-005 radial waveform (CPU, thick white ring, loud/silent every frame for 1.5 s): worst transitions per window:"]
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

    func testGainFollowsQuietAudioAndResets() {
        let layout = RadialWaveformLayout()
        layout.layout(RadialFixture.sine(97, amplitude: 0.05))
        XCTAssertEqual(layout.autoGain.level, 0.05, accuracy: 0.002, "the level follows the quiet peak")
        XCTAssertEqual(layout.radii.max() ?? 0, RadialWaveformConfiguration.defaultBaseRadius + RadialWaveformConfiguration.defaultAmplitude,
                       accuracy: 0.002, "quiet audio still reaches the full amplitude")
        layout.layout(RadialFixture.sine(97, amplitude: 0.8))
        layout.layout(RadialFixture.sine(97, amplitude: 0.05))
        XCTAssertEqual(layout.autoGain.level, 0.8, accuracy: 0.01, "the level holds after a loud frame")
        layout.reset()
        XCTAssertEqual(layout.autoGain.level, LissajousAutoGain.floor, "the loop restart starts the gain afresh")
    }
}
