// ShowCoordinator.swift — the show in the app (SHOW-001-R2 to R12; contract S3 to S5; research
// SHOW-001-D3, D5).
//
// * Owns the `ShowCueList` and its `ShowStore` (`Application Support/Show`). Loads at launch (a refused
//   file is set aside and the editor says so once); saves after every step and every edit.
// * A step that moves (Next, Previous, Go to) reads the active cue's scene, validates it (SCN-001
//   `liveState` with the app's registry and the stored photo/video) and hands it to `applyScene`, which
//   AppCoordinator sets to its settings path (no audio source change, no camera). The cue is not
//   applied again at launch (Clarifications). A scene that is missing leaves the output unchanged: the
//   position still moves, a notice shows for about 4 s and VoiceOver announces it.
// * SCN-012: a scene that cannot be decoded, has SCN-001 errors or user-relevant warnings (missing
//   media, invalid mappings, unknown layers) goes to `requestRepair` (the repair report) before
//   anything is applied; the position still moves and the output stays until the user opens it.
//   The stored file is never written. Without `requestRepair` (tests of SHOW-001 alone) the old notice.
// * Edits (add, remove, move, rename) never apply anything (SHOW-001-R6).
// * SCN-003: Duplicate Scene stores a copy of a cue's scene under a new scene ID and inserts a cue for
//   it right after that cue; Rename Scene renames the scene itself (every cue showing it), never a
//   label or an ID. `sceneNames` caches each stored scene's name for the editor.
// * SCN-004: scene folders are logical (the show index holds the tree and each scene's folder); folder
//   edits save the show only, never write a scene file, apply anything or move the position, and
//   announce on the library lane (`announceLibrary`). A duplicate goes into its source's folder.
// * SCN-005: scene tags live in the show index too; tag edits save the show only, never apply anything,
//   and announce on the library lane. A duplicate gets its source's tags.
// * SCN-006: every scene file this coordinator writes or drops (Add, Duplicate, Rename, removing a
//   scene's last cue) is reported through `sceneFilesChanged`, so scene previews never outlive the
//   file they show.
// * SCN-007: each cue may carry a transition (type, duration, MOD-004 easing) saved in `show.json`. A cue
//   apply resolves it (`CueTransitionResolver`: Reduce Motion, Reduce flashing) and hands the spec to
//   `transitionDriver` just before `applyScene`; `setTransition` saves at once and applies nothing; a
//   duplicate's cue gets its source cue's transition.
// * SCN-011: `addCopies` stores bundled template scenes as new scenes (new IDs) with their cues, all or nothing.
// * SCN-014: `installImportedScene` installs a scene pack's scene with FILE-004 (copy on a taken ID, one cue).
// Main actor; file I/O is small (≤ 1 MiB per file, typically a few KB) and only on user action.
import Foundation
import Observation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import UIKit

@MainActor
@Observable
final class ShowCoordinator {
    static let noticeDuration: Duration = .seconds(4)
    static let setAsideMessage = "The saved show could not be read and was set aside."
    static let saveFailedMessage = "The show could not be saved."
    static let sceneUnreadableMessage = "The scene could not be read."

    private(set) var list: ShowCueList
    /// Scene IDs whose files cannot be read (cues flagged "Scene missing").
    private(set) var unreadableScenes: Set<String>
    /// The last step's notice (missing scene, parts left out), shown for about 4 s.
    private(set) var notice: String?
    /// For the editor: the show was set aside at launch, or the last save failed.
    private(set) var editorMessage: String?
    /// The scene last applied by a step (DEBUG probe `showAppliedScene`).
    private(set) var appliedSceneID: String?
    /// Stored scenes' names by scene ID (SCN-003: the editor shows a name that differs from the label).
    private(set) var sceneNames: [String: String] = [:]

    @ObservationIgnored let store: ShowStore?
    @ObservationIgnored private let registry: ParameterRegistry?
    /// Applies a validated scene to the live output; returns notices (parts left out). Set by AppCoordinator.
    @ObservationIgnored var applyScene: ((SceneDocument, [SceneIssue]) -> [String])?
    /// SCN-012: shows the repair report for a cue's scene (set by AppCoordinator).
    @ObservationIgnored var requestRepair: ((SceneRepairRequest) -> Void)?
    /// Which photo and video are stored now (SCN-001 asset availability).
    @ObservationIgnored var availability: () -> StoredMediaAvailability = { StoredMediaAvailability(photos: [], videos: []) }
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// A new scene ID for Duplicate Scene (tests pass fixed IDs).
    @ObservationIgnored var makeSceneID: () -> String = { () -> String in UUID().uuidString }
    @ObservationIgnored var announce: (String) -> Void = { (message: String) in
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    /// SCN-004-R13: folder results and refusals (AppCoordinator routes them to the library lane).
    @ObservationIgnored var announceLibrary: (String) -> Void = { (_: String) in }
    /// SCN-006: scene IDs whose files were written or removed (AppCoordinator routes them to the previews).
    @ObservationIgnored var sceneFilesChanged: (Set<String>) -> Void = { (_: Set<String>) in }
    /// SCN-007: receives each applied cue's resolved transition (set by AppCoordinator; a spy in tests).
    @ObservationIgnored var transitionDriver: (any CueTransitionDriving)?
    /// SCN-007: Reduce Motion and Reduce flashing at the moment a cue applies (set by AppCoordinator).
    @ObservationIgnored var transitionSafety: () -> (reduceMotion: Bool, reduceFlashing: Bool) = { () -> (reduceMotion: Bool, reduceFlashing: Bool) in
        (reduceMotion: false, reduceFlashing: false)
    }
    /// SCN-006: the scene previews Scene Folders shows (set by AppCoordinator; nil in tests of the show alone).
    @ObservationIgnored weak var previews: ScenePreviewModel?
    /// SCN-014: scene pack export and import for Scene Folders (set by AppCoordinator; nil in tests of the show alone).
    @ObservationIgnored var scenePacks: ScenePackCoordinator?
    /// SCN-015: the scene lock (set by AppCoordinator; nil in tests of the show alone). Steps never read it.
    @ObservationIgnored var sceneLock: SceneLock?

    /// SCN-015-R6: the editor hides its edit gestures while true.
    var isEditLocked: Bool { sceneLock?.isLocked ?? false }

    /// SCN-015-R3, R4: true (with the editor message) when the scene is locked; the lock announces the refusal.
    func refusedByLock() -> Bool {
        guard sceneLock?.refusesEdit() == true else { return false }
        editorMessage = SceneLock.refusalMessage
        return true
    }

    init(store: ShowStore?, registry: ParameterRegistry?) {
        self.store = store
        self.registry = registry
        if let store {
            let loaded = store.load()
            list = loaded.list
            unreadableScenes = loaded.unreadableScenes
            editorMessage = loaded.setAside != nil ? Self.setAsideMessage : nil
        } else {
            list = ShowCueList()
            unreadableScenes = []
        }
        refreshSceneNames()
    }

    static func makeDefault() -> ShowCoordinator {
        let store = (try? ShowStore.defaultDirectory()).map(ShowStore.init(directory:))
        return ShowCoordinator(store: store, registry: try? SceneArchiveService.appRegistry())
    }

    // MARK: - Reading

    var hasCues: Bool { !list.cues.isEmpty }

    /// "Cue 2 of 5 · Intro" or "Standby · 5 cues".
    var statusText: String {
        if let cue = list.activeCue { return "\(list.positionText) · \(cue.label)" }
        return "Standby · \(list.cues.count) \(list.cues.count == 1 ? "cue" : "cues")"
    }

    /// VoiceOver value: "Cue 2 of 5, Intro" or "Standby, 5 cues".
    var accessibilityValue: String { statusText.replacingOccurrences(of: " · ", with: ", ") }

    func isSceneMissing(_ cue: ShowCue) -> Bool { unreadableScenes.contains(cue.sceneID) }

    /// The cue's scene name, when it is stored and readable.
    func sceneName(of cue: ShowCue) -> String? { sceneNames[cue.sceneID] }

    private func refreshSceneNames() {
        guard let store else { return }
        var names: [String: String] = [:]
        for id in list.sceneIDs {
            if let document = try? store.scene(id).document { names[id] = document.name }
        }
        sceneNames = names
    }

    // MARK: - Stepping (contract S3, S4)

    @discardableResult
    func next() -> ShowStep { perform { (list: inout ShowCueList) -> ShowStep in list.next() } }

    @discardableResult
    func previous() -> ShowStep { perform { (list: inout ShowCueList) -> ShowStep in list.previous() } }

    @discardableResult
    func go(to cueID: UUID) -> ShowStep { perform { (list: inout ShowCueList) -> ShowStep in list.go(to: cueID) } }

    private func perform(_ operation: (inout ShowCueList) -> ShowStep) -> ShowStep {
        let step = operation(&list)
        guard step.moved, let cue = list.activeCue else { return step }
        save()
        show(cue)
        return step
    }

    /// Reads, validates and applies the cue's scene (SHOW-001-R8, R9); SCN-012: the repair report first
    /// when the scene needs review.
    private func show(_ cue: ShowCue) {
        let number = (list.activeIndex ?? 0) + 1
        guard let store, let registry else { return post(Self.failure(number)) }
        let title = "Cue \(number) · \(cue.label)"
        let decoded: SceneDecodeResult
        do {
            decoded = try store.scene(cue.sceneID)
        } catch {
            unreadableScenes.insert(cue.sceneID)
            if case let .unreadable(refusal) = error, let requestRepair {
                clearNotice()
                return requestRepair(SceneRepairRequest(title: title, report: SceneRepairReport(refusal: refusal), document: nil))
            }
            return post(Self.failure(number))
        }
        let report = SceneRepairReport(document: decoded.document, decodeWarnings: decoded.warnings, registry: registry,
                                       assets: availability())
        guard report.needsReview, let requestRepair else {
            return apply(decoded.document, decodeWarnings: decoded.warnings, sceneID: cue.sceneID, number: number,
                         transition: cue.transition)
        }
        if !report.canOpenAsIs { unreadableScenes.insert(cue.sceneID) }
        clearNotice()
        let sceneID = cue.sceneID
        let warnings = decoded.warnings
        let transition = cue.transition
        requestRepair(SceneRepairRequest(title: title, report: report, document: decoded.document,
                                         open: { [weak self] (document: SceneDocument) in
                                             self?.apply(document, decodeWarnings: warnings, sceneID: sceneID, number: number,
                                                         transition: transition)
                                         }))
    }

    static func failure(_ number: Int) -> String { "Cue \(number): the scene could not be shown." }

    /// Validates and applies a document for the cue (as stored, or repaired by SCN-012); errors leave
    /// the output unchanged with the notice.
    private func apply(_ document: SceneDocument, decodeWarnings: [SceneIssue], sceneID: String, number: Int,
                       transition: ShowCueTransition?) {
        guard let registry else { return post(Self.failure(number)) }
        let loaded: SceneLoadResult
        do {
            loaded = try document.liveState(registry: registry, assets: availability())
        } catch {
            unreadableScenes.insert(sceneID)
            return post(Self.failure(number))
        }
        unreadableScenes.remove(sceneID)
        let safety = transitionSafety()   // SCN-007-R5: the transition first, then the scene
        transitionDriver?.driveTransition(CueTransitionResolver.resolved(transition, reduceMotion: safety.reduceMotion,
                                                                         reduceFlashing: safety.reduceFlashing),
                                          toScene: sceneID)
        let notes = applyScene?(document, decodeWarnings + loaded.warnings) ?? []
        appliedSceneID = sceneID
        if let first = notes.first {
            post("Cue \(number): \(first)")
        } else {
            clearNotice()
        }
    }

    private func clearNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    private func post(_ message: String) {
        notice = message
        announce(message)
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Editing (SHOW-001-R6, R7: never applies anything)

    /// Stores `document` (a snapshot with its own new scene ID) and appends a cue for it.
    @discardableResult
    func addScene(_ document: SceneDocument, label: String) -> Bool {
        if refusedByLock() { return false }
        guard let store else { editorMessage = Self.saveFailedMessage; return false }
        do throws(ShowStoreError) {
            try store.saveScene(document)
        } catch {
            editorMessage = Self.saveFailedMessage
            return false
        }
        do throws(ShowEditError) {
            try list.append(sceneID: document.id, label: label)
        } catch {
            editorMessage = error.description
            return false
        }
        unreadableScenes.remove(document.id)
        sceneNames[document.id] = document.name
        save()
        sceneFilesChanged([document.id])   // SCN-006
        return true
    }

    // MARK: - Template copies (SCN-011-R4 to R6: never applies anything, the position stays)

    /// Stores a copy of each document under a new scene ID and appends a cue for each (label, transition),
    /// tagging the copies; all or nothing (capacity first, written copies removed on a failure). Returns the
    /// new cues, or nil with an editor message. `ShowCoordinator+Templates` calls it for a bundled template.
    func addCopies(_ scenes: [(document: SceneDocument, label: String, transition: ShowCueTransition?)], tags: [String]) -> [ShowCue]? {
        if refusedByLock() { return nil }
        guard let store else { editorMessage = Self.saveFailedMessage; return nil }
        guard !scenes.isEmpty, list.cues.count + scenes.count <= ShowCueList.maximumCues else {
            editorMessage = ShowEditError.tooManyCues(limit: ShowCueList.maximumCues).description
            return nil
        }
        var copies: [SceneDocument] = []
        func undo(_ message: String) -> [ShowCue]? {
            for copy in copies { try? FileManager.default.removeItem(at: store.sceneFile(copy.id)) }
            editorMessage = message
            return nil
        }
        for scene in scenes {
            do throws(ShowSceneEditError) {
                copies.append(try store.storeTemplateCopy(scene.document, newID: makeSceneID(), name: scene.document.name))
            } catch {
                return undo(Self.message(for: error))
            }
        }
        var updated = list
        var cues: [ShowCue] = []
        do throws(ShowEditError) {
            for (copy, scene) in zip(copies, scenes) {
                let cue = try updated.append(sceneID: copy.id, label: scene.label)
                if let transition = scene.transition { try updated.setTransition(cue.id, to: transition) }   // SCN-007
                cues.append(updated.cues.first { (c: ShowCue) -> Bool in c.id == cue.id } ?? cue)
            }
        } catch {
            return undo(error.description)
        }
        for copy in copies {
            for tag in tags { _ = try? updated.addTag(tag, toScene: copy.id) }   // SCN-005; a refused tag is not fatal
            sceneNames[copy.id] = copy.name
            unreadableScenes.remove(copy.id)
        }
        list = updated
        save()
        sceneFilesChanged(Set(copies.map(\.id)))   // SCN-006
        return cues
    }

    // MARK: - Scene pack import (SCN-014-R6, R10: never applies anything, the position stays)

    /// Installs an imported scene through FILE-004 (Keep both: a taken ID gives a copy; one cue appended);
    /// on `.installed` the coordinator takes the stored show. `plan` is the preview's plan for `[document]`.
    func installImportedScene(_ document: SceneDocument, plan: ShowSceneImportPlan) -> ShowSceneImportOutcome {
        if refusedByLock() { return .refused(SceneLock.refusalMessage) }
        guard let store else { return .refused(Self.saveFailedMessage) }
        let outcome = store.installImportedScenes([document], plan: plan)
        if case let .installed(installed, scenes) = outcome {
            list = installed
            for scene in scenes {
                sceneNames[scene.id] = scene.name
                unreadableScenes.remove(scene.id)
            }
            sceneFilesChanged(Set(scenes.map(\.id)))   // SCN-006
        }
        return outcome
    }

    // MARK: - Duplicate and rename scenes (SCN-003-R6: never applies anything, the position stays)

    /// Stores a copy of the cue's scene under a new scene ID ("<name> copy") and inserts a cue for it
    /// ("<label> copy") right after the cue. Returns the new cue, or nil with an editor message.
    @discardableResult
    func duplicateScene(of cueID: UUID) -> ShowCue? {
        if refusedByLock() { return nil }
        guard let cue = list.cues.first(where: { (c: ShowCue) -> Bool in c.id == cueID }) else { return nil }
        guard let store else { editorMessage = Self.saveFailedMessage; return nil }
        // The limit first, so a refused duplicate writes no scene file.
        guard list.cues.count < ShowCueList.maximumCues else {
            editorMessage = ShowEditError.tooManyCues(limit: ShowCueList.maximumCues).description
            return nil
        }
        let original: SceneDocument
        do {
            original = try store.scene(cue.sceneID).document
        } catch {
            unreadableScenes.insert(cue.sceneID)
            editorMessage = Self.sceneUnreadableMessage
            return nil
        }
        let copy: SceneDocument
        do throws(ShowSceneEditError) {
            copy = try store.duplicateScene(cue.sceneID, newID: makeSceneID(), name: SceneDocument.copyName(original.name))
        } catch {
            editorMessage = Self.message(for: error)
            return nil
        }
        let inserted: ShowCue
        do throws(ShowEditError) {
            inserted = try list.insert(sceneID: copy.id, label: ShowCueList.copyLabel(cue.label), after: cue.id,
                                       transition: cue.transition)   // SCN-007-R8
        } catch {
            editorMessage = error.description   // the copy's file is removed by the next save (unreferenced)
            return nil
        }
        sceneNames[copy.id] = copy.name
        if let folder = list.folderID(ofScene: cue.sceneID) {   // SCN-004-R12: next to its source
            _ = try? list.moveScene(copy.id, to: folder)
        }
        try? list.copyTags(fromScene: cue.sceneID, toScene: copy.id)   // SCN-005-R9
        save()
        sceneFilesChanged([copy.id])   // SCN-006
        return inserted
    }

    /// Renames the cue's scene (every cue showing it); the scene ID, the cues and their labels are
    /// unchanged. False with an editor message when the name is invalid or the scene cannot be read.
    @discardableResult
    func renameScene(of cueID: UUID, to name: String) -> Bool {
        if refusedByLock() { return false }
        guard let cue = list.cues.first(where: { (c: ShowCue) -> Bool in c.id == cueID }) else { return false }
        guard let store else { editorMessage = Self.saveFailedMessage; return false }
        do throws(ShowSceneEditError) {
            let renamed = try store.renameScene(cue.sceneID, to: name)
            sceneNames[renamed.id] = renamed.name
            sceneFilesChanged([renamed.id])   // SCN-006: a new file, so its old preview goes
            return true
        } catch {
            if case .unreadable = error { unreadableScenes.insert(cue.sceneID) }
            editorMessage = Self.message(for: error)
            return false
        }
    }

    static func message(for error: ShowSceneEditError) -> String {
        switch error {
        case .unreadable: sceneUnreadableMessage
        case let .invalid(edit): edit.description
        case .sceneIDTaken, .writeFailed: saveFailedMessage
        }
    }

    func remove(_ cueID: UUID) {
        if refusedByLock() { return }
        let before = Set(list.sceneIDs)
        guard (try? list.remove(cueID)) != nil else { return }
        save()
        let gone: Set<String> = before.subtracting(list.sceneIDs)
        if !gone.isEmpty { sceneFilesChanged(gone) }   // SCN-006: the scene's file was removed
    }

    /// SCN-006: the scene's stored file (whether or not it exists).
    func sceneFileURL(_ sceneID: String) -> URL? {
        guard ShowCueList.isSceneID(sceneID) else { return nil }
        return store?.sceneFile(sceneID)
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        if refusedByLock() { return }
        guard (try? list.move(fromOffsets: offsets, toOffset: destination)) != nil else { return }
        save()
    }

    /// False when the label is not 1…80 characters on one line.
    @discardableResult
    func rename(_ cueID: UUID, to label: String) -> Bool {
        if refusedByLock() { return false }
        guard (try? list.rename(cueID, to: label)) != nil else { return false }
        save()
        return true
    }

    /// SCN-007: sets or (nil) removes a cue's transition and saves; never applies anything.
    @discardableResult
    func setTransition(_ cueID: UUID, to transition: ShowCueTransition?) -> Bool {
        if refusedByLock() { return false }
        guard (try? list.setTransition(cueID, to: transition)) != nil else { return false }
        save()
        return true
    }

    func dismissEditorMessage() { editorMessage = nil }

    // MARK: - Scene folders (SCN-004)

    static let topLevelName = "Top Level"

    /// The scene's folder path ("Set A / Encore"); nil at the top level.
    func folderPath(ofScene sceneID: String) -> String? { list.folders.pathText(of: list.folderID(ofScene: sceneID)) }

    /// A folder's path, or "Top Level" for nil.
    func destinationName(_ folder: UUID?) -> String { list.folders.pathText(of: folder) ?? Self.topLevelName }

    /// The first cue (in show order) that shows the scene.
    func firstCue(ofScene sceneID: String) -> ShowCue? {
        list.cues.first { (cue: ShowCue) -> Bool in cue.sceneID == sceneID }
    }

    /// The number of cues that show the scene.
    func cueCount(ofScene sceneID: String) -> Int {
        list.cues.filter { (cue: ShowCue) -> Bool in cue.sceneID == sceneID }.count
    }

    /// The scenes (distinct scene IDs in first-use order) whose folder is `folder`, sorted by name.
    func scenes(in folder: UUID?) -> [String] {
        let ids: [String] = list.folders.sceneIDs(in: folder, among: list.sceneIDs)
        return ids.sorted { (a: String, b: String) -> Bool in
            let na: String = SceneFolderTree.fold(sceneNames[a] ?? a)
            let nb: String = SceneFolderTree.fold(sceneNames[b] ?? b)
            return na == nb ? a < b : na < nb
        }
    }

    /// Go to Cue for a scene: its first cue, exactly as SHOW-001's Go to Cue.
    @discardableResult
    func goToScene(_ sceneID: String) -> ShowStep? {
        guard let cue = firstCue(ofScene: sceneID) else { return nil }
        return go(to: cue.id)
    }

    @discardableResult
    func createFolder(named name: String, in parent: UUID?) -> SceneFolder? {
        if refusedByLock() { return nil }
        do throws(SceneFolderError) {
            let folder = try list.createFolder(named: name, in: parent)
            save()
            announceLibrary("Created folder \(folder.name).")
            return folder
        } catch {
            refuse(error)
            return nil
        }
    }

    @discardableResult
    func renameFolder(_ id: UUID, to name: String) -> Bool {
        if refusedByLock() { return false }
        do throws(SceneFolderError) {
            try list.renameFolder(id, to: name)
            save()
            announceLibrary("Renamed folder to \(list.folders.folder(id)?.name ?? name).")
            return true
        } catch {
            refuse(error)
            return false
        }
    }

    @discardableResult
    func moveFolder(_ id: UUID, to parent: UUID?) -> Bool {
        if refusedByLock() { return false }
        guard let folder = list.folders.folder(id) else { return false }
        guard folder.parentID != parent else { return true }
        do throws(SceneFolderError) {
            try list.moveFolder(id, to: parent)
            save()
            announceLibrary("Moved folder \(folder.name) to \(destinationName(parent)).")
            return true
        } catch {
            refuse(error)
            return false
        }
    }

    /// Moves a scene to `folder` (nil = top level). Nothing is written when it is already there.
    @discardableResult
    func moveScene(_ sceneID: String, to folder: UUID?) -> Bool {
        if refusedByLock() { return false }
        do throws(SceneFolderError) {
            guard try list.moveScene(sceneID, to: folder) else { return true }
            save()
            let name: String = sceneNames[sceneID] ?? firstCue(ofScene: sceneID)?.label ?? "the scene"
            announceLibrary("Moved \(name) to \(destinationName(folder)).")
            return true
        } catch {
            refuse(error)
            return false
        }
    }

    /// Deletes a folder; its scenes and subfolders move to its parent (no scene is removed).
    @discardableResult
    func deleteFolder(_ id: UUID) -> SceneFolderDeletion? {
        if refusedByLock() { return nil }
        do throws(SceneFolderError) {
            let deletion = try list.deleteFolder(id)
            save()
            announceLibrary("Deleted folder \(deletion.folder.name); its contents moved to \(destinationName(deletion.folder.parentID)).")
            return deletion
        } catch {
            refuse(error)
            return nil
        }
    }

    // MARK: - Scene tags (SCN-005)

    /// The scene's tags (sorted; empty when none).
    func tags(ofScene sceneID: String) -> [String] { list.tags(ofScene: sceneID) }

    /// Every tag in the show, one spelling each, sorted.
    var tagVocabulary: [String] { list.tagVocabulary }

    /// How many of the show's scenes carry the tag (chip values).
    func sceneCount(withTag tag: String) -> Int {
        list.sceneIDs.filter { (id: String) -> Bool in list.tags.scene(id, has: tag) }.count
    }

    /// The scene's display name for messages.
    func displayName(ofScene sceneID: String) -> String { sceneNames[sceneID] ?? firstCue(ofScene: sceneID)?.label ?? "the scene" }

    /// Adds a tag; false (with a message and an announcement) when refused.
    @discardableResult
    func addTag(_ tag: String, toScene sceneID: String) -> Bool {
        if refusedByLock() { return false }
        do throws(SceneTagError) {
            let stored: String = try list.addTag(tag, toScene: sceneID)
            save()
            announceLibrary("Tagged \(displayName(ofScene: sceneID)) \(stored).")
            return true
        } catch {
            editorMessage = error.description
            announceLibrary(error.description)
            return false
        }
    }

    @discardableResult
    func removeTag(_ tag: String, fromScene sceneID: String) -> Bool {
        if refusedByLock() { return false }
        do throws(SceneTagError) {
            let removed: String = try list.removeTag(tag, fromScene: sceneID)
            save()
            announceLibrary("Removed tag \(removed) from \(displayName(ofScene: sceneID)).")
            return true
        } catch {
            editorMessage = error.description
            announceLibrary(error.description)
            return false
        }
    }

    private func refuse(_ error: SceneFolderError) {
        editorMessage = error.description
        announceLibrary(error.description)
    }

    private func save() {
        guard let store else { return }
        do throws(ShowStoreError) {
            try store.save(list)
            if editorMessage == Self.saveFailedMessage { editorMessage = nil }
        } catch {
            editorMessage = Self.saveFailedMessage   // the change stays in effect for the session
        }
    }

    #if DEBUG
    /// UI tests: replaces the stored show (`UITestShowFixture`).
    func replaceForUITests(_ list: ShowCueList) {
        let touched: Set<String> = Set(self.list.sceneIDs).union(list.sceneIDs)
        defer { sceneFilesChanged(touched) }   // SCN-006
        self.list = list
        unreadableScenes = Set(list.sceneIDs.filter { (id: String) -> Bool in !(store?.sceneIsReadable(id) ?? false) })
        refreshSceneNames()
        save()
    }

    /// UI tests: records the seeded cue's scene as applied (the seed sets the settings directly).
    func markAppliedForUITests(_ sceneID: String) { appliedSceneID = sceneID }
    #endif
}
