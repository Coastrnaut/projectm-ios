// MIDINoteRouter.swift — note edges to trigger commands (MIDI-006-R2, R4, R5, R6; contract N3, research
// MIDI-006-D2, D3).
//
// Pure Swift, Linux-testable, a value with no clock. It reads note messages only through `MIDIEvent.noteEdge`
// (velocity-0 note on = release, MIDI-006-R1) and keeps the set of bound keys that are down:
// * a press of a key that is up puts it down; trigger → `fire` (at most once per binding per batch), hold →
//   `engage`. A press of a key already down does nothing (no double toggle).
// * a release of a key that is down puts it up; hold → `release`. A release of a key that is up does nothing.
// * stuck notes: CC 120 (All Sound Off) and 123 (All Notes Off) release that channel's keys, System Reset all
//   keys; `releaseAll` and `release(keys:)` are called by the app when the input stops, a source goes away or a
//   held binding is removed.
// Unbound keys are not tracked, so the state is bounded by the bindings (≤ 64).
//
// MIDI-008 (specs/157-midi-008-transport, contract T2): the down set and the press rule live in `MIDIPressFilter`, shared
// by notes, CC buttons (≥ 64 press, < 64 release) and real-time Start/Continue/Stop (momentary). A press is also dropped
// when the source was pressed in the same batch (for hold targets too) or less than 30 ms earlier by message timestamp,
// so a duplicated packet never fires twice. A CC that is not bound as a button never reaches the filter.

/// What a command asks the app to do.
public enum MIDINotePhase: Sendable, Hashable {
    /// A trigger binding's press.
    case fire
    /// A hold binding's press.
    case engage
    /// A hold binding's release (key up, panic, input stopped, binding removed).
    case release
}

/// One action for the app to perform.
public struct MIDINoteCommand: Sendable, Hashable {
    public let target: MIDINoteTarget
    public let phase: MIDINotePhase
    public let key: MIDIControlKey

    public init(target: MIDINoteTarget, phase: MIDINotePhase, key: MIDIControlKey) {
        self.target = target
        self.phase = phase
        self.key = key
    }
}

public struct MIDINoteRouter: Sendable, Hashable {
    /// MIDI 1.0 channel mode messages that silence notes.
    public static let allSoundOff: UInt8 = 120
    public static let allNotesOff: UInt8 = 123

    /// MIDI-008: the shared press rule (and the down set).
    public private(set) var filter = MIDIPressFilter()

    public init() {}

    /// The bound keys that are down.
    public var down: Set<MIDIControlKey> { filter.down }

    /// MIDI-008-D7: records a learning press so its duplicate copies fire nothing.
    public mutating func registerPress(_ key: MIDIControlKey, timestamp: UInt64) {
        filter.registerPress(key, timestamp: timestamp, momentary: MIDINoteBinding.isRealTimeKey(key))
    }

    public var hasKeysDown: Bool { !down.isEmpty }

    /// Routes one batch in arrival order.
    public mutating func route(_ batch: [MIDIEvent], bindings: MIDINoteBindingList) -> [MIDINoteCommand] {
        var commands: [MIDINoteCommand] = []
        filter.beginBatch()
        for event in batch {
            if event.kind == .controlChange, event.number == Self.allSoundOff || event.number == Self.allNotesOff {
                let channel: UInt8 = event.channel
                let keys: [MIDIControlKey] = down.filter { (key: MIDIControlKey) -> Bool in key.channel == channel }
                commands.append(contentsOf: release(keys: keys, bindings: bindings))
                continue
            }
            if event.kind == .reset {
                commands.append(contentsOf: releaseAll(bindings: bindings))
                continue
            }
            guard let edge = MIDIPressFilter.rawEdge(event), let binding = bindings.binding(forKey: edge.key),
                  let decision = filter.accept(edge, timestamp: event.timestamp) else { continue }
            if let command = Self.command(for: decision, binding: binding) { commands.append(command) }
        }
        return commands
    }

    private static func command(for decision: MIDIPressDecision, binding: MIDINoteBinding) -> MIDINoteCommand? {
        switch (decision, binding.target.mode) {
        case (.press, .trigger): return MIDINoteCommand(target: binding.target, phase: .fire, key: binding.key)
        case (.press, .hold): return MIDINoteCommand(target: binding.target, phase: .engage, key: binding.key)
        case (.release, .hold): return MIDINoteCommand(target: binding.target, phase: .release, key: binding.key)
        case (.release, .trigger): return nil
        }
    }

    /// Puts every key up; `release` for each one bound to a hold target, ordered by channel then note.
    public mutating func releaseAll(bindings: MIDINoteBindingList) -> [MIDINoteCommand] {
        release(keys: Array(down), bindings: bindings)
    }

    /// Puts the given keys up; `release` for each one that was down and is bound to a hold target.
    public mutating func release<S: Sequence>(keys: S, bindings: MIDINoteBindingList) -> [MIDINoteCommand]
    where S.Element == MIDIControlKey {
        let sorted: [MIDIControlKey] = keys.sorted { (a: MIDIControlKey, b: MIDIControlKey) -> Bool in
            a.channel == b.channel ? a.number < b.number : a.channel < b.channel
        }
        var commands: [MIDINoteCommand] = []
        for key in sorted {
            guard filter.forceUp(key) else { continue }
            guard let binding = bindings.binding(forKey: key), binding.target.mode == .hold else { continue }
            commands.append(MIDINoteCommand(target: binding.target, phase: .release, key: key))
        }
        return commands
    }
}
