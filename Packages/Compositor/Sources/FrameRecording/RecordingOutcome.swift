// RecordingOutcome.swift — REC-003 stop reasons, refusals, failures and the recorded result
// (REC-003-R10 to R12, R17; contracts/video-recording.md "Notices"). Plain Swift; builds on Linux.
import Foundation

/// Why a recording ended (REC-003-R11). Every stop finishes the file and keeps what was recorded.
public enum RecordingStopReason: String, Sendable, Equatable, CaseIterable {
    case user
    case durationReached
    case background
    case paused
    case blackedOut
    case visualChanged
    case sizeChanged
    case presentationLost
    case writerFailed

    /// The notice shown after the stop (nil for the user's own stop).
    public var notice: String? {
        switch self {
        case .user: nil
        case .durationReached: "Recording stopped at the 10-minute limit."
        case .background: "Recording stopped when the app left the screen."
        case .paused: "Recording stopped when you paused."
        case .blackedOut: "Recording stopped when the output was blacked out."
        case .visualChanged: "Recording stopped when the visual changed."
        case .sizeChanged: "Recording stopped when the picture size changed."
        case .presentationLost: "Recording stopped when the visual stopped drawing."
        case .writerFailed: RecordingFailure.writerFailed("").notice
        }
    }
}

/// Why Record did not start (REC-003-R12).
public enum RecordingRefusal: String, Sendable, Equatable, CaseIterable {
    case noVisual
    case notRecordable
    case outputBlackedOut
    case paused
    case busy

    public var notice: String {
        switch self {
        case .noVisual: "Start a visualization to record."
        case .notRecordable: "Recording is available for the Camera, Photo, Video, Text and spectrum visuals."
        case .outputBlackedOut: "Restore the output to record."
        case .paused: "Resume to record."
        case .busy: "Finishing the last recording."
        }
    }
}

/// Why a recording produced no file (REC-003-R10, R17).
public enum RecordingFailure: Error, Sendable, Equatable {
    /// No codec could start a writer at this size.
    case encoderUnavailable
    /// The recorder could not make pixel buffers or textures.
    case pixelBufferUnavailable
    /// The writer failed (the system's description); the partial file was deleted.
    case writerFailed(String)
    /// Fewer than two frames were written; no file is offered.
    case tooFewFrames
    /// The recording was cancelled; the file was deleted.
    case cancelled

    public var notice: String {
        switch self {
        case .tooFewFrames: "Nothing was recorded."
        case .cancelled: "The recording was cancelled."
        case .encoderUnavailable, .pixelBufferUnavailable, .writerFailed: "The recording couldn't be finished."
        }
    }
}

/// The refusal rules, in order (REC-003-R12).
public enum RecordingGate {
    public static func refusal(visualAvailable: Bool, recordable: Bool, outputLive: Bool, paused: Bool,
                               busy: Bool) -> RecordingRefusal? {
        if busy { return .busy }
        if !visualAvailable { return .noVisual }
        if !recordable { return .notRecordable }
        if !outputLive { return .outputBlackedOut }
        if paused { return .paused }
        return nil
    }
}

/// A finished recording (REC-003-R10).
public struct RecordedVideo: Sendable, Equatable {
    public let url: URL
    public let codec: RecordingCodec
    /// The encoded video's size.
    public let width: Int
    public let height: Int
    /// Frames written.
    public let frameCount: Int
    /// The file's length (last frame + one interval).
    public let durationSeconds: Double
    public let statistics: RecordingStatistics

    public init(url: URL, codec: RecordingCodec, width: Int, height: Int, frameCount: Int, durationSeconds: Double,
                statistics: RecordingStatistics) {
        self.url = url
        self.codec = codec
        self.width = width
        self.height = height
        self.frameCount = frameCount
        self.durationSeconds = durationSeconds
        self.statistics = statistics
    }
}
