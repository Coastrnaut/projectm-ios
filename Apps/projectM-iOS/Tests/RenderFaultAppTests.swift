// RenderFaultAppTests.swift — PERF-014-T10 (US1 in the app) and T16 (the placeholder's flash safety).
//
// The Photo visual renders offscreen at 64 × 128 (small, fast) with the photo layer's prepare failing
// through the compositor's DEBUG fault injection (as a pipeline that cannot be created; the real
// recovery path). Needs a Metal device; skipped without one. Ticks are counted, never wall time.
import Compositor
import FlashSafety
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class RenderFaultAppTests: XCTestCase {
    private func output(_ device: MTLDevice) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 128, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    private func frames(_ count: Int, _ host: PhotoVisualHost, queue: MTLCommandQueue, output: MTLTexture) throws {
        for _ in 0..<count {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let ticks = host.renderTicks
            XCTAssertTrue(host.compositor.composite(into: output, commandBuffer: commands,
                                                    presentationTimeNanoseconds: (ticks + 1) * 16_666_667,
                                                    contentScale: 2, reduceFlashing: false, audio: .empty))
            commands.commit()
            commands.waitUntilCompleted()
        }
    }

    private func photoFile() throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { (context: UIGraphicsImageRendererContext) in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("perf014-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    /// S1, S2, S4 in the app: the photo's injected prepare failure is recorded, the visual keeps ticking
    /// and drawing its spectrum, the record is reported once per change, and clearing the fault brings
    /// the photo back at its retry.
    func testAPhotoPipelineFailureIsRecordedAndRecoversAtItsRetry() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let file = try photoFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        host.content = .file(file)
        host.photo.waitUntilLoaded()
        host.compositor.faultInjection.failingPrepare = ["photo"]
        let target = try output(device)

        try frames(1, host, queue: queue, output: target)
        let health = host.compositor.health
        XCTAssertEqual(health.lastReason, .layerPrepareFailed)
        XCTAssertEqual(health.faultCount, 1)
        XCTAssertEqual(health.state, .recovering)
        XCTAssertEqual(health.summary(visual: "photo"), "photo recovering layerPrepareFailed faults 1 recoveries 0 tick 1",
                       "R13: the log line names the visual, reason and counts only")
        XCTAssertEqual(host.compositor.outcome(ofLayer: 1), .rendered, "the spectrum keeps drawing")
        XCTAssertEqual(host.framesShown, 0, "no photo frame while it fails")

        try frames(28, host, queue: queue, output: target)
        XCTAssertEqual(host.renderTicks, 29, "S2: the frame loop keeps ticking")
        host.compositor.faultInjection = RenderFaultInjection()
        try frames(1, host, queue: queue, output: target)                   // tick 30: still waiting
        XCTAssertEqual(host.framesShown, 0)
        try frames(1, host, queue: queue, output: target)                   // tick 31: the retry
        XCTAssertGreaterThan(host.framesShown, 0, "S4: the photo is back at its retry")
        XCTAssertEqual(host.compositor.health.state, .healthy)
        XCTAssertEqual(host.compositor.health.recoveries, 1)
    }

    /// R13: one log per changed count (a state change alone is not logged).
    func testOneLogPerChangedCount() {
        var health = RenderHealth()
        XCTAssertNil(AppCoordinator.countsToLog(health, lastLogged: nil), "nothing recorded: nothing to log")
        health.recordFault(.gpuTimeout, atTick: 4)
        XCTAssertEqual(AppCoordinator.countsToLog(health, lastLogged: nil), [1, 0])
        health.setState(.recovering)
        XCTAssertNil(AppCoordinator.countsToLog(health, lastLogged: [1, 0]), "a state change only")
        health.recordRecovery()
        XCTAssertEqual(AppCoordinator.countsToLog(health, lastLogged: [1, 0]), [1, 1])
    }

    /// R11: a visual that could not be created is recorded as `visualUnavailable`.
    func testAVisualCreationFailureIsRecorded() {
        let health = AppCoordinator.recordingVisualUnavailable(RenderHealth())
        XCTAssertEqual(health.faultCount, 1)
        XCTAssertEqual(health.lastReason, .visualUnavailable)
        XCTAssertEqual(health.state, .healthy, "projectM is shown instead; the record only names the reason")
    }

    /// S5 (T16): the placeholder over a white picture, sampled at 60 fps through fade-in, 1 s hold and
    /// fade-out: one luminance transition per switch, never two in one second (FlashAnalysis, 0.10).
    func testThePlaceholderFadeIsOneTransitionPerSwitch() {
        XCTAssertEqual(RenderPlaceholder.opacity(elapsed: -1), 0)
        XCTAssertEqual(RenderPlaceholder.opacity(elapsed: 0.25), 0.5, accuracy: 1e-9)
        XCTAssertEqual(RenderPlaceholder.opacity(elapsed: 2), 1)
        let dt = 1.0 / 60
        var values: [Double] = Array(repeating: 1, count: 30)   // the white picture
        for i in 1...30 { values.append(1 - RenderPlaceholder.opacity(elapsed: Double(i) * dt)) }   // fade in
        values += Array(repeating: 0, count: 60)                 // held for 1 s
        for i in 1...30 { values.append(RenderPlaceholder.opacity(elapsed: Double(i) * dt)) }       // fade out
        let report = FlashAnalysis.analyze(values, frameTimes: Array(repeating: dt, count: values.count), threshold: 0.10)
        XCTAssertEqual(report.transitions, 2)
        XCTAssertLessThanOrEqual(report.maxTransitionsPerWindow, 1)
        XCTAssertLessThanOrEqual(report.maxFall, 1.0 / 30 + 1e-9, "a fade, not a cut: at most 1/30 of the range per frame")
        let strict = FlashEnvelopeConfiguration.reduceFlashing.riseRatePerSecond ?? 1
        XCTAssertGreaterThan(RenderPlaceholder.fadeSeconds, 0.10 / strict, "slower than Reduce flashing's 0.10 rise")
    }

    /// R10: the placeholder only for the shown visual's placeholder state, on the visualizer.
    func testThePlaceholderFollowsTheShownVisualsState() {
        XCTAssertTrue(AppCoordinator.rendersPlaceholder(onVisualizer: true, state: .placeholder))
        for state in [RenderHealthState.healthy, .recovering, .degraded] {
            XCTAssertFalse(AppCoordinator.rendersPlaceholder(onVisualizer: true, state: state), "\(state)")
        }
        XCTAssertFalse(AppCoordinator.rendersPlaceholder(onVisualizer: false, state: .placeholder))
    }
}
