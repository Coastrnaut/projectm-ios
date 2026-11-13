// VideoImportLimits.swift — the import limits, codecs, typed errors and track facts of a video
// (MED-002-R5, R14, R15; research MED-002-D7; contracts/video-layer.md). Plain Swift, every platform.
//
// Checked in order of cost: the file size before the file is opened, then the track facts (codec,
// picture size, frame rate, length) before any picture is decoded, then the first picture. MED-014
// (safe media decoder) may tighten them or add checks behind `VideoFrameReading`.
import CameraLayer

public struct VideoImportLimits: Sendable, Equatable {
    /// A picked file larger than this is refused (`.tooLarge`).
    public var maxFileBytes: Int64
    /// A picture longer than this on its longest side is refused (`.pictureTooLarge`).
    public var maxLongestSide: Int
    /// A higher nominal frame rate is refused (`.frameRateTooHigh`); 60.5 lets 59.94 and headers
    /// that round 60 up pass (spec R5).
    public var maxFrameRate: Double

    public init(maxFileBytes: Int64, maxLongestSide: Int, maxFrameRate: Double) {
        self.maxFileBytes = max(maxFileBytes, 1)
        self.maxLongestSide = max(maxLongestSide, 1)
        self.maxFrameRate = maxFrameRate.isFinite && maxFrameRate > 0 ? maxFrameRate : 60.5
    }

    /// 500 MB, 4096 px, 60 fps (spec Clarifications).
    public static let standard = VideoImportLimits(maxFileBytes: 500 * 1024 * 1024, maxLongestSide: 4096, maxFrameRate: 60.5)
}

/// The codecs the app plays (spec Clarifications: H.264 and HEVC only).
public enum VideoCodec: String, Sendable, Equatable {
    case h264
    case hevc

    /// From a sample description's four-character code (`avc1`, `avc3`, `hvc1`, `hev1`); nil for others.
    public init?(fourCharacterCode code: UInt32) {
        switch Self.string(code) {
        case "avc1", "avc3": self = .h264
        case "hvc1", "hev1": self = .hevc
        default: return nil
        }
    }

    static func string(_ code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Why a video was not imported or could not be played.
public enum VideoImportError: Error, Sendable, Equatable {
    /// No video pictures (not a movie, or sound only).
    case notAVideo
    /// The file is larger than `maxFileBytes`.
    case tooLarge
    /// Not H.264 or HEVC.
    case unsupportedCodec
    /// The picture is longer than `maxLongestSide`.
    case pictureTooLarge
    /// The nominal frame rate is above `maxFrameRate`.
    case frameRateTooHigh
    /// The file says it is a video but its pictures cannot be decoded.
    case damaged
    /// The picked file could not be read.
    case unreadable
    /// The copy could not be written to the app's storage.
    case saveFailed

    /// The notice text (MED-002-R14).
    public var message: String {
        switch self {
        case .notAVideo: "That file isn't a video the app can play."
        case .tooLarge: "That video is larger than 500 MB, so it wasn't imported."
        case .unsupportedCodec: "That video's format isn't supported. Choose an H.264 or HEVC video."
        case .pictureTooLarge: "That video is larger than 4K, so it wasn't imported."
        case .frameRateTooHigh: "That video has more than 60 frames per second, so it wasn't imported."
        case .damaged: "That video couldn't be read. It may be damaged."
        case .unreadable: "The video couldn't be opened."
        case .saveFailed: "The video couldn't be saved on this device."
        }
    }
}

/// The facts playback needs about a video track; nothing else is read (spec Privacy review).
public struct VideoTrackInfo: Sendable, Equatable {
    /// The encoded picture size (before rotation).
    public var width: Int
    public var height: Int
    /// Quarter turns clockwise that make the picture upright (from the track's transform).
    public var rotation: CameraRotation
    /// The nominal frame rate (0 when the file does not say).
    public var frameRate: Double
    /// The track's length; > 0 for a playable track.
    public var durationNanoseconds: Int64
    public var codec: VideoCodec

    public init(width: Int, height: Int, rotation: CameraRotation, frameRate: Double, durationNanoseconds: Int64, codec: VideoCodec) {
        self.width = width
        self.height = height
        self.rotation = rotation
        self.frameRate = frameRate
        self.durationNanoseconds = durationNanoseconds
        self.codec = codec
    }

    /// The upright size (width and height swapped for a quarter turn).
    public var uprightWidth: Int { rotation.swapsAxes ? height : width }
    public var uprightHeight: Int { rotation.swapsAxes ? width : height }

    /// Throws the first limit this track breaks (size, rate, length).
    public func check(_ limits: VideoImportLimits) throws(VideoImportError) {
        guard width > 0, height > 0, durationNanoseconds > 0 else { throw .damaged }
        guard max(width, height) <= limits.maxLongestSide else { throw .pictureTooLarge }
        guard frameRate.isFinite, frameRate <= limits.maxFrameRate else { throw .frameRateTooHigh }
    }
}
