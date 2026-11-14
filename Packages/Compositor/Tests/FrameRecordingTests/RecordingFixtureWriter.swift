// RecordingFixtureWriter.swift — QA-008-T04: writes the validation corpus at test time (research QA-008-D2,
// D3). No GPU: pixel buffers are filled on the CPU. Good files go through the recorder's own
// `VideoFileWriter` (offline mode: the app's codec preference, no reordering, AAC); files the real writer
// cannot make (another timescale, codec or metadata) go through a plain AVAssetWriter. Nothing is committed.
#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
@testable import FrameRecording
import Foundation
import XCTest

enum RecordingFixtureWriter {
    static let width = 160
    static let height = 120

    struct Spec {
        /// Frame times in 1/600 s ticks.
        var ticks: [Int64]
        /// Where the session ends (the file's duration), in ticks.
        var endTick: Int64
        /// The frame index drawn white (the flash); the others are black.
        var flashFrame: Int?
        var audio = false
        /// The 2 ms click (0.9) at this time; nil for silence.
        var clickSeconds: Double?

        /// `count` frames at `fps` from 0, ending one interval after the last.
        static func regular(frames count: Int, fps: Int = 30) -> Spec {
            let interval = Int64(RecordingSettings.timescale) / Int64(fps)
            return Spec(ticks: (0..<count).map { (k: Int) -> Int64 in Int64(k) * interval }, endTick: Int64(count) * interval)
        }
    }

    static func temporaryURL(_ name: String, ext: String = "mp4") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("QA-008-\(name)-\(UUID().uuidString).\(ext)")
    }

    // MARK: - Through the recorder's writer

    /// Writes `spec` with `VideoFileWriter` (HEVC, else H.264) and returns the file. The writer runs in its
    /// live mode, as in the app (offline mode stalls the video input when both inputs are fed from one
    /// thread); an append that finds the encoder busy is retried after 1 ms, so no frame or chunk is dropped.
    static func writeWithRecorderWriter(_ spec: Spec, url: URL) async throws -> URL {
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: width, drawableHeight: height, maxLongSide: 1920))
        let writer = try VideoFileWriter.make(url: url, geometry: geometry, settings: RecordingSettings(), realTime: true,
                                              audio: spec.audio)
        // Audio from 0 to the end of the video (REC-004: chunks offered in time order with the frames).
        let endSeconds = Double(spec.endTick) / Double(RecordingSettings.timescale)
        let audioSamples = spec.audio ? audioTrack(seconds: endSeconds, click: spec.clickSeconds) : []
        let chunkFrames = 441   // 10 ms
        var nextAudioFrame = 0
        let totalAudioFrames = audioSamples.count / 2
        for (index, tick) in spec.ticks.enumerated() {
            let buffer = try XCTUnwrap(writer.makePixelBuffer())
            fill(buffer, white: index == spec.flashFrame)
            let video = await retrying { () -> RecordingAppendResult in writer.queue.sync { writer.append(buffer, tick: tick) } }
            XCTAssertEqual(video, .appended, "frame \(index)")
            // Audio up to the next frame's time.
            let nextTick = index + 1 < spec.ticks.count ? spec.ticks[index + 1] : spec.endTick
            let audioEnd = min(totalAudioFrames, Int(Double(nextTick) / Double(RecordingSettings.timescale) * 44_100))
            while nextAudioFrame < audioEnd {
                let count = min(chunkFrames, totalAudioFrames - nextAudioFrame)
                let chunk = Array(audioSamples[(nextAudioFrame * 2)..<((nextAudioFrame + count) * 2)])
                let start = Int64(nextAudioFrame)
                let result = await retrying { () -> RecordingAppendResult in
                    writer.queue.sync { writer.appendAudio(chunk, startSample: start) }
                }
                XCTAssertEqual(result, .appended, "audio at \(start)")
                nextAudioFrame += count
            }
        }
        let finished = await writer.finish(endTick: spec.endTick, keep: true)
        if case .failure(let failure) = finished { XCTFail("finish: \(failure)") }
        return url
    }

    /// Repeats `append` while it reports `notReady` (at most 3,000 tries, 1 ms apart).
    private static func retrying(_ append: () -> RecordingAppendResult) async -> RecordingAppendResult {
        var result = append()
        var tries = 0
        while result == .notReady && tries < 3_000 {
            try? await Task.sleep(for: .milliseconds(1))
            result = append()
            tries += 1
        }
        return result
    }

    /// Interleaved stereo Float32 at 44.1 kHz: silence with a 2 ms click of 0.9.
    static func audioTrack(seconds: Double, click: Double?) -> [Float] {
        let frames = Int(seconds * 44_100)
        var samples = [Float](repeating: 0, count: frames * 2)
        if let click {
            let first = Int((click * 44_100).rounded())
            for frame in first..<min(first + 88, frames) where frame >= 0 {
                samples[2 * frame] = 0.9
                samples[2 * frame + 1] = 0.9
            }
        }
        return samples
    }

    static func fill(_ buffer: CVPixelBuffer, white: Bool) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytes = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
        memset(base, white ? 255 : 0, bytes)
        if !white {   // opaque black: alpha 255 in BGRA
            let pixels = base.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<CVPixelBufferGetHeight(buffer) {
                for x in 0..<CVPixelBufferGetWidth(buffer) { pixels[y * row + x * 4 + 3] = 255 }
            }
        }
    }

    // MARK: - Through a plain AVAssetWriter

    struct RawSpec {
        var codec: AVVideoCodecType = .h264
        var fileType: AVFileType = .mp4
        /// Frame times as (value, timescale).
        var times: [CMTime]
        var end: CMTime
        var metadata: [AVMetadataItem] = []
    }

    /// Writes black frames at the given times (frame reordering off), for files the recorder's writer refuses to make.
    static func writeRaw(_ spec: RawSpec, url: URL) async throws -> URL {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: spec.fileType)
        var output: [String: Any] = [AVVideoCodecKey: spec.codec, AVVideoWidthKey: width, AVVideoHeightKey: height]
        if spec.codec == .h264 || spec.codec == .hevc {
            output[AVVideoCompressionPropertiesKey] = [AVVideoAllowFrameReorderingKey: false]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: output)
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = spec.times.first?.timescale ?? RecordingSettings.timescale
        writer.add(input)
        writer.metadata = spec.metadata
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        for time in spec.times {
            var waited = 0
            while !input.isReadyForMoreMediaData && waited < 5_000 {
                try await Task.sleep(for: .milliseconds(1))
                waited += 1
            }
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            let pixels = try XCTUnwrap(buffer)
            fill(pixels, white: false)
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: time), "append at \(time.seconds): \(String(describing: writer.error))")
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: spec.end)
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        return url
    }

    /// A QuickTime location item (personal metadata).
    static func locationItem() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataLocationISO6709
        item.value = "+48.8577+002.2950/" as NSString
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        return item
    }
}
#endif
