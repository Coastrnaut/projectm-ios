// FlashSafetyLimiterTests.swift — VIS-001-T27: Reduce flashing for the circular spectrum
// (VIS-001-R10, S5; research VIS-001-D7). The worst input: every band alternating between 0 and 1
// each frame, at frame times from 1/120 s to 0.2 s, through the limiter and the real layout, exactly
// as the generator applies them. Pure arithmetic; no clock.
import XCTest
@testable import VisualGenerators

final class FlashSafetyLimiterTests: XCTestCase {
    private let frameTimes: [Double] = [1.0 / 120, 1.0 / 60, 1.0 / 30, 0.1, 0.2]

    /// Runs `frames` frames of alternating full/empty bands; returns the worst luminance rise and
    /// the worst bar step, each relative to its bound (≤ 1 passes).
    private func run(palette: VisualPalette, count: SpectrumBarCount, frameTime dt: Double, frames: Int = 600,
                     enabled: Bool = true) -> (rise: Double, step: Double, luminances: [Double]) {
        let limiter = FlashSafetyLimiter()
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: count, palette: palette))
        let n = count.rawValue
        let full = [Float](repeating: 1, count: n), empty = [Float](repeating: 0, count: n)
        var previousValues: [Float]?
        var previousLuminance: Double?
        var worstRise = 0.0, worstStep = 0.0
        var luminances: [Double] = []
        let clamped = min(dt, FlashSafetyLimiter.maxFrameTime)
        for f in 0..<frames {
            let target = f % 2 == 0 ? full : empty
            let shown = target.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: dt, enabled: enabled)) }
            layout.layout(shown, width: 1179, height: 2556)
            let parts = layout.luminanceComponents()
            let gain = limiter.gain(barsLuminance: parts.bars, backgroundLuminance: parts.background, frameTime: dt, enabled: enabled)
            let luminance = layout.meanRelativeLuminance(gain: gain)
            luminances.append(luminance)
            if let p = previousValues {
                for k in 0..<n { worstStep = max(worstStep, Double(abs(shown[k] - p[k])) / (Double(FlashSafetyLimiter.maxBarStepPerSecond) * clamped)) }
            }
            if let p = previousLuminance, luminance > p {
                worstRise = max(worstRise, (luminance - p - 1e-6) / (FlashSafetyLimiter.maxLuminanceRisePerSecond * clamped))
            }
            previousValues = shown
            previousLuminance = luminance
        }
        return (worstRise, worstStep, luminances)
    }

    func testAlternatingFramesObeyBothBounds() {
        var report: [String] = []
        for palette in VisualPalette.allCases {
            for count in SpectrumBarCount.allCases {
                for dt in frameTimes {
                    let r = run(palette: palette, count: count, frameTime: dt)
                    XCTAssertLessThanOrEqual(r.rise, 1, "\(palette) N=\(count.rawValue) dt=\(dt): luminance rose too fast")
                    XCTAssertLessThanOrEqual(r.step, 1 + 1e-5, "\(palette) N=\(count.rawValue) dt=\(dt): a bar moved too fast")
                    if count == .b64 { report.append("\(palette) dt=\(String(format: "%.4f", dt)) rise=\(String(format: "%.3f", r.rise)) step=\(String(format: "%.3f", r.step)) maxL=\(String(format: "%.4f", r.luminances.max() ?? 0))") }
                }
            }
        }
        print("VIS-001 flash limiter (fraction of each bound used):\n" + report.joined(separator: "\n"))
    }

    func testDisabledIsPassThrough() {
        let limiter = FlashSafetyLimiter()
        let values: [Float] = [0, 1, 0.5, .nan, 2]
        let shown = values.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: 1.0 / 60, enabled: false)) }
        XCTAssertEqual(shown, [0, 1, 0.5, 0, 1], "sanitized, not slewed")
        XCTAssertEqual(limiter.gain(barsLuminance: 0.9, backgroundLuminance: 0, frameTime: 1.0 / 60, enabled: false), 1)
        let r = run(palette: .mono, count: .b16, frameTime: 1.0 / 60, frames: 4, enabled: false)
        XCTAssertGreaterThan(r.luminances[0], 0.2, "full bands shown at once (a full white ring covers about 23.5 % of a 1179 × 2556 output)")
        XCTAssertEqual(r.luminances[1], 0, "empty at once")
    }

    func testRisingLuminanceIsDimmedAndRecovers() {
        let limiter = FlashSafetyLimiter()
        XCTAssertEqual(limiter.gain(barsLuminance: 0, backgroundLuminance: 0, frameTime: 0.1, enabled: true), 1)
        // From black to a bright frame: at most 0.25·0.1 = 0.025 per frame.
        let g = limiter.gain(barsLuminance: 0.5, backgroundLuminance: 0, frameTime: 0.1, enabled: true)
        XCTAssertEqual(Double(g) * 0.5, 0.025, accuracy: 1e-6)
        let g2 = limiter.gain(barsLuminance: 0.5, backgroundLuminance: 0, frameTime: 0.1, enabled: true)
        XCTAssertEqual(Double(g2) * 0.5, 0.05, accuracy: 1e-6)
        // A darker frame is never brightened.
        XCTAssertEqual(limiter.gain(barsLuminance: 0.01, backgroundLuminance: 0, frameTime: 0.1, enabled: true), 1)
    }

    func testResetStartsFromTheNextFrame() {
        let limiter = FlashSafetyLimiter()
        let ones = [Float](repeating: 1, count: 8)
        _ = ones.withUnsafeBufferPointer { limiter.limitValues($0, frameTime: 1.0 / 60, enabled: true) }
        _ = limiter.gain(barsLuminance: 0.4, backgroundLuminance: 0, frameTime: 1.0 / 60, enabled: true)
        limiter.reset()
        let shown = ones.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: 1.0 / 60, enabled: true)) }
        XCTAssertEqual(shown, ones, "no ramp from a stale state after reset")
        XCTAssertEqual(limiter.gain(barsLuminance: 0.4, backgroundLuminance: 0, frameTime: 1.0 / 60, enabled: true), 1)
    }

    func testFrameTimeIsClamped() {
        let limiter = FlashSafetyLimiter()
        let zero = [Float](repeating: 0, count: 4), one = [Float](repeating: 1, count: 4)
        _ = zero.withUnsafeBufferPointer { limiter.limitValues($0, frameTime: 0.1, enabled: true) }
        let shown = one.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: 5, enabled: true)) }
        XCTAssertEqual(shown, [Float](repeating: 0.4, count: 4), "4/s × 0.1 s at most")
        let negative = zero.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: -1, enabled: true)) }
        XCTAssertEqual(negative, shown, "a negative frame time moves nothing")
    }
}
