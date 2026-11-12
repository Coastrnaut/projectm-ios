// PlaybackPosition.swift — where In-App Playback is in its track (AUD-006-T14; AUD-006-R6, R8, R9;
// specs/007-aud-006-seekable-transport/data-model.md).

/// A position in the current track. `0 ≤ seconds ≤ durationSeconds`.
public struct PlaybackPosition: Sendable, Equatable {
    public let seconds: Double
    public let durationSeconds: Double

    public init(seconds: Double, durationSeconds: Double) {
        let duration = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        self.durationSeconds = duration
        self.seconds = seconds.isNaN ? 0 : min(max(0, seconds), duration)
    }

    /// Nothing loaded.
    public static let zero = PlaybackPosition(seconds: 0, durationSeconds: 0)

    public var remainingSeconds: Double { durationSeconds - seconds }
}

/// Frame arithmetic for the playback graph. Pure.
enum PlaybackPositionMath {
    /// `frame` limited to `0…length`.
    static func clamp(_ frame: Int64, length: Int64) -> Int64 {
        min(max(0, frame), max(0, length))
    }

    /// The track frame after `elapsed` frames were played from `start`: at most `length` when the
    /// track ends there, wrapped around when it loops.
    static func frame(start: Int64, elapsed: Int64, length: Int64, loops: Bool) -> Int64 {
        guard length > 0 else { return 0 }
        let total = clamp(start, length: length) + max(0, elapsed)
        return loops ? total % length : min(total, length)
    }

    /// The frame nearest to `seconds`, limited to the track. NaN counts as 0.
    static func frame(seconds: Double, sampleRate: Double, length: Int64) -> Int64 {
        guard !seconds.isNaN, sampleRate > 0, length > 0 else { return 0 }
        let frames = (seconds * sampleRate).rounded()
        if frames <= 0 { return 0 }
        if frames >= Double(length) { return length }
        return Int64(frames)
    }
}
