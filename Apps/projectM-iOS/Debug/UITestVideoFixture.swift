// UITestVideoFixture.swift — DEBUG only (MED-002-R20; research MED-002-D9). System pickers cannot be
// automated, so `-uitestSeedVideo counter` writes a 64 × 48, 30 fps, 2 s H.264 movie (each picture a
// different grey) with `AVAssetWriter` in the temporary folder and imports it through the same path
// as a picked file (VideoStore: bounded copy, checks, remux, identifier) right after launch.
// `-uitestSeedVideo corrupt` (MED-014-R14) then replaces the stored copy with a movie whose index
// (`moov`) runs past the end of the file, as if it had been damaged on disk: the video layer's
// container check must fail with the "couldn't be loaded" notice while the app keeps running.
// QA-011 MED-005-T20 (device): `-uitestSeedVideo hd30` writes a 1920 × 1080, 30 fps, 30 s clip (the largest
// reversible shape) and `-uitestSeedVideo long120` a 640 × 360, 30 fps, 2-minute clip (over the 30 s reverse limit),
// both the same way; flat grey pictures keep the files small.
// QA-011 MED-002-T27/T28 (device, Batch 5): `-uitestSeedVideo uhd60` imports a 3840 × 2160, 60 fps, 10 s clip and
// `long600` a 640 × 360, 30 fps, 10-minute clip. Each takes the Mac-made HEVC fixture from the app's Documents when it
// is there (video-hevc-4k60.mov, video-hevc-360p-10min.mov: scripts/make_media_fixtures.py, installed with
// install_test_fixtures.py --media; a copy is imported, the fixture stays) and otherwise writes an H.264 counter of
// that shape. QA-011 MED-003-T20/MED-004-T22 (pass 4, 2026-11-19): `-uitestSeedVideo h264-1080p` imports the Mac-made
// 10 s H.264 1080p clip (Documents/video-h264-1080p.mp4) the same way, else an H.264 counter of that shape, so the
// loop and speed tests no longer depend on the Files picker (covered by MED-002). Not compiled into Release builds.
#if DEBUG
import AVFoundation
import CoreVideo
import Foundation
import MediaSniffing

@MainActor
enum UITestVideoFixture {
    static let argument = "-uitestSeedVideo"

    static func seedIfRequested(_ videos: VideoCoordinator) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return }
        let fixture: String? = ["uhd60": "video-hevc-4k60.mov", "long600": "video-hevc-360p-10min.mov",
                                "h264-1080p": "video-h264-1080p.mp4"][arguments[i + 1]]
        let stem: String = "uitest-video-\(UUID().uuidString)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(stem + ".mov")
        // The Mac-made fixture keeps its own extension (an .mp4 copied under a .mov name would misname its container).
        let fixtureURL: URL? = fixture.map { FileManager.default.temporaryDirectory.appendingPathComponent(stem + "." + ($0 as NSString).pathExtension) }
        Task { @MainActor in
            let shape: (width: Int, height: Int, frames: Int, end: Bool, fps: Int) = switch arguments[i + 1] {
            case "hd30": (1920, 1080, 900, true, 30)      // MED-005-T20: 30 s 1080p
            case "long120": (640, 360, 3600, true, 30)    // MED-005-T20: 2 minutes
            case "uhd60": (3840, 2160, 600, true, 60)     // MED-002-T27/T28: 4K60, 10 s
            case "long600": (640, 360, 18_000, true, 30)  // MED-002-T27: 10 minutes
            case "h264-1080p": (1920, 1080, 300, true, 30) // MED-003-T20, MED-004-T22: 10 s 1080p
            default: (64, 48, 60, false, 30)
            }
            let written: URL? = await Task.detached(priority: .userInitiated) { () async -> URL? in
                if let fixture, let fixtureURL, copyDocumentsFixture(fixture, to: fixtureURL) { return fixtureURL }
                let made: Bool = (try? await writeCounter(to: url, frames: shape.frames, width: shape.width, height: shape.height,
                                                          endsAtLastFrame: shape.end, fps: shape.fps)) != nil
                return made ? url : nil
            }.value
            guard let written else { return }
            await videos.importNow(at: written)
            try? FileManager.default.removeItem(at: written)
            if arguments[i + 1] == "corrupt", let stored = videos.video?.url {
                try? Data(MediaFixtureBytes.movieWithOverrunningMoov()).write(to: stored, options: .atomic)
            }
        }
    }

    /// QA-011 Batch 5: copies Documents/`name` to `url` (the import deletes `url` afterwards, never the fixture).
    nonisolated static func copyDocumentsFixture(_ name: String, to url: URL) -> Bool {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let source = documents.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        return (try? FileManager.default.copyItem(at: source, to: url)) != nil
    }

    /// 60 pictures at 30 fps; picture i is grey 8 + 8 × (i % 30). FILE-008 tests pass another `frames`
    /// count for a movie with different content. `endsAtLastFrame`: the session ends at frames / 30 s, so the track
    /// lasts exactly that long (the 30 s reverse limit is inclusive).
    nonisolated static func writeCounter(to url: URL, frames: Int = 60, width: Int = 64, height: Int = 48,
                                         endsAtLastFrame: Bool = false, fps: Int = 30) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames { try autoreleasepool {
            var waited = 0
            while !input.isReadyForMoreMediaData {
                guard waited < 20_000 else { throw CocoaError(.fileWriteUnknown) }
                usleep(1000)
                waited += 1
            }
            var buffer: CVPixelBuffer?
            // Its own buffer, not one from adaptor.pixelBufferPool: the writer's pool crashed a test process
            // inside CoreVideo with a null dictionary (2026-11-14, intermittent).
            let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                      attributes as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else {
                throw CocoaError(.fileWriteUnknown)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(8 + 8 * (frame % 30)), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        } }
        input.markAsFinished()
        if endsAtLastFrame { writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps))) }
        await writer.finishWriting()   // awaited, not waited on: no priority inversion
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
#endif
