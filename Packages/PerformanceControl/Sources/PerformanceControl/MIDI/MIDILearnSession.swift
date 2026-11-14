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

    /// MIDI-006: a note learn accepts a key press only (note on with velocity > 0; never a release).
    public static func isNoteEligible(_ event: MIDIEvent) -> Bool {
        event.noteEdge == .on
    }

    /// MIDI-007: a scene learn accepts a program change or a key press (note on with velocity > 0).
    /// MIDI-008: a trigger learn accepts a press of any trigger source: a key press, a CC button press (controller
    /// 0–119, value ≥ 64) or a real-time Start, Continue or Stop (only when `allowsRealTime`; a hold row does not).
    public static func isTriggerEligible(_ event: MIDIEvent, allowsRealTime: Bool) -> Bool {
        guard let edge = MIDIPressFilter.rawEdge(event), edge.edge == .on else { return false }
        return allowsRealTime || !edge.isMomentary
    }

    public static func isSceneEligible(_ event: MIDIEvent) -> Bool {
        event.kind == .programChange || event.noteEdge == .on
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
        handle(batch, now: now, isEligible: MIDILearnEligibility.isEligible)
    }

    /// The same with another eligibility rule (MIDI-006: `MIDILearnEligibility.isNoteEligible`).
    public mutating func handle(_ batch: [MIDIEvent], now: UInt64,
                                isEligible: (MIDIEvent) -> Bool) -> MIDILearnOutcome<Target>? {
        if let expired = expire(now: now) { return expired }
        guard let target else { return nil }
        guard let index = batch.firstIndex(where: { (event: MIDIEvent) -> Bool in isEligible(event) }) else {
            return nil
        }
        self.target = nil
        return .bound(key: batch[index].controlKey, target: target, eventIndex: index)
    }
}
