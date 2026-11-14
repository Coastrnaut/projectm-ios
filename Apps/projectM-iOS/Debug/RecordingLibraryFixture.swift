// RecordingLibraryFixture.swift — REC-010 (contract C8), DEBUG only: small real recordings generated at test time
// (64×64 H.264, 2 s at 10 fps, written once with AVAssetWriter and copied) for the app tests and the UI test's seed
// `-uitestRecordingLibrarySeed <n>`, which empties the library folder and writes n recordings 1 s apart in date
// (the last one newest) once per launch.
#if DEBUG
import AVFoundation
import CoreVideo
import Foundation

enum RecordingLibraryFixture {
    static let argument = "-uitestRecordingLibrarySeed"
    @MainActor private static var seeded = false

    enum FixtureError: Error { case writer(String) }

    /// The seed count from the launch arguments, nil without the flag.
    static func seedCountFromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Int? {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return nil }
        return Int(arguments[i + 1])
    }

    @MainActor
    static func seedFromArgumentsOnce(into store: RecordingLibraryStore) {
        guard !seeded, let count = seedCountFromArguments() else { return }
        seeded = true
        _ = try? seed(count, into: store)
    }

    /// Empties the folder and writes `count` recordings, dated `base`, `base + 1 s`… (returned oldest first).
    @discardableResult
    static func seed(_ count: Int, into store: RecordingLibraryStore, base: Date = Date(timeIntervalSince1970: 1_794_000_000)) throws -> [URL] {
        try? FileManager.default.removeItem(at: store.directory)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in 0..<count {
            let date = base.addingTimeInterval(Double(index))
            let url = store.directory.appendingPathComponent("Visualizer Recording \(index + 1).mp4", isDirectory: false)
            try FileManager.default.copyItem(at: try template(), to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            urls.append(url)
        }
        return urls
    }

    /// One encoded recording per container, copied for every seeded file (encoding is the slow part).
    static func template() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingLibraryFixture-template.mp4", isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let partial = url.deletingLastPathComponent().appendingPathComponent("RecordingLibraryFixture-\(UUID().uuidString).mp4")
        try writeVideo(to: partial)
        do {
            try FileManager.default.moveItem(at: partial, to: url)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            if !FileManager.default.fileExists(atPath: url.path) { throw error }
        }
        return url
    }

    /// Writes a 64×64 H.264 file of `frames` frames at `fps`, every frame one grey `shade`.
    static func writeVideo(to url: URL, frames: Int = 20, fps: Int32 = 10, size: Int = 64, shade: UInt8 = 128) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw FixtureError.writer("cannot add input") }
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.writer(writer.error.map { "\($0)" } ?? "start") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            guard let pool = adaptor.pixelBufferPool else { throw FixtureError.writer("no pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw FixtureError.writer("no buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(buffer) * size)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) else {
                throw FixtureError.writer(writer.error.map { "\($0)" } ?? "append")
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: fps))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw FixtureError.writer(writer.error.map { "\($0)" } ?? "finish") }
    }
}
#endif
