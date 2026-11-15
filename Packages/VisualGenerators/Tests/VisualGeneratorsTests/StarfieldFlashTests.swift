// StarfieldFlashTests.swift — VIS-016-T05: the starfield's perspective and safety on the CPU (VIS-016-R5, R7; S4).
// Size and alpha grow as a star approaches (between the fades); the mean light never exceeds the 0.05 bound at the
// densest, fastest field with full bass; that field with bass bursts alternating with silence (every 0.1 s, 1.5 s at
// 60 Hz), through the limiter as `StarfieldGenerator` applies it, with and without the strongest glow's luminance
// model, stays within FX-019's transition budget in all 17 areas, measured with FlashSafety's independent
// `FlashAnalysis` (as VIS-009's test). The clock is injected. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class StarfieldFlashTests: XCTestCase {
    private typealias C = StarfieldConfiguration

    func testSizeAndAlphaGrowAsAStarApproachesAndStayBounded() {
        let big = 195.0
        var lastSide = 0.0, lastAlpha = 0.0
        var z = C.far - C.fadeInDepth
        while z > C.near + C.fadeOutDepth {
            let side = StarfieldLayout.side(z: z, big: big)
            let alpha = StarfieldLayout.alpha(z: z)
            XCTAssertGreaterThanOrEqual(side, lastSide)
            XCTAssertGreaterThanOrEqual(alpha, lastAlpha)
            XCTAssertLessThanOrEqual(side, C.maximumSide * big)
            XCTAssertGreaterThanOrEqual(side, C.minimumSidePixels)
            XCTAssertLessThanOrEqual(alpha, C.maximumAlpha)
            lastSide = side; lastAlpha = alpha; z -= 0.01
        }
        XCTAssertEqual(StarfieldLayout.alpha(z: C.far), 0, "fades in from the far plane")
        XCTAssertEqual(StarfieldLayout.alpha(z: C.near), 0, "fades out at the near plane")
    }

    func testMeanLightNeverExceedsTheBound() {
        let sim = StarfieldSimulation(configuration: C(density: 2000, speed: .fast, palette: .mono))
        let layout = StarfieldLayout()
        var scaled = false
        var largest = 0.0
        for n in 0...60 {
            sim.setBass(1)
            sim.advance(toNanoseconds: UInt64(n) * 1_000_000_000 / 60)
            // A phone-sized frame (the bound is not reached there) and a tiny one (1 px stars cover much of it).
            for (w, h) in [(390, 844), (24, 16)] {
                layout.layout(simulation: sim, width: w, height: h)
                var light = 0.0
                for k in 0..<layout.squareCount {
                    let c = layout.color(k)
                    light += layout.side(k) * layout.side(k) * Double(c.alpha) * Double(c.relativeLuminance)
                }
                let mean = light / Double(w * h)
                XCTAssertLessThanOrEqual(mean, C.lightBound + 1e-9, "frame \(n), \(w)×\(h)")
                XCTAssertEqual(mean, layout.meanLight, accuracy: 1e-9)
                if w > 100 { largest = max(largest, mean) }
                scaled = scaled || layout.lightScale < 1
            }
        }
        XCTAssertTrue(scaled, "the bound was exercised")
        print("VIS-016 starfield: largest mean light at 390×844, 2000 stars, Fast, full bass: \(largest) (bound \(C.lightBound))")
    }

    private func levels<T: FrameLuminanceTransfer>(_ layout: StarfieldLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            layout.meanLevels(gain: gain, transfer: transfer, into: b)
        }
        return out
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let limiter = FlashSafetyLimiter()
        let sim = StarfieldSimulation(configuration: C(density: 5000, speed: .fast, palette: .mono))
        let layout = StarfieldLayout()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<90 {
            sim.setBass((f / 6) % 2 == 0 ? 1 : 0)
            sim.advance(toNanoseconds: UInt64(f) * 1_000_000_000 / 60)
            layout.layout(simulation: sim, width: width, height: height)
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

    func testDensestFastestFieldWithBassBurstsObeysTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-016 starfield (CPU, 2000 white stars, Fast, bass bursts every 0.1 s for 1.5 s): worst transitions per window:"]
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
