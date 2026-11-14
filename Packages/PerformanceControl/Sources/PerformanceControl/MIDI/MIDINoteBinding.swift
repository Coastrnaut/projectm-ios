// MIDINoteBinding.swift — a learned note bound to a trigger action, and the note mapping list (MIDI-006-R3, R7;
// specs/143-midi-006-note-triggers, data-model.md, contract N2, research MIDI-006-D4).
//
// Pure Swift, Linux-testable. A binding is a note key (channel and note, kind `.noteOn`), an action and a mode,
// nothing else: no device, endpoint, name or time.
//
// Stored form, one line per binding, in the same list as MIDI-003's `cc:` lines (`settings.midi.mappings`):
// `note:<channel 0-15>:<note 0-127>=<action>`, then `;mode=hold` when held, then unknown `;` segments verbatim.
// `mode=trigger` (or no mode) reads as trigger and is never written. A `note:` line that cannot be read (unknown
// action, a mode the action does not allow, bad numbers) is kept verbatim, so a newer version's mappings survive.

/// What a note can do (research MIDI-006-D5). Stored by its raw value.
public enum MIDINoteAction: String, Sendable, Hashable, CaseIterable {
    case cueNext = "cue.next"
    case cuePrevious = "cue.previous"
    case blackout = "blackout"

    /// Only the blackout can be held (black while the key is down).
    public var allowsHold: Bool { self == .blackout }
}

/// Trigger fires on the key's down edge; hold engages on the down edge and releases on the up edge.
public enum MIDINoteMode: String, Sendable, Hashable, CaseIterable {
    case trigger
    case hold
}

/// One learnable row: an action with a mode.
public struct MIDINoteTarget: Sendable, Hashable, Identifiable {
    public let action: MIDINoteAction
    public let mode: MIDINoteMode

    /// nil when the action cannot be held.
    public init?(action: MIDINoteAction, mode: MIDINoteMode) {
        if mode == .hold && !action.allowsHold { return nil }
        self.action = action
        self.mode = mode
    }

    private init(unchecked action: MIDINoteAction, _ mode: MIDINoteMode) {
        self.action = action
        self.mode = mode
    }

    public static let nextCue = MIDINoteTarget(unchecked: .cueNext, .trigger)
    public static let previousCue = MIDINoteTarget(unchecked: .cuePrevious, .trigger)
    public static let blackoutToggle = MIDINoteTarget(unchecked: .blackout, .trigger)
    public static let blackoutHold = MIDINoteTarget(unchecked: .blackout, .hold)

    /// The rows MIDI Mappings shows, in order.
    public static let all: [MIDINoteTarget] = [nextCue, previousCue, blackoutToggle, blackoutHold]

    /// `cue.next`, `cue.previous`, `blackout`, `blackout.hold`
    public var id: String { mode == .hold ? action.rawValue + ".hold" : action.rawValue }

    /// "Next cue", "Previous cue", "Black out", "Black out while held"
    public var title: String {
        switch (action, mode) {
        case (.cueNext, _): "Next cue"
        case (.cuePrevious, _): "Previous cue"
        case (.blackout, .trigger): "Black out"
        case (.blackout, .hold): "Black out while held"
        }
    }
}

/// One note bound to one target (data-model "Note binding").
public struct MIDINoteBinding: Sendable, Hashable {
    public static let tag: String = "note"
    public static let modeKey: String = "mode"

    public let key: MIDIControlKey
    public let target: MIDINoteTarget
    /// Unknown `;` segments, verbatim, in order.
    public let extraSegments: [String]

    public init(channel: UInt8, note: UInt8, target: MIDINoteTarget, extraSegments: [String] = []) {
        self.key = MIDIControlKey(kind: .noteOn, channel: min(channel, 15), number: min(note, 127))
        self.target = target
        self.extraSegments = extraSegments
    }

    /// Whether a stored line is a note line (read or kept by this list, skipped by MIDI-003's).
    public static func isNoteLine(_ line: String) -> Bool { line.hasPrefix(tag + ":") }

    /// `note:0:60=cue.next`, `note:0:61=blackout;mode=hold`
    public var storageLine: String {
        let control: String = Self.tag + ":" + String(key.channel) + ":" + String(key.number)
        var segments: [String] = [control + "=" + target.action.rawValue]
        if target.mode == .hold { segments.append(Self.modeKey + "=" + MIDINoteMode.hold.rawValue) }
        segments.append(contentsOf: extraSegments)
        return segments.joined(separator: ";")
    }

    /// Reads a stored line; nil for anything that is not a readable note line.
    public init?(storageLine line: String) {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let control: Substring = line[line.startIndex..<equals]
        let rest: Substring = line[line.index(after: equals)...]
        let pieces: [Substring] = rest.split(separator: ";", omittingEmptySubsequences: false)
        let parts: [Substring] = control.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Substring(Self.tag),
              let channel = UInt8(parts[1]), channel <= 15,
              let note = UInt8(parts[2]), note <= 127,
              let actionText = pieces.first, let action = MIDINoteAction(rawValue: String(actionText)) else { return nil }
        var mode: MIDINoteMode = .trigger
        var sawMode: Bool = false
        var extras: [String] = []
        for raw in pieces.dropFirst() {
            let segment: String = String(raw)
            if segment.isEmpty { continue }
            let keyValue: [Substring] = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if keyValue.count == 2, keyValue[0] == Substring(Self.modeKey) {
                if sawMode { continue }
                sawMode = true
                guard let parsed = MIDINoteMode(rawValue: String(keyValue[1])) else { return nil }
                mode = parsed
            } else {
                extras.append(segment)
            }
        }
        guard let target = MIDINoteTarget(action: action, mode: mode) else { return nil }
        self.init(channel: channel, note: note, target: target, extraSegments: extras)
    }
}

/// What a note bind did to the list.
public enum MIDINoteBindOutcome: Sendable, Hashable {
    case added
    /// The target had another note, which no longer triggers anything.
    case replaced(previous: MIDIControlKey)
    /// The note triggered another target, which now has no note.
    case moved(from: MIDINoteTarget)
    case movedAndReplaced(from: MIDINoteTarget, previous: MIDIControlKey)
    /// At capacity; nothing changed.
    case full
}

/// The note mapping list: at most 64 bindings, no two share a note, no two share a target; unreadable note lines
/// are kept after them.
public struct MIDINoteBindingList: Sendable, Hashable {
    public static let capacity: Int = 64

    public private(set) var bindings: [MIDINoteBinding] = []
    /// `note:` lines this version cannot read, verbatim, in order.
    public private(set) var keptLines: [String] = []

    public init() {}

    /// Reads the `note:` lines of a stored list (others are ignored); repeats of a note or target already read and
    /// bindings beyond the capacity are dropped. MIDI-007: `note:…=cue.go:` lines belong to `MIDISceneBindingList`
    /// and are skipped here (research MIDI-007-D2), so no line is kept twice.
    public init(storageLines: [String]) {
        for line in storageLines where MIDINoteBinding.isNoteLine(line) && !MIDISceneBinding.isSceneLine(line) {
            guard let binding = MIDINoteBinding(storageLine: line) else {
                keptLines.append(line)
                continue
            }
            guard bindings.count < Self.capacity else { continue }
            let clashes: Bool = bindings.contains { (existing: MIDINoteBinding) -> Bool in
                existing.key == binding.key || existing.target == binding.target
            }
            if !clashes { bindings.append(binding) }
        }
    }

    public var storageLines: [String] {
        bindings.map { (binding: MIDINoteBinding) -> String in binding.storageLine } + keptLines
    }

    public var isEmpty: Bool { bindings.isEmpty }

    public func binding(forKey key: MIDIControlKey) -> MIDINoteBinding? {
        bindings.first { (binding: MIDINoteBinding) -> Bool in binding.key == key }
    }

    public func binding(for target: MIDINoteTarget) -> MIDINoteBinding? {
        bindings.first { (binding: MIDINoteBinding) -> Bool in binding.target == target }
    }

    /// Binds a note key to `target`, replacing the key's and the target's previous bindings.
    @discardableResult
    public mutating func bind(_ key: MIDIControlKey, to target: MIDINoteTarget) -> MIDINoteBindOutcome {
        let current: MIDINoteTarget? = binding(forKey: key)?.target
        if current == target { return .added }
        let movedFrom: MIDINoteTarget? = current
        let previousKey: MIDIControlKey? = binding(for: target)?.key
        let freed: Int = (movedFrom == nil ? 0 : 1) + (previousKey == nil ? 0 : 1)
        guard bindings.count - freed < Self.capacity else { return .full }
        bindings.removeAll { (binding: MIDINoteBinding) -> Bool in binding.key == key || binding.target == target }
        bindings.append(MIDINoteBinding(channel: key.channel, note: key.number, target: target))
        switch (movedFrom, previousKey) {
        case let (from?, previous?): return .movedAndReplaced(from: from, previous: previous)
        case let (from?, nil): return .moved(from: from)
        case let (nil, previous?): return .replaced(previous: previous)
        case (nil, nil): return .added
        }
    }

    /// Removes the target's binding; returns it.
    @discardableResult
    public mutating func remove(target: MIDINoteTarget) -> MIDINoteBinding? {
        guard let index = bindings.firstIndex(where: { (binding: MIDINoteBinding) -> Bool in binding.target == target }) else {
            return nil
        }
        return bindings.remove(at: index)
    }
}
