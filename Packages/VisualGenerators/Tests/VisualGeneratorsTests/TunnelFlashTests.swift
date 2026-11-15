// TunnelFlashTests.swift — VIS-015-T04 (VIS-015-R3, R6 to R8; S3, S4; contract T1, T4): the speed cap (3 rings/s at any
// tempo and pace, half with Reduce Motion), the bass brightness cap, the texture's seams, and bursts alternating with
// silence at the cap kept within FX-019's envelope in all 17 areas with Reduce flashing on and off (FlashSafety's
// independent `FlashAnalysis`). Pure Swift (Linux too).
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class TunnelFlashTests: XCTestCase {
    func testSpeedNeverExceedsTheCapAndReduceMotionHalvesIt() {
        for pace in TunnelPace.allCases {
            for bpm in [0.0, 30, 60, 120, 200, 400, 1000] {
                let tempo = TunnelTempo(bpm: bpm, confidence: 1)
                let full: Double = TunnelDrive.targetSpeed(tempo: tempo, ringsPerBeat: pace.ringsPerBeat, reduceMotion: false)
                let calm: Double = TunnelDrive.targetSpeed(tempo: tempo, ringsPerBeat: pace.ringsPerBeat, reduceMotion: true)
                XCTAssertLessThanOrEqual(full, TunnelDrive.maximumRingsPerSecond, "\(pace) \(bpm)")
                XCTAssertEqual(calm, full / 2, accuracy: 1e-12, "\(pace) \(bpm)")
            }
        }
        XCTAssertEqual(TunnelDrive.targetSpeed(tempo: TunnelTempo(bpm: 120, confidence: 1), ringsPerBeat: 2, reduceMotion: false), 3)
    }

    func testBassBrightensWithinTheCap() {
        XCTAssertEqual(TunnelDrive.brightnessTarget(low: 0, reduceMotion: false), 0.5)
        XCTAssertEqual(TunnelDrive.brightnessTarget(low: 1, reduceMotion: false), 0.8, accuracy: 1e-12)
        XCTAssertEqual(TunnelDrive.brightnessTarget(low: 9, reduceMotion: false), 0.8, accuracy: 1e-12)
        XCTAssertEqual(TunnelDrive.brightnessTarget(low: .nan, reduceMotion: false), 0.5)
        XCTAssertEqual(TunnelDrive.brightnessTarget(low: 1, reduceMotion: true), 0.65, accuracy: 1e-12, "half the punch")
        var drive = TunnelDrive()
        for f in 0..<120 {
            drive.advance(groups: MandalaBandGroups(low: 1, mid: 1, high: 1), tempo: .none, timeNanoseconds: UInt64(f) * 16_666_667,
                          configuration: .tunnel())
            XCTAssertLessThanOrEqual(drive.brightness, TunnelDrive.maximumBrightness)
        }
        XCTAssertGreaterThan(drive.brightness, 0.79)
    }

    func testTextureIsSeamlessAroundAndPeriodicInDepth() {
        for v in [Float(0.3), 2.7, 11.1] {
            XCTAssertEqual(TunnelMapping.texture(u: 0, v: v, seed: 1301), TunnelMapping.texture(u: 1, v: v, seed: 1301), accuracy: 1e-6)
            let near: Float = TunnelMapping.texture(u: 0.0005, v: v, seed: 1301)
            let far: Float = TunnelMapping.texture(u: 0.9995, v: v, seed: 1301)
            XCTAssertEqual(near, far, accuracy: 0.01, "no step across the angle cut at depth \(v)")
            XCTAssertEqual(TunnelMapping.texture(u: 0.37, v: v, seed: 7), TunnelMapping.texture(u: 0.37, v: v + 4096, seed: 7), accuracy: 2e-3,
                           "periodic in depth")
        }
        let centre = TunnelMapping.sample(SIMD2<Float>(0, 0), phase: 12, seed: 1301)
        XCTAssertEqual(centre.light, 0, "the centre is lost in the fog")
        XCTAssertTrue(centre.t.isFinite)
        let p = SIMD2<Float>(0.3, -0.2)
        XCTAssertEqual(TunnelMapping.sample(p, phase: 1, seed: 1301).light, TunnelMapping.sample(p, phase: 4097, seed: 1301).light, accuracy: 2e-3)
    }

    private func worstTransitions<T: FrameLuminanceTransfer>(transfer: T, enabled: Bool, width: Int, height: Int) -> Int {
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
        let envelope = FlashEnvelope()
        let areas = NoiseFieldFlashAreas()
        let c = NoiseFieldConfiguration.tunnel(pace: .double, palette: .mono)
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in c.palette.color(bar: k, of: 16) }
        var drive = TunnelDrive()
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<180 {
            let groups: MandalaBandGroups = (f / 6) % 2 == 0 ? MandalaBandGroups(low: 1, mid: 1, high: 1) : .silence
            drive.advance(groups: groups, tempo: TunnelTempo(bpm: 180, confidence: 1), timeNanoseconds: UInt64(f) * 1_000_000_000 / 60,
                          configuration: c)
            stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> Void in
                areas.sampleTunnel(configuration: c, drive: drive, paletteStops: p.baseAddress!, width: width, height: height)
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
        XCTAssertGreaterThan(shown.map { (l: [FlashLevels]) -> Double in l[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.02)
        XCTAssertEqual(drive.speed, 3, accuracy: 1e-6, "at the cap")
        return worst
    }

    func testBurstsAtTheSpeedCapObeyTheEnvelope() {
        let glow = BloomLuminanceModel(parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1))
        var report = ["VIS-015 tunnel (CPU estimate, mono, 2 rings per beat at 180 BPM = 3 rings/s, bursts for 3 s): worst transitions per window:"]
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
