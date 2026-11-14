// WaveformTriggerTests.swift — VIS-003-T02: the trigger stabilizer (VIS-003-R3 to R6, S1 to S3).
// Fixtures advance by 700…770 samples per frame, as the capture delivers audio; the start phase of
// every triggered frame must stay within 0.01 cycle of the first one. Representative cases only
// (owner rule 7); pure Swift, runs on Linux.
import XCTest
@testable import VisualGenerators

final class WaveformTriggerTests: XCTestCase {
    private let history = 4_096

    /// Runs `frames` frames of `signal` and returns the start phase of each frame (nil when free-run)
    /// and the results.
    private func run(_ signal: WaveformSignal, window: Int, frames: Int = 60,
                     trigger: WaveformTrigger = WaveformTrigger()) -> [(phase: Double, result: WaveformTriggerResult)] {
        var end: Int64 = 50_000
        var out: [(phase: Double, result: WaveformTriggerResult)] = []
        for f in 0..<frames {
            end += WaveformFrames.advance(frame: f)
            let samples = signal.history(endingAt: end, count: history)
            let result = samples.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> WaveformTriggerResult in
                trigger.locate(in: b, windowSamples: window)
            }
            let absolute: Double = Double(end - Int64(history)) + result.start
            out.append((signal.phase(at: absolute), result))
        }
        return out
    }

    func testPeriodicFixturesStayAtOnePhase() {
        let cases: [WaveformSignal] = [
            WaveformSignal(shape: .sine, frequency: 110),
            WaveformSignal(shape: .sine, frequency: 440),
            WaveformSignal(shape: .sine, frequency: 1_000),
            WaveformSignal(shape: .sine, frequency: 440, sampleRate: 48_000),
            WaveformSignal(shape: .square, frequency: 220),
            WaveformSignal(shape: .saw, frequency: 220),
            WaveformSignal(shape: .sine, frequency: 440, offset: 0.3),
            WaveformSignal(shape: .complex, frequency: 147),
        ]
        var report: [String] = ["VIS-003 trigger, worst start-phase spread over 60 frames (cycles):"]
        for signal in cases {
            let frames = run(signal, window: 882)
            var worst = 0.0
            for (f, frame) in frames.enumerated() {
                XCTAssertEqual(frame.result.mode, .triggered, "\(signal) frame \(f)")
                XCTAssertLessThanOrEqual(frame.result.start + 882, Double(history), "\(signal): the window fits")
                worst = max(worst, abs(WaveformFrames.phaseDifference(frame.phase, frames[0].phase)))
            }
            XCTAssertLessThan(worst, 0.01, "\(signal)")
            report.append("  \(signal): \(worst)")
        }
        print(report.joined(separator: "\n"))
    }

    func testSilenceAndNoiseFreeRunOnTheNewestWindow() {
        for (signal, reason) in [(WaveformSignal(shape: .silence, frequency: 0), WaveformFreeRunReason.silence),
                                 (WaveformSignal(shape: .noise, frequency: 0), WaveformFreeRunReason.aperiodic)] {
            for (f, frame) in run(signal, window: 441, frames: 20).enumerated() {
                XCTAssertEqual(frame.result.mode, .freeRun(reason), "\(signal) frame \(f)")
                XCTAssertEqual(frame.result.start, Double(history - 441), "\(signal): the newest window")
            }
        }
    }

    func testPeriodEstimateAndCrossings() throws {
        let trigger = WaveformTrigger()
        let samples = WaveformSignal(shape: .sine, frequency: 440).history(endingAt: 100_000)
        let result = samples.withUnsafeBufferPointer { trigger.locate(in: $0, windowSamples: 882) }
        let period = try XCTUnwrap(result.periodSamples)
        XCTAssertEqual(period, 44_100.0 / 440.0, accuracy: 44_100.0 / 440.0 * 0.01)
        XCTAssertGreaterThanOrEqual(result.crossingCount, 20, "a crossing every 100 samples before the window")
        // A complex wave has 3 rising crossings per period: the period is still found.
        let complex = WaveformSignal(shape: .complex, frequency: 147).history(endingAt: 100_000)
        let c = complex.withUnsafeBufferPointer { WaveformTrigger().locate(in: $0, windowSamples: 882) }
        XCTAssertEqual(try XCTUnwrap(c.periodSamples), 44_100.0 / 147.0, accuracy: 3)
    }

    func testDegenerateInputsStayInRange() {
        let trigger = WaveformTrigger()
        // NaN and infinities read 0; the window is clamped to the history.
        var samples = WaveformSignal(shape: .sine, frequency: 440).history(endingAt: 60_000)
        samples[100] = .nan; samples[2_000] = .infinity; samples[3_000] = -.infinity
        let r = samples.withUnsafeBufferPointer { trigger.locate(in: $0, windowSamples: 882) }
        XCTAssertTrue(r.start.isFinite && r.start >= 0 && r.start <= Double(history - 882))
        let wide = samples.withUnsafeBufferPointer { trigger.locate(in: $0, windowSamples: 10_000) }
        XCTAssertEqual(wide.start, 0, "a window longer than the history shows all of it")
        let empty = [Float]().withUnsafeBufferPointer { trigger.locate(in: $0, windowSamples: 441) }
        XCTAssertEqual(empty.start, 0)
        XCTAssertEqual(empty.mode, .freeRun(.silence))
        // A period longer than the search span (5 Hz): at most one crossing; the window still fits.
        let slow = WaveformSignal(shape: .sine, frequency: 5).history(endingAt: 60_000)
        let s = slow.withUnsafeBufferPointer { WaveformTrigger().locate(in: $0, windowSamples: 1_764) }
        XCTAssertLessThanOrEqual(s.crossingCount, 1)
        XCTAssertTrue(s.start >= 0 && s.start <= Double(history - 1_764))
    }

    /// VIS-003-S3: 1,000 frames leave the trigger's storage where it was (no allocation on the frame path).
    func testThousandFramesKeepFixedStorage() {
        let trigger = WaveformTrigger()
        let before = trigger.storageAddresses
        XCTAssertEqual(trigger.crossingCapacity, WaveformTrigger.maximumCrossings)
        XCTAssertEqual(trigger.referenceCapacity, WaveformTrigger.referencePoints)
        let signal = WaveformSignal(shape: .complex, frequency: 147)
        var end: Int64 = 50_000
        var samples = [Float](repeating: 0, count: history)
        for f in 0..<1_000 {
            end += WaveformFrames.advance(frame: f)
            for i in 0..<history { samples[i] = signal.value(at: end - Int64(history) + Int64(i)) }
            _ = samples.withUnsafeBufferPointer { trigger.locate(in: $0, windowSamples: f % 2 == 0 ? 882 : 1_764) }
        }
        XCTAssertEqual(trigger.storageAddresses, before)
    }

    func testResetForgetsTheReference() {
        let trigger = WaveformTrigger()
        let samples = WaveformSignal(shape: .sine, frequency: 440).history(endingAt: 60_000)
        _ = samples.withUnsafeBufferPointer { trigger.locate(in: $0, windowSamples: 882) }
        XCTAssertTrue(trigger.hasReference)
        trigger.reset()
        XCTAssertFalse(trigger.hasReference)
    }
}
