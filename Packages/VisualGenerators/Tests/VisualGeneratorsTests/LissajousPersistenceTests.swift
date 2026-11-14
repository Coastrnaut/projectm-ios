// LissajousPersistenceTests.swift — VIS-004-T08: automatic gain, persistence decay, the ACC-012 caps, the
// FX-019 envelope and fixed storage (VIS-004-S3, S4; R6, R8, R9, R13, R17). Frame durations are injected;
// nothing reads the wall clock. Runs everywhere, Linux included.
import FlashSafety
import XCTest
@testable import VisualGenerators

final class LissajousPersistenceTests: XCTestCase {
    private let frame = 1.0 / 60

    // MARK: Gain (R6)

    func testQuietSineReachesThePlotEdge() {
        let layout = LissajousLayout()
        layout.layout(LissajousFixture.history(.quadrature, amplitude: 0.05))
        XCTAssertEqual(ShapeMetrics(layout: layout).meanRadius, 1, accuracy: 0.01, "90 % of the half size: |(u, v)| = 1")
        let p = layout.point(0)
        let radius: Double = ((p.x - 128) * (p.x - 128) + (p.y - 96) * (p.y - 96)).squareRoot()
        XCTAssertEqual(radius, 0.9 * 96, accuracy: 0.01 * 0.9 * 96)
    }

    func testGainHoldsThenReleasesWithItsHalfLifeUnderTheInjectedClock() {
        var gain = LissajousAutoGain()
        XCTAssertEqual(gain.update(peak: 0.8, frameDuration: frame), 0.8)
        var t = 0.0
        var level = 0.8
        for _ in 0..<120 {   // 2 s of a quiet passage
            t += frame
            level = gain.update(peak: 0.05, frameDuration: frame)
            let expected: Double = t <= LissajousAutoGain.holdSeconds ? 0.8 : max(0.8 * pow(0.5, (t - 0.5) / 0.5), 0.05)
            XCTAssertEqual(level, expected, accuracy: 1e-9, "t = \(t)")
        }
        XCTAssertEqual(level, 0.8 * pow(0.5, 3), accuracy: 1e-9)
        // It never falls below the current peak, and a rise is followed at once.
        for _ in 0..<600 { level = gain.update(peak: 0.05, frameDuration: frame) }
        XCTAssertEqual(level, 0.05, accuracy: 1e-12)
        XCTAssertEqual(gain.update(peak: 0.3, frameDuration: frame), 0.3)
        // Floor and frame-duration clamp.
        var quiet = LissajousAutoGain()
        XCTAssertEqual(quiet.update(peak: 0.001, frameDuration: frame), LissajousAutoGain.floor)
        var jump = LissajousAutoGain()
        jump.update(peak: 1, frameDuration: frame)
        XCTAssertEqual(jump.update(peak: 0, frameDuration: 10), 1, "a 10 s frame counts as 0.1 s: still holding")
        XCTAssertEqual(jump.update(peak: 0, frameDuration: .nan), 1, "NaN counts as 0 s")
    }

    // MARK: Persistence (R8)

    func testSnapshotWeightsFollowTheHalfLifeAndDieAtFourHalfLives() {
        let h = 0.2
        let layout = LissajousLayout(configuration: LissajousConfiguration(persistenceHalfLife: h))
        let loud = LissajousFixture.history(.quadrature)
        for _ in 0..<30 { layout.layout(loud, frameDuration: frame) }   // 0.5 s of signal
        XCTAssertGreaterThan(layout.snapshotCount, 0)
        XCTAssertLessThanOrEqual(layout.snapshotCount, LissajousLayout.snapshotCapacity)
        for i in 0..<layout.snapshotCount {
            let age = layout.snapshotAge(i)
            XCTAssertEqual(layout.snapshotWeight(i), (pow(0.5, age / h) - 1.0 / 16) / (15.0 / 16), accuracy: 1e-9)
            XCTAssertLessThan(age, 4 * h)
        }
        // Silence: no new snapshot, the old ones keep fading and are gone after 4 half-lives.
        let silence = LissajousFixture.silence()
        var t = 0.0
        while t < 4 * h + 0.05 {
            let before = layout.snapshotCount
            layout.layout(silence, frameDuration: frame)
            t += frame
            XCTAssertLessThanOrEqual(layout.snapshotCount, before, "no snapshot is taken in silence")
            XCTAssertEqual(layout.pointCount, 0)
            for i in 0..<layout.snapshotCount {
                XCTAssertEqual(layout.snapshotWeight(i), (pow(0.5, layout.snapshotAge(i) / h) - 1.0 / 16) / (15.0 / 16), accuracy: 1e-9)
            }
        }
        XCTAssertEqual(layout.snapshotCount, 0, "none survives 4 half-lives")
        XCTAssertEqual(LissajousLayout.snapshotWeight(age: 0, halfLife: h), 1)
        XCTAssertEqual(LissajousLayout.snapshotWeight(age: 4 * h, halfLife: h), 0, accuracy: 1e-12, "0 at the cut: no pop")
        XCTAssertEqual(LissajousLayout.snapshotWeight(age: 1, halfLife: 0), 0)
        XCTAssertEqual(layout.vertexCount(), 0)
    }

    func testGhostsDrawBehindTheTraceWithTheirWeightAndClearOnModeChangeOffAndReset() {
        let layout = LissajousLayout(configuration: LissajousConfiguration(persistenceHalfLife: 0.2))
        var end = 60_000
        for _ in 0..<12 {
            layout.layout(LissajousFixture.history(.quadrature, endingAt: end), frameDuration: frame)
            end += 735
        }
        let ghosts = layout.snapshotCount
        XCTAssertGreaterThan(ghosts, 1)
        let ghostRegions = ghosts * LissajousLayout.snapshotSegments
        XCTAssertEqual(layout.flashRegionCount, ghostRegions + LissajousLayout.traceSegments)
        XCTAssertEqual(layout.flashRegionColor(0).alpha, Float(layout.snapshotWeight(0)), accuracy: 1e-6, "the oldest first")
        XCTAssertEqual(layout.flashRegionColor(ghostRegions).alpha, 1, "the trace last, at full weight")
        XCTAssertGreaterThan(layout.vertexCount(), 6 * LissajousLayout.traceSegments)

        var c = layout.configuration
        c.mode = .midSide
        layout.configuration = c
        XCTAssertEqual(layout.snapshotCount, 0, "a mode change clears the ghosts")
        layout.layout(LissajousFixture.history(.quadrature), frameDuration: frame)
        XCTAssertEqual(layout.snapshotCount, 1)
        c.persistenceHalfLife = 0
        layout.configuration = c
        XCTAssertEqual(layout.snapshotCount, 0, "off clears the ghosts")
        c.persistenceHalfLife = 0.2
        layout.configuration = c
        layout.layout(LissajousFixture.history(.quadrature), frameDuration: frame)
        layout.reset()
        XCTAssertEqual(layout.snapshotCount, 0)
        XCTAssertEqual(layout.autoGain, LissajousAutoGain())
        XCTAssertEqual(layout.clock, 0)
    }

    func testPersistenceOffByDefaultTakesNoSnapshot() {
        let layout = LissajousLayout()
        for _ in 0..<30 { layout.layout(LissajousFixture.history(.quadrature), frameDuration: frame) }
        XCTAssertEqual(layout.snapshotCount, 0)
        XCTAssertEqual(layout.vertexCount(), 6 * LissajousLayout.traceSegments)
    }

    // MARK: ACC-012 caps (R9)

    func testHalfLifeFollowsTheTrailsCaps() {
        typealias C = LissajousConfiguration
        XCTAssertEqual(C.persistenceHalfLife(enabled: false, clamp: .standard), 0)
        XCTAssertEqual(C.persistenceHalfLife(enabled: true, clamp: .standard), 0.2)
        let custom = { (intensity: Double) -> SafetyClamp in
            SafetyClamp(profile: SensorySafetyProfile(preset: .custom,
                                                      custom: SensorySafetyLimits(flashesPerSecond: 3, riseLimitPerSecond: nil,
                                                                                  intensityLimit: intensity)),
                        reduceFlashingSetting: false)
        }
        XCTAssertEqual(C.persistenceHalfLife(enabled: true, clamp: custom(0.2)), 0.1, accuracy: 1e-12)
        XCTAssertEqual(C.persistenceHalfLife(enabled: true, clamp: custom(0)), 0, "a cap of 0 turns it off")
        let reduce = SafetyClamp(profile: .standard, reduceFlashingSetting: true)
        XCTAssertLessThanOrEqual(C.persistenceHalfLife(enabled: true, clamp: reduce), 0.25)
        XCTAssertEqual(C(persistenceHalfLife: .nan).persistenceHalfLife, 0)
        XCTAssertEqual(C(persistenceHalfLife: 9).persistenceHalfLife, 0.5)
        XCTAssertEqual(C(lineThickness: .infinity).lineThickness, C.defaultLineThickness)
    }

    // MARK: FX-019 envelope (R13)

    func testLoudSilentAlternationStaysWithinTheEnvelope() {
        for enabled in [true, false] {
            let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
            let layout = LissajousLayout(configuration: LissajousConfiguration(persistenceHalfLife: 0.2, lineThickness: 0.05,
                                                                               palette: .mono))
            let limiter = FlashSafetyLimiter()
            let loud = LissajousFixture.history(.quadrature, amplitude: 1)
            let silence = LissajousFixture.silence()
            var shown: [[FlashLevels]] = []
            for f in 0..<90 {   // 1.5 s at 60 Hz (more than one 1 s window; the Debug cost is the per-frame bisection)
                layout.layout(f % 2 == 0 ? loud : silence, frameDuration: frame, width: 390, height: 844)
                let gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: frame, enabled: enabled)
                var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
                out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
                    layout.meanLevels(gain: gain, transfer: IdentityLuminanceTransfer(), into: b)
                }
                shown.append(out)
            }
            let times = [Double](repeating: frame, count: shown.count)
            var worst = 0
            for z in 0..<FlashZones.count {
                for s in FlashSignal.allCases {
                    let series: [Double] = shown.map { (levels: [FlashLevels]) -> Double in levels[z][s] }
                    let result = FlashAnalysis.analyze(series, frameTimes: times, threshold: configuration.threshold(for: s))
                    worst = max(worst, result.maxTransitionsPerWindow)
                    if let rate = configuration.riseRatePerSecond {
                        XCTAssertLessThanOrEqual(result.maxRise, rate * frame + 1e-9, "area \(z) \(s)")
                    }
                }
            }
            XCTAssertLessThanOrEqual(worst, configuration.transitionBudget, "Reduce flashing \(enabled)")
            let lit: Double = shown.map { (levels: [FlashLevels]) -> Double in levels[FlashZones.wholeFrame].luminance }.max() ?? 0
            XCTAssertGreaterThan(lit, 0.005, "frames were not blank")
        }
    }

    // MARK: Storage (R17)

    func testStorageNeverChangesOver120Frames() {
        let layout = LissajousLayout(configuration: LissajousConfiguration(persistenceHalfLife: 0.2))
        let before = layout.storageAddresses
        let histories = [LissajousFixture.history(.quadrature), LissajousFixture.history(.inPhase), LissajousFixture.silence()]
        let levels = UnsafeMutableBufferPointer<FlashLevels>.allocate(capacity: FlashZones.count)
        defer { levels.deallocate() }
        for f in 0..<120 {
            layout.layout(histories[f % 3], frameDuration: frame)
            layout.meanLevels(gain: 1, transfer: IdentityLuminanceTransfer(), into: levels)
        }
        XCTAssertEqual(layout.storageAddresses, before)
    }
}
