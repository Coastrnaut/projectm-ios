// MIDIPressFilter.swift — the one place that decides whether a trigger source was pressed or released (MIDI-008-R3,
// R4; specs/157-midi-008-transport, contract T1, research MIDI-008-D2, D3, D7).
//
// Pure Swift, Linux-testable, a value with no clock: it reads the messages' own timestamps (monotonic nanoseconds,
// 0 = unknown). Three source kinds share one rule:
// * a note (MIDI-006's `noteEdge`: velocity > 0 presses, note off or velocity 0 releases);
// * a CC button (controllers 0–119): a value ≥ 64 presses, a value < 64 releases. Repeated high values are not new
//   presses because the key is still down (the hysteresis);
// * a real-time message: Start and Continue press the `.start` source, Stop the `.stop` source. They have no release,
//   so they are momentary: never left down.
// A press is dropped (nil, and no state change, so its matching release is ignored too) when the key is down, when it
// was already pressed in this batch, or when it arrives less than 30 ms after the key's previous accepted press
// (duplicated press-and-release packets). A release counts only when the key was down.
// The router calls it only for bound keys, so the state is bounded by the bindings.

/// What a raw message means for a trigger source.
public struct MIDITriggerEdge: Sendable, Hashable {
    public let key: MIDIControlKey
    public let edge: MIDINoteEdge
    /// Real-time sources press and release at once.
    public let isMomentary: Bool

    public init(key: MIDIControlKey, edge: MIDINoteEdge, isMomentary: Bool = false) {
        self.key = key
        self.edge = edge
        self.isMomentary = isMomentary
    }
}

/// An accepted edge.
public enum MIDIPressDecision: Sendable, Hashable {
    case press
    case release
}

public struct MIDIPressFilter: Sendable, Hashable {
    /// Presses of one source closer than this are one press (spec Clarifications: 30 ms).
    public static let repeatWindowNanoseconds: UInt64 = 30_000_000
    /// A CC value at or above this presses a CC button; below it releases.
    public static let buttonThreshold: UInt32 = 64
    /// The key every Start and Continue presses.
    public static let startKey = MIDIControlKey(kind: .start, channel: 0, number: 0)
    /// The key every Stop presses.
    public static let stopKey = MIDIControlKey(kind: .stop, channel: 0, number: 0)

    /// Keys whose press was accepted and not yet released (never real-time keys).
    public private(set) var down: Set<MIDIControlKey> = []
    private var lastPress: [MIDIControlKey: UInt64] = [:]
    private var pressedInBatch: Set<MIDIControlKey> = []

    public init() {}

    /// The trigger source and edge a message gives; nil for messages that cannot trigger.
    public static func rawEdge(_ event: MIDIEvent) -> MIDITriggerEdge? {
        switch event.kind {
        case .noteOn, .noteOff:
            guard let edge = event.noteEdge else { return nil }
            return MIDITriggerEdge(key: event.controlKey, edge: edge)
        case .controlChange:
            guard event.number <= MIDILearnEligibility.highestLearnableController else { return nil }
            let edge: MIDINoteEdge = event.value >= buttonThreshold ? .on : .off
            return MIDITriggerEdge(key: event.controlKey, edge: edge)
        case .start, .continue:
            return MIDITriggerEdge(key: startKey, edge: .on, isMomentary: true)
        case .stop:
            return MIDITriggerEdge(key: stopKey, edge: .on, isMomentary: true)
        default:
            return nil
        }
    }

    /// Starts a new delivered batch (the same-batch rule).
    public mutating func beginBatch() {
        pressedInBatch.removeAll(keepingCapacity: true)
    }

    /// Applies the rule to one edge; nil when it is a repeat or a release of a key that is up.
    public mutating func accept(_ edge: MIDITriggerEdge, timestamp: UInt64) -> MIDIPressDecision? {
        let key: MIDIControlKey = edge.key
        switch edge.edge {
        case .on:
            if down.contains(key) || pressedInBatch.contains(key) { return nil }
            if isWithinWindow(key, timestamp) { return nil }
            registerPress(key, timestamp: timestamp, momentary: edge.isMomentary)
            return .press
        case .off:
            return down.remove(key) == nil ? nil : .release
        }
    }

    /// Records an accepted press without deciding (MIDI-008-D7: the learning press, so its copies fire nothing).
    public mutating func registerPress(_ key: MIDIControlKey, timestamp: UInt64, momentary: Bool) {
        if !momentary { down.insert(key) }
        pressedInBatch.insert(key)
        if timestamp != 0 { lastPress[key] = timestamp }
    }

    /// Puts a key up without a decision (panic, input stopped, binding changed); true when it was down.
    @discardableResult
    public mutating func forceUp(_ key: MIDIControlKey) -> Bool {
        down.remove(key) != nil
    }

    /// MIDI-013 (specs/183-midi-013-panic, research MIDI-013-D1): forgets everything: down keys, last-press times and
    /// same-batch presses, so the next press of any key is a fresh press.
    public mutating func reset() {
        down.removeAll()
        lastPress.removeAll()
        pressedInBatch.removeAll()
    }

    /// MIDI-013: true when no key is down and no press is remembered.
    public var isEmpty: Bool { down.isEmpty && lastPress.isEmpty && pressedInBatch.isEmpty }

    private func isWithinWindow(_ key: MIDIControlKey, _ timestamp: UInt64) -> Bool {
        guard timestamp != 0, let last = lastPress[key] else { return false }
        let gap: UInt64 = timestamp >= last ? timestamp - last : last - timestamp
        return gap < Self.repeatWindowNanoseconds
    }
}

extension MIDIEvent {
    /// MIDI-008: the trigger source a learn binds: a note's key, a CC button's key (controllers 0–119), `.start` for
    /// Start and Continue, `.stop` for Stop; nil for anything else.
    public var triggerKey: MIDIControlKey? { MIDIPressFilter.rawEdge(self)?.key }
}
