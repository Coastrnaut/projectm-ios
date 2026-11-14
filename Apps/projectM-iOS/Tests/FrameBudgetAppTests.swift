// FrameBudgetAppTests.swift — PERF-002-T08 (specs/160-perf-002-gpu-budget): the DEBUG slow-stage injection
// (contract C5), the meter's lifetime in the attachment (PERF-002-R11), the overlay's flag split (R8), the
// export conversion (R9), and that judging the budget only ever touches the visual through its timer (R6).
import Diagnostics
import FrameTiming
import XCTest
@testable import projectM_iOS

/// A visual that counts every time the app touches it.
@MainActor
private final class SpyTimedVisual: FrameStageTimed {
    private(set) var timerAssignments = 0
    var stageTimer: FrameStageTimer? {
        didSet {
            timerAssignments += 1
            stageTimer?.configure(pipeline: [.audio, .render, .present])
        }
    }
}

@MainActor
final class FrameBudgetAppTests: XCTestCase {
    private func report(renderMs: Double, samples: Int = 120) -> FrameStageReport {
        FrameStageReport(frames: samples, stages: [
            .init(stage: .audio, cpu: .measured(samples: samples, medianMs: 0.1, p95Ms: 0.2), gpu: .unavailable),
            .init(stage: .render, cpu: .measured(samples: samples, medianMs: renderMs, p95Ms: renderMs), gpu: .unavailable),
            .init(stage: .present, cpu: .unavailable, gpu: .unavailable),
        ], frameGPU: .unavailable, rejectedSamples: 0)
    }

    func testSlowStageArgumentParsing() {
        XCTAssertEqual(SlowStageInjection.parse("render:40"), SlowStageInjection(stage: .render, milliseconds: 40))
        XCTAssertEqual(SlowStageInjection.parse("composite:14.2")?.milliseconds, 14.2)
        XCTAssertNil(SlowStageInjection.parse("bogus:40"))
        XCTAssertNil(SlowStageInjection.parse("render:abc"))
        XCTAssertNil(SlowStageInjection.parse("render:-1"))
        XCTAssertNil(SlowStageInjection.parse("render"))
        XCTAssertNil(SlowStageInjection.launch, "unit tests launch without the argument")
    }

    func testInjectionReplacesOnlyTheNamedStagesCPUFigure() {
        let original = report(renderMs: 2)
        let injected = SlowStageInjection(stage: .render, milliseconds: 40).apply(to: original)
        XCTAssertEqual(injected.stages[1].cpu, .measured(samples: 120, medianMs: 40, p95Ms: 40))
        XCTAssertEqual(injected.stages[0], original.stages[0])
        XCTAssertEqual(injected.stages[2], original.stages[2], "an unmeasured stage stays unavailable")
        XCTAssertEqual(injected.frameGPU, .unavailable)
        XCTAssertEqual(SlowStageInjection(stage: .composite, milliseconds: 40).apply(to: original), original, "absent stage")
    }

    func testMeterFollowsTheWindowAndOnlyTouchesTheVisualThroughItsTimer() {
        let attachment = FrameStageAttachment()
        let first = SpyTimedVisual()
        let second = SpyTimedVisual()
        let deadline = FrameDeadline(framesPerSecond: 60)
        attachment.sync(overlayShown: true, target: first)
        XCTAssertEqual(attachment.budget.evaluate(report(renderMs: 30), deadline: deadline).flagged, [.stage(.render, .cpu)])
        for _ in 0..<5 {   // five overlay refreshes while flagged
            attachment.sync(overlayShown: true, target: first)
            _ = attachment.budget.evaluate(report(renderMs: 30), deadline: deadline)
        }
        XCTAssertEqual(first.timerAssignments, 1, "judging the budget never touches the visual")
        attachment.sync(overlayShown: true, target: second)
        XCTAssertEqual(attachment.budget.flags, 0, "a new visual starts with no flags")
        _ = attachment.budget.evaluate(report(renderMs: 30), deadline: deadline)
        attachment.sync(overlayShown: false, target: second)
        XCTAssertEqual(attachment.budget.flags, 0, "overlay off forgets the flags")
    }

    func testOverlaySplitsTheFlagLines() {
        let lines: [String] = ["stages ms (median/p95)", "render 40.00/40.00", "gpu unavailable",
                               "budget 16.67 ms @60 fps, limit 13.33 ms (80%)", "estimate cpu 40.20 ms, gpu unavailable",
                               "over budget: render cpu 40.00 ms > 13.33 ms"]
        let split = PerformanceOverlay.splitBudgetFlags(lines)
        XCTAssertEqual(split.flags, ["over budget: render cpu 40.00 ms > 13.33 ms"])
        XCTAssertEqual(split.plain, Array(lines.prefix(5)))
    }

    func testDeadlineUsesTheCapAndExportCarriesTheVerdict() {
        XCTAssertLessThanOrEqual(AppCoordinator.frameDeadline().framesPerSecond, 60, "QualityGovernor caps every visual at 60 fps")
        let input = report(renderMs: 30)
        let verdict = FrameBudgetMeter().evaluate(input, deadline: FrameDeadline(framesPerSecond: 60))
        let exported = AppCoordinator.exportTimings(input, budget: verdict)
        XCTAssertEqual(exported.budget?.flaggedPasses, ["render cpu"])
        XCTAssertEqual(exported.budget?.deadlineMs ?? 0, 16.667, accuracy: 0.001)
        XCTAssertEqual(exported.budget?.thresholdShare, 0.8)
        XCTAssertNil(exported.budget?.gpuEstimateMs)
        XCTAssertNil(AppCoordinator.exportTimings(input).budget)
    }
}
