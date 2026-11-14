// RecordingFrameRateFixtureTests.swift — REC-006-T06, the row's acceptance ("Fixture output reports selected
// nominal frame rate and bounded dropped frames"): for 24, 30 and 60 fps, frames with injected render times
// (steady 60 Hz and 120 Hz, jittery, one 200 ms stall) are recorded by `MetalFrameRecorder` with the real
// writer (offline, 64×48, H.264) and read back. Checks: the file's nominal frame rate equals the selection
// (track `nominalFrameRate` without drops, `minFrameDuration` = 1/fps always), every frame time is exactly
// n/fps, and the recorder's reported dropped count is 0 for steady rendering, the stall's empty slots (or one
// more, research REC-006-D8) for the stall and at most 1% of slots for jitter. Representative cases, not a
// cross-product (owner rule 7). GPU test; skipped without Metal. Host results are not device evidence
// (REC-006-T15).
#if canImport(Metal) && canImport(AVFoundation) && !COMPOSITOR_NO_METAL
import AVFoundation
@testable import FrameRecording
import Foundation
import Metal
import XCTest

final class RecordingFrameRateFixtureTests: XCTestCase {
    private struct Outcome {
        let video: RecordedVideo
        let info: RecordedVideoInfo
        let interval: Int64
    }

    private func gpu() throws -> (MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device (CI simulator or Linux); RecordingFrameRateTests cover the rules.")
        }
        return (device, queue)
    }

    /// Records `times` at `fps` and reads the file back.
    private func record(_ times: [UInt64], fps: Int, name: String) async throws -> Outcome {
        let (device, queue) = try gpu()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC-006-\(fps)-\(UUID().uuidString).mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let settings = RecordingQualityProfile.draft.settings(frameRate: fps)   // H.264: available on every host
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 64, drawableHeight: 48,
                                              settings: settings, realTime: false)
        for (k, time) in times.enumerated() {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let level = Double(k % 32) / 32
            let outcome = recorder.recordFrame(presentationNanoseconds: 3_000_000_000 + time, drawableWidth: 64, drawableHeight: 48,
                                               commandBuffer: commands) { (texture: MTLTexture) -> Bool in
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColor(red: level, green: 1 - level, blue: 0.5, alpha: 1)
                guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
                encoder.endEncoding()
                return true
            }
            XCTAssertTrue(outcome == .submitted || outcome == .skippedRate, "\(name) frame \(k): \(outcome)")
            commands.commit()
            if outcome == .submitted {
                recorder.waitForPendingFrames()   // no queue drops: drops come only from the injected times
            }
        }
        let video = try (await recorder.finish()).get()
        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        let fpsText = String(format: "%.2f", info.trackNominalFrameRate)
        print("REC-006 fixture \(fps)fps \(name): frames=\(info.frameCount) dropped=\(video.droppedFrames) nominal=\(fpsText) "
              + "minFrameDuration=\(info.minFrameDurationTicks.map(String.init) ?? "nil")/600")
        return Outcome(video: video, info: info, interval: settings.frameIntervalTicks)
    }

    /// The checks every case shares: the selected rate, the exact grid, the report adds up.
    private func checkGrid(_ o: Outcome, fps: Int, name: String) {
        XCTAssertEqual(o.video.frameRate, fps, name)
        XCTAssertEqual(o.info.frameCount, o.video.frameCount, name)
        XCTAssertTrue(o.info.timesStrictlyIncrease, name)
        XCTAssertTrue(o.info.presentationTicks.allSatisfy { (t: Int64) -> Bool in t % o.interval == 0 },
                      "\(name): every time is n/\(fps) s: \(o.info.presentationTicks)")
        XCTAssertEqual(o.info.minFrameDurationTicks, o.interval, "\(name): minimum frame duration 1/\(fps) s")
        let slots = Int((o.info.presentationTicks.last ?? 0) / o.interval) + 1
        XCTAssertEqual(o.info.frameCount + o.video.droppedFrames, slots, "\(name): frames + dropped = slots")
    }

    func testSteadyRenderingRecordsTheSelectedRateWithNoDrops() async throws {
        for fps in RecordingFrameRateChoice.supportedRates {
            for hz: UInt64 in [60, 120] {
                let name = "\(hz)Hz"
                let o = try await record(FrameTimes.steady(hz: hz), fps: fps, name: name)
                checkGrid(o, fps: fps, name: "\(name) → \(fps)")
                XCTAssertEqual(o.video.droppedFrames, 0, "\(name) → \(fps)")
                XCTAssertEqual(o.info.frameCount, fps, "\(name) → \(fps): one second")
                XCTAssertEqual(o.info.trackNominalFrameRate, Double(fps), accuracy: 0.01, "\(name) → \(fps): nominal frame rate")
                XCTAssertEqual(o.info.presentationTicks, (0..<fps).map { (n: Int) -> Int64 in Int64(n) * o.interval })
            }
        }
    }

    func testAStallReportsItsEmptySlots() async throws {
        let times = FrameTimes.stalled()
        for fps in RecordingFrameRateChoice.supportedRates {
            let o = try await record(times, fps: fps, name: "stall200ms")
            checkGrid(o, fps: fps, name: "stall → \(fps)")
            let empty = FrameTimes.emptyWindows(times, fps: fps)
            XCTAssertGreaterThan(empty, 0)
            XCTAssertGreaterThanOrEqual(o.video.droppedFrames, empty, "stall → \(fps)")
            XCTAssertLessThanOrEqual(o.video.droppedFrames, empty + 1, "stall → \(fps)")
            XCTAssertLessThanOrEqual(o.video.droppedFrames, (fps * 200 + 999) / 1000, "stall → \(fps): ⌈0.2 × fps⌉")
            XCTAssertEqual(o.video.droppedFrames, GridRun(times, fps: fps).dropped, "the recorder reports what the grid left empty")
        }
    }

    func testJitteryRenderingDropsAtMostOnePercent() async throws {
        let cases: [(Int, String, [UInt64])] = [
            (24, "60Hz±3ms", FrameTimes.jittery(hz: 60, jitterMicroseconds: 3_000)),
            (60, "120Hz±2ms", FrameTimes.jittery(hz: 120, jitterMicroseconds: 2_000)),
        ]
        for (fps, name, times) in cases {
            let o = try await record(times, fps: fps, name: name)
            checkGrid(o, fps: fps, name: "\(name) → \(fps)")
            let slots = o.info.frameCount + o.video.droppedFrames
            XCTAssertLessThanOrEqual(Double(o.video.droppedFrames), Double(slots) * 0.01, "\(name) → \(fps)")
        }
    }
}
#endif
