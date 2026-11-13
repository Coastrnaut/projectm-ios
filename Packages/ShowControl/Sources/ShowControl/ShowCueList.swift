// ShowCueList.swift — the manual cue list, version 1 (SHOW-001-R1 to R6; data-model.md; contract
// S3; research SHOW-001-D3).
//
// A value type: every operation reads only `cues` and `position`, so the same operations from the
// same state always give the same position and scene ID (SHOW-001-R5). No clock, no randomness;
// cue IDs come from the caller (`append(sceneID:label:cueID:)` defaults to a fresh UUID, tests pass
// their own).
import Foundation

/// One cue: a stable cue ID, the SCN-001 scene it shows, and the operator's label.
public struct ShowCue: Sendable, Hashable, Identifiable {
    /// Never changes (moves and renames keep it).
    public let id: UUID
    /// Canonical uppercase UUID text (the SCN-001 scene `id`); several cues may share it.
    public let sceneID: String
    /// Trimmed, 1…80 characters, no line breaks.
    public internal(set) var label: String

    public init(id: UUID, sceneID: String, label: String) {
        self.id = id
        self.sceneID = sceneID
        self.label = label
    }
}

/// Where the show stands: before the first cue, or on one cue (by its ID, so it survives reorder).
public enum ShowPosition: Sendable, Hashable {
    case standby
    case cue(UUID)
}

/// What a step did (contract S3). Only `.moved` applies a scene.
public enum ShowStepOutcome: String, Sendable, Hashable {
    case moved
    /// Next on the last cue: nothing changes (no wrap; Clarifications).
    case atEnd
    /// Previous on the first cue or at Standby: nothing changes.
    case atStart
    /// The show has no cues.
    case empty
    /// Go to a cue ID the show does not have.
    case unknownCue
}

/// The result of next, previous or go to: the outcome, the position and the active scene after it.
public struct ShowStep: Sendable, Hashable {
    public let outcome: ShowStepOutcome
    public let position: ShowPosition
    /// The active cue's scene ID after the step (nil at Standby).
    public let sceneID: String?

    public var moved: Bool { outcome == .moved }
}

public enum ShowEditError: Error, Sendable, Hashable, CustomStringConvertible {
    case tooManyCues(limit: Int)
    case invalidLabel
    case invalidSceneID(String)
    case unknownCue(UUID)
    case duplicateCueID(UUID)
    case invalidMove

    public var description: String {
        switch self {
        case let .tooManyCues(limit): "A show holds at most \(limit) cues."
        case .invalidLabel: "A cue label is 1 to \(ShowCueList.maximumLabelLength) characters on one line."
        case let .invalidSceneID(id): "\"\(id)\" is not a scene ID."
        case let .unknownCue(id): "The show has no cue \(id.uuidString)."
        case let .duplicateCueID(id): "The cue ID \(id.uuidString) is used twice."
        case .invalidMove: "The cues cannot be moved there."
        }
    }
}

public struct ShowCueList: Sendable, Hashable {
    public static let maximumCues = 256
    public static let maximumLabelLength = 80
    public static let defaultName = "Show"

    public let id: UUID
    public private(set) var name: String
    /// In show order.
    public private(set) var cues: [ShowCue]
    public private(set) var position: ShowPosition

    /// An empty show at Standby.
    public init(id: UUID = UUID(), name: String = ShowCueList.defaultName) {
        self.id = id
        self.name = Self.normalizedLabel(name) ?? Self.defaultName
        cues = []
        position = .standby
    }

    /// A show from stored parts, checked like a loaded file (SHOW-001-R11): too many cues, a bad
    /// label or scene ID, or a duplicate cue ID throws. A position naming no cue becomes Standby.
    public init(id: UUID, name: String, cues: [ShowCue], position: ShowPosition) throws(ShowEditError) {
        guard cues.count <= Self.maximumCues else { throw .tooManyCues(limit: Self.maximumCues) }
        var seen = Set<UUID>()
        var checked: [ShowCue] = []
        for cue in cues {
            guard seen.insert(cue.id).inserted else { throw .duplicateCueID(cue.id) }
            guard Self.isSceneID(cue.sceneID) else { throw .invalidSceneID(cue.sceneID) }
            guard let label = Self.normalizedLabel(cue.label), label == cue.label else { throw .invalidLabel }
            checked.append(cue)
        }
        guard let name = Self.normalizedLabel(name) else { throw .invalidLabel }
        self.id = id
        self.name = name
        self.cues = checked
        if case let .cue(active) = position, !seen.contains(active) {
            self.position = .standby
        } else {
            self.position = position
        }
    }

    // MARK: - Reading

    /// The active cue's index (nil at Standby).
    public var activeIndex: Int? {
        guard case let .cue(id) = position else { return nil }
        return cues.firstIndex { (cue: ShowCue) -> Bool in cue.id == id }
    }

    public var activeCue: ShowCue? { activeIndex.map { (i: Int) -> ShowCue in cues[i] } }
    public var activeSceneID: String? { activeCue?.sceneID }

    /// Whether Next would move (SHOW-001-R13: otherwise the button is unavailable).
    public var canGoNext: Bool {
        guard !cues.isEmpty else { return false }
        guard let index = activeIndex else { return true }
        return index < cues.count - 1
    }

    /// Whether Previous would move.
    public var canGoPrevious: Bool { (activeIndex ?? 0) > 0 }

    /// "Cue 2 of 5", or "Standby".
    public var positionText: String {
        guard let index = activeIndex else { return "Standby" }
        return "Cue \(index + 1) of \(cues.count)"
    }

    /// Every scene ID the cues refer to, in first-use order without repeats.
    public var sceneIDs: [String] {
        var seen = Set<String>()
        return cues.compactMap { (cue: ShowCue) -> String? in seen.insert(cue.sceneID).inserted ? cue.sceneID : nil }
    }

    // MARK: - Stepping (contract S3)

    /// Standby → cue 1; cue n → cue n + 1; the last cue → `.atEnd` (no wrap).
    @discardableResult
    public mutating func next() -> ShowStep {
        guard !cues.isEmpty else { return step(.empty) }
        let target: Int
        if let index = activeIndex {
            guard index < cues.count - 1 else { return step(.atEnd) }
            target = index + 1
        } else {
            target = 0
        }
        position = .cue(cues[target].id)
        return step(.moved)
    }

    /// Cue n → cue n − 1; cue 1 and Standby → `.atStart`.
    @discardableResult
    public mutating func previous() -> ShowStep {
        guard !cues.isEmpty else { return step(.empty) }
        guard let index = activeIndex, index > 0 else { return step(.atStart) }
        position = .cue(cues[index - 1].id)
        return step(.moved)
    }

    /// Any existing cue, the active one included (its scene is shown again).
    @discardableResult
    public mutating func go(to cueID: UUID) -> ShowStep {
        guard cues.contains(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { return step(.unknownCue) }
        position = .cue(cueID)
        return step(.moved)
    }

    /// Back to Standby (used by tests and a later "reset show"; never applies a scene).
    public mutating func standBy() { position = .standby }

    private func step(_ outcome: ShowStepOutcome) -> ShowStep {
        ShowStep(outcome: outcome, position: position, sceneID: activeSceneID)
    }

    // MARK: - Editing (SHOW-001-R6: never changes the output; the position follows its cue ID)

    /// Appends a cue at the end. The label is trimmed.
    @discardableResult
    public mutating func append(sceneID: String, label: String, cueID: UUID = UUID()) throws(ShowEditError) -> ShowCue {
        guard cues.count < Self.maximumCues else { throw .tooManyCues(limit: Self.maximumCues) }
        guard Self.isSceneID(sceneID) else { throw .invalidSceneID(sceneID) }
        guard let label = Self.normalizedLabel(label) else { throw .invalidLabel }
        guard !cues.contains(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .duplicateCueID(cueID) }
        let cue = ShowCue(id: cueID, sceneID: sceneID, label: label)
        cues.append(cue)
        return cue
    }

    /// Inserts a cue right after the cue `after` (SCN-003 Duplicate Scene). The label is trimmed; the
    /// position keeps its cue.
    @discardableResult
    public mutating func insert(sceneID: String, label: String, after: UUID, cueID: UUID = UUID()) throws(ShowEditError) -> ShowCue {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == after }) else { throw .unknownCue(after) }
        guard cues.count < Self.maximumCues else { throw .tooManyCues(limit: Self.maximumCues) }
        guard Self.isSceneID(sceneID) else { throw .invalidSceneID(sceneID) }
        guard let label = Self.normalizedLabel(label) else { throw .invalidLabel }
        guard !cues.contains(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .duplicateCueID(cueID) }
        let cue = ShowCue(id: cueID, sceneID: sceneID, label: label)
        cues.insert(cue, at: index + 1)
        return cue
    }

    /// Removes a cue. Removing the active cue makes the cue before it active without showing it
    /// (Standby if it was first), so Next plays the cue that followed the removed one.
    @discardableResult
    public mutating func remove(_ cueID: UUID) throws(ShowEditError) -> ShowCue {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .unknownCue(cueID) }
        if position == .cue(cueID) {
            position = index > 0 ? .cue(cues[index - 1].id) : .standby
        }
        return cues.remove(at: index)
    }

    /// Moves the cues at `offsets` to before `destination` (the list's own indexing, as a list's
    /// drag-to-reorder reports it). The position keeps its cue.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) throws(ShowEditError) {
        guard !offsets.isEmpty else { return }
        guard let last = offsets.last, last < cues.count, destination >= 0, destination <= cues.count else { throw .invalidMove }
        let moving = offsets.map { (i: Int) -> ShowCue in cues[i] }
        var rest: [ShowCue] = []
        for (i, cue) in cues.enumerated() where !offsets.contains(i) { rest.append(cue) }
        let before = offsets.filter { (i: Int) -> Bool in i < destination }.count
        rest.insert(contentsOf: moving, at: destination - before)
        cues = rest
    }

    public mutating func rename(_ cueID: UUID, to label: String) throws(ShowEditError) {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .unknownCue(cueID) }
        guard let label = Self.normalizedLabel(label) else { throw .invalidLabel }
        cues[index].label = label
    }

    // MARK: - Rules

    /// "<label> copy" for a duplicated scene's cue, the label shortened so it fits 80 characters
    /// (SCN-003).
    public static func copyLabel(_ label: String) -> String {
        let suffix = " copy"
        let base = normalizedLabel(label) ?? "Cue"
        let room = maximumLabelLength - suffix.count
        let shortened = base.count > room ? (normalizedLabel(String(base.prefix(room))) ?? "Cue") : base
        return shortened + suffix
    }

    /// Trimmed text of 1…80 characters with no line breaks, or nil.
    public static func normalizedLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLabelLength else { return nil }
        guard !trimmed.contains(where: { (c: Character) -> Bool in c.isNewline }) else { return nil }
        return trimmed
    }

    /// Canonical uppercase UUID text, as SCN-001 writes scene IDs.
    public static func isSceneID(_ text: String) -> Bool {
        UUID(uuidString: text)?.uuidString == text
    }
}
