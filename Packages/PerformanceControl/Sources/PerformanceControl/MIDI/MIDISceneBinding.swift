// MIDISceneBinding.swift — a program change or note bound to a show scene, the "program number selects cue" mode,
// and the scene mapping list (MIDI-007-R1, R6, R7; specs/147-midi-007-scene-selection, data-model.md, contract S1,
// S2, research MIDI-007-D1, D2, D4).
//
// Pure Swift, Linux-testable. A binding is a key (program change: kind `.programChange`, number = program; note:
// kind `.noteOn`), and a scene ID, nothing else: no device, endpoint, name or time.
//
// Stored form, one line per binding, in the same list as MIDI-003's `cc:` and MIDI-006's `note:` lines
// (`settings.midi.mappings`):
// * `pc:<channel 0-15>:<program 0-127>=cue.go:<sceneID>` and `note:<channel>:<note>=cue.go:<sceneID>`, then unknown
//   `;` segments verbatim;
// * the mode, at most one line: `pc:*:*=cue.position` (any channel) or `pc:<channel>:*=cue.position`.
// This list owns every `pc:` line and every `note:` line whose action starts with `cue.go:`; MIDI-006's list skips
// them. A line it owns but cannot read is kept verbatim, so a newer version's mappings survive.

/// Which program changes select a cue by position (research MIDI-007-D4). Off by default.
public enum MIDIProgramCueMode: Sendable, Hashable {
    case off
    case anyChannel
    /// 0–15
    case channel(UInt8)

    public static let action: String = "cue.position"

    /// Whether a program change on `channel` selects a cue by position.
    public func matches(channel: UInt8) -> Bool {
        switch self {
        case .off: false
        case .anyChannel: true
        case let .channel(own): own == channel
        }
    }

    /// nil when off.
    public var storageLine: String? {
        switch self {
        case .off: nil
        case .anyChannel: MIDISceneBinding.programTag + ":*:*=" + Self.action
        case let .channel(channel): MIDISceneBinding.programTag + ":" + String(channel) + ":*=" + Self.action
        }
    }

    /// Reads `pc:*:*=cue.position` or `pc:<0-15>:*=cue.position` (no extra segments); nil otherwise.
    public init?(storageLine line: String) {
        let parts: [Substring] = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == Substring(Self.action) else { return nil }
        let control: [Substring] = parts[0].split(separator: ":", omittingEmptySubsequences: false)
        guard control.count == 3, control[0] == Substring(MIDISceneBinding.programTag), control[2] == "*" else { return nil }
        if control[1] == "*" {
            self = .anyChannel
        } else if let channel = UInt8(control[1]), channel <= 15 {
            self = .channel(channel)
        } else {
            return nil
        }
    }
}

/// One program change or note bound to one scene (data-model "Scene mapping").
public struct MIDISceneBinding: Sendable, Hashable {
    public static let programTag: String = "pc"
    public static let actionPrefix: String = "cue.go:"
    public static let maximumSceneIDLength: Int = 64

    public let key: MIDIControlKey
    public let sceneID: String
    /// Unknown `;` segments, verbatim, in order.
    public let extraSegments: [String]

    /// `key.kind` must be `.programChange` or `.noteOn` (anything else is stored as a program change).
    public init(key: MIDIControlKey, sceneID: String, extraSegments: [String] = []) {
        let kind: MIDIEventKind = key.kind == .noteOn ? .noteOn : .programChange
        self.key = MIDIControlKey(kind: kind, channel: min(key.channel, 15), number: min(key.number, 127))
        self.sceneID = sceneID
        self.extraSegments = extraSegments
    }

    /// The keys a scene can be bound to: a program change, or a note (MIDI-006's note key).
    public static func isBindableKey(_ key: MIDIControlKey) -> Bool {
        key.kind == .programChange || key.kind == .noteOn
    }

    /// 1–64 characters of letters, digits, `-`, `_`, `.` (SCN-001 IDs are UUID text).
    public static func isValidSceneID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= maximumSceneIDLength else { return false }
        return id.utf8.allSatisfy { (byte: UInt8) -> Bool in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x2D || byte == 0x5F || byte == 0x2E
        }
    }

    /// Whether this list owns a stored line: every `pc:` line, and every `note:` line whose action starts with
    /// `cue.go:` (readable or not).
    public static func isSceneLine(_ line: String) -> Bool {
        if line.hasPrefix(programTag + ":") { return true }
        guard line.hasPrefix(MIDINoteBinding.tag + ":"), let equals = line.firstIndex(of: "=") else { return false }
        return line[line.index(after: equals)...].hasPrefix(actionPrefix)
    }

    /// `pc:0:5=cue.go:<id>`, `note:0:60=cue.go:<id>`
    public var storageLine: String {
        let tag: String = key.kind == .noteOn ? MIDINoteBinding.tag : Self.programTag
        let control: String = tag + ":" + String(key.channel) + ":" + String(key.number)
        let segments: [String] = [control + "=" + Self.actionPrefix + sceneID] + extraSegments
        return segments.joined(separator: ";")
    }

    /// Reads a stored line; nil for anything that is not a readable scene line.
    public init?(storageLine line: String) {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let control: [Substring] = line[line.startIndex..<equals].split(separator: ":", omittingEmptySubsequences: false)
        let pieces: [Substring] = line[line.index(after: equals)...].split(separator: ";", omittingEmptySubsequences: false)
        guard control.count == 3, let action = pieces.first, action.hasPrefix(Self.actionPrefix) else { return nil }
        let kind: MIDIEventKind
        switch control[0] {
        case Substring(Self.programTag): kind = .programChange
        case Substring(MIDINoteBinding.tag): kind = .noteOn
        default: return nil
        }
        guard let channel = UInt8(control[1]), channel <= 15, let number = UInt8(control[2]), number <= 127 else { return nil }
        let sceneID: String = String(action.dropFirst(Self.actionPrefix.count))
        guard Self.isValidSceneID(sceneID) else { return nil }
        let extras: [String] = pieces.dropFirst().compactMap { (raw: Substring) -> String? in raw.isEmpty ? nil : String(raw) }
        self.init(key: MIDIControlKey(kind: kind, channel: channel, number: number), sceneID: sceneID, extraSegments: extras)
    }
}

/// What a scene bind did to the list.
public enum MIDISceneBindOutcome: Sendable, Hashable {
    case added
    /// The scene had another key, which no longer selects anything.
    case replaced(previous: MIDIControlKey)
    /// The key selected another scene, which now has no key.
    case moved(fromScene: String)
    case movedAndReplaced(fromScene: String, previous: MIDIControlKey)
    /// At capacity; nothing changed.
    case full
}

/// The scene mapping list: at most 128 bindings, no two share a key, no two share a scene; the position mode;
/// unreadable scene lines kept after them.
public struct MIDISceneBindingList: Sendable, Hashable {
    public static let capacity: Int = 128

    public private(set) var bindings: [MIDISceneBinding] = []
    public var programCueMode: MIDIProgramCueMode = .off
    /// Scene lines this version cannot read, verbatim, in order.
    public private(set) var keptLines: [String] = []

    public init() {}

    /// Reads the scene lines of a stored list (others are ignored); repeats of a key or scene already read, later
    /// mode lines and bindings beyond the capacity are dropped.
    public init(storageLines: [String]) {
        var sawMode: Bool = false
        for line in storageLines where MIDISceneBinding.isSceneLine(line) {
            if let mode = MIDIProgramCueMode(storageLine: line) {
                if !sawMode { programCueMode = mode }
                sawMode = true
                continue
            }
            guard let binding = MIDISceneBinding(storageLine: line) else {
                keptLines.append(line)
                continue
            }
            guard bindings.count < Self.capacity else { continue }
            let clashes: Bool = bindings.contains { (existing: MIDISceneBinding) -> Bool in
                existing.key == binding.key || existing.sceneID == binding.sceneID
            }
            if !clashes { bindings.append(binding) }
        }
    }

    /// Bindings, then the mode line, then kept lines.
    public var storageLines: [String] {
        var lines: [String] = bindings.map { (binding: MIDISceneBinding) -> String in binding.storageLine }
        if let mode = programCueMode.storageLine { lines.append(mode) }
        return lines + keptLines
    }

    /// No bindings and the mode off (kept lines alone drive nothing).
    public var isEmpty: Bool { bindings.isEmpty && programCueMode == .off }

    public func binding(forKey key: MIDIControlKey) -> MIDISceneBinding? {
        bindings.first { (binding: MIDISceneBinding) -> Bool in binding.key == key }
    }

    public func binding(forScene sceneID: String) -> MIDISceneBinding? {
        bindings.first { (binding: MIDISceneBinding) -> Bool in binding.sceneID == sceneID }
    }

    /// Binds a program or note key to a scene, replacing the key's and the scene's previous bindings. Callers check
    /// `MIDISceneBinding.isBindableKey` and `isValidSceneID` first.
    @discardableResult
    public mutating func bind(_ key: MIDIControlKey, to sceneID: String) -> MIDISceneBindOutcome {
        let current: String? = binding(forKey: key)?.sceneID
        if current == sceneID { return .added }
        let previousKey: MIDIControlKey? = binding(forScene: sceneID)?.key
        let freed: Int = (current == nil ? 0 : 1) + (previousKey == nil ? 0 : 1)
        guard bindings.count - freed < Self.capacity else { return .full }
        bindings.removeAll { (binding: MIDISceneBinding) -> Bool in binding.key == key || binding.sceneID == sceneID }
        bindings.append(MIDISceneBinding(key: key, sceneID: sceneID))
        switch (current, previousKey) {
        case let (from?, previous?): return .movedAndReplaced(fromScene: from, previous: previous)
        case let (from?, nil): return .moved(fromScene: from)
        case let (nil, previous?): return .replaced(previous: previous)
        case (nil, nil): return .added
        }
    }

    @discardableResult
    public mutating func remove(sceneID: String) -> MIDISceneBinding? {
        guard let index = bindings.firstIndex(where: { (binding: MIDISceneBinding) -> Bool in binding.sceneID == sceneID }) else {
            return nil
        }
        return bindings.remove(at: index)
    }

    @discardableResult
    public mutating func remove(key: MIDIControlKey) -> MIDISceneBinding? {
        guard let index = bindings.firstIndex(where: { (binding: MIDISceneBinding) -> Bool in binding.key == key }) else {
            return nil
        }
        return bindings.remove(at: index)
    }
}
