// MetalFrameRecorder.swift — REC-003 GPU-fed recorder (contracts/video-recording.md; research
// REC-003-D4 to D6; ADR-0027).
//
// Per frame (the frame loop's thread, never waits): the size check → the timeline (time rules and
// rate cap) → the bounded gate (3 in flight) → a pixel buffer from the pool → its `bgra8Unorm_srgb`
// Metal texture from the texture cache → the caller encodes the shown frame into it in its own
// command buffer → when that command buffer completes, the buffer is appended on the writer's serial
// queue and the slot is released. Frames are appended in submission order (command buffers of one
// queue complete in order; the writer queue is serial).
//
// `finish` stops accepting frames, waits (asynchronously) for the frames in flight, then ends the
// session one interval after the last appended frame. Fewer than two frames, a writer failure or
// `cancel` delete the file.
#if canImport(Metal) && canImport(CoreVideo) && canImport(AVFoundation) && !COMPOSITOR_NO_METAL
import CoreVideo
import Foundation
import Metal
import Synchronization

public final class MetalFrameRecorder: @unchecked Sendable {
    public enum FrameOutcome: Equatable, Sendable {
        /// Encoded into a pixel buffer; appended when the command buffer completes.
        case submitted
        /// Closer to the last frame than the frame-rate cap allows (not a drop).
        case skippedRate
        /// Left out (queue full, no buffer, time not increasing); counted in `statistics`.
        case dropped
        /// The drawable no longer matches the recording's size: stop the recording.
        case sizeChanged
        /// The maximum duration is reached: stop the recording.
        case durationReached
        /// `finish` or `cancel` was called; nothing more is taken.
        case finished
        /// The writer failed: stop the recording (`finish` reports the failure).
        case failed
    }

    private struct Shared {
        var statistics = RecordingStatistics()
        var lastAppendedTick: Int64?
        var stopped = false
        var writerFailed = false
        var finishTask: Task<Result<RecordedVideo, RecordingFailure>, Never>?
    }

    public let geometry: RecordingGeometry
    public let settings: RecordingSettings
    public let url: URL
    public var codec: RecordingCodec { sink.codec }

    private let sink: any RecordingSampleSink
    private let textureCache: CVMetalTextureCache
    private let gate: RecordingFrameGate
    private let pending = DispatchGroup()
    private let shared = Mutex(Shared())
    /// Frame-loop thread only.
    private var timeline: RecordingTimeline

    /// A recorder writing to `url` at the drawable's (even-cropped) size, scaled to fit the settings.
    public convenience init(device: MTLDevice, url: URL, drawableWidth: Int, drawableHeight: Int,
                            settings: RecordingSettings = .standard, realTime: Bool = true) throws(RecordingFailure) {
        guard let geometry = RecordingGeometry(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                               maxLongSide: settings.maxLongSide) else { throw .pixelBufferUnavailable }
        let writer = try VideoFileWriter.make(url: url, geometry: geometry, settings: settings, realTime: realTime)
        try self.init(device: device, url: url, geometry: geometry, settings: settings, sink: writer)
    }

    /// Tests: any sink (a stalled writer).
    init(device: MTLDevice, url: URL, geometry: RecordingGeometry, settings: RecordingSettings,
         sink: any RecordingSampleSink) throws(RecordingFailure) {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw .pixelBufferUnavailable
        }
        self.geometry = geometry
        self.settings = settings
        self.url = url
        self.sink = sink
        textureCache = cache
        gate = RecordingFrameGate(capacity: settings.framesInFlight)
        timeline = RecordingTimeline(settings: settings)
    }

    // MARK: - Frames (frame-loop thread)

    /// Offers one shown frame. `encode` draws it into the given texture (`bgra8Unorm_srgb`,
    /// `geometry.sourceWidth × sourceHeight`) with `commandBuffer`, which the caller commits afterwards.
    public func recordFrame(presentationNanoseconds: UInt64, drawableWidth: Int, drawableHeight: Int,
                            commandBuffer: MTLCommandBuffer, encode: (MTLTexture) -> Bool) -> FrameOutcome {
        let (stopped, failed) = shared.withLock { (s: inout Shared) -> (Bool, Bool) in (s.stopped, s.writerFailed) }
        if stopped { return .finished }
        if failed { return .failed }
        guard geometry.matches(drawableWidth: drawableWidth, drawableHeight: drawableHeight) else { return .sizeChanged }
        let tick: Int64
        switch timeline.admit(presentationNanoseconds: presentationNanoseconds) {
        case .candidate(let t): tick = t
        case .skippedRate:
            count { (s: inout RecordingStatistics) -> Void in s.skippedRate += 1 }
            return .skippedRate
        case .droppedNotIncreasing:
            count { (s: inout RecordingStatistics) -> Void in s.droppedNotIncreasing += 1 }
            return .dropped
        case .durationReached:
            return .durationReached
        }
        guard gate.tryAcquire() else {                                     // REC-003-R7: never wait
            count { (s: inout RecordingStatistics) -> Void in s.droppedBusy += 1 }
            return .dropped
        }
        guard let buffer = sink.makePixelBuffer(), let texture = makeTexture(buffer),
              let metal = CVMetalTextureGetTexture(texture), encode(metal) else {
            gate.release()
            count { (s: inout RecordingStatistics) -> Void in s.droppedBusy += 1 }
            return .dropped
        }
        timeline.markWritten(tick: tick)
        pending.enter()
        // The buffer and its texture are used by nothing else until the append; they are released after it.
        nonisolated(unsafe) let pixels = buffer
        nonisolated(unsafe) let keepAlive = texture
        let sink = sink, gate = gate, pending = pending
        commandBuffer.addCompletedHandler { [self] (completed: MTLCommandBuffer) in
            let drawn = completed.status == .completed
            sink.queue.async {
                defer {
                    _ = keepAlive
                    gate.release()
                    pending.leave()
                }
                guard drawn else {
                    self.count { (s: inout RecordingStatistics) -> Void in s.droppedBusy += 1 }
                    return
                }
                switch sink.append(pixels, tick: tick) {
                case .appended:
                    self.shared.withLock { (s: inout Shared) -> Void in
                        s.statistics.written += 1
                        s.lastAppendedTick = tick
                    }
                case .notReady:
                    self.count { (s: inout RecordingStatistics) -> Void in s.droppedNotReady += 1 }
                case .failed:
                    self.shared.withLock { (s: inout Shared) -> Void in s.writerFailed = true }
                }
            }
        }
        return .submitted
    }

    private func makeTexture(_ buffer: CVPixelBuffer) -> CVMetalTexture? {
        let attributes: [String: Any] = [
            kCVMetalTextureUsage as String: MTLTextureUsage([.renderTarget, .shaderRead, .shaderWrite]).rawValue,
        ]
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, attributes as CFDictionary,
                                                               .bgra8Unorm_srgb, geometry.sourceWidth, geometry.sourceHeight, 0, &texture)
        return status == kCVReturnSuccess ? texture : nil
    }

    private func count(_ change: (inout RecordingStatistics) -> Void) {
        shared.withLock { (s: inout Shared) -> Void in change(&s.statistics) }
    }

    // MARK: - State (any thread)

    public var statistics: RecordingStatistics { shared.withLock { (s: inout Shared) -> RecordingStatistics in s.statistics } }

    /// Length of what was appended so far (last frame + one interval).
    public var recordedSeconds: Double {
        let last = shared.withLock { (s: inout Shared) -> Int64? in s.lastAppendedTick }
        guard let last else { return 0 }
        return Double(last + settings.frameIntervalTicks) / Double(RecordingSettings.timescale)
    }

    /// True after the writer failed (the frame loop should stop the recording).
    public var hasFailed: Bool { shared.withLock { (s: inout Shared) -> Bool in s.writerFailed } }

    /// The most frames in flight at once (tests, diagnostics).
    public var maxFramesInFlight: Int { gate.maxInFlight }
    public var framesInFlight: Int { gate.inFlight }

    /// Tests: blocks until every submitted frame was appended or dropped.
    public func waitForPendingFrames() { pending.wait() }

    // MARK: - Finish

    /// Stops taking frames, waits for the frames in flight and finishes the file. Idempotent: later
    /// calls return the first result.
    public func finish() async -> Result<RecordedVideo, RecordingFailure> {
        await end(keep: true)
    }

    /// Stops and deletes the file.
    public func cancel() async {
        _ = await end(keep: false)
    }

    private func end(keep: Bool) async -> Result<RecordedVideo, RecordingFailure> {
        let task = shared.withLock { (s: inout Shared) -> Task<Result<RecordedVideo, RecordingFailure>, Never> in
            if let existing = s.finishTask { return existing }
            s.stopped = true
            let created = Task { () -> Result<RecordedVideo, RecordingFailure> in await self.performEnd(keep: keep) }
            s.finishTask = created
            return created
        }
        return await task.value
    }

    private func performEnd(keep: Bool) async -> Result<RecordedVideo, RecordingFailure> {
        let pending = pending, queue = sink.queue
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending.notify(queue: queue) { continuation.resume() }
        }
        let (statistics, last, failed) = shared.withLock { (s: inout Shared) -> (RecordingStatistics, Int64?, Bool) in
            (s.statistics, s.lastAppendedTick, s.writerFailed)
        }
        let endTick = (last ?? 0) + settings.frameIntervalTicks
        guard keep, !failed, statistics.written >= 2 else {
            let result = await sink.finish(endTick: endTick, keep: false)
            if !keep { return .failure(.cancelled) }
            if failed {
                if case .failure(let failure) = result { return .failure(failure) }
                return .failure(.writerFailed("append failed"))
            }
            return .failure(.tooFewFrames)
        }
        switch await sink.finish(endTick: endTick, keep: true) {
        case .failure(let failure):
            return .failure(failure)
        case .success:
            return .success(RecordedVideo(url: url, codec: sink.codec, width: geometry.outputWidth, height: geometry.outputHeight,
                                          frameCount: statistics.written,
                                          durationSeconds: Double(endTick) / Double(RecordingSettings.timescale),
                                          statistics: statistics))
        }
    }
}
#endif
