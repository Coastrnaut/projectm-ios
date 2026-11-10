// make_app_preview.swift — App Store app preview from a simulator screen recording (no audio).
//
//   swift scripts/make_app_preview.swift <input.mov> <output.mp4> <width> <height> <start-s> <duration-s>
//
// Takes only the video track (the output has no audio track), trims to [start, start + duration],
// scales it to fill width x height (centered crop if the aspect ratio differs slightly), and exports
// H.264 at 30 fps. App Store sizes: iPhone 6.9" 886 x 1920, iPad 13" 1200 x 1600 (portrait);
// 15-30 s. Record with:  xcrun simctl io <udid> recordVideo --codec=h264 <file.mov>
import AVFoundation
import Foundation

let a = CommandLine.arguments
guard a.count == 7, let width = Int(a[3]), let height = Int(a[4]), let start = Double(a[5]), let duration = Double(a[6]) else {
    print("usage: make_app_preview.swift <in> <out> <width> <height> <start-s> <duration-s>")
    exit(2)
}
let input = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let output = URL(fileURLWithPath: a[2])
try? FileManager.default.removeItem(at: output)

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        guard let source = try await input.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
        let natural = try await source.load(.naturalSize)
        let transform = try await source.load(.preferredTransform)
        let size = natural.applying(transform)
        let srcW = abs(size.width), srcH = abs(size.height)

        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: duration, preferredTimescale: 600))
        try track.insertTimeRange(range, of: source, at: .zero)

        // Scale to fill, centered.
        let scale = max(Double(width) / srcW, Double(height) / srcH)
        let dx = (Double(width) - srcW * scale) / 2, dy = (Double(height) - srcH * scale) / 2
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                                    .concatenating(CGAffineTransform(translationX: dx, y: dy)), at: .zero)
        instruction.layerInstructions = [layer]
        let video = AVMutableVideoComposition()
        video.renderSize = CGSize(width: width, height: height)
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = [instruction]

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CocoaError(.featureUnsupported)
        }
        export.videoComposition = video
        try await export.export(to: output, as: .mp4)
        let result = AVURLAsset(url: output)
        let v = try await result.loadTracks(withMediaType: .video)
        let au = try await result.loadTracks(withMediaType: .audio)
        let d = try await result.load(.duration)
        let n = try await v.first!.load(.naturalSize)
        let fps = try await v.first!.load(.nominalFrameRate)
        print("\(output.lastPathComponent): \(Int(n.width))x\(Int(n.height)), \(String(format: "%.2f", d.seconds)) s, \(String(format: "%.1f", fps)) fps, video tracks \(v.count), audio tracks \(au.count)")
    } catch {
        print("failed: \(error)")
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()
