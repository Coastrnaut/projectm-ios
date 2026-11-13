// AVVideoProbe.swift — the import checks of a picked video (MED-002-R5; research MED-002-D7).
//
// In order of cost, each failure typed: the file size (`.fileSizeKey`, before the file is opened) →
// the container's structure (`VideoContainerCheck`, MED-014-R7, R8: boxes inside the file, a `moov`,
// a video track, its coded size) → a video track (`.notAVideo`) → its codec from the sample description (`.unsupportedCodec`) → size,
// rotation, nominal frame rate and length (`VideoTrackInfo.check`) → the first picture decodes
// (`.damaged`): one picture at most 256 px through `AVAssetImageGenerator.image(at:)`, an async API
// that suspends instead of blocking the importing thread on AVFoundation's lower-priority decode
// threads (MED-014-R9; research MED-014-D4: the MED-002 priority-inversion notice). Only those facts are read: no metadata of the asset or the track (spec Privacy
// review). AVFoundation only (`#if canImport(AVFoundation)`).
#if canImport(AVFoundation)
import AVFoundation
import CameraLayer
import CoreMedia
import Foundation

public enum VideoProbe {
    /// The facts of `url`'s first video track, or the first limit it breaks.
    public static func check(_ url: URL, limits: VideoImportLimits) async throws(VideoImportError) -> VideoTrackInfo {
        let size: Int
        do {
            guard let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw VideoImportError.unreadable }
            size = bytes
        } catch {
            throw .unreadable
        }
        guard Int64(size) <= limits.maxFileBytes else { throw .tooLarge }
        try VideoContainerCheck.check(url, limits: limits)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let (_, info, _) = try await load(asset)
        try info.check(limits)
        guard await decodesFirstPicture(asset) else { throw .damaged }
        return info
    }

    /// The first video track and its facts, plus its time range on the file's timeline.
    static func load(_ asset: AVURLAsset) async throws(VideoImportError) -> (AVAssetTrack, VideoTrackInfo, CMTimeRange) {
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw .notAVideo
        }
        guard let track = tracks.first else { throw .notAVideo }
        let descriptions: [CMFormatDescription], natural: CGSize, transform: CGAffineTransform, rate: Float, range: CMTimeRange
        do {
            (descriptions, natural, transform, rate, range) = try await track.load(.formatDescriptions, .naturalSize, .preferredTransform,
                                                                                  .nominalFrameRate, .timeRange)
        } catch {
            throw .damaged
        }
        guard let description = descriptions.first else { throw .damaged }
        guard let codec = VideoCodec(fourCharacterCode: CMFormatDescriptionGetMediaSubType(description)) else { throw .unsupportedCodec }
        let seconds = range.duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw .damaged }
        let info = VideoTrackInfo(width: Int(natural.width.rounded()), height: Int(natural.height.rounded()),
                                  rotation: rotation(of: transform), frameRate: Double(rate),
                                  durationNanoseconds: nanoseconds(range.duration), codec: codec)
        return (track, info, range)
    }

    /// The quarter turn of a track's preferred transform (iPhone portrait video: 90° clockwise).
    static func rotation(of transform: CGAffineTransform) -> CameraRotation {
        CameraRotation(degrees: atan2(Double(transform.b), Double(transform.a)) * 180 / .pi)
    }

    static func nanoseconds(_ time: CMTime) -> Int64 {
        guard time.isNumeric else { return 0 }
        return CMTimeConvertScale(time, timescale: 1_000_000_000, method: .roundTowardNegativeInfinity).value
    }

    /// The size the first-picture check decodes at (bounded memory whatever the video's size).
    static let firstPictureMaximumSize = CGSize(width: 256, height: 256)

    /// Decodes the first picture, at most 256 px, without blocking the calling thread.
    static func decodesFirstPicture(_ asset: AVAsset) async -> Bool {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = false
        generator.maximumSize = firstPictureMaximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .positiveInfinity
        do {
            let (image, _) = try await generator.image(at: .zero)
            return image.width > 0 && image.height > 0
        } catch {
            return false
        }
    }
}

/// The reader settings shared by the probe and playback (research MED-002-D2).
enum AVVideoFrameReaderSettings {
    /// 32BGRA, Metal-compatible, converted to BT.709 R′G′B′ whatever the source's colorimetry (an HDR
    /// or Display P3 video is converted, its highlights clipped), so the shader's sRGB decode is the
    /// same approximation for every file.
    static let output: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
    ]
}
#endif
