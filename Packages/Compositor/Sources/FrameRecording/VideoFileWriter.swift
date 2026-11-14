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
}

extension RecordingSampleSink {
    var hasAudio: Bool { false }
    func appendAudio(_ samples: [Float], startSample: Int64) -> RecordingAppendResult { .failed }
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
    /// REC-004: the AAC input and the LPCM format of its chunks (nil without audio).
    private let audioInput: AVAssetWriterInput?
    private let audioFormat: CMAudioFormatDescription?

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
    }

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
            AVVideoAverageBitRateKey: codec.averageBitRate(width: geometry.outputWidth, height: geometry.outputHeight,
                                                           frameRate: settings.maxFrameRate),
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
        if geometry.isScaled { output[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspect }
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
            while !input.isReadyForMoreMediaData && writer.status == .writing && waited < 5 {
                Thread.sleep(forTimeInterval: 0.002)   // offline only, on the writer queue
                waited += 0.002
            }
            guard input.isReadyForMoreMediaData else { return writer.status == .writing ? .notReady : .failed }
        }
        return adaptor.append(buffer, withPresentationTime: CMTime(value: tick, timescale: RecordingSettings.timescale))
            ? .appended : .failed
    }

    /// REC-004: live, a not-ready input drops the chunk (never waits); offline, waits on this queue.
    func appendAudio(_ samples: [Float], startSample: Int64) -> RecordingAppendResult {
        guard let audioInput, let audioFormat, writer.status == .writing else { return .failed }
        if !audioInput.isReadyForMoreMediaData {
            if realTime { return .notReady }
            var waited = 0.0
            while !audioInput.isReadyForMoreMediaData && writer.status == .writing && waited < 5 {
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
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)   // REC-003-R17: no partial file is kept
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
                try? FileManager.default.removeItem(at: url)
                done(.failure(RecordingFailure.fromWriterError(finished.error, fallback: "finish failed")))
            }
        }
    }
}

/// REC-015-R12 test seam: forwards to the real writer until `fault.afterFrames` frames were appended,
/// then fails every append; finishing cancels the real writer (its file is deleted) and reports the
/// injected error as a real writer failure would be reported.
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

    func append(_ buffer: CVPixelBuffer, tick: Int64) -> RecordingAppendResult {
        if failed || appended >= fault.afterFrames {
            failed = true
            return .failed
        }
        let result = inner.append(buffer, tick: tick)
        if result == .appended { appended += 1 }
        return result
    }

    func finish(endTick: Int64, keep: Bool) async -> Result<Void, RecordingFailure> {
        let hasFailed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async { continuation.resume(returning: self.failed) }
        }
        guard hasFailed else { return await inner.finish(endTick: endTick, keep: keep) }
        _ = await inner.finish(endTick: endTick, keep: false)
        return .failure(RecordingFailure.fromWriterError(fault.error, fallback: "injected"))
    }
}
#endif
