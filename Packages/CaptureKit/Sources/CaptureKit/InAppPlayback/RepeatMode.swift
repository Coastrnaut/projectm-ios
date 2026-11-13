// RepeatMode.swift — the repeat modes of the queue and what a play order answers at the end of a
// track (AUD-004; specs/017-aud-004-loop-track-and-queue/data-model.md, contracts/repeat-mode.md).
// Foundation only, all platforms.
import Foundation

/// How the queue of imported audio continues at the end of a track (AUD-004-R1 to R5).
public enum RepeatMode: String, Sendable, CaseIterable {
    /// The next queued track; after the last, playback stops with the first track cued at 0:00.
    case off
    /// The queued current track repeats without a gap.
    case one
    /// The next queued track, wrapping from the last to the first (the default; AUD-006-R17).
    case all

    /// The mode a tap on the Repeat control moves to: Off → All Tracks → One Track → Off (AUD-004-R12).
    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// What follows when a track plays to its end (`PlayOrder.endOfTrack(after:)`).
public enum EndOfTrackStep: Sendable, Equatable {
    /// Continue with this item from its start. The same item as the one that ended: it repeats,
    /// and the backend loops it without a gap.
    case play(PlaybackItem)
    /// Stop at the end. With a cue, the transport then waits, stopped, at the cue's 0:00, and Play
    /// starts it (AUD-004-R5, R6); without one it stays at the end of the track (AUD-006-R17).
    case stop(cue: PlaybackItem?)
}
