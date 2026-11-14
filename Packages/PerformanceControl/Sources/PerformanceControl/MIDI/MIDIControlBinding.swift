// MIDIControlBinding.swift — one learned MIDI control bound to one parameter, and the mapping list's
// policy (MIDI-003-R4, R5, R9, R16; specs/128-midi-003-midi-learn, data-model.md, research MIDI-003-D1, D2,
// D7).
//
// Pure Swift, Linux-testable. A binding is a control key (MIDI-002's kind, channel and number) and a
// parameter ID, nothing else: no device, endpoint, name or time, so the stored list cannot identify the
// user's equipment (ADR-0038 Decision 8). The list keeps one binding per control and one per parameter
// (rebinding replaces) and at most 64 bindings.
//
// Stored form, one line per binding: `cc:<channel 0-15>:<number 0-119>=<parameter ID>`. MIDI-004 onward may
// append `;`-separated options after the parameter ID; this row writes none and ignores them on read.
import ParameterGraph

/// One control bound to one parameter (data-model "Binding").
public struct MIDIControlBinding: Sendable, Hashable {
    public let key: MIDIControlKey
    public let target: ParameterID

    public init(key: MIDIControlKey, target: ParameterID) {
        self.key = key
        self.target = target
    }

    static let controlChangeTag: String = "cc"

    /// `cc:0:7=effect.bloom.intensity`
    public var storageLine: String {
        let channel: String = String(key.channel)
        let number: String = String(key.number)
        let control: String = Self.controlChangeTag + ":" + channel + ":" + number
        return control + "=" + target.rawValue
    }

    /// Reads a stored line; nil for anything but a control change on channel 0–15, controller 0–119 and a
    /// non-empty parameter ID. Options after `;` are ignored (MIDI-003-R16).
    public init?(storageLine line: String) {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let control: Substring = line[line.startIndex..<equals]
        let rest: Substring = line[line.index(after: equals)...]
        let targetText: Substring = rest.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts: [Substring] = control.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Substring(Self.controlChangeTag),
              let channel = UInt8(parts[1]), channel <= 15,
              let number = UInt8(parts[2]), number <= MIDILearnEligibility.highestLearnableController,
              !targetText.isEmpty else { return nil }
        self.key = MIDIControlKey(kind: .controlChange, channel: channel, number: number)
        self.target = ParameterID(String(targetText))
    }
}

/// What a bind did to the list (data-model "Binding list").
public enum MIDIBindOutcome: Sendable, Hashable {
    /// Neither the control nor the parameter was bound.
    case added
    /// The parameter had another control, which no longer drives anything.
    case replaced(previous: MIDIControlKey)
    /// The control drove another parameter, which now has no control.
    case moved(from: ParameterID)
    /// Both of the above.
    case movedAndReplaced(from: ParameterID, previous: MIDIControlKey)
    /// The list is at capacity; nothing changed.
    case full
}

/// The ordered mapping list: at most 64 bindings, no two share a control, no two share a parameter.
public struct MIDIBindingList: Sendable, Hashable {
    public static let capacity: Int = 64

    public private(set) var bindings: [MIDIControlBinding] = []

    public init() {}

    /// Reads stored lines in order, skipping unreadable lines, targets not in `allowedTargets`, lines that
    /// repeat a control or a parameter already read, and lines beyond the capacity.
    public init(storageLines: [String], allowedTargets: Set<ParameterID>) {
        for line in storageLines {
            guard bindings.count < Self.capacity else { break }
            guard let binding = MIDIControlBinding(storageLine: line), allowedTargets.contains(binding.target) else { continue }
            let clashes: Bool = bindings.contains { (existing: MIDIControlBinding) -> Bool in
                existing.key == binding.key || existing.target == binding.target
            }
            if !clashes { bindings.append(binding) }
        }
    }

    public var storageLines: [String] {
        bindings.map { (binding: MIDIControlBinding) -> String in binding.storageLine }
    }

    public var isEmpty: Bool { bindings.isEmpty }
    public var count: Int { bindings.count }

    public func target(for key: MIDIControlKey) -> ParameterID? {
        bindings.first { (binding: MIDIControlBinding) -> Bool in binding.key == key }?.target
    }

    public func binding(for target: ParameterID) -> MIDIControlBinding? {
        bindings.first { (binding: MIDIControlBinding) -> Bool in binding.target == target }
    }

    /// Binds `key` to `target`, replacing the control's and the parameter's previous bindings (research
    /// MIDI-003-D2). Binding a pair that already exists is `.added` with no change.
    @discardableResult
    public mutating func bind(_ key: MIDIControlKey, to target: ParameterID) -> MIDIBindOutcome {
        let movedFrom: ParameterID? = self.target(for: key).flatMap { (old: ParameterID) -> ParameterID? in
            old == target ? nil : old
        }
        let previousKey: MIDIControlKey? = binding(for: target).flatMap { (old: MIDIControlBinding) -> MIDIControlKey? in
            old.key == key ? nil : old.key
        }
        if self.target(for: key) == target { return .added }
        let freed: Int = (movedFrom == nil ? 0 : 1) + (previousKey == nil ? 0 : 1)
        guard bindings.count - freed < Self.capacity else { return .full }
        bindings.removeAll { (binding: MIDIControlBinding) -> Bool in binding.key == key || binding.target == target }
        bindings.append(MIDIControlBinding(key: key, target: target))
        switch (movedFrom, previousKey) {
        case let (from?, previous?): return .movedAndReplaced(from: from, previous: previous)
        case let (from?, nil): return .moved(from: from)
        case let (nil, previous?): return .replaced(previous: previous)
        case (nil, nil): return .added
        }
    }

    /// Removes the parameter's binding; returns it.
    @discardableResult
    public mutating func remove(target: ParameterID) -> MIDIControlBinding? {
        guard let index = bindings.firstIndex(where: { (binding: MIDIControlBinding) -> Bool in binding.target == target }) else {
            return nil
        }
        return bindings.remove(at: index)
    }
}
