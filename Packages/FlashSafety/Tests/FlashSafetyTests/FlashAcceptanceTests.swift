// FlashAcceptanceTests.swift — FX-019-T07, T17, T18: the roadmap acceptance ("Synthetic alternating
// white/black frames obey configured limiter") through the pure envelope, both configurations,
// every area and signal. Each output series is measured by `FlashAnalysis` (independent of the
// envelope's state). Constant frame times; seeded noise; no clock.
import XCTest
@testable import FlashSafety

final class FlashAcceptanceTests: XCTestCase {
    struct Sequence {
        let name: String
        let frames: [[FlashLevels]]     // 17 areas per frame, at gain 1
        let frameTime: Double
    }

    static let white = FlashLevels(luminance: 1, redness: 0)
    static let black = FlashLevels.zero
    static let red = FlashLevels(luminance: 0.2126, redness: 1)
    static let gray50 = FlashLevels(luminance: FlashColor.decodeSRGB(0.5), redness: 0)

    static func solid(_ l: FlashLevels) -> [FlashLevels] { [FlashLevels](repeating: l, count: FlashZones.count) }

    /// Alternation between `a` and `b`, each held for half a period of `hertz`, at 60 fps, `seconds`.
    static func alternate(_ a: FlashLevels, _ b: FlashLevels, hertz: Double, seconds: Double = 3) -> [[FlashLevels]] {
        let n = Int(seconds * 60)
        let half = max(1, Int((60 / hertz / 2).rounded()))
        return (0..<n).map { solid(($0 / half) % 2 == 0 ? a : b) }
    }

    static var sequences: [Sequence] {
        var noise: [[FlashLevels]] = []
        var seed: UInt64 = 0x5EED
        for _ in 0..<180 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let encoded = Double(seed >> 11) / Double(1 << 53)
            noise.append(solid(FlashLevels(luminance: FlashColor.decodeSRGB(encoded), redness: 0)))
        }
        let fade = (0..<600).map { i -> [FlashLevels] in
            let t = Double(i) / 60
            return solid(FlashLevels(luminance: t <= 5 ? 0.2 * t : max(0, 1 - 0.2 * (t - 5)), redness: 0))
        }
        let single = (0..<61).map { solid($0 == 30 ? white : black) }
        let local = (0..<180).map { i -> [FlashLevels] in
            var f = solid(FlashLevels(luminance: 0.2, redness: 0))
            f[5] = i % 2 == 0 ? white : black
            f[FlashZones.wholeFrame].luminance = 0.2 + (i % 2 == 0 ? 0.8 / 16 : -0.2 / 16)
            return f
        }
        return [
            Sequence(name: "white/black 60 Hz", frames: alternate(white, black, hertz: 30), frameTime: 1.0 / 60),
            Sequence(name: "white/black 30 Hz", frames: alternate(white, black, hertz: 15), frameTime: 1.0 / 60),
            Sequence(name: "white/black 15 Hz", frames: alternate(white, black, hertz: 7.5), frameTime: 1.0 / 60),
            Sequence(name: "white/black 10 Hz", frames: alternate(white, black, hertz: 5), frameTime: 1.0 / 60),
            Sequence(name: "red/black 10 Hz", frames: alternate(red, black, hertz: 5), frameTime: 1.0 / 60),
            Sequence(name: "50% gray steps 5 Hz", frames: alternate(gray50, black, hertz: 5), frameTime: 1.0 / 60),
            Sequence(name: "slow fade 0.2/s", frames: fade, frameTime: 1.0 / 60),
            Sequence(name: "single flash", frames: single, frameTime: 1.0 / 60),
            Sequence(name: "noise", frames: noise, frameTime: 1.0 / 60),
            Sequence(name: "tile-5 strobe 60 Hz", frames: local, frameTime: 1.0 / 60),
        ]
    }

    /// Runs a sequence; returns the shown levels per frame and the gains.
    static func run(_ s: Sequence, _ c: FlashEnvelopeConfiguration) -> (shown: [[FlashLevels]], gains: [Float]) {
        let e = FlashEnvelope()
        var shown: [[FlashLevels]] = [], gains: [Float] = []
        for f in s.frames {
            let g = f.withUnsafeBufferPointer { e.gain(inputs: $0, frameTime: s.frameTime, configuration: c) }
            gains.append(g)
            shown.append(f.map { FlashLevels(luminance: $0.luminance * Double(g), redness: $0.redness * Double(g)) })
        }
        return (shown, gains)
    }

    struct Measured { var worstTransitions = 0; var worstRiseOverBound = 0.0; var brighter = false }

    static func measure(_ s: Sequence, _ shown: [[FlashLevels]], _ c: FlashEnvelopeConfiguration) -> Measured {
        var m = Measured()
        let times = [Double](repeating: s.frameTime, count: shown.count)
        for z in 0..<FlashZones.count {
            for signal in FlashSignal.allCases {
                let series = shown.map { $0[z][signal] }
                let r = FlashAnalysis.analyze(series, frameTimes: times, threshold: c.threshold(for: signal), window: c.window)
                m.worstTransitions = max(m.worstTransitions, r.maxTransitionsPerWindow)
                if let rate = c.riseRatePerSecond { m.worstRiseOverBound = max(m.worstRiseOverBound, r.maxRise - rate * s.frameTime) }
                for i in 0..<shown.count where shown[i][z][signal] > s.frames[i][z][signal] { m.brighter = true }
            }
        }
        return m
    }

    func testAcceptanceMatrix() {
        var report = ["FX-019 acceptance, pure envelope (worst transitions per 1 s window over 17 areas × 2 signals; input → output):"]
        for s in Self.sequences {
            for (label, c) in [("on", FlashEnvelopeConfiguration.reduceFlashing), ("off", .alwaysOn)] {
                let first = Self.run(s, c), second = Self.run(s, c)
                XCTAssertEqual(first.gains, second.gains, "\(s.name) \(label): deterministic")
                let input = Self.measure(s, s.frames, c)
                let m = Self.measure(s, first.shown, c)
                XCTAssertLessThanOrEqual(m.worstTransitions, c.transitionBudget, "\(s.name) \(label)")
                XCTAssertLessThanOrEqual(m.worstRiseOverBound, 1e-9, "\(s.name) \(label): rise rate")
                XCTAssertFalse(m.brighter, "\(s.name) \(label): never brighter than the input")
                report.append("\(s.name) [\(label)] transitions/window \(input.worstTransitions) → \(m.worstTransitions) (limit \(c.transitionBudget)); min gain \(String(format: "%.4f", first.gains.min() ?? 1))")
            }
        }
        print(report.joined(separator: "\n"))
    }

    /// FX-019-T17 (US2): with Reduce flashing off, ordinary content is untouched.
    func testOffLeavesSingleFlashesAndFadesUnchanged() {
        for name in ["single flash", "slow fade 0.2/s"] {
            let s = Self.sequences.first { $0.name == name }!
            XCTAssertTrue(Self.run(s, .alwaysOn).gains.allSatisfy { $0 == 1 }, name)
        }
        // A 4-frame alternation (VIS-001's pass-through case) fits the cap.
        let four = Sequence(name: "4 frames", frames: Array(Self.alternate(Self.white, Self.black, hertz: 30).prefix(4)), frameTime: 1.0 / 60)
        XCTAssertTrue(Self.run(four, .alwaysOn).gains.allSatisfy { $0 == 1 })
    }

    /// FX-019-T18 (US3): a slow fade is bit-for-bit unchanged with either setting.
    func testSlowFadeIsUnchanged() {
        let s = Self.sequences.first { $0.name == "slow fade 0.2/s" }!
        for c in [FlashEnvelopeConfiguration.reduceFlashing, .alwaysOn] {
            let shown = Self.run(s, c).shown
            XCTAssertEqual(shown, s.frames)
        }
    }

    /// FX-019-T18 (US3): no pumping. After a clamped 60 Hz strobe the input stays white; the output
    /// rises monotonically to it. Reports the frames to recovery.
    func testRecoveryAfterAStrobeIsMonotone() {
        var report: [String] = []
        for (label, c) in [("on", FlashEnvelopeConfiguration.reduceFlashing), ("off", .alwaysOn)] {
            let frames = Self.alternate(Self.white, Self.black, hertz: 30, seconds: 1) + [[FlashLevels]](repeating: Self.solid(Self.white), count: 360)
            let shown = Self.run(Sequence(name: "recovery", frames: frames, frameTime: 1.0 / 60), c).shown
            let tail = shown.suffix(360).map { $0[FlashZones.wholeFrame].luminance }
            for i in 1..<tail.count { XCTAssertGreaterThanOrEqual(tail[i], tail[i - 1], "\(label) frame \(i): no oscillation") }
            XCTAssertEqual(tail.last ?? 0, 1, accuracy: 1e-9, "\(label): recovers fully")
            let recovered = tail.firstIndex { $0 >= 1 - 1e-9 } ?? -1
            report.append("\(label): \(recovered) frames (\(String(format: "%.2f", Double(recovered) / 60)) s) from the strobe's end to full brightness")
        }
        print("FX-019 recovery after a strobe (monotone):\n" + report.joined(separator: "\n"))
    }
}
