// AudioClockDriftTests.swift — PERF-013-T04 (specs/216-perf-013-audio-render-sync, US2, S1-S3): the roadmap acceptance
// "Injected timestamp drift is detected and corrected within budget".
//
// Simulated time only (no wall clock). The bus maps samples to host time at the nominal 44.1 kHz from an exact anchor;
// the audio's real clock runs at 44.1 kHz × (1 + drift). Analysis frames end every 512 samples and become readable
// `latency` + a deterministic one-sided jitter (0…10 ms) after their audio was captured; a 60 Hz display link reads the
// newest readable frame at each tick and presents one refresh later. True age = presentation − true capture time.
// With this jitter each 1 s bucket minimum carries about 1 ms of noise, which sets the budget (spec S1, research D3).
import FrameTiming
import XCTest

final class AudioClockDriftTests: XCTestCase {
    struct Run {
        var earlyErrors: [Double] = []   // |meter age − true age| (ns) from 15 s to 30 s of audio
        var errorsAfterBudget: [Double] = []   // from 30 s on
        var maxStep: Double = 0                // largest correction change per frame (ns)
        var maxOvershoot: Double = 0           // how far the correction passed the true offset (ns)
        var summary = FeatureAgeSummary()
        var nonZeroCorrections: Int = 0
    }

    static let rate: Double = 44_100
    /// Budget (spec S1): age error ≤ 3 ms from 15 s of audio, ≤ 2 ms from 30 s; correction never past the truth by > 2 ms.
    static let earlySeconds: Double = 15
    static let budgetSeconds: Double = 30
    static let earlyBudget: Double = 3_000_000
    static let budget: Double = 2_000_000
    static let overshootBudget: Double = 2_000_000

    /// - Parameters: drift as a fraction (500e-6 = +500 ppm); `step` adds `stepNanoseconds` of latency from `stepAt` s.
    func simulate(drift: Double, seconds: Double = 60, latency: Double = 5_000_000, stepAt: Double? = nil,
                  stepNanoseconds: Double = 0, seed initial: UInt64 = 0x1234_5678) -> Run {
        let meter = FeatureAgeMeter()
        let anchor: Double = 1_000_000_000_000
        let tick: Double = 1_000_000_000 / 60
        var seed: UInt64 = initial
        func jitter() -> Double {   // deterministic LCG, 0…10 ms
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 40) / Double(1 << 24) * 10_000_000
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
            return (sample, capture(sample) + latency + extra + jitter())
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
        XCTAssertLessThanOrEqual(run.earlyErrors.max() ?? .infinity, Self.earlyBudget, "≤ 3 ms from 15 s", file: file, line: line)
        XCTAssertLessThanOrEqual(run.errorsAfterBudget.max() ?? .infinity, late, "≤ 2 ms from 30 s to 60 s",
                                 file: file, line: line)
        XCTAssertLessThanOrEqual(run.maxStep, FeatureAgeMeter.maxStepNanoseconds + 1e-6, "steps ≤ 0.25 ms", file: file, line: line)
        XCTAssertLessThanOrEqual(run.maxOvershoot, Self.overshootBudget, "never past the truth by > 2 ms", file: file, line: line)
    }

    func testPositiveDriftIsDetectedAndCorrectedWithinBudget() {
        for seed: UInt64 in [7, 99, 2_026] {   // other jitter sequences, same budget
            let other = simulate(drift: 500e-6, seed: seed)
            XCTAssertTrue(other.summary.driftDetected, "seed \(seed)")
            assertWithinBudget(other)
        }
        let run = simulate(drift: 500e-6)
        XCTAssertTrue(run.summary.driftDetected)
        XCTAssertEqual(run.summary.detections, 1)
        XCTAssertEqual(run.summary.driftPPM ?? 0, -500, accuracy: 25, "residual slope = −drift")
        assertWithinBudget(run)
    }

    func testNegativeDriftIsDetectedAndCorrectedWithinBudget() {
        for seed: UInt64 in [7, 99, 2_026] {
            let other = simulate(drift: -500e-6, seed: seed)
            XCTAssertTrue(other.summary.driftDetected, "seed \(seed)")
            assertWithinBudget(other)
        }
        let run = simulate(drift: -500e-6)
        XCTAssertTrue(run.summary.driftDetected)
        XCTAssertEqual(run.summary.driftPPM ?? 0, 500, accuracy: 25)
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
        let run = simulate(drift: 500e-6, stepAt: 25, stepNanoseconds: 50_000_000)
        XCTAssertTrue(run.summary.driftDetected)
        XCTAssertEqual(run.summary.detections, 1)
        XCTAssertGreaterThanOrEqual(run.summary.steps, 1)
        // A step splits the history into two intercepts (the slope rests on shorter spans); the same budget holds.
        assertWithinBudget(run)
    }

    func testEstimatorNeedsTenBucketsAndHysteresis() {
        var estimator = AudioClockDriftEstimator()
        // 1 ms per second of audio = 1,000 ppm, observed at every bucket start.
        for second in 0..<10 {
            estimator.observe(sessionSample: Int64(second) * 44_100, residualNanoseconds: Double(second) * 1_000_000)
        }
        XCTAssertNil(estimator.driftPPM, "9 closed buckets: no verdict")
        XCTAssertFalse(estimator.detected)
        XCTAssertTrue(estimator.observe(sessionSample: 10 * 44_100, residualNanoseconds: 10_000_000))
        XCTAssertEqual(estimator.driftPPM ?? 0, 1_000, accuracy: 0.001)
        XCTAssertEqual(estimator.targetNanoseconds(atSessionSample: 44_100), 1_000_000, accuracy: 0.01)
        estimator.reset()
        XCTAssertFalse(estimator.detected)
        XCTAssertEqual(estimator.targetNanoseconds(atSessionSample: 44_100), 0)
    }

    /// QA-011 (D1/D2, 2026-11-15): start-up lateness after a visual switch fitted as −3,300 and −5,600 ppm. No audio
    /// clock drifts that much, so such a slope is never a detection and nothing is corrected.
    func testImplausibleSlopeIsNeverDrift() {
        var estimator = AudioClockDriftEstimator()
        for second in 0..<30 {   // −5 ms per second of audio = −5,000 ppm
            estimator.observe(sessionSample: Int64(second) * 44_100, residualNanoseconds: -Double(second) * 5_000_000)
        }
        XCTAssertEqual(estimator.driftPPM ?? 0, -5_000, accuracy: 0.001)
        XCTAssertFalse(estimator.detected)
        XCTAssertEqual(estimator.targetNanoseconds(atSessionSample: 30 * 44_100), 0)
    }

    func testNewSessionResetsTheCorrection() {
        let meter = FeatureAgeMeter()
        var sample: Int64 = 0
        var host: UInt64 = 1_000_000_000
        for _ in 0..<(20 * 60) {   // 20 s of +1,000 ppm residual growth
            sample += 735
            host += 16_666_667
            let bus: UInt64 = 1_000_000_000 + UInt64(Double(sample) / 44_100 * 1e9)
            let drift: UInt64 = UInt64(Double(sample) / 44_100 * 1_000_000)   // 1 ms per s
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
