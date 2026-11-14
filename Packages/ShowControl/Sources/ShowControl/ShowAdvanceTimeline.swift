// ShowAdvanceTimeline.swift — the timed cue advance engine (SHOW-002-R3 to R8, R12; data-model.md; contract
// specs/208-show-002-timed-cue-advance/contracts/show-cue-dwell.md D3; research SHOW-002-D1, D2, D4).
//
// A pure value type driven by an injected monotonic clock (`Duration` since an arbitrary origin; never wall-clock
// time). It holds at most one pending advance: idle, running (cue and deadline) or held (cue and remaining time).
// * A cue that starts (any step that moved) with a dwell and a next cue schedules exactly one advance at
//   start + dwell; anything else is idle (R3, R8).
// * `due(at:)` returns the cue once, at the first time ≥ its deadline, and goes idle (R4). A time far past several
//   deadlines still returns one cue: the caller restarts the timeline from that time (no catch-up; D2, R5).
// * Holding (pause, blackout, repair report, background) keeps the remaining time; releasing continues from it.
//   A cue that starts while held starts held with its full dwell (R7, D4).
// `ShowTimedAdvance` applies a due advance to a `ShowCueList` (the pure acceptance path). Foundation only (Linux).
import Foundation

// MARK: - Clocks (SHOW-002-D1)

/// A monotonic time source: never goes backwards, unaffected by the time of day.
public protocol ShowMonotonicClock: AnyObject, Sendable {
    /// Elapsed time since the clock's own origin.
    func now() -> Duration
}

/// The app's clock: `ContinuousClock` (monotonic; keeps counting while the device sleeps).
public final class ShowContinuousClock: ShowMonotonicClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    public init() { origin = clock.now }

    public func now() -> Duration { clock.now - origin }
}

/// A test clock moved by hand. Not thread-safe by design: tests drive it from one thread.
public final class ShowManualClock: ShowMonotonicClock, @unchecked Sendable {
    private var current: Duration

    public init(_ start: Duration = .zero) { current = start }

    public func now() -> Duration { current }

    /// Moves forward (a negative step is ignored: the clock is monotonic).
    public func advance(by step: Duration) {
        guard step > .zero else { return }
        current += step
    }

    /// Jumps to `time` when it is later than now.
    public func set(_ time: Duration) {
        guard time > current else { return }
        current = time
    }
}

// MARK: - Timeline

public struct ShowAdvanceTimeline: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case idle
        /// The advance from `cueID` is due at `deadline`.
        case running(cueID: UUID, deadline: Duration)
        /// Frozen with `remaining` left.
        case held(cueID: UUID, remaining: Duration)
    }

    public private(set) var phase: Phase = .idle
    /// Whether a hold is in effect (kept while idle, so a cue that starts during a hold starts held).
    public private(set) var isHeld = false

    public init() {}

    /// The cue whose advance is pending (nil when idle).
    public var cueID: UUID? {
        switch phase {
        case .idle: nil
        case let .running(cueID, _), let .held(cueID, _): cueID
        }
    }

    public var isIdle: Bool { phase == .idle }

    /// A cue became active at `now` (any step that moved, or a dwell edit on the active cue). Replaces whatever was
    /// pending: one advance at `now + dwell` when the cue has a dwell and a next cue, otherwise idle.
    public mutating func cueStarted(_ cue: ShowCue?, hasNext: Bool, at now: Duration) {
        guard let cue, let dwell = cue.dwell, hasNext else {
            phase = .idle
            return
        }
        phase = isHeld ? .held(cueID: cue.id, remaining: dwell.duration) : .running(cueID: cue.id, deadline: now + dwell.duration)
    }

    /// Holds or releases the countdown, keeping the remaining time.
    public mutating func setHeld(_ held: Bool, at now: Duration) {
        guard held != isHeld else { return }
        isHeld = held
        switch phase {
        case .idle:
            break
        case let .running(cueID, deadline) where held:
            phase = .held(cueID: cueID, remaining: max(.zero, deadline - now))
        case let .held(cueID, remaining) where !held:
            phase = .running(cueID: cueID, deadline: now + remaining)
        default:
            break
        }
    }

    /// The cue to advance from when its deadline has been reached (`now ≥ deadline`); fires once, then idle.
    public mutating func due(at now: Duration) -> UUID? {
        guard case let .running(cueID, deadline) = phase, now >= deadline else { return nil }
        phase = .idle
        return cueID
    }

    /// Time left (nil when idle; never negative).
    public func remaining(at now: Duration) -> Duration? {
        switch phase {
        case .idle: nil
        case let .running(_, deadline): max(.zero, deadline - now)
        case let .held(_, remaining): remaining
        }
    }

    /// Whole seconds left, rounded up ("Next in 0:01" until the deadline), or nil when idle.
    public func remainingWholeSeconds(at now: Duration) -> Int? {
        guard let left = remaining(at: now) else { return nil }
        let parts = left.components
        return Int(parts.seconds) + (parts.attoseconds > 0 ? 1 : 0)
    }

    /// Drops the pending advance (the hold state is kept).
    public mutating func cancel() { phase = .idle }
}

// MARK: - Applying it to a cue list (the pure acceptance path)

public enum ShowTimedAdvance {
    /// One tick: when the active cue's advance is due, steps the list once with `next()` and restarts the timeline
    /// for the new cue from `now` (SHOW-002-R4, R5). Returns the step, or nil when nothing was due. A due cue that
    /// is no longer the active one is dropped.
    @discardableResult
    public static func tick(list: inout ShowCueList, timeline: inout ShowAdvanceTimeline, at now: Duration) -> ShowStep? {
        guard let cueID = timeline.due(at: now) else { return nil }
        guard list.activeCue?.id == cueID else { return nil }
        let step = list.next()
        if step.moved { started(list: list, timeline: &timeline, at: now) }
        return step
    }

    /// A manual step (SHOW-002-R6): applies `operation` and, when it moved, starts the new cue's countdown at `now`.
    @discardableResult
    public static func step(list: inout ShowCueList, timeline: inout ShowAdvanceTimeline, at now: Duration,
                            _ operation: (inout ShowCueList) -> ShowStep) -> ShowStep {
        let step = operation(&list)
        if step.moved { started(list: list, timeline: &timeline, at: now) }
        return step
    }

    /// Restarts the timeline for the list's active cue at `now`.
    public static func started(list: ShowCueList, timeline: inout ShowAdvanceTimeline, at now: Duration) {
        timeline.cueStarted(list.activeCue, hasNext: list.canGoNext, at: now)
    }
}
