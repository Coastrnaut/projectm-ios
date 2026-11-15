// KaleidoscopeDriveFlashTests.swift — VIS-014-T05 (VIS-014-R5, R7, R8; S3, S4; research VIS-014-D3): the turning
// drive and flash safety. Silence settles at 0.1 rad/s and full bass at 0.4 (never more), half with Reduce Motion; the
// rotation never runs backwards, advances at most 1 s of turning per frame and stays 0 when unfolded. Bursts
// alternating with silence keep every area of the folded field within FX-019's envelope with Reduce flashing on and
// off, measured with FlashSafety's independent `FlashAnalysis`. The clock is injected. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class KaleidoscopeDriveFlashTests: XCTestCase {
    private func settle(_ groups: MandalaBandGroups, _ c: NoiseFieldConfiguration, frames: Int = 240) -> NoiseFieldDrive {
        var drive = NoiseFieldDrive()
        for f in 0..<frames {
            drive.advance(groups: groups, timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, frameDuration: 1.0 / 60, configuration: c)
        }
        return drive
    }

    func testTurningSpeedFollowsTheBassWithinTheCap() {
        let c = NoiseFieldConfiguration.kaleidoscope()
        XCTAssertEqual(settle(.silence, c).spin, 0.1, accuracy: 0.001)
        XCTAssertEqual(settle(MandalaBandGroups(low: 1, mid: 1, high: 1), c).spin, 0.4, accuracy: 0.004)
        XCTAssertEqual(KaleidoscopeFold.spinTarget(low: 5, reduceMotion: false), 0.4)
        XCTAssertEqual(KaleidoscopeFold.spinTarget(low: .nan, reduceMotion: false), 0.1)
        let calm = NoiseFieldConfiguration.kaleidoscope(reduceMotion: true)
        XCTAssertEqual(settle(MandalaBandGroups(low: 1, mid: 1, high: 1), calm).spin, 0.2, accuracy: 0.002, "Reduce Motion halves it")
        XCTAssertEqual(settle(.silence, calm).spin, 0.05, accuracy: 0.001)
    }

    func testRotationRunsForwardBoundedAndOnlyWhenFolded() {
        let c = NoiseFieldConfiguration.kaleidoscope()
        var drive = NoiseFieldDrive()
        let loud = MandalaBandGroups(low: 1, mid: 1, high: 1)
        drive.advance(groups: loud, timeNanoseconds: 0, frameDuration: 0.1, configuration: c)
        XCTAssertEqual(drive.rotation, 0, "the first frame is the anchor")
        drive.advance(groups: loud, timeNanoseconds: 10_000_000_000, frameDuration: 0.1, configuration: c)
        XCTAssertGreaterThan(drive.rotation, 0)
        XCTAssertLessThanOrEqual(drive.rotation, KaleidoscopeFold.maximumSpin * 1.0 + 1e-12, "a 10 s gap turns at most 1 s worth")
        let before: Double = drive.rotation
        drive.advance(groups: loud, timeNanoseconds: 5_000_000_000, frameDuration: 0.1, configuration: c)
        XCTAssertEqual(drive.rotation, before, "time going backwards does not turn it back")
        XCTAssertEqual(settle(MandalaBandGroups(low: 1, mid: 1, high: 1), NoiseFieldConfiguration()).rotation, 0, "the plain field never turns")
        let long = settle(.silence, c, frames: 60 * 120)
        XCTAssertTrue(long.rotation >= 0 && long.rotation < 2 * Double.pi, "wrapped to one turn")
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let envelope = FlashEnvelope()
        let areas = NoiseFieldFlashAreas()
        let c = NoiseFieldConfiguration(frequency: 8, octaves: 6, palette: .mono, wedges: 7)
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16) }
        var drive = NoiseFieldDrive()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<180 {
            let groups: MandalaBandGroups = (f / 6) % 2 == 0 ? MandalaBandGroups(low: 1, mid: 1, high: 1) : .silence
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
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.05)
        return worst
    }

    func testBurstsAlternatingWithSilenceObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-014 kaleidoscope (CPU estimate, mono, 7 wedges, 8 cells, 6 octaves, bursts for 3 s): worst transitions per window:"]
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

    func testFlashSamplesAreFolded() {
        let c = NoiseFieldConfiguration.kaleidoscope(wedges: 4, palette: .mono)
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16) }
        var drive = NoiseFieldDrive()
        drive.advance(groups: .silence, timeNanoseconds: 0, frameDuration: 0.1, configuration: c)
        let areas = NoiseFieldFlashAreas()
        stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> Void in
            areas.sample(configuration: c, drive: drive, paletteStops: p.baseAddress!, width: 160, height: 160)
        }
        // Rotation 0, 4 wedges on a square grid: sample (column, row) and its quarter turn about the centre agree.
        let side: Int = NoiseFieldFlashAreas.gridSide
        for (column, row) in [(0, 1), (2, 5), (3, 3), (6, 1)] {
            let turned: Int = column * side + (side - 1 - row)
            XCTAssertEqual(areas.value(row * side + column), areas.value(turned), accuracy: 1e-4, "(\(column), \(row))")
        }
    }
}
