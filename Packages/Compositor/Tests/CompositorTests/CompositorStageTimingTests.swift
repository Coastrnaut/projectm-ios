// CompositorStageTimingTests.swift — PERF-001-T07 (PERF-001-S3; contracts/frame-stage-timer.md C4, C5): real
// composites on the Mac's GPU, timed the way the app's compositor visuals time them. Asserts only that the
// timings are finite and non-negative (no wall-clock bounds).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FrameTiming
import Metal
import XCTest

final class CompositorStageTimingTests: XCTestCase {
    func testCompositeAndOutputStageTimingsAreFinite() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("base", color: Pixel(0.2, 0.3, 0.4, 1)),
                                                                     SolidLayer("top", color: Pixel(0.1, 0, 0, 0.5))])
        let timer = FrameStageTimer()
        timer.configure(pipeline: [.composite, .output, .present])
        let gpuTimes = MetalGPUFrameTimes()
        compositor.stageClock = { () -> UInt64 in timer.now() }
        let output = try rig.output(.bgra8Unorm_srgb, width: 128, height: 128)
        let frames = 6
        for i in 0..<frames {
            timer.beginFrame()
            gpuTimes.drain(into: timer)
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let start = timer.now()
            let ok = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000 + UInt64(i) * 16_666_667,
                                          contentScale: 2, reduceFlashing: false, audio: .empty)
            let end = timer.now()
            XCTAssertTrue(ok)
            XCTAssertGreaterThanOrEqual(compositor.lastOutputPassStartNanoseconds, start, "the mark lies inside the call")
            XCTAssertLessThanOrEqual(compositor.lastOutputPassStartNanoseconds, end)
            timer.recordSplit(.composite, .output, start: start, mark: compositor.lastOutputPassStartNanoseconds, end: end)
            timer.begin(.present)
            commands.commit()
            timer.end(.present)
            gpuTimes.track(commands)
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            timer.endFrame()
        }
        gpuTimes.drain(into: timer)

        let report = timer.report()
        XCTAssertEqual(report.labels, ["composite", "output", "present"])
        XCTAssertEqual(report.rejectedSamples, 0)
        for summary in report.stages {
            guard case let .measured(samples, median, p95) = summary.cpu else { return XCTFail("\(summary.label) unavailable") }
            XCTAssertEqual(samples, frames)
            XCTAssertTrue(median.isFinite && p95.isFinite && median >= 0 && p95 >= median, "\(summary.label): \(median)/\(p95)")
            XCTAssertEqual(summary.gpu, .unavailable, "one command buffer per frame: no per-stage GPU time")
        }
        switch report.frameGPU {
        case let .measured(samples, median, p95):
            XCTAssertEqual(samples, frames)
            XCTAssertTrue(median.isFinite && p95.isFinite && median >= 0, "frame GPU \(median)/\(p95)")
        case .unavailable:
            // A GPU that reports no timestamps is marked unavailable, never 0 (PERF-001-R3).
            print("PERF-001: this GPU reported no command-buffer timestamps")
        }
        print("PERF-001 composite stages: " + report.lines.joined(separator: " | "))
    }

    func testWithoutStageClockNothingIsStamped() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("base", color: Pixel(1, 1, 1, 1))])
        try rig.frame(compositor, into: rig.output(), time: 1_000_000_000)
        XCTAssertEqual(compositor.lastOutputPassStartNanoseconds, 0)
        XCTAssertNil(compositor.stageClock)
    }
}
#endif
