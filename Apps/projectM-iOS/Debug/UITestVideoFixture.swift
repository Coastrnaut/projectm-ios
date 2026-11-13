// UITestVideoFixture.swift — DEBUG only (MED-002-R20; research MED-002-D9). System pickers cannot be
// automated, so `-uitestSeedVideo counter` writes a 64 × 48, 30 fps, 2 s H.264 movie (each picture a
// different grey) with `AVAssetWriter` in the temporary folder and imports it through the same path
// as a picked file (VideoStore: bounded copy, checks, remux, identifier) right after launch.
// `-uitestSeedVideo corrupt` (MED-014-R14) then replaces the stored copy with a movie whose index
// (`moov`) runs past the end of the file, as if it had been damaged on disk: the video layer's
// container check must fail with the "couldn't be loaded" notice while the app keeps running. Not
// compiled into Release builds.
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-video-\(UUID().uuidString).mov")
        Task { @MainActor in
            let written = await Task.detached(priority: .userInitiated) { () async -> Bool in
                (try? await writeCounter(to: url)) != nil
            }.value
            guard written else { return }
            await videos.importNow(at: url)
            try? FileManager.default.removeItem(at: url)
            if arguments[i + 1] == "corrupt", let stored = videos.video?.url {
                try? Data(MediaFixtureBytes.movieWithOverrunningMoov()).write(to: stored, options: .atomic)
            }
        }
    }

    /// 60 pictures at 30 fps; picture i is grey 8 + 8 × (i % 30).
    nonisolated static func writeCounter(to url: URL) async throws {
        let width = 64, height = 48
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
        for frame in 0..<60 {
            var waited = 0
            while !input.isReadyForMoreMediaData {
                guard waited < 5000 else { throw CocoaError(.fileWriteUnknown) }
                usleep(1000)
                waited += 1
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw CocoaError(.fileWriteUnknown)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(8 + 8 * (frame % 30)), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()   // awaited, not waited on: no priority inversion
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
#endif
