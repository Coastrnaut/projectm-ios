// ShowCoordinator.swift — the show in the app (SHOW-001-R2 to R12; contract S3 to S5; research
// SHOW-001-D3, D5).
//
// * Owns the `ShowCueList` and its `ShowStore` (`Application Support/Show`). Loads at launch (a refused
//   file is set aside and the editor says so once); saves after every step and every edit.
// * A step that moves (Next, Previous, Go to) reads the active cue's scene, validates it (SCN-001
//   `liveState` with the app's registry and the stored photo/video) and hands it to `applyScene`, which
//   AppCoordinator sets to its settings path (no audio source change, no camera). The cue is not
//   applied again at launch (Clarifications). A scene that is missing or has SCN-001 errors leaves the
//   output unchanged: the position still moves, a notice shows for about 4 s and VoiceOver announces it.
// * Edits (add, remove, move, rename) never apply anything (SHOW-001-R6).
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

    private(set) var list: ShowCueList
    /// Scene IDs whose files cannot be read (cues flagged "Scene missing").
    private(set) var unreadableScenes: Set<String>
    /// The last step's notice (missing scene, parts left out), shown for about 4 s.
    private(set) var notice: String?
    /// For the editor: the show was set aside at launch, or the last save failed.
    private(set) var editorMessage: String?
    /// The scene last applied by a step (DEBUG probe `showAppliedScene`).
    private(set) var appliedSceneID: String?

    @ObservationIgnored let store: ShowStore?
    @ObservationIgnored private let registry: ParameterRegistry?
    /// Applies a validated scene to the live output; returns notices (parts left out). Set by AppCoordinator.
    @ObservationIgnored var applyScene: ((SceneDocument, [SceneIssue]) -> [String])?
    /// Which photo and video are stored now (SCN-001 asset availability).
    @ObservationIgnored var availability: () -> StoredMediaAvailability = { StoredMediaAvailability(photos: [], videos: []) }
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored var announce: (String) -> Void = { (message: String) in
        UIAccessibility.post(notification: .announcement, argument: message)
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

    /// Reads, validates and applies the cue's scene (SHOW-001-R8, R9).
    private func show(_ cue: ShowCue) {
        let number = (list.activeIndex ?? 0) + 1
        let failure = "Cue \(number): the scene could not be shown."
        guard let store, let registry else { return post(failure) }
        let decoded: SceneDecodeResult
        do {
            decoded = try store.scene(cue.sceneID)
        } catch {
            unreadableScenes.insert(cue.sceneID)
            return post(failure)
        }
        let loaded: SceneLoadResult
        do {
            loaded = try decoded.document.liveState(registry: registry, assets: availability())
        } catch {
            unreadableScenes.insert(cue.sceneID)
            return post(failure)
        }
        unreadableScenes.remove(cue.sceneID)
        let notes = applyScene?(decoded.document, decoded.warnings + loaded.warnings) ?? []
        appliedSceneID = cue.sceneID
        if let first = notes.first {
            post("Cue \(number): \(first)")
        } else {
            noticeTask?.cancel()
            notice = nil
        }
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
        save()
        return true
    }

    func remove(_ cueID: UUID) {
        guard (try? list.remove(cueID)) != nil else { return }
        save()
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard (try? list.move(fromOffsets: offsets, toOffset: destination)) != nil else { return }
        save()
    }

    /// False when the label is not 1…80 characters on one line.
    @discardableResult
    func rename(_ cueID: UUID, to label: String) -> Bool {
        guard (try? list.rename(cueID, to: label)) != nil else { return false }
        save()
        return true
    }

    func dismissEditorMessage() { editorMessage = nil }

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
        self.list = list
        unreadableScenes = Set(list.sceneIDs.filter { (id: String) -> Bool in !(store?.sceneIsReadable(id) ?? false) })
        save()
    }

    /// UI tests: records the seeded cue's scene as applied (the seed sets the settings directly).
    func markAppliedForUITests(_ sceneID: String) { appliedSceneID = sceneID }
    #endif
}
