// RecordedVideoInspector.swift — REC-003 read-back of a recorded file (REC-003-S1, S5): codec, size,
// frame count and every frame's presentation time (from the compressed samples, no decoding), track
// counts and metadata. Used by the tests and the app's DEBUG probe.
#if canImport(AVFoundation)
import AVFoundation
import Foundation

public struct RecordedVideoInfo: Sendable, Equatable {
    /// The sample description's four-character code ("hvc1", "avc1").
    public let codec: String
    public let width: Int
    public let height: Int
    public let frameCount: Int
    /// Each sample's presentation time in 1/600 s, in file order.
    public let presentationTicks: [Int64]
    public let durationSeconds: Double
    public let videoTrackCount: Int
    public let audioTrackCount: Int
    /// Metadata items of the asset (common and format-specific).
    public let metadataCount: Int
    /// REC-004: the first audio track's format ("aac ", 44,100, 2), nil without an audio track.
    public var audioCodec: String? = nil
    public var audioSampleRate: Double? = nil
    public var audioChannelCount: Int? = nil
    /// REC-005-R10: the video track's compressed bytes (audio excluded).
    public var videoBytes: Int = 0

    /// REC-005: frames per second of the file (frames / duration).
    public var nominalFrameRate: Double { durationSeconds > 0 ? Double(frameCount) / durationSeconds : 0 }

    /// REC-005-R10: the video's average bit rate, bits per second (video bytes × 8 / duration).
    public var averageVideoBitRate: Double { durationSeconds > 0 ? Double(videoBytes) * 8 / durationSeconds : 0 }

    /// "video hvc1 1178x2556 frames=58 duration=1.93 audio=0" (the DEBUG probe).
    public var summary: String {
        "video \(codec) \(width)x\(height) frames=\(frameCount) duration=\(String(format: "%.2f", durationSeconds)) audio=\(audioTrackCount)"
    }

    /// True when every presentation time is later than the one before.
    public var timesStrictlyIncrease: Bool {
        zip(presentationTicks, presentationTicks.dropFirst()).allSatisfy { (pair: (Int64, Int64)) -> Bool in pair.1 > pair.0 }
    }
}

public enum RecordedVideoInspector {
    /// Reads the file, or nil when it has no readable video track.
    public static func inspect(_ url: URL) async -> RecordedVideoInfo? {
        let asset = AVURLAsset(url: url)
        guard let videoTracks = try? await asset.loadTracks(withMediaType: .video), let track = videoTracks.first,
              let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
              let (descriptions, size) = try? await track.load(.formatDescriptions, .naturalSize),
              let duration = try? await asset.load(.duration) else { return nil }
        let metadata = (try? await asset.load(.metadata)) ?? []
        let codec = descriptions.first.map { (d: CMFormatDescription) -> String in fourCC(CMFormatDescriptionGetMediaSubType(d)) } ?? "?"
        guard let (ticks, bytes) = compressedSamples(asset: asset, track: track) else { return nil }
        var info = RecordedVideoInfo(codec: codec, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                                     frameCount: ticks.count, presentationTicks: ticks, durationSeconds: duration.seconds,
                                     videoTrackCount: videoTracks.count, audioTrackCount: audioTracks.count,
                                     metadataCount: metadata.count)
        info.videoBytes = bytes
        if let audio = audioTracks.first, let audioDescriptions = try? await audio.load(.formatDescriptions),
           let description = audioDescriptions.first {
            info.audioCodec = fourCC(CMFormatDescriptionGetMediaSubType(description))
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                info.audioSampleRate = asbd.mSampleRate
                info.audioChannelCount = Int(asbd.mChannelsPerFrame)
            }
        }
        return info
    }

    /// Every sample's presentation time and the total compressed size (REC-005-R10), without decoding.
    private static func compressedSamples(asset: AVAsset, track: AVAssetTrack) -> ([Int64], Int)? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)   // compressed samples: no decoding
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var ticks: [Int64] = []
        var bytes = 0
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            bytes += CMSampleBufferGetTotalSampleSize(sample)
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            ticks.append(CMTimeConvertScale(time, timescale: RecordingSettings.timescale, method: .roundHalfAwayFromZero).value)
        }
        return reader.status == .completed ? (ticks, bytes) : nil
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
#endif
