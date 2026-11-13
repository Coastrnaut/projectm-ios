// VideoFileWriter.swift — REC-003 video file writer (REC-003-R6, R8, R17; research REC-003-D1, D2).
//
// One `AVAssetWriter` (MP4) with one video input and a pixel-buffer adaptor; nothing else: no audio
// input (REC-004), no metadata items. The codecs are tried in the settings' order (HEVC, then H.264):
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
    let queue = DispatchQueue(label: "REC-003 video writer", qos: .userInitiated)
    let url: URL
    // Used only on `queue` after `make` returns.
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let pool: CVPixelBufferPool
    private let realTime: Bool

    private init(codec: RecordingCodec, url: URL, writer: AVAssetWriter, input: AVAssetWriterInput,
                 adaptor: AVAssetWriterInputPixelBufferAdaptor, pool: CVPixelBufferPool, realTime: Bool) {
        self.codec = codec
        self.url = url
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.pool = pool
        self.realTime = realTime
    }

    /// A started writer at `url` (an existing file there is replaced), or `encoderUnavailable`.
    static func make(url: URL, geometry: RecordingGeometry, settings: RecordingSettings,
                     realTime: Bool) throws(RecordingFailure) -> VideoFileWriter {
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
                                   realTime: realTime)
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
            let failure = writer.status == .failed ? RecordingFailure.writerFailed(writer.error?.localizedDescription ?? "failed") : nil
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)   // REC-003-R17: no partial file is kept
            done(failure.map { (f: RecordingFailure) -> Result<Void, RecordingFailure> in .failure(f) } ?? .success(()))
            return
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: endTick, timescale: RecordingSettings.timescale))
        let writer = writer
        nonisolated(unsafe) let finished = writer   // read only in the handler, after writing ended
        writer.finishWriting {
            if finished.status == .completed {
                done(.success(()))
            } else {
                try? FileManager.default.removeItem(at: url)
                done(.failure(.writerFailed(finished.error?.localizedDescription ?? "finish failed")))
            }
        }
    }
}
#endif
