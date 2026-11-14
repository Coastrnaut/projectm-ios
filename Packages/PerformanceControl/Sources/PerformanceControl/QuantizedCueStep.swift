// QuantizedCueStep.swift — SHOW-003: a cue step (Next, Previous, Go to) held until the next beat or bar
// (specs/214-show-003-beat-quantized-cues; R2, R3, R5, R6, R8, R9; research SHOW-003-D1, D4; contract Q1).
//
// * One slot: at most one step waits. The same manual request again cancels it, a different one replaces it (its
//   deadline recomputed at the new request time); a timed request (SHOW-002) only fills an empty slot.
// * Reuses MOD-017: `QuantizeMode` (Off, Beat, Bar; Cue has no meaning for a cue step and is stored as Off),
//   `QuantizeImmediateReason` and `TempoSnapshot.nextBoundary(after:beats:)` (strictly after; bars of `beatsPerBar`
//   beats from the grid's anchor). The deadline is fixed at request time, so a wait never exceeds one beat or bar.
// * Exactly once by removal: `takeDue(at:)` returns the request and empties the slot.
// * Fallback: Beat/Bar without a tempo with phase applies immediately (`.applyNow(.noTempo)`).
// No clock is read here: every time is an argument (monotonic nanoseconds on the analysis bus's clock).
import Foundation

/// A cue step a performer (or the timed advance) asked for.
public enum CueStepRequest: Sendable, Hashable {
    case next
    case previous
    case go(UUID)
}

/// What a cue step request did.
public enum CueStepRequestResult: Sendable, Hashable {
    /// The caller steps now (Off, or no tempo).
    case applyNow(QuantizeImmediateReason)
    /// Queued in an empty slot until the deadline.
    case queued(deadline: UInt64)
    /// Replaced the waiting step (latest wins); the new deadline.
    case replaced(deadline: UInt64)
    /// The same request again: the waiting step was cancelled.
    case cancelled
    /// A timed request while a step already waits: nothing changed.
    case kept
}

/// The single queued cue step (SHOW-003).
public struct QuantizedCueStep: Sendable, Hashable {
    public struct Pending: Sendable, Hashable {
        public let request: CueStepRequest
        public let requestedAt: UInt64
        public let deadline: UInt64
        public let timed: Bool
    }

    public private(set) var mode: QuantizeMode
    public let beatsPerBar: UInt64
    public private(set) var pending: Pending?

    public init(mode: QuantizeMode = .off, beatsPerBar: UInt64 = 4) {
        self.mode = Self.supported(mode)
        self.beatsPerBar = max(beatsPerBar, 1)
    }

    /// Cue mode is not a cue step boundary: it is stored as Off.
    public static func supported(_ mode: QuantizeMode) -> QuantizeMode { mode == .cue ? .off : mode }

    public var deadline: UInt64? { pending?.deadline }
    public var pendingRequest: CueStepRequest? { pending?.request }
    public var isQuantizing: Bool { mode == .beat || mode == .bar }

    /// A request at `time`. `timed` marks SHOW-002's advance: it never cancels or replaces a waiting step.
    public mutating func request(_ request: CueStepRequest, at time: UInt64, tempo: TempoSnapshot,
                                 timed: Bool = false) -> CueStepRequestResult {
        guard isQuantizing else {
            pending = nil
            return .applyNow(.off)
        }
        let beats: UInt64 = mode == .beat ? 1 : beatsPerBar
        guard let deadline = tempo.nextBoundary(after: time, beats: beats) else {
            pending = nil
            return .applyNow(.noTempo)
        }
        let next = Pending(request: request, requestedAt: time, deadline: deadline, timed: timed)
        guard let current = pending else {
            pending = next
            return .queued(deadline: deadline)
        }
        if timed { return .kept }
        if current.request == request {
            pending = nil
            return .cancelled
        }
        pending = next
        return .replaced(deadline: deadline)
    }

    /// The waiting request when `time` has reached its deadline (removed: it is returned once); nil otherwise.
    public mutating func takeDue(at time: UInt64) -> CueStepRequest? {
        guard let current = pending, time >= current.deadline else { return nil }
        pending = nil
        return current.request
    }

    /// Cancels the waiting step; true when one was dropped.
    @discardableResult
    public mutating func cancel() -> Bool {
        guard pending != nil else { return false }
        pending = nil
        return true
    }

    /// Sets the mode; a change of mode cancels the waiting step. True when one was dropped.
    @discardableResult
    public mutating func setMode(_ newMode: QuantizeMode) -> Bool {
        let supported: QuantizeMode = Self.supported(newMode)
        guard supported != mode else { return false }
        mode = supported
        return cancel()
    }
}
