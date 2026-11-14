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
// REC-004 (contract C3): with `audio: true` the file also has an AAC track. `appendAudio` (any thread)
// places host-timed chunks relative to the first video frame (`RecordingAudioTimeline`) and appends them
// on the same serial queue; `endAudio` ends the audio for good (a source switch: no silence follows).
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
        /// REC-004: where audio goes in the file (origin = the first admitted frame's time).
        var audio = RecordingAudioTimeline()
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
    /// Frame-loop thread only: the origin was handed to the audio timeline.
    private var audioOriginSet = false

    /// REC-004: true when the file has an AAC input (the recording's audio decision was "include").
    public var hasAudioTrack: Bool { sink.hasAudio }

    /// A recorder writing to `url` at the drawable's (even-cropped) size, scaled to fit the settings.
    /// `fault` (REC-015 tests) makes the writer fail after some frames.
    public convenience init(device: MTLDevice, url: URL, drawableWidth: Int, drawableHeight: Int,
                            settings: RecordingSettings = .standard, realTime: Bool = true,
                            fault: RecordingWriterFault? = nil, audio: Bool = false) throws(RecordingFailure) {
        guard let geometry = RecordingGeometry(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                               maxLongSide: settings.maxLongSide) else { throw .pixelBufferUnavailable }
        let writer = try VideoFileWriter.make(url: url, geometry: geometry, settings: settings, realTime: realTime, audio: audio)
        // REC-015-R12: tests may make the writer fail after N frames (nil in the app's normal use).
        let sink: any RecordingSampleSink = fault.map { (f: RecordingWriterFault) -> any RecordingSampleSink in
            FaultInjectingSink(wrapping: writer, fault: f)
        } ?? writer
        try self.init(device: device, url: url, geometry: geometry, settings: settings, sink: sink)
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
        let admission = timeline.admit(presentationNanoseconds: presentationNanoseconds)
        if !audioOriginSet, let origin = timeline.originNanoseconds {   // REC-004: audio is placed from the video's origin
            audioOriginSet = true
            shared.withLock { (s: inout Shared) -> Void in s.audio.setOrigin(nanoseconds: origin) }
        }
        switch admission {
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
        let interval: Int64 = settings.frameIntervalTicks
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
                        if let previous = s.lastAppendedTick {   // REC-006 contract C2: empty slots in between
                            s.statistics.droppedSlots += Int(max((tick - previous) / interval - 1, 0))
                        }
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

    // MARK: - Audio (REC-004, any thread)

    /// Offers `frames` interleaved stereo Float32 frames at 44.1 kHz whose first frame was captured at
    /// `firstSampleNanoseconds` (uptime clock, like the frames). Ignored without an audio track, after
    /// `endAudio()` or finish, and before the first video frame. Copies the samples; never waits.
    public func appendAudio(_ samples: UnsafePointer<Float>, frames: Int, firstSampleNanoseconds: UInt64) {
        guard sink.hasAudio, frames > 0 else { return }
        let pending = pending
        let placement = shared.withLock { (s: inout Shared) -> RecordingAudioTimeline.Placement? in
            guard !s.stopped, !s.writerFailed,
                  let placed = s.audio.place(frames: frames, firstSampleNanoseconds: firstSampleNanoseconds) else { return nil }
            pending.enter()   // inside the lock: `finish` cannot start between the check and the enter
            return placed
        }
        guard let placement else { return }
        let start = placement.skipFrames * 2
        let chunk = Array(UnsafeBufferPointer(start: samples + start, count: placement.frames * 2))
        let sink = sink
        sink.queue.async { [self] in
            defer { pending.leave() }
            switch sink.appendAudio(chunk, startSample: placement.startSample) {
            case .appended:
                count { (s: inout RecordingStatistics) -> Void in s.audioFramesWritten += placement.frames }
            case .notReady:
                count { (s: inout RecordingStatistics) -> Void in s.audioFramesDropped += placement.frames }
            case .failed:
                shared.withLock { (s: inout Shared) -> Void in s.writerFailed = true }
            }
        }
    }

    /// Ends the audio for good (REC-004-R5): later chunks are ignored; no silence is added.
    public func endAudio() {
        shared.withLock { (s: inout Shared) -> Void in s.audio.end() }
    }

    /// True after `endAudio()`.
    public var audioEnded: Bool { shared.withLock { (s: inout Shared) -> Bool in s.audio.ended } }

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
                                          statistics: statistics, frameRate: settings.maxFrameRate))
        }
    }
}
#endif
