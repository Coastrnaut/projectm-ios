// VideoFileWriter.swift — REC-003 video file writer (REC-003-R6, R8, R17; research REC-003-D1, D2).
//
// One `AVAssetWriter` (MP4) with one video input and a pixel-buffer adaptor, and (REC-004, only when the
// recording's audio decision is "include") one AAC input fed with LPCM Float32 stereo 44.1 kHz chunks;
// no metadata items. The codecs are tried in the settings' order (HEVC, then H.264):
// a codec is used when the writer accepts its settings and starts. Every call after `make` runs on the
// writer's serial `queue`; real-time appends never wait (a not-ready encoder drops the frame), offline
// appends wait for the encoder on that queue (never on the caller's thread).
#if canImport(AVFoundation) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
import Foundation
import Synchronization

/// REC-016-R4 (research REC-016-D5): live recorders and writers in this process (a writer owns its pixel-buffer
/// pool). Diagnostics and tests only; in memory, never stored.
public enum RecordingResourceLedger {
    private static let counts = Mutex<(recorders: Int, writers: Int)>((0, 0))

    public static var liveRecorders: Int { counts.withLock { (c: inout (recorders: Int, writers: Int)) -> Int in c.recorders } }
    public static var liveWriters: Int { counts.withLock { (c: inout (recorders: Int, writers: Int)) -> Int in c.writers } }

    static func recorder(_ delta: Int) { counts.withLock { (c: inout (recorders: Int, writers: Int)) -> Void in c.recorders += delta } }
    static func writer(_ delta: Int) { counts.withLock { (c: inout (recorders: Int, writers: Int)) -> Void in c.writers += delta } }
}

/// The result of one append.
enum RecordingAppendResult: Equatable, Sendable {
    case appended
    case notReady
    case failed
}

/// Where the recorder's pixel buffers go (the writer, or a test double). `append` and `finish` run on
/// `queue`; `makePixelBuffer` may run on any thread.
protocol RecordingSampleSink: AnyObject, Sendable {
    var codec: RecordingCodec { get }
    var queue: DispatchQueue { get }
    func makePixelBuffer() -> CVPixelBuffer?
    func append(_ buffer: CVPixelBuffer, tick: Int64) -> RecordingAppendResult
    /// Ends the file at `endTick` and keeps it, or (keep false) cancels and deletes it.
    func finish(endTick: Int64, keep: Bool) async -> Result<Void, RecordingFailure>
    /// REC-004: true when the file has an AAC input.
    var hasAudio: Bool { get }
    /// REC-004: appends interleaved stereo Float32 frames at `startSample` (44.1 kHz from the session start). On `queue`.
    func appendAudio(_ samples: [Float], startSample: Int64) -> RecordingAppendResult
    /// REC-016-R3 (contract C1.2): after a writer failure, keeps what is usable — a healthy writer is finished at
    /// `endTick`, a failed one keeps its completed fragments — or deletes the file. Returns the failure to report.
    func salvage(endTick: Int64) async -> (RecordingSalvageOutcome, RecordingFailure)
}

extension RecordingSampleSink {
    var hasAudio: Bool { false }
    func appendAudio(_ samples: [Float], startSample: Int64) -> RecordingAppendResult { .failed }
    /// Sinks without fragments keep nothing (REC-003-R17's behaviour).
    func salvage(endTick: Int64) async -> (RecordingSalvageOutcome, RecordingFailure) {
        if case .failure(let failure) = await finish(endTick: endTick, keep: false) { return (.nothing, failure) }
        return (.nothing, .writerFailed("append failed"))
    }
}

/// REC-004-R7: AAC-LC, 44.1 kHz stereo, 128 kb/s; the input is LPCM Float32 interleaved stereo.
enum RecordingAudioFormat {
    static let sampleRate = 44_100
    static let channels = 2
    static let bitRate = 128_000

    static var outputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
        ]
    }

    static func makeFormatDescription() -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                                    magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                                    formatDescriptionOut: &description)
        return status == noErr ? description : nil
    }

    /// One LPCM sample buffer of `samples` (interleaved stereo) at `startSample`.
    static func makeSampleBuffer(_ samples: [Float], startSample: Int64, format: CMAudioFormatDescription) -> CMSampleBuffer? {
        let frames = samples.count / channels
        guard frames > 0 else { return nil }
        let bytes = frames * channels * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { return nil }
        let copied = samples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        var buffer: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: CMTime(value: startSample, timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &buffer)
        return status == noErr ? buffer : nil
    }
}

/// IOSurface-backed, Metal-compatible 32BGRA pixel buffers of one size.
enum RecordingPixelBuffers {
    static func attributes(width: Int, height: Int) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
    }

    static func makePool(width: Int, height: Int, minimumCount: Int) -> CVPixelBufferPool? {
        let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: minimumCount]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary,
                                             attributes(width: width, height: height) as CFDictionary, &pool)
        return status == kCVReturnSuccess ? pool : nil
    }
}

final class VideoFileWriter: RecordingSampleSink, @unchecked Sendable {
    let codec: RecordingCodec
    /// Utility QoS: appends never wait on the encoder in real time, and `cancelWriting` waits on
    /// AVFoundation's own utility threads (a higher QoS here would be a priority inversion).
    let queue = DispatchQueue(label: "REC-003 video writer", qos: .utility)
    let url: URL
    // Used only on `queue` after `make` returns.
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let pool: CVPixelBufferPool
    private let realTime: Bool
    /// Offline (tests' fixtures; the app always records live): how long `append` waits for a not-ready input before
    /// it drops the frame as `notReady`. Only a hang guard: a slow software encoder (CI's iOS Simulator took 432 s
    /// for REC-005's 2 s 1440 × 2880 HEVC fixture) must never lose a frame to it. Was 5 s until run 43612171768.
    static let offlineReadyTimeoutSeconds = 30.0
    /// REC-004: the AAC input and the LPCM format of its chunks (nil without audio).
    private let audioInput: AVAssetWriterInput?
    private let audioFormat: CMAudioFormatDescription?
    /// Used only on `queue`: the last appended video time (REC-016 failure injection).
    private var lastTick: Int64?

    var hasAudio: Bool { audioInput != nil }

    private init(codec: RecordingCodec, url: URL, writer: AVAssetWriter, input: AVAssetWriterInput,
                 adaptor: AVAssetWriterInputPixelBufferAdaptor, pool: CVPixelBufferPool, realTime: Bool,
                 audioInput: AVAssetWriterInput?, audioFormat: CMAudioFormatDescription?) {
        self.audioInput = audioInput
        self.audioFormat = audioFormat
        self.codec = codec
        self.url = url
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.pool = pool
        self.realTime = realTime
        RecordingResourceLedger.writer(1)
    }

    deinit { RecordingResourceLedger.writer(-1) }

    /// A started writer at `url` (an existing file there is replaced), or `encoderUnavailable`.
    /// `audio` (REC-004): adds the AAC input; without it the file has no audio track.
    static func make(url: URL, geometry: RecordingGeometry, settings: RecordingSettings,
                     realTime: Bool, audio: Bool = false) throws(RecordingFailure) -> VideoFileWriter {
        let audioFormat: CMAudioFormatDescription? = audio ? RecordingAudioFormat.makeFormatDescription() : nil
        if audio && audioFormat == nil { throw .encoderUnavailable }
        guard let pool = RecordingPixelBuffers.makePool(width: geometry.sourceWidth, height: geometry.sourceHeight,
                                                        minimumCount: settings.framesInFlight) else {
            throw .pixelBufferUnavailable
        }
        for codec in settings.codecPreference {
            try? FileManager.default.removeItem(at: url)
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { continue }
            let output = outputSettings(codec: codec, geometry: geometry, settings: settings)
            guard writer.canApply(outputSettings: output, forMediaType: .video) else { continue }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: output)
            input.expectsMediaDataInRealTime = realTime
            input.mediaTimeScale = RecordingSettings.timescale
            guard writer.canAdd(input) else { continue }
            writer.add(input)
            var audioInput: AVAssetWriterInput?
            if audio {
                guard writer.canApply(outputSettings: RecordingAudioFormat.outputSettings, forMediaType: .audio) else { continue }
                let added = AVAssetWriterInput(mediaType: .audio, outputSettings: RecordingAudioFormat.outputSettings)
                added.expectsMediaDataInRealTime = realTime
                guard writer.canAdd(added) else { continue }
                writer.add(added)
                audioInput = added
            }
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: RecordingPixelBuffers.attributes(width: geometry.sourceWidth, height: geometry.sourceHeight))
            writer.metadata = []                       // REC-003-R8: no metadata items
            writer.shouldOptimizeForNetworkUse = false
            // REC-016-R1 (ADR-0061): completed fragments survive a writer failure; a normal finish defragments.
            writer.movieFragmentInterval = CMTime(seconds: settings.fragmentIntervalSeconds, preferredTimescale: RecordingSettings.timescale)
            guard writer.startWriting() else {
                writer.cancelWriting()
                continue
            }
            writer.startSession(atSourceTime: .zero)
            return VideoFileWriter(codec: codec, url: url, writer: writer, input: input, adaptor: adaptor, pool: pool,
                                   realTime: realTime, audioInput: audioInput, audioFormat: audioFormat)
        }
        try? FileManager.default.removeItem(at: url)
        throw .encoderUnavailable
    }

    /// Research REC-003-D2: size, bit rate, key frames, Rec. 709 tags, scaling when the output is smaller.
    static func outputSettings(codec: RecordingCodec, geometry: RecordingGeometry, settings: RecordingSettings) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.averageBitRate(codec: codec, width: geometry.outputWidth,
                                                              height: geometry.outputHeight),   // REC-005: profile rate
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoExpectedSourceFrameRateKey: settings.maxFrameRate,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        var output: [String: Any] = [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: geometry.outputWidth,
            AVVideoHeightKey: geometry.outputHeight,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        if geometry.isScaled {   // REC-014 (ADR-0060): an aspect preset crops the centre to fill; Match screen fits
            output[AVVideoScalingModeKey] = geometry.cropsToFill ? AVVideoScalingModeResizeAspectFill : AVVideoScalingModeResizeAspect
        }
        return output
    }

    func makePixelBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }

    func append(_ buffer: CVPixelBuffer, tick: Int64) -> RecordingAppendResult {
        guard writer.status == .writing else { return .failed }
        if !input.isReadyForMoreMediaData {
            if realTime { return .notReady }       // REC-003-R7: never wait while live
            var waited = 0.0
            while !input.isReadyForMoreMediaData && writer.status == .writing && waited < Self.offlineReadyTimeoutSeconds {
                Thread.sleep(forTimeInterval: 0.002)   // offline only, on the writer queue
                waited += 0.002
            }
            guard input.isReadyForMoreMediaData else { return writer.status == .writing ? .notReady : .failed }
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: tick, timescale: RecordingSettings.timescale)) else {
            return .failed
        }
        lastTick = tick
        return .appended
    }

    /// REC-004: live, a not-ready input drops the chunk (never waits); offline, waits on this queue.
    func appendAudio(_ samples: [Float], startSample: Int64) -> RecordingAppendResult {
        guard let audioInput, let audioFormat, writer.status == .writing else { return .failed }
        if !audioInput.isReadyForMoreMediaData {
            if realTime { return .notReady }
            var waited = 0.0
            while !audioInput.isReadyForMoreMediaData && writer.status == .writing && waited < Self.offlineReadyTimeoutSeconds {
                Thread.sleep(forTimeInterval: 0.002)   // offline only, on the writer queue
                waited += 0.002
            }
            guard audioInput.isReadyForMoreMediaData else { return writer.status == .writing ? .notReady : .failed }
        }
        guard let buffer = RecordingAudioFormat.makeSampleBuffer(samples, startSample: startSample, format: audioFormat) else {
            return .notReady
        }
        return audioInput.append(buffer) ? .appended : .failed
    }

    func finish(endTick: Int64, keep: Bool) async -> Result<Void, RecordingFailure> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, RecordingFailure>, Never>) in
            queue.async {
                self.finishOnQueue(endTick: endTick, keep: keep) { (result: Result<Void, RecordingFailure>) in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func finishOnQueue(endTick: Int64, keep: Bool, done: @escaping @Sendable (Result<Void, RecordingFailure>) -> Void) {
        let url = url
        guard keep, writer.status == .writing else {
            // REC-015-R7: an out-of-space error becomes `storageFull`.
            let failure: RecordingFailure? = writer.status == .failed ? RecordingFailure.fromWriterError(writer.error, fallback: "failed") : nil
            if keep, let failure, failure != .storageFull {   // REC-016-R3: the caller salvages the fragments
                done(.failure(failure))
                return
            }
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)   // a cancel, or out of storage: no partial file is kept
            done(failure.map { (f: RecordingFailure) -> Result<Void, RecordingFailure> in .failure(f) } ?? .success(()))
            return
        }
        input.markAsFinished()
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: endTick, timescale: RecordingSettings.timescale))
        let writer = writer
        nonisolated(unsafe) let finished = writer   // read only in the handler, after writing ended
        writer.finishWriting {
            if finished.status == .completed {
                done(.success(()))
            } else {
                let failure = RecordingFailure.fromWriterError(finished.error, fallback: "finish failed")
                if failure == .storageFull { try? FileManager.default.removeItem(at: url) }   // else REC-016: salvaged by the caller
                done(.failure(failure))
            }
        }
    }

    // MARK: - REC-016 salvage (contract C1)

    func salvage(endTick: Int64) async -> (RecordingSalvageOutcome, RecordingFailure) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(RecordingSalvageOutcome, RecordingFailure), Never>) in
            queue.async {
                self.salvageOnQueue(endTick: endTick) { (result: (RecordingSalvageOutcome, RecordingFailure)) in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func salvageOnQueue(endTick: Int64, done: @escaping @Sendable ((RecordingSalvageOutcome, RecordingFailure)) -> Void) {
        let url = url
        let failure: RecordingFailure = writer.status == .failed
            ? RecordingFailure.fromWriterError(writer.error, fallback: "failed") : .writerFailed("append failed")
        let exists = { () -> Bool in FileManager.default.fileExists(atPath: url.path) }
        if failure == .storageFull || (writer.status != .writing && writer.status != .failed) {
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)   // REC-016-R9: out of storage keeps REC-015-R7
            done((.nothing, failure))
            return
        }
        guard writer.status == .writing, lastTick != nil else {   // failed: never cancel (it deletes the fragments)
            done((writer.status == .failed && exists() ? .partial : .nothing, failure))
            return
        }
        input.markAsFinished()   // healthy: finish at the last appended frame
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: endTick, timescale: RecordingSettings.timescale))
        let writer = writer
        nonisolated(unsafe) let finished = writer
        writer.finishWriting {
            done((finished.status == .completed ? .finished : (exists() ? .partial : .nothing), failure))
        }
    }

    /// REC-016-R6: cancels a started writer that will never be used (its file is deleted). Any thread but `queue`.
    func discard() {
        queue.sync {
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// REC-016-R2 (research REC-016-D3), tests and DEBUG only, on `queue`: drives the real writer to its failed
    /// state with a duplicate presentation time and waits (at most 2 s) for AVFoundation to report it.
    func forceFailureOnQueue() {
        guard writer.status == .writing, let buffer = makePixelBuffer() else { return }
        let tick = lastTick ?? 0
        var waited = 0.0
        for _ in 0..<(lastTick == nil ? 2 : 1) {
            while !input.isReadyForMoreMediaData && writer.status == .writing && waited < 2 {
                Thread.sleep(forTimeInterval: 0.002)
                waited += 0.002
            }
            _ = adaptor.append(buffer, withPresentationTime: CMTime(value: tick, timescale: RecordingSettings.timescale))
        }
        while writer.status == .writing && waited < 2 {
            Thread.sleep(forTimeInterval: 0.005)
            waited += 0.005
        }
    }
}

/// REC-015-R12, REC-016-R2 test seam (tests and DEBUG only). `appendFails`: forwards to the real writer until
/// `fault.afterFrames` frames were appended, then fails every append (the real writer stays healthy). `writerFails`:
/// at that point drives the real writer to its failed state. `finishFails`: drives it there when the recording is
/// finished. Out-of-space errors end as REC-015 did (file deleted).
final class FaultInjectingSink: RecordingSampleSink, @unchecked Sendable {
    private let inner: any RecordingSampleSink
    private let fault: RecordingWriterFault
    /// Used only on `queue`.
    private var appended = 0
    private var failed = false

    init(wrapping inner: any RecordingSampleSink, fault: RecordingWriterFault) {
        self.inner = inner
        self.fault = fault
    }

    var codec: RecordingCodec { inner.codec }
    var queue: DispatchQueue { inner.queue }
    var hasAudio: Bool { inner.hasAudio }
    func makePixelBuffer() -> CVPixelBuffer? { inner.makePixelBuffer() }
    func appendAudio(_ samples: [Float], startSample: Int64) -> RecordingAppendResult {
        failed ? .failed : inner.appendAudio(samples, startSample: startSample)
    }

    private var failsAppends: Bool { fault.kind == .appendFails || fault.kind == .writerFails }

    func append(_ buffer: CVPixelBuffer, tick: Int64) -> RecordingAppendResult {
        if failed || (failsAppends && appended >= fault.afterFrames) {
            if !failed, fault.kind == .writerFails { (inner as? VideoFileWriter)?.forceFailureOnQueue() }
            failed = true
            return .failed
        }
        let result = inner.append(buffer, tick: tick)
        if result == .appended { appended += 1 }
        return result
    }

    private func hasFailed() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async { continuation.resume(returning: self.failed) }
        }
    }

    func finish(endTick: Int64, keep: Bool) async -> Result<Void, RecordingFailure> {
        if keep, fault.kind == .finishFails, let writer = inner as? VideoFileWriter {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async {
                    writer.forceFailureOnQueue()
                    continuation.resume()
                }
            }
            return await inner.finish(endTick: endTick, keep: true)
        }
        guard await hasFailed() else { return await inner.finish(endTick: endTick, keep: keep) }
        _ = await inner.finish(endTick: endTick, keep: false)
        return .failure(RecordingFailure.fromWriterError(fault.error, fallback: "injected"))
    }

    func salvage(endTick: Int64) async -> (RecordingSalvageOutcome, RecordingFailure) {
        let failure = RecordingFailure.fromWriterError(fault.error, fallback: "injected")
        if failure == .storageFull {   // REC-016-R9: REC-015-R7 unchanged
            _ = await inner.finish(endTick: endTick, keep: false)
            return (.nothing, failure)
        }
        let (outcome, _) = await inner.salvage(endTick: endTick)
        return (outcome, failure)
    }
}
#endif
