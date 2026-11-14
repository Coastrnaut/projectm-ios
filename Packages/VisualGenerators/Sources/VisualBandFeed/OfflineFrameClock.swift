// OfflineFrameClock.swift — REC-013 the export's fixed clock (specs/240-rec-013-deterministic-offline-export; R3;
// research REC-013-D1). Plain integer arithmetic; builds on Linux.
//
// Frame n is drawn at n × 1e9 / fps ns (no real clock is read) and the analysis has then read the audio up to sample
// round(n × 44,100 / fps). An export of S samples has round(S × fps / 44,100) frames.

public struct OfflineFrameClock: Sendable, Equatable {
    public static let sampleRate = 44_100
    public static let supportedRates: [Int] = [30, 60]

    public let fps: Int

    /// `fps` must be positive (the export offers 30 and 60).
    public init(fps: Int) {
        precondition(fps > 0, "frame rate")
        self.fps = fps
    }

    /// The frame's time in nanoseconds from the start of the export.
    public func timeNanoseconds(frame: Int) -> UInt64 {
        UInt64(frame) * 1_000_000_000 / UInt64(fps)
    }

    /// The audio sample (per channel, from the start) the analysis has read up to when frame `frame` is drawn.
    public func samplePosition(frame: Int) -> Int {
        (frame * Self.sampleRate + fps / 2) / fps
    }

    /// Frames of an export of `samples` stereo frames (rounded to the nearest frame).
    public func frameCount(samples: Int) -> Int {
        guard samples > 0 else { return 0 }
        return (samples * fps + Self.sampleRate / 2) / Self.sampleRate
    }

    /// The frame duration in seconds.
    public var frameDuration: Double { 1.0 / Double(fps) }
}
