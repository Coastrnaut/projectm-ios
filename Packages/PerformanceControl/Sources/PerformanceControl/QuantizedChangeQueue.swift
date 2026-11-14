// QuantizedChangeQueue.swift — MOD-017: discrete changes applied on beat, bar or cue boundaries
// (specs/206-mod-017-quantized-changes; R4 to R6, R8, R10; research MOD-017-D1 to D5; contract Q1).
//
// * Boundaries come from SHOW-011's `TempoSnapshot` (manual tap tempo first, else ANL-005's estimate): Beat is the
//   first beat strictly after the request, Bar the first multiple of `beatsPerBar` beats from the grid's anchor
//   strictly after it (no downbeat detection; 4/4). The deadline is fixed at request time (D2).
// * At most one entry per key: a later request replaces it, a request equal to the current value cancels it (D5).
// * Exactly once by removal (D4): `takeDue(at:)` and `cueStepped()` remove what they return.
// * Fallback (D3): Beat/Bar without a tempo with phase, or Cue without cues, applies immediately.
// No clock is read here: every time is an argument (monotonic nanoseconds on the analysis bus's clock).

/// How discrete parameter changes are timed.
public enum QuantizeMode: String, Sendable, Hashable, CaseIterable, Codable {
    case off
    case beat
    case bar
    case cue
}

/// When a queued change applies.
public enum QuantizeBoundary: Sendable, Hashable {
    /// A beat or bar boundary (monotonic nanoseconds).
    case time(UInt64)
    /// The next cue step.
    case nextCue
}

/// Why a request applied at once.
public enum QuantizeImmediateReason: Sendable, Hashable {
    case off
    /// Beat or Bar mode without a tempo with phase.
    case noTempo
    /// Cue mode without any cue.
    case noCue
}

/// What a request did.
public enum QuantizeRequestResult: Sendable, Hashable {
    /// The caller applies the value now.
    case applyNow(QuantizeImmediateReason)
    /// Queued (or replaced a queued entry) until the boundary.
    case queued(QuantizeBoundary)
    /// The value equals the current one and a queued entry for the key was removed.
    case cancelled
    /// The value equals the current one and nothing was queued: nothing to do.
    case unchanged
}

/// One queued change.
public struct QueuedChange<Key: Hashable & Sendable, Value: Equatable & Sendable>: Sendable {
    public let key: Key
    public let value: Value
    public let requestedAt: UInt64
    public let boundary: QuantizeBoundary
    /// Request order (increasing).
    public let sequence: UInt64
}

extension QueuedChange: Equatable where Value: Equatable {}

extension TempoSnapshot {
    /// The first grid point `anchor + k·beats·period` (k any integer) strictly after `time`; nil without a period
    /// or an anchor, or for `beats == 0`.
    public func nextBoundary(after time: UInt64, beats: UInt64) -> UInt64? {
        guard beats > 0, let anchor = anchorNanoseconds, let period = periodNanoseconds, period > 0 else { return nil }
        let (span, overflow) = period.multipliedReportingOverflow(by: beats)
        guard !overflow else { return nil }
        if time < anchor {
            let steps: UInt64 = (anchor - time - 1) / span
            return anchor - steps * span
        }
        let steps: UInt64 = (time - anchor) / span + 1
        let (offset, offsetOverflow) = steps.multipliedReportingOverflow(by: span)
        guard !offsetOverflow else { return nil }
        let (result, sumOverflow) = anchor.addingReportingOverflow(offset)
        return sumOverflow ? nil : result
    }
}

/// The queue of discrete changes waiting for their boundary (MOD-017).
public struct QuantizedChangeQueue<Key: Hashable & Sendable, Value: Equatable & Sendable>: Sendable {
    public typealias Change = QueuedChange<Key, Value>

    public private(set) var mode: QuantizeMode
    public let beatsPerBar: UInt64
    /// Queued changes in request order.
    public private(set) var entries: [Change] = []
    private var nextSequence: UInt64 = 0

    public init(mode: QuantizeMode = .off, beatsPerBar: UInt64 = 4) {
        self.mode = mode
        self.beatsPerBar = max(beatsPerBar, 1)
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func pendingValue(for key: Key) -> Value? {
        entries.first { (entry: Change) -> Bool in entry.key == key }?.value
    }

    public func boundary(for key: Key) -> QuantizeBoundary? {
        entries.first { (entry: Change) -> Bool in entry.key == key }?.boundary
    }

    /// The earliest timed boundary; nil when nothing timed is queued.
    public var nextDeadline: UInt64? {
        var earliest: UInt64?
        for entry in entries {
            if case let .time(t) = entry.boundary, earliest.map({ (e: UInt64) -> Bool in t < e }) ?? true { earliest = t }
        }
        return earliest
    }

    /// A request for `key` at `time`. `current` is the value in effect now (not a queued one).
    public mutating func request(_ key: Key, value: Value, current: Value, at time: UInt64,
                                 tempo: TempoSnapshot, hasCues: Bool) -> QuantizeRequestResult {
        let existing: Int? = entries.firstIndex { (entry: Change) -> Bool in entry.key == key }
        if value == current {
            guard let existing else { return .unchanged }
            entries.remove(at: existing)
            return .cancelled
        }
        let boundary: QuantizeBoundary
        switch mode {
        case .off:
            if let existing { entries.remove(at: existing) }
            return .applyNow(.off)
        case .beat, .bar:
            let beats: UInt64 = mode == .beat ? 1 : beatsPerBar
            guard let deadline = tempo.nextBoundary(after: time, beats: beats) else {
                if let existing { entries.remove(at: existing) }
                return .applyNow(.noTempo)
            }
            boundary = .time(deadline)
        case .cue:
            guard hasCues else {
                if let existing { entries.remove(at: existing) }
                return .applyNow(.noCue)
            }
            boundary = .nextCue
        }
        if let existing { entries.remove(at: existing) }
        entries.append(Change(key: key, value: value, requestedAt: time, boundary: boundary, sequence: nextSequence))
        nextSequence += 1
        return .queued(boundary)
    }

    /// Removes and returns every timed change whose boundary is at or before `time`, in request order.
    public mutating func takeDue(at time: UInt64) -> [Change] {
        var due: [Change] = []
        var kept: [Change] = []
        for entry in entries {
            if case let .time(t) = entry.boundary, t <= time { due.append(entry) } else { kept.append(entry) }
        }
        entries = kept
        return due
    }

    /// A cue step: in Cue mode every queued change applies (returned, in request order); in Beat or Bar mode the
    /// queue is cleared (R8). Both remove what they cover.
    public mutating func cueStepped() -> (apply: [Change], dropped: Int) {
        let all: [Change] = entries
        entries.removeAll()
        return mode == .cue ? (all, 0) : ([], all.count)
    }

    /// Sets the mode; a change of mode clears the queue. Returns the number dropped.
    @discardableResult
    public mutating func setMode(_ newMode: QuantizeMode) -> Int {
        guard newMode != mode else { return 0 }
        mode = newMode
        return clear()
    }

    /// Clears the queue; returns the number dropped.
    @discardableResult
    public mutating func clear() -> Int {
        let count: Int = entries.count
        entries.removeAll()
        return count
    }
}
