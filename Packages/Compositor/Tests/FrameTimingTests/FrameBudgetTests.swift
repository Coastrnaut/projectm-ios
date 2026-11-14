// FrameBudgetTests.swift — PERF-002-T04 (specs/160-perf-002-gpu-budget; contract C1-C3). Pure Swift, runs on
// Linux. Stage times are injected (a manual clock or ready-made reports): no wall-clock assertions.
import FrameTiming
import XCTest

/// A manual nanosecond clock.
private final class BudgetClock {
    var nanoseconds: UInt64 = 1_000_000_000
    func advance(ms: Double) { nanoseconds += UInt64((ms * 1_000_000).rounded()) }
}

/// A renderer that only counts what the frame loop asked it to do.
private final class SpyRenderer {
    private(set) var frames = 0
    private(set) var drawCalls = 0
    private(set) var presents = 0
    func draw() { drawCalls += 1 }
    func present() { presents += 1; frames += 1 }
}

final class FrameBudgetTests: XCTestCase {
    private let deadline60 = FrameDeadline(framesPerSecond: 60)

    private func measured(_ p95: Double, samples: Int = 120) -> StageStatistic {
        .measured(samples: samples, medianMs: p95 / 2, p95Ms: p95)
    }

    private func report(cpu: [(FrameStage, Double)], gpu: [FrameStage: Double] = [:], frameGPU: StageStatistic = .unavailable,
                        samples: Int = 120) -> FrameStageReport {
        let stages: [FrameStageReport.StageSummary] = cpu.map { (stage: FrameStage, ms: Double) -> FrameStageReport.StageSummary in
            let gpuStatistic: StageStatistic = gpu[stage].map { (value: Double) -> StageStatistic in self.measured(value, samples: samples) } ?? .unavailable
            return FrameStageReport.StageSummary(stage: stage, cpu: measured(ms, samples: samples), gpu: gpuStatistic)
        }
        return FrameStageReport(frames: samples, stages: stages, frameGPU: frameGPU, rejectedSamples: 0)
    }

    // MARK: - Acceptance (PERF-002-S1)

    func testOnlyTheCompositePassOverTheThresholdIsFlagged() {
        let meter = FrameBudgetMeter()
        let input = report(cpu: [(.audio, 0.4), (.composite, 14.2), (.output, 1.1), (.encode, 0.9), (.present, 0.3)],
                           frameGPU: measured(5.0))
        let verdict = meter.evaluate(input, deadline: deadline60)
        XCTAssertEqual(verdict.flagged, [.stage(.composite, .cpu)])
        XCTAssertEqual(verdict.flagged.compactMap(\.stage).map(\.label), ["composite"])
        XCTAssertEqual(verdict.thresholdMs, 13.3333, accuracy: 0.001)
        XCTAssertEqual(verdict.cpuEstimateMs ?? -1, 0.4 + 14.2 + 1.1 + 0.9 + 0.3, accuracy: 1e-9)
        XCTAssertEqual(verdict.gpuEstimateMs ?? -1, 5.0, accuracy: 1e-9)
    }

    // MARK: - The render path is unaffected (PERF-002-S2)

    /// One frame loop: the timer brackets each stage around the spy's calls; with the meter on, the overlay's
    /// once-a-second evaluation runs every 60 frames. Returns the spy and the flags seen.
    private func runLoop(frames: Int, renderMs: Double, meterOn: Bool) -> (SpyRenderer, [[BudgetPass]]) {
        let clock = BudgetClock()
        let timer = FrameStageTimer(clock: { clock.nanoseconds })
        timer.configure(pipeline: [.audio, .render, .present])
        let spy = SpyRenderer()
        let meter = FrameBudgetMeter()
        var seen: [[BudgetPass]] = []
        for index in 1...frames {
            timer.beginFrame()
            timer.begin(.audio); clock.advance(ms: 0.2); timer.end(.audio)
            timer.begin(.render); spy.draw(); clock.advance(ms: renderMs); timer.end(.render)
            timer.begin(.present); spy.present(); clock.advance(ms: 0.1); timer.end(.present)
            timer.endFrame()
            if meterOn && index % 60 == 0 {
                seen.append(meter.evaluate(timer.report(), deadline: deadline60).flagged)
            }
        }
        return (spy, seen)
    }

    func testFlaggingNeverSkipsOrAltersAFrame() {
        let frames = 600
        let (withoutMeter, _) = runLoop(frames: frames, renderMs: 20, meterOn: false)
        let (flagging, seen) = runLoop(frames: frames, renderMs: 20, meterOn: true)
        let (fast, fastSeen) = runLoop(frames: frames, renderMs: 2, meterOn: true)
        XCTAssertTrue(seen.allSatisfy { (flags: [BudgetPass]) -> Bool in flags == [.stage(.render, .cpu)] }, "\(seen)")
        XCTAssertTrue(fastSeen.allSatisfy(\.isEmpty))
        for spy in [withoutMeter, flagging, fast] {
            XCTAssertEqual(spy.frames, frames, "every frame rendered")
            XCTAssertEqual(spy.drawCalls, frames, "no draw skipped")
            XCTAssertEqual(spy.presents, frames, "no present skipped")
        }
    }

    // MARK: - Deadline (PERF-002-S3)

    func testDeadlinesAt60And120And30FPS() {
        XCTAssertEqual(FrameDeadline(framesPerSecond: 60).periodMs, 16.67, accuracy: 0.01)
        XCTAssertEqual(FrameDeadline(framesPerSecond: 120).periodMs, 8.33, accuracy: 0.01)
        XCTAssertEqual(FrameDeadline(framesPerSecond: 30).periodMs, 33.33, accuracy: 0.01)
        XCTAssertEqual(FrameDeadline(displayMaximumFPS: 120, frameRateCap: 60).framesPerSecond, 60, "the cap wins on ProMotion")
        XCTAssertEqual(FrameDeadline(displayMaximumFPS: 60, frameRateCap: 30).framesPerSecond, 30, "Low Power cap")
        XCTAssertEqual(FrameDeadline(displayMaximumFPS: 120, frameRateCap: nil).framesPerSecond, 120)
        XCTAssertEqual(FrameDeadline(displayMaximumFPS: 0, frameRateCap: .nan).framesPerSecond, 60, "fallback")
        XCTAssertEqual(FrameDeadline(displayMaximumFPS: nil, frameRateCap: -.infinity).framesPerSecond, 60)
    }

    func testADeadlineChangeAppliesAtTheNextEvaluation() {
        let meter = FrameBudgetMeter()
        let input = report(cpu: [(.render, 20)])
        XCTAssertEqual(meter.evaluate(input, deadline: deadline60).flagged, [.stage(.render, .cpu)])
        XCTAssertEqual(meter.evaluate(input, deadline: FrameDeadline(framesPerSecond: 30)).flagged, [],
                       "20 ms is under 70% of 33.33 ms: cleared")
    }

    // MARK: - Unavailable and GPU passes (PERF-002-S4)

    func testAnUnavailablePassIsNeverFlagged() {
        let meter = FrameBudgetMeter()
        let input = report(cpu: [(.audio, 0.5), (.render, 2)])   // frame GPU unavailable (ANGLE, simulator)
        let verdict = meter.evaluate(input, deadline: FrameDeadline(framesPerSecond: 1000))   // 1 ms deadline
        XCTAssertEqual(verdict.flagged, [.stage(.render, .cpu)])
        let frame = verdict.passes.first { (status: PassStatus) -> Bool in status.pass == .frameGPU }
        XCTAssertEqual(frame?.isAvailable, false)
        XCTAssertEqual(frame?.isOver, false)
        XCTAssertNil(verdict.gpuEstimateMs)
        XCTAssertFalse(verdict.passes.contains { (status: PassStatus) -> Bool in status.pass == .stage(.render, .gpu) },
                       "a stage GPU pass is listed only when measured")
        // A figure that becomes unavailable drops its flag.
        let gpuOver = report(cpu: [(.render, 1)], frameGPU: measured(15))
        XCTAssertEqual(meter.evaluate(gpuOver, deadline: deadline60).flagged, [.frameGPU])
        XCTAssertEqual(meter.evaluate(report(cpu: [(.render, 1)]), deadline: deadline60).flagged, [])
    }

    func testMeasuredStageGPUPassesAreJudged() {
        let meter = FrameBudgetMeter()
        let input = report(cpu: [(.composite, 3)], gpu: [.composite: 14], frameGPU: measured(15))
        XCTAssertEqual(meter.evaluate(input, deadline: deadline60).flagged, [.stage(.composite, .gpu), .frameGPU])
    }

    // MARK: - Hysteresis, minimum samples, boundary

    func testFlagsClearOnlyBelowTheClearLevel() {
        let meter = FrameBudgetMeter()   // 60 fps: threshold 13.33 ms, clear 11.67 ms
        XCTAssertEqual(meter.evaluate(report(cpu: [(.composite, 14)]), deadline: deadline60).flagged.count, 1)
        XCTAssertEqual(meter.evaluate(report(cpu: [(.composite, 12.5)]), deadline: deadline60).flagged.count, 1, "inside the band: kept")
        XCTAssertEqual(meter.evaluate(report(cpu: [(.composite, 11.0)]), deadline: deadline60).flagged.count, 0, "below clear")
        XCTAssertEqual(meter.evaluate(report(cpu: [(.composite, 12.5)]), deadline: deadline60).flagged.count, 0, "inside the band: stays clear")
        _ = meter.evaluate(report(cpu: [(.composite, 14)]), deadline: deadline60)
        meter.reset()
        XCTAssertEqual(meter.flags, 0)
    }

    func testAtTheThresholdIsNotFlagged() {
        let meter = FrameBudgetMeter(policy: FrameBudgetPolicy(thresholdShare: 0.5, clearShare: 0.4))
        let at = report(cpu: [(.render, FrameDeadline(framesPerSecond: 50).periodMs * 0.5)])   // exactly 10 ms
        XCTAssertEqual(meter.evaluate(at, deadline: FrameDeadline(framesPerSecond: 50)).flagged, [])
    }

    func testTooFewSamplesNeverChangeAFlag() {
        let meter = FrameBudgetMeter()
        XCTAssertEqual(meter.evaluate(report(cpu: [(.render, 30)], samples: 29), deadline: deadline60).flagged, [], "fresh window")
        XCTAssertEqual(meter.evaluate(report(cpu: [(.render, 30)], samples: 30), deadline: deadline60).flagged.count, 1)
        XCTAssertEqual(meter.evaluate(report(cpu: [(.render, 1)], samples: 5), deadline: deadline60).flagged.count, 1, "kept")
    }

    func testAStageThatLeavesTheReportLosesItsFlag() {
        let meter = FrameBudgetMeter()
        XCTAssertEqual(meter.evaluate(report(cpu: [(.render, 1), (.encode, 20)]), deadline: deadline60).flagged,
                       [.stage(.encode, .cpu)])
        XCTAssertEqual(meter.evaluate(report(cpu: [(.render, 1)]), deadline: deadline60).flagged, [], "recording stopped")
        XCTAssertEqual(meter.flags, 0)
    }

    func testPolicyIsClamped() {
        let defaults = FrameBudgetPolicy()
        XCTAssertEqual(defaults.thresholdShare, 0.8)
        XCTAssertEqual(defaults.clearShare, 0.7)
        XCTAssertEqual(defaults.minimumSamples, 30)
        let wild = FrameBudgetPolicy(thresholdShare: 3, clearShare: 2, minimumSamples: -4)
        XCTAssertEqual(wild.thresholdShare, 1)
        XCTAssertEqual(wild.clearShare, 1)
        XCTAssertEqual(wild.minimumSamples, 1)
        let invalid = FrameBudgetPolicy(thresholdShare: .nan, clearShare: 0)
        XCTAssertEqual(invalid.thresholdShare, 0.8)
        XCTAssertEqual(invalid.clearShare, 0.7)
        XCTAssertEqual(FrameBudgetPolicy(thresholdShare: 0.5, clearShare: -1).clearShare, 0.5)
    }

    // MARK: - Overlay text

    func testOverlayLines() {
        let meter = FrameBudgetMeter()
        let verdict = meter.evaluate(report(cpu: [(.audio, 0.5), (.composite, 14.2)], frameGPU: measured(3.2)), deadline: deadline60)
        XCTAssertEqual(verdict.lines, ["budget 16.67 ms @60 fps, limit 13.33 ms (80%)",
                                       "estimate cpu 14.70 ms, gpu 3.20 ms",
                                       "over budget: composite cpu 14.20 ms > 13.33 ms"])
        let empty = FrameBudgetMeter().evaluate(FrameStageReport(frames: 0, stages: [], frameGPU: .unavailable, rejectedSamples: 0),
                                                deadline: FrameDeadline(framesPerSecond: 30))
        XCTAssertEqual(empty.lines, ["budget 33.33 ms @30 fps, limit 26.67 ms (80%)", "estimate cpu unavailable, gpu unavailable"])
        XCTAssertEqual(empty.flagged, [])
        XCTAssertEqual(BudgetPass.frameGPU.label, "gpu frame")
        XCTAssertEqual(BudgetPass.stage(.render, .gpu).label, "render gpu")
    }
}
