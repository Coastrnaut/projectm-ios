// StrobeEnvelopeTests.swift — FX-019-T13 (CPU, every host): native visuals through the strobe safety
// envelope after the glow (FX-019-R4, R9, R11; research FX-019-D6). Area levels come from the
// layout's exact geometry; outputs are measured with FlashSafety's independent `FlashAnalysis`.
// Pure arithmetic with constant frame times; no clock.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class StrobeEnvelopeTests: XCTestCase {
    private let width = 1179, height = 2556
    private let strongest = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))

    private func levels<T: FrameLuminanceTransfer>(_ layout: CircularSpectrumLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { layout.meanLevels(gain: gain, transfer: transfer, into: $0) }
        return out
    }

    func testTilesAddUpToTheWholeFrame() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b64, palette: .spectrum))
        layout.layout((0..<64).map { Float($0 % 7) / 6 }, width: width, height: height)
        let l = levels(layout, gain: 0.7, IdentityLuminanceTransfer())
        XCTAssertEqual(l[FlashZones.wholeFrame].luminance, layout.meanLuminance(gain: 0.7, transfer: IdentityLuminanceTransfer()), accuracy: 1e-12)
        let tileMean = l.prefix(FlashZones.tileCount).reduce(0) { $0 + $1.luminance } / Double(FlashZones.tileCount)
        XCTAssertEqual(tileMean, l[FlashZones.wholeFrame].luminance, accuracy: l[FlashZones.wholeFrame].luminance * 1e-3,
                       "exact tile coverage of the tessellated bars (chords differ from arcs by < 0.1 %)")
        // The red bars (hue 0°) sit at the top of the ring: the redness is in the upper tiles.
        layout.layout([Float](repeating: 1, count: 64), width: width, height: height)
        let full = levels(layout, gain: 1, IdentityLuminanceTransfer())
        XCTAssertGreaterThan(full[1].redness + full[2].redness + full[5].redness + full[6].redness, 0)
        XCTAssertEqual(full[12].redness + full[13].redness + full[14].redness + full[15].redness, 0, "bottom row: no bars")
    }

    func testTheGlowOnlyRaisesTheLevels() {
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b64, palette: .mono))
        layout.layout([Float](repeating: 1, count: 64), width: width, height: height)
        let plain = levels(layout, gain: 1, IdentityLuminanceTransfer()), glow = levels(layout, gain: 1, strongest)
        for z in 0..<FlashZones.count { XCTAssertGreaterThanOrEqual(glow[z].luminance, plain[z].luminance, "area \(z)") }
        XCTAssertEqual(glow[FlashZones.wholeFrame].luminance, layout.meanLuminance(gain: 1, transfer: strongest), accuracy: 1e-12)
    }

    /// Bands alternating 0/1 every frame for 2 s at 60 fps through the limiter as the generator
    /// applies it; every area's output measured against the budget. Four representative cases
    /// (owner rule 7): white bars without glow and spectrum bars with the strongest glow, each with
    /// Reduce flashing on and off.
    func testAlternatingBandsObeyTheEnvelope() {
        var report = ["FX-019 native visual (CPU, 1179 × 2556, bands 0/1 every frame): worst transitions per window, input → output:"]
        for (palette, glow) in [(VisualPalette.mono, false), (.spectrum, true)] {
            for enabled in [true, false] {
                let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
                let limiter = FlashSafetyLimiter()
                let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b64, palette: palette))
                let reference = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b64, palette: palette))
                let full = [Float](repeating: 1, count: 64), empty = [Float](repeating: 0, count: 64)
                var shown: [[FlashLevels]] = [], input: [[FlashLevels]] = []
                for f in 0..<120 {
                    let target = f % 2 == 0 ? full : empty
                    let values = target.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: 1.0 / 60, enabled: enabled)) }
                    layout.layout(values, width: width, height: height)
                    reference.layout(target, width: width, height: height)
                    let gain: Float
                    if glow {
                        gain = limiter.gain(for: layout, transfer: strongest, frameTime: 1.0 / 60, enabled: enabled)
                        shown.append(levels(layout, gain: gain, strongest))
                        input.append(levels(reference, gain: 1, strongest))
                    } else {
                        gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: 1.0 / 60, enabled: enabled)
                        shown.append(levels(layout, gain: gain, IdentityLuminanceTransfer()))
                        input.append(levels(reference, gain: 1, IdentityLuminanceTransfer()))
                    }
                }
                let times = [Double](repeating: 1.0 / 60, count: shown.count)
                var worstIn = 0, worstOut = 0
                for z in 0..<FlashZones.count {
                    for s in FlashSignal.allCases {
                        let t = configuration.threshold(for: s)
                        worstIn = max(worstIn, FlashAnalysis.analyze(input.map { $0[z][s] }, frameTimes: times, threshold: t).maxTransitionsPerWindow)
                        let out = FlashAnalysis.analyze(shown.map { $0[z][s] }, frameTimes: times, threshold: t)
                        worstOut = max(worstOut, out.maxTransitionsPerWindow)
                        if let rate = configuration.riseRatePerSecond {
                            XCTAssertLessThanOrEqual(out.maxRise, rate / 60 + 1e-9, "\(palette) glow \(glow) area \(z) \(s)")
                        }
                    }
                }
                let label = "\(palette) glow \(glow ? "max" : "off") Reduce flashing \(enabled ? "on" : "off")"
                XCTAssertLessThanOrEqual(worstOut, configuration.transitionBudget, label)
                report.append("\(label): \(worstIn) → \(worstOut) (limit \(configuration.transitionBudget))")
            }
        }
        print(report.joined(separator: "\n"))
    }

    /// FX-019-R11: the host's loop restart calls `reset()`, which restarts only the bar slew.
    func testResetKeepsTheEnvelopeHistory() {
        let limiter = FlashSafetyLimiter()
        var gain: Float = 1
        for f in 0..<7 {
            gain = limiter.gain(barsLuminance: f % 2 == 0 ? 0.5 : 0, backgroundLuminance: 0, frameTime: 1.0 / 60, enabled: false)
        }
        XCTAssertLessThan(gain, 1, "the always-on cap holds the 7th transition")
        limiter.reset()
        _ = limiter.gain(barsLuminance: 0, backgroundLuminance: 0, frameTime: 1.0 / 60, enabled: false)
        XCTAssertLessThan(limiter.gain(barsLuminance: 0.5, backgroundLuminance: 0, frameTime: 1.0 / 60, enabled: false), 1,
                          "still held after reset()")
        limiter.resetEnvelope()
        XCTAssertEqual(limiter.gain(barsLuminance: 0.5, backgroundLuminance: 0, frameTime: 1.0 / 60, enabled: false), 1)
    }
}
