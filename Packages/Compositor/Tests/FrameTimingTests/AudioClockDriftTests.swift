// AudioClockDriftTests.swift — PERF-013-T04 (specs/216-perf-013-audio-render-sync, US2, S1-S3): the roadmap acceptance
// "Injected timestamp drift is detected and corrected within budget".
//
// Simulated time only (no wall clock). The bus maps samples to host time at the nominal 44.1 kHz from an exact anchor;
// the audio's real clock runs at 44.1 kHz × (1 + drift). Analysis frames end every 512 samples and become readable
// `latency` + a deterministic one-sided jitter (0…10 ms) after their audio was captured; a 60 Hz display link reads the
// newest readable frame at each tick and presents one refresh later. True age = presentation − true capture time.
// With this jitter each 1 s bucket minimum carries about 1 ms of noise, which sets the budget (spec S1, research D3).
// A verdict needs 30 s of audio and a slope that stays straight and steady over 10 more fits (QA-011 D2, 2026-11-20),
// so it comes at about 40 s and the budget starts at 45 s.
import FrameTiming
import XCTest

final class AudioClockDriftTests: XCTestCase {
    struct Run {
        var earlyErrors: [Double] = []   // |meter age − true age| (ns) from 45 s to 55 s of audio
        var errorsAfterBudget: [Double] = []   // from 55 s on
        var maxStep: Double = 0                // largest correction change per frame (ns)
        var maxOvershoot: Double = 0           // how far the correction passed the true offset (ns)
        var summary = FeatureAgeSummary()
        var nonZeroCorrections: Int = 0
        var maxTrueAge: Double = 0             // the largest true age (ns)
        var maxAgeExcess: Double = 0           // how far a measured age rose above the largest true age so far (ns)
    }

    static let rate: Double = 44_100
    /// Budget (spec S1): age error ≤ 3 ms from 45 s of audio, ≤ 2 ms from 55 s; correction never past the truth by > 2 ms.
    static let earlySeconds: Double = 45
    static let budgetSeconds: Double = 55
    static let earlyBudget: Double = 3_000_000
    static let budget: Double = 2_000_000
    static let overshootBudget: Double = 2_000_000

    /// - Parameters: drift as a fraction (250e-6 = +250 ppm); `step` adds `stepNanoseconds` of latency from `stepAt` s;
    ///   `jitterNanoseconds` is the one-sided jitter's range; `wander` adds a slowly varying latency (ns) at an audio time (s).
    func simulate(drift: Double, seconds: Double = 90, latency: Double = 5_000_000, stepAt: Double? = nil,
                  stepNanoseconds: Double = 0, jitterNanoseconds: Double = 10_000_000, wander: ((Double) -> Double)? = nil,
                  seed initial: UInt64 = 0x1234_5678) -> Run {
        let meter = FeatureAgeMeter()
        let anchor: Double = 1_000_000_000_000
        let tick: Double = 1_000_000_000 / 60
        var seed: UInt64 = initial
        func jitter() -> Double {   // deterministic LCG, 0…jitterNanoseconds
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 40) / Double(1 << 24) * jitterNanoseconds
        }
        func capture(_ sample: Int64) -> Double { anchor + Double(sample) / (Self.rate * (1 + drift)) * 1e9 }
        func bus(_ sample: Int64) -> UInt64 { UInt64(anchor + Double(sample) / Self.rate * 1e9) }
        var run = Run()
        var nextFrame: Int64 = 0   // frame index j: ends at 2,048 + 512 j
        var readable: (Int64, Double)? = nil
        var pending: (Int64, Double) = (0, 0)
        func makePending(_ j: Int64) -> (Int64, Double) {
            let sample: Int64 = 2_048 + 512 * j
            let seconds: Double = (capture(sample) - anchor) / 1e9
            let extra: Double = stepAt.map { (at: Double) -> Double in seconds >= at ? stepNanoseconds : 0 } ?? 0
            let slow: Double = wander?(seconds) ?? 0
            return (sample, capture(sample) + latency + extra + slow + jitter())
        }
        pending = makePending(0)
        var lastSequence: Int64 = -1
        var previousCorrection: Double = 0
        var k: Double = 1
        while k * tick < seconds * 1e9 {
            let now: Double = anchor + k * tick
            // Frames become readable in order (the bus publishes in ID order); jitter can only delay.
            while pending.1 <= now {
                readable = (nextFrame, pending.1)
                nextFrame += 1
                pending = makePending(nextFrame)
                if pending.1 < readable!.1 { pending.1 = readable!.1 }
            }
            var stamp: FeatureFrameStamp?
            if let (j, _) = readable, j != lastSequence {
                lastSequence = j
                let sample: Int64 = 2_048 + 512 * j
                stamp = FeatureFrameStamp(session: 1, sequence: UInt64(j + 1), sessionSample: sample, busHostNanoseconds: bus(sample))
            }
            let presentation: Double = now + tick
            if let age = meter.frame(stamp, arrivalNanoseconds: UInt64(now), presentationNanoseconds: UInt64(presentation)),
               let (j, _) = readable {
                let sample: Int64 = 2_048 + 512 * j
                let trueAge: Double = presentation - capture(sample)
                run.maxTrueAge = max(run.maxTrueAge, trueAge)
                run.maxAgeExcess = max(run.maxAgeExcess, age - run.maxTrueAge)
                let audioSeconds: Double = Double(sample) / Self.rate
                if audioSeconds >= Self.budgetSeconds {
                    run.errorsAfterBudget.append(abs(age - trueAge))
                } else if audioSeconds >= Self.earlySeconds {
                    run.earlyErrors.append(abs(age - trueAge))
                }
                let correction: Double = meter.correctionNanoseconds
                if correction != 0 { run.nonZeroCorrections += 1 }
                run.maxStep = max(run.maxStep, abs(correction - previousCorrection))
                previousCorrection = correction
                let trueOffset: Double = capture(sample) - Double(bus(sample))
                // Overshoot: the correction beyond the true offset, in the offset's direction.
                let beyond: Double = trueOffset >= 0 ? correction - trueOffset : trueOffset - correction
                run.maxOvershoot = max(run.maxOvershoot, beyond)
            }
            k += 1
        }
        run.summary = meter.summary()
        return run
    }

    func assertWithinBudget(_ run: Run, late: Double = AudioClockDriftTests.budget, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(run.earlyErrors.isEmpty, file: file, line: line)
        XCTAssertFalse(run.errorsAfterBudget.isEmpty, file: file, line: line)
        XCTAssertLessThanOrEqual(run.earlyErrors.max() ?? .infinity, Self.earlyBudget, "≤ 3 ms from 45 s", file: file, line: line)
        XCTAssertLessThanOrEqual(run.errorsAfterBudget.max() ?? .infinity, late, "≤ 2 ms from 55 s to 90 s",
                                 file: file, line: line)
        XCTAssertLessThanOrEqual(run.maxStep, FeatureAgeMeter.maxStepNanoseconds + 1e-6, "steps ≤ 0.25 ms", file: file, line: line)
        XCTAssertLessThanOrEqual(run.maxOvershoot, Self.overshootBudget, "never past the truth by > 2 ms", file: file, line: line)
    }

    func testPositiveDriftIsDetectedAndCorrectedWithinBudget() {
        for seed: UInt64 in [7, 99, 2_026] {   // other jitter sequences, same budget
            let other = simulate(drift: 250e-6, seed: seed)
            XCTAssertTrue(other.summary.driftDetected, "seed \(seed)")
            assertWithinBudget(other)
        }
        let run = simulate(drift: 250e-6)
        XCTAssertTrue(run.summary.driftDetected)
        XCTAssertEqual(run.summary.detections, 1)
        XCTAssertEqual(run.summary.driftPPM ?? 0, -250, accuracy: 25, "residual slope = −drift")
        assertWithinBudget(run)
    }

    func testNegativeDriftIsDetectedAndCorrectedWithinBudget() {
        for seed: UInt64 in [7, 99, 2_026] {
            let other = simulate(drift: -250e-6, seed: seed)
            XCTAssertTrue(other.summary.driftDetected, "seed \(seed)")
            assertWithinBudget(other)
        }
        let run = simulate(drift: -250e-6)
        XCTAssertTrue(run.summary.driftDetected)
        XCTAssertEqual(run.summary.driftPPM ?? 0, 250, accuracy: 25)
        assertWithinBudget(run)
    }

    func testNoDriftNeverCorrects() {
        for seed: UInt64 in [7, 99, 2_026] {
            let other = simulate(drift: 0, seed: seed)
            XCTAssertEqual(other.nonZeroCorrections, 0, "seed \(seed)")
            XCTAssertEqual(other.summary.detections, 0, "seed \(seed)")
        }
        let run = simulate(drift: 0)
        XCTAssertFalse(run.summary.driftDetected)
        XCTAssertEqual(run.summary.detections, 0)
        XCTAssertEqual(run.nonZeroCorrections, 0)
        XCTAssertLessThanOrEqual(run.errorsAfterBudget.max() ?? .infinity, 1, "no drift: age exact")
        XCTAssertLessThanOrEqual(run.earlyErrors.max() ?? .infinity, 1)
    }

    func testLatencyStepIsNotDrift() {
        // AUD-013's offset raised by 100 ms at 20 s: a step, not a slope.
        let run = simulate(drift: 0, seconds: 40, stepAt: 20, stepNanoseconds: 100_000_000)
        XCTAssertFalse(run.summary.driftDetected)
        XCTAssertEqual(run.nonZeroCorrections, 0)
        XCTAssertGreaterThanOrEqual(run.summary.steps, 1)
    }

    func testStepDuringDriftKeepsTheCorrection() {
        let run = simulate(drift: 250e-6, stepAt: 25, stepNanoseconds: 50_000_000)
        XCTAssertTrue(run.summary.driftDetected)
        XCTAssertEqual(run.summary.detections, 1)
        XCTAssertGreaterThanOrEqual(run.summary.steps, 1)
        // A step splits the history into two intercepts (the slope rests on shorter spans); the same budget holds.
        assertWithinBudget(run)
    }

    func testEstimatorNeedsThirtyBucketsAndTenConfirmations() {
        var estimator = AudioClockDriftEstimator()
        // 0.2 ms per second of audio = 200 ppm, observed at every bucket start.
        for second in 0..<30 {
            estimator.observe(sessionSample: Int64(second) * 44_100, residualNanoseconds: Double(second) * 200_000)
        }
        XCTAssertNil(estimator.driftPPM, "29 closed buckets: no fit")
        for second in 30..<39 {
            estimator.observe(sessionSample: Int64(second) * 44_100, residualNanoseconds: Double(second) * 200_000)
        }
        XCTAssertEqual(estimator.driftPPM ?? 0, 200, accuracy: 0.001)
        XCTAssertFalse(estimator.detected, "9 passing fits: not confirmed yet")
        XCTAssertTrue(estimator.observe(sessionSample: 39 * 44_100, residualNanoseconds: 7_800_000))
        XCTAssertEqual(estimator.driftPPM ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(estimator.targetNanoseconds(atSessionSample: 44_100), 200_000, accuracy: 0.01)
        estimator.reset()
        XCTAssertFalse(estimator.detected)
        XCTAssertEqual(estimator.targetNanoseconds(atSessionSample: 44_100), 0)
    }

    /// QA-011 (D1/D2, 2026-11-15): start-up lateness after a visual switch fitted as −3,300 and −5,600 ppm. No audio
    /// clock drifts that much, so such a slope is never a detection and nothing is corrected.
    func testImplausibleSlopeIsNeverDrift() {
        var estimator = AudioClockDriftEstimator()
        for second in 0..<40 {   // −5 ms per second of audio = −5,000 ppm
            estimator.observe(sessionSample: Int64(second) * 44_100, residualNanoseconds: -Double(second) * 5_000_000)
        }
        XCTAssertEqual(estimator.driftPPM ?? 0, -5_000, accuracy: 0.001)
        XCTAssertFalse(estimator.detected)
        XCTAssertEqual(estimator.targetNanoseconds(atSessionSample: 40 * 44_100), 0)
    }

    // MARK: - QA-011 D2 microphone (2026-11-20): jitter and wandering latency are not drift

    /// Large one-sided jitter only (0…30 ms, a busy main thread): no verdict, the estimate stays near 0.
    func testJitterOnlyIsNotDrift() {
        for seed: UInt64 in [7, 99, 2_026] {
            let run = simulate(drift: 0, jitterNanoseconds: 30_000_000, seed: seed)
            XCTAssertEqual(run.summary.detections, 0, "seed \(seed)")
            XCTAssertEqual(run.nonZeroCorrections, 0, "seed \(seed)")
            XCTAssertLessThanOrEqual(abs(run.summary.driftPPM ?? .infinity), 50, "seed \(seed): about 0 ppm")
        }
    }

    /// The D2 trace: the latency floor wanders by ±15 ms over two minutes (local slopes up to ±785 ppm, the fits went
    /// from −753 to +316 ppm). Not a clock rate: never detected, never corrected, the age stays exact. The slower,
    /// smaller wanders keep every local slope under the 300 ppm cap, so the straightness and halves checks must reject
    /// them.
    func testWanderingLatencyIsNotDrift() {
        let cases: [(seed: UInt64, period: Double, amplitude: Double)] = [
            (7, 120, 15_000_000), (99, 90, 15_000_000), (2_026, 160, 15_000_000),   // the D2 shape
            (7, 120, 5_000_000), (2_026, 90, 3_500_000),                            // local slopes ≤ 262 ppm
        ]
        for c in cases {
            let run = simulate(drift: 0, seconds: 180,
                               wander: { (t: Double) -> Double in c.amplitude * sin(2 * .pi * t / c.period) }, seed: c.seed)
            let label: String = "seed \(c.seed), period \(c.period) s, ±\(c.amplitude / 1e6) ms"
            XCTAssertEqual(run.summary.detections, 0, label)
            XCTAssertEqual(run.nonZeroCorrections, 0, label)
            XCTAssertLessThanOrEqual(run.errorsAfterBudget.max() ?? .infinity, 1, "no correction: age exact, " + label)
        }
    }

    /// A wander slow enough to look straight over the whole 64 s window (±8 ms over 200 s: at most 251 ppm, steady for
    /// 30 s around each crossing) cannot be told from drift by arrival times alone, and may be "corrected". The bound
    /// then holds: the correction follows the floor's own movement, so the measured age never rises above the largest
    /// true age by more than 3 ms (2 ms margin + about 1 ms of bucket noise), and never by the slope × session time.
    func testSlowWanderCorrectionNeverInflatesTheAge() {
        for seed: UInt64 in [7, 99, 2_026] {
            let run = simulate(drift: 0, seconds: 240,
                               wander: { (t: Double) -> Double in 8_000_000 * sin(2 * .pi * t / 200) }, seed: seed)
            XCTAssertLessThanOrEqual(run.maxAgeExcess, 3_000_000, "seed \(seed)")
            XCTAssertLessThanOrEqual(run.maxStep, FeatureAgeMeter.maxStepNanoseconds + 1e-6, "seed \(seed)")
        }
    }

    /// A true, constant 80 ppm (a plausible crystal difference) is detected and corrected within budget.
    func testEightyPPMDriftIsDetected() {
        for seed: UInt64 in [7, 99, 2_026] {
            let run = simulate(drift: 80e-6, seed: seed)
            XCTAssertTrue(run.summary.driftDetected, "seed \(seed)")
            XCTAssertEqual(run.summary.driftPPM ?? 0, -80, accuracy: 20, "seed \(seed)")
            assertWithinBudget(run)
        }
    }

    /// Whatever the slope, the target never exceeds the floor's own movement (+ 2 ms) nor opposes it: a fitted slope
    /// over a floor that has not moved cannot inflate the age.
    func testTargetIsBoundedByTheFloorMovement() {
        var estimator = AudioClockDriftEstimator()
        for second in 0..<40 {   // +200 ppm for 40 s: 39 buckets closed, the floor moved 7.6 ms
            estimator.observe(sessionSample: Int64(second) * 44_100, residualNanoseconds: Double(second) * 200_000)
        }
        XCTAssertTrue(estimator.detected)
        XCTAssertEqual(estimator.targetNanoseconds(atSessionSample: 39 * 44_100), 7_800_000, accuracy: 1)
        // A floor that moved less than the slope claims (the session started long before the floor was watched):
        var late = AudioClockDriftEstimator()
        for second in 500..<540 {
            late.observe(sessionSample: Int64(second) * 44_100, residualNanoseconds: Double(second - 500) * 200_000)
        }
        XCTAssertTrue(late.detected)
        XCTAssertEqual(late.targetNanoseconds(atSessionSample: 539 * 44_100), 9_800_000, accuracy: 1,
                       "not 107.8 ms: the floor's 7.6 ms carried 1 s on, + 2 ms")
    }

    func testNewSessionResetsTheCorrection() {
        let meter = FeatureAgeMeter()
        var sample: Int64 = 0
        var host: UInt64 = 1_000_000_000
        for _ in 0..<(50 * 60) {   // 50 s of +200 ppm residual growth
            sample += 735
            host += 16_666_667
            let bus: UInt64 = 1_000_000_000 + UInt64(Double(sample) / 44_100 * 1e9)
            let drift: UInt64 = UInt64(Double(sample) / 44_100 * 200_000)   // 0.2 ms per s
            meter.frame(FeatureFrameStamp(session: 1, sequence: UInt64(sample), sessionSample: sample, busHostNanoseconds: bus),
                        arrivalNanoseconds: bus + 5_000_000 + drift, presentationNanoseconds: bus + 20_000_000)
        }
        XCTAssertTrue(meter.summary().driftDetected)
        XCTAssertGreaterThan(meter.correctionNanoseconds, 0)
        meter.frame(FeatureFrameStamp(session: 2, sequence: 1, sessionSample: 2_048, busHostNanoseconds: host),
                    arrivalNanoseconds: host + 5_000_000, presentationNanoseconds: host + 20_000_000)
        XCTAssertEqual(meter.correctionNanoseconds, 0)
        XCTAssertFalse(meter.summary().driftDetected)
    }
}
