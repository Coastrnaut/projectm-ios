// RecordingTimedStopTests.swift — REC-008-T04, T05, T12, the row's acceptance ("Ten-second target closes file with
// readable index and no extra frames"; specs/180-rec-008-timed-stop, contract C1, C2). Frames with injected render
// times (steady at the recording rate, steady 60 Hz decimated to 30 fps, jittery 60 Hz) are offered to a recorder
// whose length is 10 s until it answers `durationReached`; then the frame path calls `beginFinish()` (never waits)
// and the file is read back with QA-008's `RecordingValidator` and REC-003's inspector. Checks: duration 10 s
// within one frame, exactly fps × 10 frames on the grid, none at or after 10 s, the frame after the end never
// encoded, a readable index (the validator and AVAsset playable), audio ending within 20 ms of 10 s. A render-thread
// spy proves the finish never runs on the frame path. Representative cases (owner rule 7). GPU tests: skipped
// without Metal; the audio timeline tests cover the trim rule everywhere. Host results are not device evidence.
#if canImport(Metal) && canImport(AVFoundation) && !COMPOSITOR_NO_METAL
import AVFoundation
import CoreVideo
@testable import FrameRecording
import Foundation
import Metal
import XCTest

/// A sink that writes nothing, flags any append or finish made on the render queue, and holds `finish` until released.
private final class RenderSpySink: RecordingSampleSink, @unchecked Sendable {
    static let renderKey = DispatchSpecificKey<Bool>()
    let codec = RecordingCodec.h264
    let queue = DispatchQueue(label: "REC-008 spy sink")
    private let pool: CVPixelBufferPool
    private let lock = NSLock()
    private var held: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var finishCalls = 0
    private(set) var finishOnRenderQueue = false
    private(set) var appendOnRenderQueue = false
    private(set) var appended = 0

    init(width: Int, height: Int) throws {
        pool = try XCTUnwrap(RecordingPixelBuffers.makePool(width: width, height: height, minimumCount: 3))
    }

    func makePixelBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        return CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess ? buffer : nil
    }

    func append(_ buffer: CVPixelBuffer, tick: Int64) -> RecordingAppendResult {
        let onRender = DispatchQueue.getSpecific(key: Self.renderKey) == true
        lock.withLock { () -> Void in
            appended += 1
            if onRender { appendOnRenderQueue = true }
        }
        return .appended
    }

    func finish(endTick: Int64, keep: Bool) async -> Result<Void, RecordingFailure> {
        let onRender = DispatchQueue.getSpecific(key: Self.renderKey) == true
        let alreadyReleased = lock.withLock { () -> Bool in
            finishCalls += 1
            if onRender { finishOnRenderQueue = true }
            return released
        }
        if !alreadyReleased {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    if released { return true }
                    held = c
                    return false
                }
                if resumeNow { c.resume() }
            }
        }
        return .success(())
    }

    /// Lets a held (or later) finish complete.
    func release() {
        let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { held = nil }
            return held
        }
        c?.resume()
    }

    var isFinishing: Bool { lock.withLock { () -> Bool in finishCalls > 0 } }
}

final class RecordingTimedStopTests: XCTestCase {
    private let base: UInt64 = 7_000_000_000
    private let length = 10

    private func gpu() throws -> (MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device (CI simulator or Linux); RecordingAudioTimelineTests cover the trim rule.")
        }
        return (device, queue)
    }

    /// One frame cleared to a level; `encoded` counts the frames the recorder asked to draw.
    private func offer(_ recorder: MetalFrameRecorder, queue: MTLCommandQueue, ns: UInt64, width: Int, height: Int,
                       encoded: inout Int) throws -> MetalFrameRecorder.FrameOutcome {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var drew = false
        let outcome = recorder.recordFrame(presentationNanoseconds: ns, drawableWidth: width, drawableHeight: height,
                                           commandBuffer: commands) { (texture: MTLTexture) -> Bool in
            drew = true
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        if drew { encoded += 1 }
        commands.commit()
        commands.waitUntilCompleted()
        return outcome
    }

    private struct Run {
        var video: RecordedVideo
        var info: RecordedVideoInfo
        var report: RecordingValidationReport
        var encoded: Int
        var interval: Int64
    }

    /// Offers `times` (ns from the first frame) at `fps` to a recorder with a 10 s length; on `durationReached` the
    /// frame path calls `beginFinish()` as the app's tap does. `stopAfter`: the test finishes earlier (a manual stop).
    private func record(_ times: [UInt64], fps: Int, audio: Bool = false, stopAfter: Double? = nil,
                        name: String) async throws -> Run {
        let (device, queue) = try gpu()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC-008-\(name)-\(UUID().uuidString).mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var settings = RecordingQualityProfile.draft.settings(frameRate: fps)   // H.264: every host
        settings.maxDurationSeconds = length
        let (width, height) = audio ? (160, 120) : (64, 48)
        // The audio fixture uses the live writer (as REC-004's mux test); video-only runs are offline (no drops).
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: width, drawableHeight: height,
                                              settings: settings, realTime: audio, audio: audio)
        var encoded = 0
        var chunk = 0   // 10 ms audio chunks from the first frame
        var reachedEnd = false
        for time in times {
            if let stopAfter, Double(time) / 1e9 >= stopAfter { break }
            let outcome = try offer(recorder, queue: queue, ns: base + time, width: width, height: height, encoded: &encoded)
            if audio {   // the tap pumps audio after each frame: chunks up to one frame later
                while Double(chunk) / 100 < Double(time) / 1e9 + 1.0 / Double(fps) {
                    offerTone(recorder, chunk: chunk)
                    chunk += 1
                }
            }
            if outcome == .durationReached {
                recorder.beginFinish()   // REC-008-R3: on the frame path, never waits
                reachedEnd = true
                break
            }
            XCTAssertTrue(outcome == .submitted || outcome == .skippedRate, "\(name) at \(time) ns: \(outcome)")
            recorder.waitForPendingFrames()   // test pacing only: no queue drops
            if audio { try await Task.sleep(for: .milliseconds(3)) }
        }
        XCTAssertEqual(reachedEnd, stopAfter == nil, "\(name): the length was reached")
        let video = try (await recorder.finish()).get()
        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        let expectation = RecordingExpectation(frameRate: fps, durationSeconds: stopAfter ?? Double(length), expectsAudio: audio)
        let report = await RecordingValidator.validate(url, expectation: expectation)
        print("REC-008 \(name): \(report.summary.split(separator: "\n").first ?? "") encoded=\(encoded)")
        return Run(video: video, info: info, report: report, encoded: encoded, interval: settings.frameIntervalTicks)
    }

    private func offerTone(_ recorder: MetalFrameRecorder, chunk: Int) {
        let frames = 441
        let samples = [Float](repeating: 0.5, count: frames * 2)
        samples.withUnsafeBufferPointer { (p: UnsafeBufferPointer<Float>) -> Void in
            recorder.appendAudio(p.baseAddress!, frames: frames, firstSampleNanoseconds: base + UInt64(chunk) * 10_000_000)
        }
    }

    /// The acceptance checks for a 10 s file at `fps`.
    private func checkTenSeconds(_ run: Run, fps: Int, name: String) async throws {
        let limitTicks = Int64(length) * Int64(RecordingSettings.timescale)
        XCTAssertTrue(run.report.passed, "\(name): \(run.report.summary)")
        XCTAssertEqual(run.info.frameCount, fps * length, "\(name): exactly fps × 10 frames")
        XCTAssertEqual(run.video.frameCount, fps * length, name)
        XCTAssertEqual(run.encoded, fps * length, "\(name): the frame at the end was never encoded")
        XCTAssertTrue(run.info.presentationTicks.allSatisfy { (t: Int64) -> Bool in t < limitTicks }, "\(name): no frame at or after 10 s")
        XCTAssertEqual(run.info.presentationTicks, (0..<(fps * length)).map { (n: Int) -> Int64 in Int64(n) * run.interval },
                       "\(name): PTS n/fps")
        XCTAssertEqual(run.info.durationSeconds, Double(length), accuracy: 1.0 / Double(fps), "\(name): 10 s within one frame")
        XCTAssertEqual(run.video.durationSeconds, Double(length), accuracy: 1e-9, "\(name): ends at exactly 10.000 s")
        let asset = AVURLAsset(url: run.video.url)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable, "\(name): the index (moov) is readable and the file plays")
    }

    // MARK: - REC-008-T04 acceptance

    func testTenSecondTargetAtTheRecordingRateClosesTheFileWithNoExtraFrames() async throws {
        for fps in [24, 30, 60] {
            let times = FrameTimes.steady(hz: UInt64(fps), seconds: 10.5)
            let run = try await record(times, fps: fps, name: "steady\(fps)")
            try await checkTenSeconds(run, fps: fps, name: "steady \(fps) fps")
        }
    }

    func testJittery60HzRenderDecimatedTo30fpsStopsAtTenSeconds() async throws {
        for (name, times) in [("60Hz", FrameTimes.steady(hz: 60, seconds: 10.5)),
                              ("60Hz±2ms", FrameTimes.jittery(hz: 60, jitterMicroseconds: 2_000, seconds: 10.5))] {
            let run = try await record(times, fps: 30, name: name)
            try await checkTenSeconds(run, fps: 30, name: "\(name) → 30 fps")
            XCTAssertEqual(run.video.droppedFrames, 0, name)
        }
    }

    func testAudioEndsWithinTwentyMillisecondsOfTheTarget() async throws {
        let run = try await record(FrameTimes.steady(hz: 30, seconds: 10.5), fps: 30, audio: true, name: "audio30")
        try await checkTenSeconds(run, fps: 30, name: "audio")
        let measurement = try await XCTUnwrapAsync(await RecordingValidator.measure(run.video.url))
        XCTAssertEqual(measurement.audioTrackCount, 1)
        let audioEnd = Double(measurement.audioSampleCount) / 44_100
        print("REC-008 audio end \(String(format: "%.4f", audioEnd)) s, written \(run.video.statistics.audioFramesWritten) frames")
        XCTAssertEqual(audioEnd, Double(length), accuracy: RecordingAudioTimeline.toleranceSeconds, "audio ends within 20 ms of 10 s")
        XCTAssertLessThanOrEqual(run.video.statistics.audioFramesWritten, length * 44_100, "no audio sample at or after 10 s is written")
    }

    // MARK: - REC-008-T12 a stop before the target

    func testAStopBeforeTheTargetKeepsWhatWasRecorded() async throws {
        let run = try await record(FrameTimes.steady(hz: 30, seconds: 10.5), fps: 30, stopAfter: 4, name: "manual4s")
        XCTAssertTrue(run.report.passed, run.report.summary)
        XCTAssertEqual(run.info.frameCount, 120)
        XCTAssertEqual(run.video.durationSeconds, 4, accuracy: 1e-9, "no padding to the target")
    }

    // MARK: - REC-008-T05 render-thread spy

    func testTheFramePathNeverWaitsOnTheFinish() async throws {
        let (device, queue) = try gpu()
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: 64, drawableHeight: 48, maxLongSide: 1920))
        let sink = try RenderSpySink(width: 64, height: 48)
        let settings = RecordingSettings(maxFrameRate: 30, maxDurationSeconds: 1)
        let recorder = try MetalFrameRecorder(device: device, url: FileManager.default.temporaryDirectory.appendingPathComponent("spy.mp4"),
                                              geometry: geometry, settings: settings, sink: sink)
        let render = DispatchQueue(label: "REC-008 render thread")
        render.setSpecific(key: RenderSpySink.renderKey, value: true)
        // The frame loop: 1.2 s of 30 fps frames, all on the render queue, `beginFinish` on the frame that crossed the end.
        let outcomes: [MetalFrameRecorder.FrameOutcome] = try render.sync { () throws -> [MetalFrameRecorder.FrameOutcome] in
            var result: [MetalFrameRecorder.FrameOutcome] = []
            var encoded = 0
            for k in 0..<36 {
                let outcome = try offer(recorder, queue: queue, ns: base + UInt64(k) * 1_000_000_000 / 30, width: 64, height: 48,
                                        encoded: &encoded)
                result.append(outcome)
                if outcome == .durationReached { recorder.beginFinish() }   // returns although the sink's finish is held
                if outcome == .submitted { recorder.waitForPendingFrames() }
            }
            XCTAssertEqual(encoded, 30, "only the frames before the end were drawn")
            return result
        }
        XCTAssertEqual(outcomes.filter { (o: MetalFrameRecorder.FrameOutcome) -> Bool in o == .submitted }.count, 30)
        XCTAssertEqual(outcomes[30], .durationReached)
        XCTAssertTrue(outcomes[31...].allSatisfy { (o: MetalFrameRecorder.FrameOutcome) -> Bool in o == .finished },
                      "after beginFinish every frame is refused at once")
        // The frame loop is done while the writer's finish is still held: nothing on the frame path waited for it.
        for _ in 0..<200 where !sink.isFinishing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(sink.finishCalls, 1, "the finish started off the frame path")
        sink.release()
        let result = await recorder.finish()   // joins the finish beginFinish started
        guard case .success(let video) = result else { return XCTFail("finish: \(result)") }
        XCTAssertEqual(video.frameCount, 30)
        XCTAssertEqual(video.durationSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(sink.finishCalls, 1, "finish() after beginFinish() is the same finish")
        XCTAssertFalse(sink.finishOnRenderQueue, "no finishWriting on the frame path")
        XCTAssertFalse(sink.appendOnRenderQueue, "appends run on the writer queue")
        XCTAssertEqual(sink.appended, 30)
    }
}
#endif
