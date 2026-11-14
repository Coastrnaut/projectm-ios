// MIDILearnSession.swift — learn mode: the next eligible control change binds the selected parameter
// (MIDI-003-R2, R3, R6; specs/128-midi-003-midi-learn, data-model "Learn session", research MIDI-003-D3, D4).
//
// Pure Swift, Linux-testable, a value with no clock of its own: every call takes `now` in monotonic
// nanoseconds, so tests are deterministic. `handle` returns at most one `.bound` per call (the first eligible
// event in arrival order) and ends learn mode with it, so one message creates one binding.

/// Which received messages learn mode accepts (research MIDI-003-D3).
public enum MIDILearnEligibility {
    /// Controllers 120–127 are MIDI 1.0 channel mode messages (all sound off, reset all controllers, local
    /// control, all notes off, omni off/on, mono, poly): commands, never learned.
    public static let highestLearnableController: UInt8 = 119

    public static func isEligible(_ event: MIDIEvent) -> Bool {
        event.kind == .controlChange && event.number <= highestLearnableController
    }
}

/// How a learn session ended.
public enum MIDILearnOutcome<Target: Hashable & Sendable>: Sendable, Hashable {
    /// `eventIndex` is the learning message's position in its batch (it applies no value).
    case bound(key: MIDIControlKey, target: Target, eventIndex: Int)
    case timedOut(target: Target)
    case cancelled(target: Target)
}

/// Idle, or learning for one target until a deadline.
public struct MIDILearnSession<Target: Hashable & Sendable>: Sendable, Hashable {
    /// 30 seconds (spec Assumptions).
    public static var timeoutNanoseconds: UInt64 { 30_000_000_000 }

    public private(set) var target: Target?
    public private(set) var deadline: UInt64 = 0

    public init() {}

    public var isLearning: Bool { target != nil }

    /// Starts (or restarts, for a new target) learning; the newest request wins.
    public mutating func start(target: Target, now: UInt64) {
        self.target = target
        let (sum, overflow) = now.addingReportingOverflow(Self.timeoutNanoseconds)
        deadline = overflow ? UInt64.max : sum
    }

    /// Ends learning when the deadline has passed.
    public mutating func expire(now: UInt64) -> MIDILearnOutcome<Target>? {
        guard let target, now >= deadline else { return nil }
        self.target = nil
        return .timedOut(target: target)
    }

    public mutating func cancel() -> MIDILearnOutcome<Target>? {
        guard let target else { return nil }
        self.target = nil
        return .cancelled(target: target)
    }

    /// Expires first, then binds the first eligible event of `batch` (MIDI-003-R2, R3).
    public mutating func handle(_ batch: [MIDIEvent], now: UInt64) -> MIDILearnOutcome<Target>? {
        if let expired = expire(now: now) { return expired }
        guard let target else { return nil }
        guard let index = batch.firstIndex(where: { (event: MIDIEvent) -> Bool in MIDILearnEligibility.isEligible(event) }) else {
            return nil
        }
        self.target = nil
        return .bound(key: batch[index].controlKey, target: target, eventIndex: index)
    }
}
