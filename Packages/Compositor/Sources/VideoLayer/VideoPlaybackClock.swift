// VideoPlaybackClock.swift — the playback time of a video layer (MED-002-R9; research MED-002-D4).
// Plain Swift, every platform; integer nanoseconds, no allocation.
//
// The clock advances by the difference between successive presentation times (the display link's
// target times in the app, injected times in tests), so the video plays at its intended rate (1×)
// through slow frames. Rules: the first call is playback time 0; a difference in (0, 1 s] is added in
// full (not CMP-001's 0.1 s clamp, which would slow the video after a hitch); a difference above 1 s
// (a pause, the background, a long stall) or ≤ 0 (time never runs backwards) adds nothing, so the
// video continues from the picture it stopped at. MED-004 (speed) scales the added difference.

public struct VideoPlaybackClock: Sendable, Equatable {
    /// The largest presentation-time step that still advances playback.
    public static let maxStepNanoseconds: UInt64 = 1_000_000_000

    private var previous: UInt64?
    /// Nanoseconds of playback on the video's unwrapped (looping) timeline.
    public private(set) var playbackNanoseconds: Int64 = 0

    public init() {}

    /// Advances to the frame shown at `presentationNanoseconds` and returns the playback time.
    @discardableResult
    public mutating func advance(to presentationNanoseconds: UInt64) -> Int64 {
        if let previous, presentationNanoseconds > previous {
            let step = presentationNanoseconds - previous
            if step <= Self.maxStepNanoseconds { playbackNanoseconds += Int64(step) }
        }
        if previous == nil || presentationNanoseconds > previous! { previous = presentationNanoseconds }
        return playbackNanoseconds
    }

    /// Playback restarts at 0 with no previous presentation time (new content).
    public mutating func reset() {
        previous = nil
        playbackNanoseconds = 0
    }

    /// Forgets the previous presentation time but keeps the playback time (resume after a stop:
    /// the next frame continues at the same picture).
    public mutating func forgetPresentation() {
        previous = nil
    }
}
