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
    /// SCN-007: how the cue's scene comes in (nil = the default, an instant change).
    public internal(set) var transition: ShowCueTransition?
    /// SHOW-002: how long the cue stays before the show advances by itself (nil = Off, manual only).
    public internal(set) var dwell: ShowCueDwell?
    /// SHOW-004: the transition used for the edge into this cue instead of the scene default (`transition`); nil = use
    /// the scene default. Stored with the cue in the show, never in the scene and never in `transition`.
    public internal(set) var transitionOverride: ShowCueTransition?
    /// SHOW-005: Next and Previous (manual, timed, quantized) pass over a skipped cue; Go to Cue still reaches it.
    public internal(set) var skipped: Bool
    /// SHOW-012: the operator's private note (`ShowCueNote` rules; nil = none). Operator UI only, never live output.
    public internal(set) var operatorNote: String?

    public init(id: UUID, sceneID: String, label: String, transition: ShowCueTransition? = nil, dwell: ShowCueDwell? = nil,
                transitionOverride: ShowCueTransition? = nil, skipped: Bool = false, operatorNote: String? = nil) {
        self.id = id
        self.sceneID = sceneID
        self.label = label
        self.transition = transition
        self.dwell = dwell
        self.transitionOverride = transitionOverride
        self.skipped = skipped
        self.operatorNote = operatorNote
    }

    /// SHOW-004-R3: what a step into this cue drives: the override when set, else the scene default (nil = at once).
    public var effectiveTransition: ShowCueTransition? { transitionOverride ?? transition }
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
    /// SHOW-005: Next or Previous when every cue is skipped: nothing changes.
    case allSkipped
    /// Go to a cue ID the show does not have.
    case unknownCue
    /// SHOW-003: the step waits for the next beat or bar (returned by the app's quantized gate only; `ShowCueList` never
    /// returns it). Nothing changed yet.
    case queued
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
    /// SHOW-012: a note longer than `ShowCueNote.maximumCharacters`, or not in its stored form.
    case invalidNote

    public var description: String {
        switch self {
        case let .tooManyCues(limit): "A show holds at most \(limit) cues."
        case .invalidLabel: "A cue label is 1 to \(ShowCueList.maximumLabelLength) characters on one line."
        case let .invalidSceneID(id): "\"\(id)\" is not a scene ID."
        case let .unknownCue(id): "The show has no cue \(id.uuidString)."
        case let .duplicateCueID(id): "The cue ID \(id.uuidString) is used twice."
        case .invalidMove: "The cues cannot be moved there."
        case .invalidNote: "A note is at most \(ShowCueNote.maximumCharacters) characters."
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
    /// SCN-004: the scene folder tree and each scene's folder (logical; scene files never move).
    public internal(set) var folders: SceneFolderTree = SceneFolderTree()
    /// SCN-005: each scene's tags (by scene ID; scene files never change).
    public internal(set) var tags: SceneTagMap = SceneTagMap()
    /// SHOW-008: keyframe tracks along the show timeline (independent of the cues; `ShowKeyframeTracks` keeps its rules).
    public var tracks: ShowKeyframeTracks = ShowKeyframeTracks()

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
            if let note = cue.operatorNote, ShowCueNote.normalized(note) != note { throw .invalidNote }   // SHOW-012
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

    /// Whether Next would move (SHOW-001-R13: otherwise the button is unavailable; SHOW-005: skipped cues do not count).
    public var canGoNext: Bool { nextIndex() != nil }

    /// SHOW-006: the cue Next would reach (skipped cues passed over); nil at the end, for an empty show or when every
    /// cue after the active one is skipped.
    public var nextCue: ShowCue? { nextIndex().map { (i: Int) -> ShowCue in cues[i] } }

    /// Whether Previous would move (SHOW-005: skipped cues do not count).
    public var canGoPrevious: Bool { previousIndex() != nil }

    /// SHOW-005: every cue is skipped (false for an empty show).
    public var allSkipped: Bool {
        !cues.isEmpty && cues.allSatisfy { (cue: ShowCue) -> Bool in cue.skipped }
    }

    /// SHOW-005: the first cue after the active one (or from the top at Standby) that is not skipped.
    private func nextIndex() -> Int? {
        let start: Int = (activeIndex ?? -1) + 1
        guard start < cues.count else { return nil }
        return cues[start...].firstIndex { (cue: ShowCue) -> Bool in !cue.skipped }
    }

    /// SHOW-005: the last cue before the active one that is not skipped (nil at Standby).
    private func previousIndex() -> Int? {
        guard let index = activeIndex, index > 0 else { return nil }
        return cues[..<index].lastIndex { (cue: ShowCue) -> Bool in !cue.skipped }
    }

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

    /// Standby → the first cue; cue n → the next cue; the last cue → `.atEnd` (no wrap). SHOW-005: skipped cues are passed
    /// over; every cue skipped → `.allSkipped`.
    @discardableResult
    public mutating func next() -> ShowStep {
        guard !cues.isEmpty else { return step(.empty) }
        guard !allSkipped else { return step(.allSkipped) }
        guard let target = nextIndex() else { return step(.atEnd) }
        position = .cue(cues[target].id)
        return step(.moved)
    }

    /// Cue n → the cue before; the first cue and Standby → `.atStart`. SHOW-005: skipped cues are passed over; every cue
    /// skipped → `.allSkipped`.
    @discardableResult
    public mutating func previous() -> ShowStep {
        guard !cues.isEmpty else { return step(.empty) }
        guard !allSkipped else { return step(.allSkipped) }
        guard let target = previousIndex() else { return step(.atStart) }
        position = .cue(cues[target].id)
        return step(.moved)
    }

    /// Any existing cue, the active one included (its scene is shown again).
    @discardableResult
    public mutating func go(to cueID: UUID) -> ShowStep {
        guard cues.contains(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { return step(.unknownCue) }
        position = .cue(cueID)
        return step(.moved)
    }

    /// SHOW-003: the current position with outcome `.queued` (the app's quantized gate; nothing changes).
    public func queuedStep() -> ShowStep { step(.queued) }

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
    /// position keeps its cue. SCN-007: `transition` is the new cue's transition (a duplicate passes its source's);
    /// SHOW-002: `dwell` likewise; SHOW-004: `transitionOverride` likewise; SHOW-005: `skipped` likewise; SHOW-012:
    /// `operatorNote` likewise (already in stored form, else `.invalidNote`).
    @discardableResult
    public mutating func insert(sceneID: String, label: String, after: UUID, cueID: UUID = UUID(),
                                transition: ShowCueTransition? = nil, dwell: ShowCueDwell? = nil,
                                transitionOverride: ShowCueTransition? = nil, skipped: Bool = false,
                                operatorNote: String? = nil) throws(ShowEditError) -> ShowCue {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == after }) else { throw .unknownCue(after) }
        guard cues.count < Self.maximumCues else { throw .tooManyCues(limit: Self.maximumCues) }
        guard Self.isSceneID(sceneID) else { throw .invalidSceneID(sceneID) }
        guard let label = Self.normalizedLabel(label) else { throw .invalidLabel }
        guard !cues.contains(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .duplicateCueID(cueID) }
        if let operatorNote, ShowCueNote.normalized(operatorNote) != operatorNote { throw .invalidNote }
        let cue = ShowCue(id: cueID, sceneID: sceneID, label: label, transition: transition, dwell: dwell,
                          transitionOverride: transitionOverride, skipped: skipped, operatorNote: operatorNote)
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

    /// SHOW-005: marks a cue skipped or not. Never changes the position (skipping the active cue keeps it) or the order.
    public mutating func setSkipped(_ cueID: UUID, _ skipped: Bool) throws(ShowEditError) {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .unknownCue(cueID) }
        cues[index].skipped = skipped
    }

    /// SHOW-012-R1: sets a cue's note from edited text (cleaned by `ShowCueNote`); empty text or nil removes it; text longer
    /// than 500 characters throws `.invalidNote`. Never changes the position, the order or any other field. Returns the
    /// stored note.
    @discardableResult
    public mutating func setOperatorNote(_ cueID: UUID, to text: String?) throws(ShowEditError) -> String? {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .unknownCue(cueID) }
        let clean: String = ShowCueNote.cleaned(text ?? "")
        guard !clean.isEmpty else {
            cues[index].operatorNote = nil
            return nil
        }
        guard let note = ShowCueNote.normalized(clean) else { throw .invalidNote }
        cues[index].operatorNote = note
        return note
    }

    /// SCN-007: sets (or, with nil, removes) a cue's transition. Never changes the position or the order.
    public mutating func setTransition(_ cueID: UUID, to transition: ShowCueTransition?) throws(ShowEditError) {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .unknownCue(cueID) }
        cues[index].transition = transition
    }

    /// SHOW-004: sets (or, with nil, removes) the override for the edge into a cue. Never changes the position, the order
    /// or any cue's scene default (`transition`).
    public mutating func setTransitionOverride(_ cueID: UUID, to transition: ShowCueTransition?) throws(ShowEditError) {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .unknownCue(cueID) }
        cues[index].transitionOverride = transition
    }

    /// SHOW-002: sets (or, with nil, turns off) a cue's dwell. Never changes the position or the order.
    public mutating func setDwell(_ cueID: UUID, to dwell: ShowCueDwell?) throws(ShowEditError) {
        guard let index = cues.firstIndex(where: { (cue: ShowCue) -> Bool in cue.id == cueID }) else { throw .unknownCue(cueID) }
        cues[index].dwell = dwell
    }

    // MARK: - Scene folders (SCN-004: never changes cues, their order, the position or a scene ID)

    /// The scene's folder (nil = top level).
    public func folderID(ofScene sceneID: String) -> UUID? { folders.folderID(ofScene: sceneID) }

    @discardableResult
    public mutating func createFolder(named name: String, in parent: UUID?, id: UUID = UUID()) throws(SceneFolderError) -> SceneFolder {
        try folders.createFolder(named: name, in: parent, id: id)
    }

    public mutating func renameFolder(_ id: UUID, to name: String) throws(SceneFolderError) {
        try folders.renameFolder(id, to: name)
    }

    public mutating func moveFolder(_ id: UUID, to parent: UUID?) throws(SceneFolderError) {
        try folders.moveFolder(id, to: parent)
    }

    /// Puts a scene the cues refer to in `folder` (nil = top level); false when it was already there.
    @discardableResult
    public mutating func moveScene(_ sceneID: String, to folder: UUID?) throws(SceneFolderError) -> Bool {
        guard cues.contains(where: { (cue: ShowCue) -> Bool in cue.sceneID == sceneID }) else { throw .sceneNotInShow(sceneID) }
        return try folders.moveScene(sceneID, to: folder)
    }

    @discardableResult
    public mutating func deleteFolder(_ id: UUID) throws(SceneFolderError) -> SceneFolderDeletion {
        try folders.deleteFolder(id)
    }

    // MARK: - Scene tags (SCN-005: never changes cues, their order, the position or a scene ID)

    private func showsScene(_ sceneID: String) -> Bool {
        cues.contains(where: { (cue: ShowCue) -> Bool in cue.sceneID == sceneID })
    }

    /// The scene's tags, limited to scenes the cues show (sorted).
    public func tags(ofScene sceneID: String) -> [String] { showsScene(sceneID) ? tags.tags(ofScene: sceneID) : [] }

    /// The tags of the scenes the cues show, one spelling each, sorted.
    public var tagVocabulary: [String] {
        var live = tags
        live.prune(keepingScenes: Set(sceneIDs))
        return live.vocabulary
    }

    /// Adds a tag to a scene the cues show; returns the spelling stored.
    @discardableResult
    public mutating func addTag(_ tag: String, toScene sceneID: String) throws(SceneTagError) -> String {
        guard showsScene(sceneID) else { throw .sceneNotInShow(sceneID) }
        tags.prune(keepingScenes: Set(sceneIDs))   // tags of scenes that left the show never count
        return try tags.add(tag, to: sceneID)
    }

    @discardableResult
    public mutating func removeTag(_ tag: String, fromScene sceneID: String) throws(SceneTagError) -> String {
        guard showsScene(sceneID) else { throw .sceneNotInShow(sceneID) }
        return try tags.remove(tag, from: sceneID)
    }

    /// Duplicate Scene: the copy gets its source's tags (SCN-005-R9).
    public mutating func copyTags(fromScene source: String, toScene target: String) throws(SceneTagError) {
        guard showsScene(target) else { throw .sceneNotInShow(target) }
        tags.copyTags(from: source, to: target)
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
