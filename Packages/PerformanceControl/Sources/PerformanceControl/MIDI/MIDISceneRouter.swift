// MIDISceneRouter.swift — program changes and note presses to scene commands (MIDI-007-R2, R6; contract S3,
// research MIDI-007-D3).
//
// Pure Swift, Linux-testable, stateless. For each event in arrival order:
// * a program change with a scene binding (channel and program match) → `.scene`;
// * otherwise a program change on a channel the position mode covers → `.cue(program)` (program n → cue n + 1);
// * a note's down edge (`noteEdge == .on`, velocity > 0) with a scene binding → `.scene`; a release does nothing.
// The newest command of a batch wins, so at most one scene is applied per drain (≤ 30 Hz). Repeats of the current
// scene are dropped by the app's performer (debounce), so no key state is kept here.

/// What the app is asked to select.
public enum MIDISceneCommand: Sendable, Hashable {
    /// Select the scene's first cue.
    case scene(id: String, key: MIDIControlKey)
    /// Select the cue at this 0-based position.
    case cue(index: Int, key: MIDIControlKey)
}

public enum MIDISceneRouter {
    /// The newest command of `batch`, or nil.
    public static func route(_ batch: [MIDIEvent], list: MIDISceneBindingList) -> MIDISceneCommand? {
        guard !list.isEmpty else { return nil }
        var newest: MIDISceneCommand?
        for event in batch {
            if let command = command(for: event, list: list) { newest = command }
        }
        return newest
    }

    /// The command one event gives, or nil.
    public static func command(for event: MIDIEvent, list: MIDISceneBindingList) -> MIDISceneCommand? {
        switch event.kind {
        case .programChange:
            let key: MIDIControlKey = event.controlKey
            if let binding = list.binding(forKey: key) { return .scene(id: binding.sceneID, key: key) }
            guard list.programCueMode.matches(channel: event.channel) else { return nil }
            return .cue(index: Int(event.number), key: key)
        case .noteOn, .noteOff:
            guard event.noteEdge == .on, let binding = list.binding(forKey: event.controlKey) else { return nil }
            return .scene(id: binding.sceneID, key: binding.key)
        default:
            return nil
        }
    }
}
