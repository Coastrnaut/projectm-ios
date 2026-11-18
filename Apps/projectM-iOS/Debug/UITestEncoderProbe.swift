// UITestEncoderProbe.swift — QA-011 REC-003-T23 diagnosis (2026-11-18). `-uitestEncoderProbe <seconds>` runs a plain
// real-time AVAssetWriter (HEVC, the screen's native size, 40 Mbit/s, 60 fps; CPU-filled 32BGRA pictures) inside the
// running app, 4 s after launch and without the recorder, and shows how many of the offered frames the input refused
// in the `encoderProbe` value ("offered=<n> refused=<n> done=<0|1>"). The same writer refuses none in
// `EncoderThroughputBench` with the app idle; refusals here mean the visualizing app starves the encoder. Not compiled
// into Release builds.
#if DEBUG
import AVFoundation
import CoreVideo
import Foundation
import UIKit

@MainActor
@Observable
final class UITestEncoderProbe {
    static let shared = UITestEncoderProbe()
    private(set) var value = "idle"

    func startIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-uitestEncoderProbe"), i + 1 < arguments.count,
              let seconds = Double(arguments[i + 1]), seconds > 0 else { return }
        let native = UIScreen.main.nativeBounds
        let width = Int(min(native.width, native.height)) & ~1, height = Int(max(native.width, native.height)) & ~1
        value = "starting"
        Thread.detachNewThread { [weak self] in
            let result = Self.run(seconds: seconds, width: width, height: height)
            // Also a file, so a launch without XCUITest (devicectl, no probe labels over the visual) can be read back.
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? result.write(to: documents.appendingPathComponent("encoder-probe.txt"), atomically: true, encoding: .utf8)
            }
            Task { @MainActor in self?.value = result }
        }
    }

    nonisolated private static func run(seconds: Double, width: Int, height: Int) -> String {
        Thread.sleep(forTimeInterval: 4)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("encoder-probe-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return "failed writer" }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 40_000_000, AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoExpectedSourceFrameRateKey: 60, AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { return "failed input" }
        writer.add(input)
        guard writer.startWriting() else { return "failed start" }
        writer.startSession(atSourceTime: .zero)
        var buffers: [CVPixelBuffer] = []
        for seed in 0..<4 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
            guard let made = buffer else { return "failed buffer" }
            CVPixelBufferLockBaseAddress(made, [])
            if let base = CVPixelBufferGetBaseAddress(made) {
                memset(base, Int32(40 + seed * 50), CVPixelBufferGetDataSize(made) / 2)
            }
            CVPixelBufferUnlockBaseAddress(made, [])
            buffers.append(made)
        }
        let frames = Int(seconds * 60)
        var refused = 0
        let start = Date()
        for i in 0..<frames {
            let wait = start.addingTimeInterval(Double(i) / 60).timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            if input.isReadyForMoreMediaData {
                _ = adaptor.append(buffers[i % buffers.count], withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 60))
            } else {
                refused += 1
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        return "offered=\(frames) refused=\(refused) done=1"
    }
}
#endif
