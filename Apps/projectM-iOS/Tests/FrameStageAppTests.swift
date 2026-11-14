// FrameStageAppTests.swift — PERF-001-T11 (specs/152-perf-001-stage-timings): the visuals' stage pipelines,
// attaching and detaching the shared timer (PERF-001-R8, R11), the overlay lines and the export conversion
// (R10). Metal hosts need a Metal device (the simulator renders with the host GPU); skips without one.
import ANGLERendering
import Diagnostics
import FrameTiming
import Metal
import XCTest
@testable import projectM_iOS

/// A visual that only records what it was given.
@MainActor
private final class FakeTimedVisual: FrameStageTimed {
    var stageTimer: FrameStageTimer? {
        didSet { stageTimer?.configure(pipeline: [.audio, .render, .present]) }
    }
}

@MainActor
final class FrameStageAppTests: XCTestCase {
    func testPipelinesPerVisual() {
        XCTAssertEqual(ANGLERenderer.frameStages.map(\.label), ["audio", "render", "output", "present"])
        XCTAssertEqual(NativeSpectrumHost.frameStages.map(\.label), ["audio", "render", "encode", "present"])
        XCTAssertEqual(compositorFrameStages.map(\.label), ["audio", "composite", "output", "encode", "present"])
    }

    func testTimerFollowsTheShownVisualAndStopsWithTheOverlay() {
        let attachment = FrameStageAttachment()
        let first = FakeTimedVisual()
        let second = FakeTimedVisual()
        attachment.sync(overlayShown: false, target: first)
        XCTAssertNil(first.stageTimer, "overlay off: no timing work")
        XCTAssertNil(attachment.timer)

        attachment.sync(overlayShown: true, target: first)
        let timer = try? XCTUnwrap(first.stageTimer)
        XCTAssertTrue(timer === attachment.timer)
        attachment.sync(overlayShown: true, target: first)
        XCTAssertTrue(first.stageTimer === timer, "the same visual keeps its timer and window")

        attachment.sync(overlayShown: true, target: second)
        XCTAssertNil(first.stageTimer, "only the shown visual measures")
        XCTAssertTrue(second.stageTimer === timer)

        attachment.sync(overlayShown: false, target: second)   // the overlay was turned off
        XCTAssertNil(second.stageTimer)
        XCTAssertNil(attachment.timer)
        XCTAssertNil(attachment.visual)

        attachment.sync(overlayShown: true, target: nil)   // no visual shown
        XCTAssertNil(attachment.timer)
    }

    func testNativeHostConfiguresItsPipeline() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32)
        let timer = FrameStageTimer()
        host.stageTimer = timer
        XCTAssertEqual(timer.pipeline, NativeSpectrumHost.frameStages)
        host.stageTimer = nil
    }

    func testCompositorHostSetsAndClearsTheOutputPassMark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertNil(host.compositor.stageClock, "no timer: the compositor reads no clock")
        let timer = FrameStageTimer(clock: { () -> UInt64 in 42 })
        host.stageTimer = timer
        XCTAssertEqual(timer.pipeline, compositorFrameStages)
        XCTAssertEqual(host.compositor.stageClock?(), 42)
        host.stageTimer = nil
        XCTAssertNil(host.compositor.stageClock)
    }

    func testExportConversion() {
        var clock: UInt64 = 0
        let timer = FrameStageTimer(clock: { () -> UInt64 in clock })
        timer.configure(pipeline: compositorFrameStages)
        timer.beginFrame()
        timer.begin(.audio); clock += 1_000_000; timer.end(.audio)
        timer.recordSplit(.composite, .output, start: clock, mark: clock + 2_000_000, end: clock + 2_500_000)
        timer.endFrame()
        timer.recordFrameGPU(seconds: 0.003)
        let export = AppCoordinator.exportTimings(timer.report())
        XCTAssertEqual(export.windowFrames, 1)
        XCTAssertEqual(export.stages.map(\.name), ["audio", "composite", "output", "present"], "encode only while recording")
        XCTAssertEqual(export.stages[0].cpuMedianMs ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(export.stages[1].cpuP95Ms ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(export.stages[3].samples, 0)
        XCTAssertNil(export.stages[3].cpuMedianMs, "unavailable: absent, not 0")
        XCTAssertNil(export.stages[0].gpuMedianMs)
        XCTAssertEqual(export.frameGPUMedianMs ?? -1, 3, accuracy: 1e-9)
    }

    func testOverlayLinesFormat() {
        let report = FrameStageReport(frames: 2, stages: [.init(stage: .audio, cpu: .measured(samples: 2, medianMs: 0.051, p95Ms: 0.09),
                                                                gpu: .unavailable)],
                                      frameGPU: .unavailable, rejectedSamples: 0)
        XCTAssertEqual(report.lines, ["stages ms (median/p95)", "audio 0.05/0.09", "gpu unavailable"])
    }
}
