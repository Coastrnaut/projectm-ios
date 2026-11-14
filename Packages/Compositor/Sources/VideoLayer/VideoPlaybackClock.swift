// VideoPlaybackClock.swift — the playback time of a video layer (MED-002-R9; research MED-002-D4).
// Plain Swift, every platform; integer nanoseconds, no allocation.
//
// The clock advances by the difference between successive presentation times (the display link's
// target times in the app, injected times in tests), so the video plays at its intended rate (1×)
// through slow frames. Rules: the first call is playback time 0; a difference in (0, 1 s] is added in
// full (not CMP-001's 0.1 s clamp, which would slow the video after a hitch); a difference above 1 s
// (a pause, the background, a long stall) or ≤ 0 (time never runs backwards) adds nothing, so the
// video continues from the picture it stopped at.
// MED-004 (research MED-004-D1, D2): the added difference is scaled by `speed` with exact integer
// arithmetic: `step × percent + remainder`, divided by 100, the remainder carried, so the total added
// is ⌊Σ step × percent / 100⌋ with no drift. `setSpeed` keeps the playback time (a change never
// jumps) and starts a new measurement window (DEBUG probe: video time over presentation time).

public struct VideoPlaybackClock: Sendable, Equatable {
    /// The largest presentation-time step that still advances playback.
    public static let maxStepNanoseconds: UInt64 = 1_000_000_000

    private var previous: UInt64?
    /// Nanoseconds of playback on the video's unwrapped (looping) timeline (video time).
    public private(set) var playbackNanoseconds: Int64 = 0
    /// MED-004: the speed the added steps are scaled by.
    public private(set) var speed: VideoPlaybackSpeed = .normal
    /// MED-004: hundredths of a nanosecond not yet added (0…99).
    private var remainder: Int64 = 0
    /// MED-004: presentation time counted (steps that advanced playback) since the last speed change.
    public private(set) var presentationSinceSpeedChange: Int64 = 0
    /// MED-004: video time added since the last speed change.
    public private(set) var playbackSinceSpeedChange: Int64 = 0

    public init() {}

    /// Advances to the frame shown at `presentationNanoseconds` and returns the playback time.
    @discardableResult
    public mutating func advance(to presentationNanoseconds: UInt64) -> Int64 {
        if let previous, presentationNanoseconds > previous {
            let step = presentationNanoseconds - previous
            if step <= Self.maxStepNanoseconds { add(Int64(step)) }
        }
        if previous == nil || presentationNanoseconds > previous! { previous = presentationNanoseconds }
        return playbackNanoseconds
    }

    private mutating func add(_ step: Int64) {
        let scaled: Int64 = step * Int64(speed.percent) + remainder
        let added: Int64 = scaled / 100
        remainder = scaled % 100
        playbackNanoseconds += added
        presentationSinceSpeedChange += step
        playbackSinceSpeedChange += added
    }

    /// MED-004: from the next step, playback advances at `speed`; the playback time is kept.
    public mutating func setSpeed(_ speed: VideoPlaybackSpeed) {
        guard speed != self.speed else { return }
        self.speed = speed
        presentationSinceSpeedChange = 0
        playbackSinceSpeedChange = 0
    }

    /// Playback restarts at 0 with no previous presentation time (new content); the speed is kept.
    public mutating func reset() {
        previous = nil
        playbackNanoseconds = 0
        remainder = 0
        presentationSinceSpeedChange = 0
        playbackSinceSpeedChange = 0
    }

    /// Forgets the previous presentation time but keeps the playback time (resume after a stop:
    /// the next frame continues at the same picture).
    public mutating func forgetPresentation() {
        previous = nil
    }
}
