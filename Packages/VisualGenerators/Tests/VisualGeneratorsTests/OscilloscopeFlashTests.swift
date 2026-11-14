// OscilloscopeFlashTests.swift — VIS-003-T11: the oscilloscope feeds FX-019's strobe safety envelope like
// the spectra (VIS-003-R9, S5; FX-019-R4, R9). A 60 Hz alternation of a full-scale 220 Hz sine and
// silence (a thick white line jumping between a waveform and a flat line) for 2 s through the limiter
// (10 ms window, 440 points; about 1.2 s per run in Debug, where the envelope bisects every frame),
// as `OscilloscopeGenerator` applies it, with and without the strongest glow's luminance model,
// measured with FlashSafety's independent `FlashAnalysis`. Constant frame times; no clock. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class OscilloscopeFlashTests: XCTestCase {
    private func levels<T: FrameLuminanceTransfer>(_ layout: OscilloscopeLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { layout.meanLevels(gain: gain, transfer: transfer, into: $0) }
        return out
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let layout = OscilloscopeLayout(configuration: OscilloscopeConfiguration(windowMilliseconds: 10, lineThickness: 0.05, palette: .mono))
        let loud = WaveformSignal(shape: .sine, frequency: 220, amplitude: 1).history(endingAt: 40_000)
        let silent = [Float](repeating: 0, count: 4_096)
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<120 {
            (f % 2 == 0 ? loud : silent).withUnsafeBufferPointer { layout.layout(samples: $0, width: width, height: height) }
            let gain = limiter.gain(for: layout, transfer: transfer, frameTime: dt, enabled: enabled)
            shown.append(levels(layout, gain: gain, transfer))
        }
        let times = [Double](repeating: dt, count: shown.count)
        var worst = 0
        for z in 0..<FlashZones.count {
            for s in FlashSignal.allCases {
                let out = FlashAnalysis.analyze(shown.map { $0[z][s] }, frameTimes: times, threshold: configuration.threshold(for: s))
                worst = max(worst, out.maxTransitionsPerWindow)
                if let rate = configuration.riseRatePerSecond {
                    XCTAssertLessThanOrEqual(out.maxRise, rate * dt + 1e-9, "area \(z) \(s)")
                }
            }
        }
        XCTAssertGreaterThan(shown.map { $0[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.005, "frames were not blank")
        return worst
    }

    func testSixtyHertzAlternationObeysTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-003 oscilloscope (CPU, thick white line, loud/silent every frame for 2 s): worst transitions per window:"]
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

    func testPortraitAndLandscapeKeepTheLineInside() {
        let layout = OscilloscopeLayout(configuration: OscilloscopeConfiguration(windowMilliseconds: 40, lineThickness: 0.05))
        let samples = WaveformSignal(shape: .square, frequency: 110, amplitude: 1).history(endingAt: 40_000)
        for (w, h) in [(390, 844), (844, 390), (1_024, 1_366)] {
            samples.withUnsafeBufferPointer { layout.layout(samples: $0, width: w, height: h) }
            XCTAssertEqual(layout.point(0).x, 0)
            XCTAssertEqual(layout.point(layout.pointCount - 1).x, Double(w), accuracy: 1e-9, "\(w) × \(h): across the full width")
            for j in 0..<layout.pointCount {
                let p = layout.point(j)
                XCTAssertTrue(p.y - layout.thicknessPixels / 2 >= 0 && p.y + layout.thicknessPixels / 2 <= Double(h),
                              "\(w) × \(h): point \(j) and its thickness inside the height")
            }
        }
    }
}
