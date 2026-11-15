// ShowTimeline.swift — SHOW-007 the show timeline, seek plans and scrub coalescing (specs/243-show-007-timeline-transport;
// R1 to R4; data-model.md; contract T1 to T3; research SHOW-007-D1 to D3).
//
// * `ShowTimeline` places the cues that are not skipped end to end by their SHOW-002 dwell, from 0:00. It ends at the
//   first such cue without a dwell (an open end: the timed advance stops there too); later cues are not on it. A time
//   maps to one cue and its elapsed time; a cue and elapsed time map back to a time. With Loop, times wrap.
// * `ShowSeekPlan` turns a seek into nothing, a countdown move inside the active cue, or one apply of the destination
//   cue: the cues in between are never applied (no duplicate events; D2).
// * `ShowScrub` holds a drag's preview time and commits it once on release (D3).
// Pure value types, Foundation only (Linux).
import Foundation

public struct ShowTimeline: Sendable, Hashable {
    public struct Entry: Sendable, Hashable {
        public let cueID: UUID
        /// The cue's index in the list.
        public let index: Int
        public let start: Duration
        /// The dwell; nil only for the last entry (an open end).
        public let span: Duration?
    }

    /// A time resolved to a cue.
    public struct Point: Sendable, Hashable {
        public let cueID: UUID
        /// The cue's index in the list.
        public let index: Int
        public let elapsed: Duration
        /// Time left in the cue (nil for an open end).
        public let remaining: Duration?
        /// The time on the timeline.
        public let time: Duration
    }

    public let entries: [Entry]
    /// The sum of the spans (an open end adds nothing).
    public let duration: Duration

    public init(list: ShowCueList) {
        var built: [Entry] = []
        var start: Duration = .zero
        for (index, cue) in list.cues.enumerated() where !cue.skipped {
            let span: Duration? = cue.dwell?.duration
            built.append(Entry(cueID: cue.id, index: index, start: start, span: span))
            guard let span else { break }   // the open end: later cues are not on the timeline
            start += span
        }
        entries = built
        duration = start
    }

    public var isEmpty: Bool { entries.isEmpty }
    /// The last entry has no dwell.
    public var isOpenEnded: Bool { entries.last.map { (e: Entry) -> Bool in e.span == nil } ?? false }
    /// Loop needs every timeline cue timed.
    public var canLoop: Bool { !entries.isEmpty && !isOpenEnded && duration > .zero }

    public func entry(for cueID: UUID) -> Entry? {
        entries.first { (e: Entry) -> Bool in e.cueID == cueID }
    }

    /// The cue at `time` (negative counts as 0). Looping (when `canLoop`) wraps the time; otherwise it is clamped to the
    /// end, which is the last cue with nothing left (or an open-ended last cue at its start). Nil for an empty timeline.
    public func locate(_ time: Duration, looping: Bool) -> Point? {
        guard let last = entries.last else { return nil }
        var t: Duration = max(.zero, time)
        if looping, canLoop {
            t = Self.wrapped(t, by: duration)
        } else if t > duration {
            t = duration
        }
        for entry in entries {
            if let span = entry.span, t < entry.start + span { return point(entry, elapsed: t - entry.start) }
        }
        return point(last, elapsed: last.span ?? .zero)
    }

    /// The time of `elapsed` (clamped to the cue's span) into `cueID`; nil when the cue is not on the timeline.
    public func time(ofCue cueID: UUID, elapsed: Duration) -> Duration? {
        guard let entry = entry(for: cueID) else { return nil }
        let limit: Duration = entry.span ?? .zero
        return entry.start + min(max(.zero, elapsed), limit)
    }

    /// The time of the active cue with `remaining` left in it (nil remaining: its start); nil off the timeline.
    public func time(ofCue cueID: UUID, remaining: Duration?) -> Duration? {
        guard let entry = entry(for: cueID) else { return nil }
        guard let span = entry.span, let remaining else { return entry.start }
        return entry.start + span - min(max(.zero, remaining), span)
    }

    /// With Loop, the cue the show wraps to after `cueID` (the first entry when `cueID` is the last); otherwise nil.
    public func loopTarget(from cueID: UUID, looping: Bool) -> UUID? {
        guard looping, canLoop, let last = entries.last, last.cueID == cueID else { return nil }
        return entries.first?.cueID
    }

    private func point(_ entry: Entry, elapsed: Duration) -> Point {
        let remaining: Duration? = entry.span.map { (span: Duration) -> Duration in max(.zero, span - elapsed) }
        return Point(cueID: entry.cueID, index: entry.index, elapsed: elapsed, remaining: remaining, time: entry.start + elapsed)
    }

    /// `t` modulo `period` (both non-negative; period > 0), in nanoseconds (a timeline is at most 256 h).
    static func wrapped(_ t: Duration, by period: Duration) -> Duration {
        let n: Int64 = nanoseconds(t)
        let p: Int64 = nanoseconds(period)
        guard p > 0 else { return .zero }
        return .nanoseconds(n % p)
    }

    static func nanoseconds(_ d: Duration) -> Int64 {
        let parts = d.components
        return parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
    }
}

// MARK: - Seek plan (R2, R3; D2)

public enum ShowSeekAction: Sendable, Hashable {
    /// Already there: nothing to do.
    case none
    /// Inside the active cue: only its countdown moves to `remaining`.
    case reposition(cueID: UUID, remaining: Duration?)
    /// Another cue: apply it once, with `remaining` left.
    case apply(cueID: UUID, remaining: Duration?)
}

public enum ShowSeekPlan {
    /// What a seek to `time` does. `currentRemaining` is the active cue's countdown now (nil when none runs).
    public static func plan(activeCueID: UUID?, timeline: ShowTimeline, to time: Duration, looping: Bool,
                            currentRemaining: Duration?) -> ShowSeekAction {
        guard let point = timeline.locate(time, looping: looping) else { return .none }
        guard point.cueID == activeCueID else { return .apply(cueID: point.cueID, remaining: point.remaining) }
        if point.remaining == currentRemaining { return .none }
        return .reposition(cueID: point.cueID, remaining: point.remaining)
    }
}

// MARK: - Scrub (R4; D3)

/// A drag on the timeline: only a preview time while it moves, one commit when it ends.
public struct ShowScrub: Sendable, Hashable {
    public private(set) var isScrubbing = false
    /// The time under the finger (nil when not scrubbing or not moved yet).
    public private(set) var previewTime: Duration?

    public init() {}

    public mutating func begin() {
        isScrubbing = true
        previewTime = nil
    }

    /// Moves the preview (starts a scrub when none runs). Never seeks.
    public mutating func move(to time: Duration) {
        isScrubbing = true
        previewTime = max(.zero, time)
    }

    /// Ends the drag: the time to seek to once, or nil when it never moved.
    public mutating func end() -> Duration? {
        defer { cancel() }
        return isScrubbing ? previewTime : nil
    }

    public mutating func cancel() {
        isScrubbing = false
        previewTime = nil
    }
}
