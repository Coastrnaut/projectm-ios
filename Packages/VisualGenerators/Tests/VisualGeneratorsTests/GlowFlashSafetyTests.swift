// GlowFlashSafetyTests.swift — FX-001-T14 (CPU, every host): Reduce flashing bounds the composited
// frame with the glow on (FX-001-R10, S4; research FX-001-D4). The worst input — every band
// alternating between 0 and 1 each frame — through the limiter, the real layout and the bloom's
// luminance model, exactly as `CircularSpectrumGenerator` combines them. Pure arithmetic; no clock.
import XCTest
@testable import VisualGenerators
@testable import VisualEffects

final class GlowFlashSafetyTests: XCTestCase {
    private let frameTimes: [Double] = [1.0 / 120, 1.0 / 60, 1.0 / 30, 0.2]
    private let strongest = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))

    /// Runs alternating frames; `transferFrom` is the first frame using the glow model (earlier
    /// frames use the VIS-001 path). Returns the worst rise relative to its bound (≤ 1 passes).
    private func run(palette: VisualPalette, frameTime dt: Double, frames: Int = 600, transferFrom: Int = 0,
                     enabled: Bool = true) -> (rise: Double, gains: [Float], peak: Double) {
        let limiter = FlashSafetyLimiter()
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b64, palette: palette))
        let full = [Float](repeating: 1, count: 64), empty = [Float](repeating: 0, count: 64)
        var previous: Double?
        var worst = 0.0, peak = 0.0
        var gains: [Float] = []
        let clamped = min(dt, FlashSafetyLimiter.maxFrameTime)
        for f in 0..<frames {
            let target = f % 2 == 0 ? full : empty
            let shown = target.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: dt, enabled: enabled)) }
            layout.layout(shown, width: 1179, height: 2556)
            let gain: Float
            let luminance: Double
            if f >= transferFrom {
                gain = limiter.gain(for: layout, transfer: strongest, frameTime: dt, enabled: enabled)
                luminance = layout.meanLuminance(gain: gain, transfer: strongest)
            } else {
                let parts = layout.luminanceComponents()
                gain = limiter.gain(barsLuminance: parts.bars, backgroundLuminance: parts.background, frameTime: dt, enabled: enabled)
                luminance = layout.meanRelativeLuminance(gain: gain)
            }
            gains.append(gain)
            peak = max(peak, luminance)
            if let p = previous, luminance > p {
                worst = max(worst, (luminance - p - 1e-8) / (FlashSafetyLimiter.maxLuminanceRisePerSecond * clamped))
            }
            previous = luminance
        }
        return (worst, gains, peak)
    }

    func testAlternatingFramesWithTheStrongestGlowObeyTheRiseBound() {
        var report: [String] = []
        // Owner rule 7 (2026-11-13): every palette at the typical 60 Hz frame time, plus the
        // extreme frame times on one palette, 240 frames each (4 s at 60 Hz, 4 one-second windows),
        // instead of every palette at every frame time for 600 frames (10.1 s after FX-019).
        let cases = VisualPalette.allCases.map { ($0, 1.0 / 60) } + frameTimes.map { (VisualPalette.spectrum, $0) }
        for (palette, dt) in cases {
            do {
                let r = run(palette: palette, frameTime: dt, frames: 240)
                XCTAssertLessThanOrEqual(r.rise, 1, "\(palette) dt=\(dt): composited luminance rose too fast")
                report.append("\(palette) dt=\(String(format: "%.4f", dt)) rise=\(String(format: "%.3f", r.rise)) peak=\(String(format: "%.4f", r.peak))")
            }
        }
        print("FX-001 flash (fraction of the bound used, glow at maximum):\n" + report.joined(separator: "\n"))
    }

    func testTurningTheGlowOnMidRunObeysTheSameBound() {
        // Owner rule 7: two representative cases (typical and slowest frame time) on 240 frames,
        // switching the glow on mid-run, instead of every palette × frame time on 600 frames.
        for (palette, dt) in [(VisualPalette.mono, 1.0 / 60), (VisualPalette.spectrum, frameTimes.max() ?? 0.2)] {
            XCTAssertLessThanOrEqual(run(palette: palette, frameTime: dt, frames: 240, transferFrom: 121).rise, 1, "\(palette) dt=\(dt)")
        }
    }

    func testGlowNeedsLowerGainThanTheBarsAlone() {
        // The limiter sees the glow: under the same input the gains with the model are never higher.
        let withGlow = run(palette: .mono, frameTime: 1.0 / 60, frames: 120).gains
        let without = run(palette: .mono, frameTime: 1.0 / 60, frames: 120, transferFrom: .max).gains
        XCTAssertTrue(zip(withGlow, without).allSatisfy { $0 <= $1 + 1e-6 })
        XCTAssertTrue(zip(withGlow, without).contains { $0 < $1 - 1e-3 }, "the glow actually lowered some gains")
    }

    /// Amended by FX-019 (stricter on purpose): with Reduce flashing off the always-on cap still
    /// applies, so frames pass at gain 1 until a strobe reaches 6 transitions per second.
    func testReduceFlashingOffLeavesGainOneUntilTheCap() {
        let gains = run(palette: .spectrum, frameTime: 1.0 / 60, frames: 60, enabled: false).gains
        XCTAssertEqual(Array(gains.prefix(6)), [1, 1, 1, 1, 1, 1], "five transitions pass unchanged")
        XCTAssertLessThan(gains[6], 1, "the 7th would leave no room for its fall")
    }
}
