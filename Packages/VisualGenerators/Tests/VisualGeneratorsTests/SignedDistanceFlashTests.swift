// SignedDistanceFlashTests.swift — VIS-017-T07 (VIS-017-R6, R7; S4): the 64 flash samples of the SDF shapes stay below
// full white (ACC-012), and bass bursts alternating with silence keep every one of FX-019's 17 areas within the
// envelope's transition budget with Reduce flashing on and off, portrait and landscape with the strongest glow
// (FlashSafety's independent `FlashAnalysis`). Pure Swift (Linux too).
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class SignedDistanceFlashTests: XCTestCase {
    func testSamplesStayBelowFullWhiteAndShowTheShapes() {
        let areas = NoiseFieldFlashAreas()
        let stops: [LinearColor] = (0..<16).map { (_: Int) -> LinearColor in LinearColor(red: 1, green: 1, blue: 1, alpha: 1) }
        let pose = SignedDistancePose(angle: 0.7, sphereRadius: 0.7, brightness: 0.8)
        stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> Void in
            areas.sampleSignedDistance(pose: pose, quality: .high, paletteStops: p.baseAddress!, width: 390, height: 844)
        }
        var lit = 0
        for k in 0..<NoiseFieldFlashAreas.sampleCount {
            XCTAssertLessThanOrEqual(areas.color(k).relativeLuminance, 0.8 + 1e-5)
            if areas.value(k) > 0.05 { lit += 1 }
        }
        XCTAssertGreaterThan(lit, 2, "the shapes are seen by the estimate")
        XCTAssertLessThan(lit, NoiseFieldFlashAreas.sampleCount, "the background is dark")
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let envelope = FlashEnvelope()
        let areas = NoiseFieldFlashAreas()
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in VisualPalette.mono.color(bar: k, of: 16) }
        var drive = SignedDistanceDrive()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<120 {
            let groups: MandalaBandGroups = (f / 6) % 2 == 0 ? MandalaBandGroups(low: 1, mid: 1, high: 1) : .silence
            drive.advance(groups: groups, timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, reduceMotion: false)
            stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> Void in
                areas.sampleSignedDistance(pose: drive.pose, quality: .low, paletteStops: p.baseAddress!, width: width, height: height)
            }
            let gain: Float = areas.gain(envelope: envelope, transfer: transfer, frameTime: dt, configuration: configuration)
            var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
            out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
                areas.levels(gain: gain, transfer: transfer, into: b)
            }
            shown.append(out)
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
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.005)
        return worst
    }

    func testBassBurstsObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-017 SDF shapes (CPU estimate, mono, Low, bursts every 0.1 s for 2 s): worst transitions per window:"]
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
