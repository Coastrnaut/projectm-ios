// OfflineVideoFileWriter.swift — REC-013 the offline export's MP4 writer (specs/240-rec-013-deterministic-offline-export;
// R3, R6; research REC-013-D5).
//
// REC-003's `VideoFileWriter` (codecs HEVC then H.264, AAC 44.1 kHz stereo, no metadata, fragments) driven from 8-bit
// BGRA bytes the caller already read back, one frame at a time, at exact slots: frame n at n × (600 / fps) ticks.
// The writer runs in its live mode and a not-ready input is retried (1 ms apart, at most 30 s per sample), so no
// frame or chunk is ever dropped: the offline mode stalls when both inputs are fed from one thread (QA-008's fixture
// writer saw the same). The caller interleaves: frame n, then its audio [s(n), s(n + 1)). Cancel or a failure deletes
// the file.
#if canImport(AVFoundation) && canImport(CoreVideo)
import CoreVideo
import Foundation

public final class OfflineVideoFileWriter: @unchecked Sendable {
    /// Retries of a not-ready append (1 ms apart): 30 s.
    static let maximumTries = 30_000

    public let url: URL
    public let width: Int
    public let height: Int
    public let fps: Int
    public var codec: RecordingCodec { writer.codec }
    public var hasAudio: Bool { writer.hasAudio }
    private let writer: VideoFileWriter
    private let interval: Int64
    /// Frames appended (the caller's thread only).
    public private(set) var framesWritten = 0

    /// A started writer at `url` (replaced if present) for `width × height` (even) frames at `fps` (1…60).
    public init(url: URL, width: Int, height: Int, fps: Int, audio: Bool) throws(RecordingFailure) {
        let settings = RecordingSettings(maxFrameRate: fps, maxLongSide: max(width, height, 16))
        guard width % 2 == 0, height % 2 == 0,
              let geometry = RecordingGeometry(drawableWidth: width, drawableHeight: height, settings: settings),
              !geometry.isScaled else { throw .pixelBufferUnavailable }
        writer = try VideoFileWriter.make(url: url, geometry: geometry, settings: settings, realTime: true, audio: audio)
        self.url = url
        self.width = width
        self.height = height
        self.fps = settings.maxFrameRate
        interval = settings.frameIntervalTicks
    }

    /// Appends the next frame from `bgra` (`height` rows of `bytesPerRow` bytes, top-down). False after a failure.
    public func appendFrame(bgra: UnsafeRawPointer, bytesPerRow: Int) async -> Bool {
        guard let buffer = writer.makePixelBuffer(), fill(buffer, from: bgra, bytesPerRow: bytesPerRow) else { return false }
        let tick: Int64 = Int64(framesWritten) * interval
        nonisolated(unsafe) let pixels = buffer
        let writer = writer
        let result = await retrying { () -> RecordingAppendResult in writer.queue.sync { writer.append(pixels, tick: tick) } }
        guard result == .appended else { return false }
        framesWritten += 1
        return true
    }

    /// Appends interleaved stereo Float32 frames at 44.1 kHz starting at `startSample`. False after a failure.
    public func appendAudio(_ samples: [Float], startSample: Int64) async -> Bool {
        let writer = writer
        let result = await retrying { () -> RecordingAppendResult in writer.queue.sync { writer.appendAudio(samples, startSample: startSample) } }
        return result == .appended
    }

    /// Ends the file one interval after the last frame and keeps it.
    public func finish() async -> Result<Void, RecordingFailure> {
        await writer.finish(endTick: Int64(framesWritten) * interval, keep: true)
    }

    /// Stops and deletes the file.
    public func cancel() async {
        _ = await writer.finish(endTick: Int64(framesWritten) * interval, keep: false)
    }

    private func fill(_ buffer: CVPixelBuffer, from source: UnsafeRawPointer, bytesPerRow: Int) -> Bool {
        guard CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        let destinationRow = CVPixelBufferGetBytesPerRow(buffer)
        let rowBytes = min(width * 4, bytesPerRow, destinationRow)
        for y in 0..<height {
            (base + y * destinationRow).copyMemory(from: source + y * bytesPerRow, byteCount: rowBytes)
        }
        return true
    }

    private func retrying(_ append: () -> RecordingAppendResult) async -> RecordingAppendResult {
        var result = append()
        var tries = 0
        while result == .notReady && tries < Self.maximumTries {
            try? await Task.sleep(nanoseconds: 1_000_000)
            result = append()
            tries += 1
        }
        return result
    }
}
#endif
