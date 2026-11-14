// MetalFrameRecorderTests.swift — REC-003-T13, T14: the recorder's bounded queue with a stalled writer,
// sizes, finishing and failures. GPU tests (no drawing: the frames are cleared pixel buffers); skipped
// without a Metal device.
#if canImport(Metal) && canImport(AVFoundation) && !COMPOSITOR_NO_METAL
import AVFoundation
import CoreVideo
@testable import FrameRecording
import Foundation
import Metal
import XCTest

/// A sink whose appends block until the test releases them (REC-003-S2), or fail on demand.
private final class StalledSink: RecordingSampleSink, @unchecked Sendable {
    let codec = RecordingCodec.h264
    let queue = DispatchQueue(label: "stalled sink")
    let pool: CVPixelBufferPool
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var appendedTicks: [Int64] = []
    private var finishes: [Bool] = []
    var failAppends = false

    init(width: Int, height: Int) throws {
        pool = try XCTUnwrap(RecordingPixelBuffers.makePool(width: width, height: height, minimumCount: 3))
    }

    func makePixelBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        return CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess ? buffer : nil
    }

    func append(_ buffer: CVPixelBuffer, tick: Int64) -> RecordingAppendResult {
        gate.wait()
        if failAppends { return .failed }
        lock.lock(); appendedTicks.append(tick); lock.unlock()
        return .appended
    }

    func release(_ count: Int) { for _ in 0..<count { gate.signal() } }
    var ticks: [Int64] { lock.lock(); defer { lock.unlock() }; return appendedTicks }
    var finishedKeeping: [Bool] { lock.lock(); defer { lock.unlock() }; return finishes }

    func finish(endTick: Int64, keep: Bool) async -> Result<Void, RecordingFailure> {
        lock.withLock { () -> Void in finishes.append(keep) }
        return .success(())
    }
}

final class MetalFrameRecorderTests: XCTestCase {
    private func gpu() throws -> (MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device (CI simulator or Linux); the rule tests cover the contract.")
        }
        return (device, queue)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("REC-003-\(name)-\(UUID().uuidString).mp4")
    }

    /// One frame: clears the pixel buffer's texture to a gray level in `commands`.
    private func offer(_ recorder: MetalFrameRecorder, queue: MTLCommandQueue, time: UInt64, width: Int = 64, height: Int = 48,
                       level: Double = 0.5) throws -> MetalFrameRecorder.FrameOutcome {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let outcome = recorder.recordFrame(presentationNanoseconds: time, drawableWidth: width, drawableHeight: height,
                                           commandBuffer: commands) { (texture: MTLTexture) -> Bool in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: level, green: level, blue: level, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        commands.commit()
        commands.waitUntilCompleted()
        return outcome
    }

    private let frame: UInt64 = 1_000_000_000 / 30

    /// REC-003-S2: an encoder that stops accepting never makes the frame loop wait; at most 3 frames
    /// are in flight and every other frame is counted as dropped.
    func testStalledWriterBoundsFramesInFlightAndDropsTheRest() throws {
        let (device, queue) = try gpu()
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: 64, drawableHeight: 48, maxLongSide: 1920))
        let sink = try StalledSink(width: 64, height: 48)
        let recorder = try MetalFrameRecorder(device: device, url: temporaryURL("stalled"), geometry: geometry,
                                              settings: .standard, sink: sink)
        var outcomes: [MetalFrameRecorder.FrameOutcome] = []
        for k in 0..<12 {   // every call returns although nothing is appended
            outcomes.append(try offer(recorder, queue: queue, time: UInt64(k) * frame))
        }
        XCTAssertEqual(outcomes.filter { (o: MetalFrameRecorder.FrameOutcome) -> Bool in o == .submitted }.count, 3)
        XCTAssertEqual(outcomes.filter { (o: MetalFrameRecorder.FrameOutcome) -> Bool in o == .dropped }.count, 9)
        XCTAssertLessThanOrEqual(recorder.maxFramesInFlight, 3)
        XCTAssertEqual(recorder.framesInFlight, 3)
        XCTAssertEqual(recorder.statistics.droppedBusy, 9)
        XCTAssertEqual(recorder.statistics.written, 0)

        sink.release(3)   // the encoder catches up
        recorder.waitForPendingFrames()
        XCTAssertEqual(recorder.framesInFlight, 0)
        XCTAssertEqual(sink.ticks, [0, 20, 40], "submitted frames are appended in order")
        sink.release(100)
        XCTAssertEqual(try offer(recorder, queue: queue, time: 12 * frame), .submitted, "frames are written again")
        XCTAssertEqual(try offer(recorder, queue: queue, time: 12 * frame), .dropped, "an equal time is never written")
        recorder.waitForPendingFrames()
        XCTAssertEqual(sink.ticks, [0, 20, 40, 240])
        XCTAssertEqual(recorder.statistics.droppedNotIncreasing, 1)
        XCTAssertEqual(recorder.statistics.written, 4)
    }

    /// A drawable of another size stops the recording; odd sizes crop to even.
    func testSizeChangeAndOddDrawables() throws {
        let (device, queue) = try gpu()
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: 65, drawableHeight: 49, maxLongSide: 1920))
        let sink = try StalledSink(width: geometry.sourceWidth, height: geometry.sourceHeight)
        sink.release(100)
        let recorder = try MetalFrameRecorder(device: device, url: temporaryURL("size"), geometry: geometry,
                                              settings: .standard, sink: sink)
        XCTAssertEqual(try offer(recorder, queue: queue, time: 0, width: 65, height: 49), .submitted)
        XCTAssertEqual(try offer(recorder, queue: queue, time: frame, width: 64, height: 48), .submitted, "the same even size")
        XCTAssertEqual(try offer(recorder, queue: queue, time: 2 * frame, width: 48, height: 64), .sizeChanged)
    }

    /// One frame is not a recording: no file (REC-003 edge case); a second finish returns the same result
    /// and later frames are refused.
    func testFinishIsIdempotentAndNeedsTwoFrames() async throws {
        let (device, queue) = try gpu()
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: 64, drawableHeight: 48, maxLongSide: 1920))
        let sink = try StalledSink(width: 64, height: 48)
        sink.release(100)
        let recorder = try MetalFrameRecorder(device: device, url: temporaryURL("one"), geometry: geometry,
                                              settings: .standard, sink: sink)
        XCTAssertEqual(try offer(recorder, queue: queue, time: 0), .submitted)
        let first = await recorder.finish()
        let second = await recorder.finish()
        XCTAssertEqual(first, .failure(.tooFewFrames))
        XCTAssertEqual(second, first)
        XCTAssertEqual(sink.finishedKeeping, [false], "finished once, the file deleted")
        XCTAssertEqual(try offer(recorder, queue: queue, time: frame), .finished)
    }

    /// REC-003-R17: a writer failure stops the recorder and finishing reports it without keeping a file.
    func testWriterFailureStopsTheRecorder() async throws {
        let (device, queue) = try gpu()
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: 64, drawableHeight: 48, maxLongSide: 1920))
        let sink = try StalledSink(width: 64, height: 48)
        sink.failAppends = true
        sink.release(100)
        let recorder = try MetalFrameRecorder(device: device, url: temporaryURL("fail"), geometry: geometry,
                                              settings: .standard, sink: sink)
        XCTAssertEqual(try offer(recorder, queue: queue, time: 0), .submitted)
        recorder.waitForPendingFrames()
        XCTAssertTrue(recorder.hasFailed)
        XCTAssertEqual(try offer(recorder, queue: queue, time: frame), .failed)
        let result = await recorder.finish()
        guard case .failure(.writerFailed) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(sink.finishedKeeping, [false])
    }

    /// The real writer: a larger drawable is scaled to fit the long-side cap; one video track, no audio.
    func testRealWriterScalesToTheCap() async throws {
        let (device, queue) = try gpu()
        let url = temporaryURL("scaled")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings = RecordingSettings(maxLongSide: 160, codecPreference: [.h264])
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 320, drawableHeight: 240,
                                              settings: settings, realTime: false)
        XCTAssertEqual([recorder.geometry.sourceWidth, recorder.geometry.sourceHeight], [320, 240])
        for k in 0..<10 {
            XCTAssertEqual(try offer(recorder, queue: queue, time: UInt64(k) * frame, width: 320, height: 240,
                                     level: Double(k) / 10), .submitted)
            recorder.waitForPendingFrames()
        }
        let video = try (await recorder.finish()).get()
        XCTAssertEqual([video.width, video.height, video.frameCount], [160, 120, 10])
        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        XCTAssertEqual([info.width, info.height], [160, 120])
        XCTAssertEqual(info.codec, "avc1")
        XCTAssertEqual(info.frameCount, 10)
        XCTAssertEqual(info.audioTrackCount, 0)
        XCTAssertEqual(info.videoTrackCount, 1)
    }

    /// Cancelling deletes the file.
    func testCancelDeletesTheFile() async throws {
        let (device, queue) = try gpu()
        let url = temporaryURL("cancel")
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 64, drawableHeight: 48,
                                              settings: RecordingSettings(codecPreference: [.h264]), realTime: false)
        for k in 0..<3 { _ = try offer(recorder, queue: queue, time: UInt64(k) * frame) }
        await recorder.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let again = await recorder.finish()
        XCTAssertEqual(again, .failure(.cancelled))
    }

    // MARK: - REC-015 disk guard

    /// REC-015-S2: free space that drops below the stop threshold at frame k stops the recording; the
    /// finished file plays: k frames, strictly increasing times.
    func testLowStorageStopFinishesAPlayableFile() async throws {
        let (device, queue) = try gpu()
        let url = temporaryURL("lowstorage")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings = RecordingSettings(codecPreference: [.h264])
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 64, drawableHeight: 48,
                                              settings: settings, realTime: false)
        let policy = RecordingStoragePolicy(estimate: RecordingStorageEstimate(geometry: recorder.geometry, settings: settings))
        let plenty: Int64 = 64_000_000_000
        let low: Int64 = 50_000_000
        let k = 6
        var stoppedAt: Int?
        for i in 0..<20 {
            let available: Int64 = i >= k ? low : plenty   // the fake probe's reading before frame i
            if policy.shouldStop(availableBytes: available, fileBytes: RecordingStorage.fileBytes(at: url),
                                 recordedSeconds: recorder.recordedSeconds) {
                stoppedAt = i
                break
            }
            XCTAssertEqual(try offer(recorder, queue: queue, time: UInt64(i) * frame, level: Double(i % 10) / 10), .submitted)
            recorder.waitForPendingFrames()
        }
        XCTAssertEqual(stoppedAt, k)
        let video = try (await recorder.finish()).get()
        XCTAssertEqual(video.frameCount, k)
        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        XCTAssertEqual(info.frameCount, k)
        XCTAssertTrue(info.timesStrictlyIncrease, "\(info.presentationTicks)")
        XCTAssertEqual(info.presentationTicks, [0, 20, 40, 60, 80, 100])
        // QA-008-T08: the stopped file passes the whole validation (6 frames = 0.2 s, video only, no metadata).
        let report = await RecordingValidator.validate(url, expectation: RecordingExpectation(durationSeconds: 0.2))
        XCTAssertTrue(report.passed, report.summary)
    }

    /// REC-015-S3: a real writer made to fail with "disk full" after 3 frames: the recorder stops, the
    /// outcome is `storageFull` and no partial file is left.
    func testInjectedDiskFullIsStorageFullAndDeletesTheFile() async throws {
        let (device, queue) = try gpu()
        let url = temporaryURL("diskfull")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 64, drawableHeight: 48,
                                              settings: RecordingSettings(codecPreference: [.h264]), realTime: false,
                                              fault: .diskFull(afterFrames: 3))
        for i in 0..<4 {
            XCTAssertEqual(try offer(recorder, queue: queue, time: UInt64(i) * frame), .submitted)
            recorder.waitForPendingFrames()
        }
        XCTAssertTrue(recorder.hasFailed)
        XCTAssertEqual(recorder.statistics.written, 3)
        XCTAssertEqual(try offer(recorder, queue: queue, time: 4 * frame), .failed)
        let result = await recorder.finish()
        XCTAssertEqual(result, .failure(.storageFull))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "no partial file is offered or kept")
    }
}

/// `XCTUnwrap` for an async-produced optional.
func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
#endif
