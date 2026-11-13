// BloomLuminanceModelTests.swift — FX-001-T05: the luminance transfer that lets Reduce flashing
// see the glow, the layout's mean luminance through a transfer, and the limiter's bisection gain
// (FX-001-R10; research FX-001-D4). Pure arithmetic; runs on Linux.
import XCTest
@testable import VisualGenerators
@testable import VisualEffects

final class BloomLuminanceModelTests: XCTestCase {
    private func y(_ c: LinearColor) -> Double { Double(c.relativeLuminance) }

    func testModelIsIdentityWhenPassThroughAndAddsThresholdedLuminanceOtherwise() {
        let colors = [LinearColor(red: 1, green: 1, blue: 1), LinearColor(red: 0.8, green: 0.1, blue: 0.3),
                      LinearColor(red: 0.2, green: 0.2, blue: 0.2), .opaqueBlack]
        for c in colors {
            XCTAssertEqual(BloomLuminanceModel(parameters: BloomParameters()).outputLuminance(ofFlatColor: c), y(c))
            XCTAssertEqual(BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 0)).outputLuminance(ofFlatColor: c), y(c))
            let p = BloomParameters(enabled: true, intensity: 0.8, threshold: 0.5, knee: 0.5)
            XCTAssertEqual(BloomLuminanceModel(parameters: p).outputLuminance(ofFlatColor: c),
                           y(c) + Double(Float(0.8)) * y(p.thresholded(c)), accuracy: 1e-9)
        }
        XCTAssertEqual(IdentityLuminanceTransfer().outputLuminance(ofFlatColor: LinearColor(red: 1, green: 0, blue: 0)), 0.2126, accuracy: 1e-6)
    }

    func testModelIsNondecreasingInBrightness() {
        let model = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, threshold: 0.3, knee: 1))
        for base in [LinearColor(red: 1, green: 0.5, blue: 0.1), LinearColor(red: 0.2, green: 1, blue: 1)] {
            var previous = -1.0
            for i in 0...1000 {
                let s = Float(i) / 1000
                let v = model.outputLuminance(ofFlatColor: LinearColor(red: base.red * s, green: base.green * s, blue: base.blue * s))
                XCTAssertGreaterThanOrEqual(v, previous - 1e-12)
                previous = v
            }
        }
    }

    func testLayoutMeanLuminanceThroughTheIdentityMatchesTheVIS001Formula() {
        for palette in VisualPalette.allCases {
            for count in SpectrumBarCount.allCases {
                let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: count, palette: palette))
                let bands = (0..<count.rawValue).map { Float($0 % 5) / 4 }
                layout.layout(bands, width: 1179, height: 2556)
                for gain: Float in [0, 0.3, 1] {
                    XCTAssertEqual(layout.meanLuminance(gain: gain, transfer: IdentityLuminanceTransfer()),
                                   layout.meanRelativeLuminance(gain: gain), accuracy: 1e-6, "\(palette) N=\(count.rawValue) g=\(gain)")
                }
            }
        }
    }

    func testBisectionGain() {
        // Disabled: 1, and the first frame: 1.
        let limiter = FlashSafetyLimiter()
        XCTAssertEqual(limiter.gain(frameTime: 1.0 / 60, enabled: true) { Double($0) * 0.5 }, 1, "first frame")
        let off = FlashSafetyLimiter()
        _ = off.gain(frameTime: 1.0 / 60, enabled: false) { _ in 0 }
        XCTAssertEqual(off.gain(frameTime: 1.0 / 60, enabled: false) { Double($0) * 0.9 }, 1)

        // A linear model reproduces the closed form of gain(barsLuminance:…).
        for (bars, background) in [(0.5, 0.0), (0.3, 0.01), (0.9, 0.05)] {
            let a = FlashSafetyLimiter(), b = FlashSafetyLimiter()
            _ = a.gain(barsLuminance: 0, backgroundLuminance: background, frameTime: 1.0 / 60, enabled: true)
            _ = b.gain(frameTime: 1.0 / 60, enabled: true) { _ in background }
            let closed = a.gain(barsLuminance: bars, backgroundLuminance: background, frameTime: 1.0 / 60, enabled: true)
            let bisected = b.gain(frameTime: 1.0 / 60, enabled: true) { Double($0) * bars + background }
            XCTAssertEqual(bisected, closed, accuracy: 1e-6)
            XCTAssertLessThanOrEqual(Double(bisected) * bars + background, background + FlashSafetyLimiter.maxLuminanceRisePerSecond / 60 + 1e-12)
        }

        // A nonlinear model: the shown luminance never exceeds the ceiling.
        let c = FlashSafetyLimiter()
        _ = c.gain(frameTime: 0.02, enabled: true) { _ in 0 }
        let model: (Float) -> Double = { g in Double(g) * 0.2 + Double(max(g - 0.1, 0) * max(g - 0.1, 0)) * 3 }
        let g = c.gain(frameTime: 0.02, enabled: true, luminanceAtGain: model)
        XCTAssertLessThanOrEqual(model(g), 0.25 * 0.02 + 1e-12)
        XCTAssertGreaterThan(model(g), 0.25 * 0.02 * 0.999, "the largest feasible gain, within the bisection's precision")

        // A background above the ceiling: gain 0.
        let d = FlashSafetyLimiter()
        _ = d.gain(frameTime: 0.02, enabled: true) { _ in 0 }
        XCTAssertEqual(d.gain(frameTime: 0.02, enabled: true) { Double($0) + 0.5 }, 0)
    }
}
