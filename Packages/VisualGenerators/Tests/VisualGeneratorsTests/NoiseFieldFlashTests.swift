// NoiseFieldFlashTests.swift — VIS-013-T08 (VIS-013-R6, S3): the noise field feeds FX-019's strobe safety envelope like
// the other native visuals. Full bands alternating with silence every 0.1 s at 60 Hz for 3 s, the mono palette at the
// highest frequency and octaves, through `NoiseFieldFlashAreas` as `NoiseFieldGenerator` applies it, with and without
// the strongest glow's luminance model, measured with FlashSafety's independent `FlashAnalysis`. The clock is
// injected. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class NoiseFieldFlashTests: XCTestCase {
    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let envelope = FlashEnvelope()
        let areas = NoiseFieldFlashAreas()
        let c = NoiseFieldConfiguration(frequency: 8, octaves: 6, palette: .mono)
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16) }
        var drive = NoiseFieldDrive()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<180 {
            let loud = (f / 6) % 2 == 0
            let groups = loud ? MandalaBandGroups(low: 1, mid: 1, high: 1) : .silence
            drive.advance(groups: groups, timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, frameDuration: dt, configuration: c)
            stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> Void in
                areas.sample(configuration: c, drive: drive, paletteStops: p.baseAddress!, width: width, height: height)
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
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.05,
                             "frames were not blank")
        return worst
    }

    func testBandsAlternatingWithSilenceObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-013 noise field (CPU estimate, mono, 8 cells, 6 octaves, full bands alternating with silence for 3 s): worst transitions per window:"]
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

    func testSamplesAreTheFieldsColoursCappedAtTheBrightness() {
        let areas = NoiseFieldFlashAreas()
        let c = NoiseFieldConfiguration(palette: .mono)
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16) }
        var drive = NoiseFieldDrive()
        drive.advance(groups: MandalaBandGroups(low: 1, mid: 1, high: 1), timeNanoseconds: 0, frameDuration: 0.1, configuration: c)
        stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> Void in
            areas.sample(configuration: c, drive: drive, paletteStops: p.baseAddress!, width: 100, height: 100)
        }
        for k in 0..<NoiseFieldFlashAreas.sampleCount {
            let n: Float = areas.value(k)
            XCTAssertEqual(areas.color(k).red, (0.25 + 0.75 * n) * Float(drive.brightness), accuracy: 1e-6)
            XCTAssertLessThanOrEqual(areas.color(k).red, 0.8)
        }
    }
}
