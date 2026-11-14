// FrameStageTimerTests.swift — PERF-001-T05 (specs/152-perf-001-stage-timings; contract C1-C3). Pure Swift,
// runs on Linux. Every time comes from an injected clock: no wall-clock assertions.
import FrameTiming
import XCTest

/// A manual nanosecond clock.
private final class ManualClock {
    var nanoseconds: UInt64 = 1_000_000_000
    func advance(ms: Double) { nanoseconds += UInt64((ms * 1_000_000).rounded()) }
}

final class FrameStageTimerTests: XCTestCase {
    private let tolerance = 1e-9

    private func makeTimer(_ pipeline: [FrameStage], capacity: Int = FrameStageTimer.defaultCapacity) -> (FrameStageTimer, ManualClock) {
        let clock = ManualClock()
        let timer = FrameStageTimer(capacity: capacity, clock: { clock.nanoseconds })
        timer.configure(pipeline: pipeline)
        return (timer, clock)
    }

    /// Drives one frame whose stages take the given milliseconds.
    private func frame(_ timer: FrameStageTimer, _ clock: ManualClock, _ durations: [(FrameStage, Double)]) {
        timer.beginFrame()
        for (stage, ms) in durations {
            timer.begin(stage)
            clock.advance(ms: ms)
            timer.end(stage)
        }
        timer.endFrame()
    }

    private func assertMeasured(_ statistic: StageStatistic, samples: Int, median: Double, p95: Double,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard case let .measured(count, medianMs, p95Ms) = statistic else {
            return XCTFail("expected a measurement, got \(statistic)", file: file, line: line)
        }
        XCTAssertEqual(count, samples, file: file, line: line)
        XCTAssertTrue(medianMs.isFinite && p95Ms.isFinite && medianMs >= 0 && p95Ms >= 0, file: file, line: line)
        XCTAssertEqual(medianMs, median, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(p95Ms, p95, accuracy: tolerance, file: file, line: line)
    }

    // MARK: - Acceptance (PERF-001-S1, roadmap: "Synthetic frame reports finite timings with correct stage labels.")

    func testSyntheticFrameReportsFiniteTimingsWithCorrectStageLabels() {
        let pipeline: [FrameStage] = [.audio, .render, .composite, .output, .encode, .present]
        let (timer, clock) = makeTimer(pipeline)
        let injected: [(FrameStage, Double)] = [(.audio, 2), (.render, 3), (.composite, 4), (.output, 5), (.present, 6)]
        frame(timer, clock, injected)

        let report = timer.report()
        XCTAssertEqual(report.frames, 1)
        // encode is conditional and was not measured (no recording): not listed.
        XCTAssertEqual(report.labels, ["audio", "render", "composite", "output", "present"])
        for (summary, (stage, ms)) in zip(report.stages, injected) {
            XCTAssertEqual(summary.stage, stage)
            assertMeasured(summary.cpu, samples: 1, median: ms, p95: ms)
            XCTAssertEqual(summary.gpu, .unavailable, "\(stage.label): no GPU value was reported")
        }
        XCTAssertEqual(report.frameGPU, .unavailable)
        XCTAssertEqual(report.rejectedSamples, 0)
        XCTAssertEqual(report.lines, ["stages ms (median/p95)", "audio 2.00/2.00", "render 3.00/3.00", "composite 4.00/4.00",
                                      "output 5.00/5.00", "present 6.00/6.00", "gpu unavailable"])
    }

    func testPipelineStageWithoutSamplesIsUnavailableNotZero() {
        let (timer, clock) = makeTimer([.audio, .render, .present])
        frame(timer, clock, [(.audio, 1), (.present, 2)])   // render bailed out
        let report = timer.report()
        XCTAssertEqual(report.labels, ["audio", "render", "present"])
        XCTAssertEqual(report.stages[1].cpu, .unavailable)
        XCTAssertEqual(report.lines[2], "render –")
    }

    func testNoFramesMeansEveryStageUnavailable() {
        let (timer, _) = makeTimer([.audio, .render])
        let report = timer.report()
        XCTAssertEqual(report.frames, 0)
        XCTAssertEqual(report.stages.map(\.cpu), [.unavailable, .unavailable])
    }

    func testGPUValuesAreReportedWhereRecorded() {
        let (timer, clock) = makeTimer([.audio, .composite, .present])
        timer.beginFrame()
        timer.begin(.composite); clock.advance(ms: 1); timer.end(.composite)
        XCTAssertTrue(timer.record(.composite, gpuSeconds: 0.004))
        timer.endFrame()
        XCTAssertTrue(timer.recordFrameGPU(seconds: 0.007))
        let report = timer.report()
        assertMeasured(report.stages[1].gpu, samples: 1, median: 4, p95: 4)
        assertMeasured(report.frameGPU, samples: 1, median: 7, p95: 7)
        XCTAssertEqual(report.stages[0].cpu, .unavailable)
        XCTAssertEqual(report.lines[2], "composite 1.00/1.00 gpu 4.00/4.00")
        XCTAssertEqual(report.lines.last, "gpu 7.00/7.00")
    }

    // MARK: - Ring and statistics (PERF-001-S2)

    func testMedianAndP95() {
        let (timer, clock) = makeTimer([.render])
        for ms in 1...20 { frame(timer, clock, [(.render, Double(ms))]) }   // 1…20 ms
        // even count: median = (10 + 11) / 2; p95 nearest rank: ⌈19⌉ − 1 = index 18 → 19 ms
        assertMeasured(timer.report().stages[0].cpu, samples: 20, median: 10.5, p95: 19)
        frame(timer, clock, [(.render, 21)])   // odd count: median 11; ⌈19.95⌉ − 1 = 19 → 20 ms
        assertMeasured(timer.report().stages[0].cpu, samples: 21, median: 11, p95: 20)
    }

    func testRingWrapsAroundKeepingTheMostRecentFrames() {
        let (timer, clock) = makeTimer([.render], capacity: 4)
        for ms in [100.0, 200, 1, 2, 3, 4] { frame(timer, clock, [(.render, ms)]) }
        let report = timer.report()
        XCTAssertEqual(report.frames, 4)
        assertMeasured(report.stages[0].cpu, samples: 4, median: 2.5, p95: 4)   // 100 and 200 overwritten
        for _ in 0..<6 { XCTAssertTrue(timer.recordFrameGPU(seconds: 0.001)) }
        assertMeasured(timer.report().frameGPU, samples: 4, median: 1, p95: 1)
    }

    // MARK: - Rejection (PERF-001-R4)

    func testNaNInfiniteAndNegativeSamplesAreRejected() {
        let (timer, clock) = makeTimer([.audio, .render])
        timer.beginFrame()
        XCTAssertFalse(timer.record(.audio, cpuSeconds: .nan))
        XCTAssertFalse(timer.record(.audio, cpuSeconds: -0.001))
        XCTAssertFalse(timer.record(.audio, cpuSeconds: .infinity))
        XCTAssertFalse(timer.record(.render, gpuSeconds: .nan))
        XCTAssertFalse(timer.recordFrameGPU(seconds: -1))
        XCTAssertFalse(timer.recordFrameGPU(seconds: .nan))
        // A clock that goes backwards: end before begin.
        timer.begin(.render)
        clock.nanoseconds -= 5_000_000
        timer.end(.render)
        timer.endFrame()
        let report = timer.report()
        XCTAssertEqual(report.rejectedSamples, 7)
        XCTAssertEqual(report.frames, 0, "a frame that stored nothing is not kept")
        XCTAssertEqual(report.stages.map(\.cpu), [.unavailable, .unavailable])
        XCTAssertEqual(report.frameGPU, .unavailable)
        XCTAssertEqual(report.lines.last, "rejected 7")
        frame(timer, clock, [(.audio, 1)])
        XCTAssertTrue(timer.report().stages[0].cpu.isAvailable)
    }

    func testStageBegunButNotEndedRecordsNothing() {
        let (timer, clock) = makeTimer([.audio, .render])
        timer.beginFrame()
        timer.begin(.audio); clock.advance(ms: 1); timer.end(.audio)
        timer.begin(.render); clock.advance(ms: 9)   // the frame bailed out
        timer.endFrame()
        timer.end(.render)   // too late: the frame is over
        let report = timer.report()
        XCTAssertEqual(report.stages[1].cpu, .unavailable)
        XCTAssertEqual(report.rejectedSamples, 0)
    }

    func testStagesOutsideThePipelineAreIgnored() {
        let (timer, clock) = makeTimer([.audio])
        frame(timer, clock, [(.audio, 1), (.render, 2)])
        XCTAssertFalse(timer.record(.render, cpuSeconds: 0.001))
        XCTAssertEqual(timer.report().labels, ["audio"])
    }

    // MARK: - Encode only while recording (PERF-001-R5)

    func testEncodeAppearsOnlyWhileRecording() {
        let pipeline: [FrameStage] = [.audio, .composite, .output, .encode, .present]
        let (timer, clock) = makeTimer(pipeline, capacity: 3)
        let base: [(FrameStage, Double)] = [(.audio, 1), (.composite, 2), (.output, 1), (.present, 1)]
        frame(timer, clock, base)
        XCTAssertFalse(timer.report().labels.contains("encode"))
        frame(timer, clock, [(.audio, 1), (.composite, 2), (.output, 1), (.encode, 3), (.present, 1)])   // recording
        let recording = timer.report()
        XCTAssertEqual(recording.labels, ["audio", "composite", "output", "encode", "present"])
        assertMeasured(recording.stages[3].cpu, samples: 1, median: 3, p95: 3)
        for _ in 0..<3 { frame(timer, clock, base) }   // recording stopped; the encode frame leaves the window
        XCTAssertEqual(timer.report().labels, ["audio", "composite", "output", "present"])
    }

    // MARK: - Window lifecycle

    func testConfigureClearsTheWindowAndOrdersStages() {
        let (timer, clock) = makeTimer([.present, .audio, .audio])
        XCTAssertEqual(timer.pipeline, [.audio, .present])
        frame(timer, clock, [(.audio, 1)])
        timer.recordFrameGPU(seconds: 0.001)
        timer.configure(pipeline: [.audio, .render])
        let report = timer.report()
        XCTAssertEqual(report.frames, 0)
        XCTAssertEqual(report.frameGPU, .unavailable)
        XCTAssertEqual(report.labels, ["audio", "render"])
    }

    func testRepeatedRecordsInOneFrameAccumulate() {
        let (timer, clock) = makeTimer([.encode])
        timer.beginFrame()
        timer.begin(.encode); clock.advance(ms: 1); timer.end(.encode)
        timer.record(.encode, cpuSeconds: 0.002)
        timer.endFrame()
        assertMeasured(timer.report().stages[0].cpu, samples: 1, median: 3, p95: 3)
    }

    // MARK: - Cost (PERF-001-S5): on demand only, reported and not asserted.

    func testBenchCostPerFrame() throws {
        guard ProcessInfo.processInfo.environment["PERF001_BENCH"] == "1" else {
            throw XCTSkip("set PERF001_BENCH=1 to measure the timer's cost per frame")
        }
        let timer = FrameStageTimer()
        timer.configure(pipeline: FrameStage.allCases)
        let frames = 200_000
        let start = FrameStageTimer.systemClock()
        for _ in 0..<frames {
            timer.beginFrame()
            for stage in FrameStage.allCases {
                timer.begin(stage)
                timer.end(stage)
            }
            timer.endFrame()
        }
        let elapsed = Double(FrameStageTimer.systemClock() - start)
        print("PERF-001 bench: \(String(format: "%.1f", elapsed / Double(frames))) ns per frame of 6 stages (\(frames) frames)")
    }
}
