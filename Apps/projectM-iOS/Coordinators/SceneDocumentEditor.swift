// SceneDocumentEditor.swift — UIX-008 one editor window's model (specs/294-uix-008-multiwindow-document-editing,
// data-model "SceneDocumentEditor", contract W3, W4; research UIX-008-D3, D5).
//
// * Holds its own working copy of one saved scene, the file bytes it was read from (or last saved), and its own
//   SCN-010 history (standard bounds). Editors share nothing but the library they read and write through.
// * Edits: the name (SCN-003 rules; coalescing key `name`) and each layer's opacity (clamped to 0…1; key
//   `opacity.<instance>`). Neither can make a valid scene invalid, so saving needs no repair step.
// * Save goes through the library (`saveEditedScene`): refused while the scene is locked or no longer stored, and
//   a conflict (nothing written) when the file changed since it was read; Replace writes anyway, Reload reads the
//   file again. Saving never applies anything to the live output (UIX-008-R5, R12).
// Main actor; no engine, capture, renderer or timer (UIX-008-R7).
import Foundation
import Observation
import SceneFormat

/// The library an editor reads and writes through (`ShowCoordinator+SceneEditing`; a fake is never needed: tests
/// use a `ShowCoordinator` over a temporary store).
@MainActor
protocol SceneDocumentLibrary: AnyObject {
    /// The scene's document and the file's bytes; nil when it is not in the library or cannot be read.
    func editableScene(_ sceneID: String) -> (document: SceneDocument, bytes: [UInt8])?
    /// Writes `document` (contract W4); `expectedBytes` nil means Replace (no conflict check).
    func saveEditedScene(_ document: SceneDocument, expectedBytes: [UInt8]?) -> SceneEditorSaveOutcome
}

enum SceneEditorSaveOutcome: Equatable {
    /// Written; the file's bytes now.
    case saved([UInt8])
    /// The file changed since it was read; nothing written.
    case conflict
    /// Refused with a message; nothing written.
    case refused(String)
}

@MainActor
@Observable
final class SceneDocumentEditor {
    static let missingMessage = "This scene is no longer stored."
    static let invalidOpacityMessage = "The layer is not in this scene."

    let sceneID: String
    /// The working copy; nil when the scene could not be read.
    private(set) var document: SceneDocument?
    /// The file's bytes when read or last saved (the conflict check).
    private(set) var baseBytes: [UInt8] = []
    /// The last refusal or error, for the window.
    private(set) var message: String?
    /// The last save found the file changed elsewhere (the window offers Replace or Reload).
    private(set) var conflict = false
    private(set) var history: SceneHistory<SceneDocument>?
    /// The canonical bytes of the document as read or last saved (the dirty check; a migrated file's raw bytes differ).
    private var cleanBytes: [UInt8] = []
    @ObservationIgnored private let library: any SceneDocumentLibrary

    init(sceneID: String, library: any SceneDocumentLibrary) {
        self.sceneID = sceneID
        self.library = library
        load()
    }

    var isMissing: Bool { document == nil }

    /// Unsaved edits: the working copy's canonical bytes differ from the file's.
    var isDirty: Bool {
        guard let document else { return false }
        return document.encoded() != cleanBytes
    }

    var canUndo: Bool { history?.canUndo ?? false }
    var canRedo: Bool { history?.canRedo ?? false }

    func dismissMessage() { message = nil }

    // MARK: - Edits (UIX-008-R3, R4)

    /// Renames the working copy; false (with SCN-003's message) when the name is invalid.
    @discardableResult
    func rename(_ name: String) -> Bool {
        guard let document else { return false }
        do throws(SceneEditError) {
            let renamed: SceneDocument = try document.renamed(to: name)
            apply(renamed, label: "Name", key: "name")
            return true
        } catch {
            message = error.description
            return false
        }
    }

    /// Sets a layer's opacity (clamped to 0…1).
    @discardableResult
    func setOpacity(_ opacity: Double, ofLayer instance: UInt64) -> Bool {
        guard var edited = document,
              let index = edited.layers.firstIndex(where: { (layer: SceneLayer) -> Bool in layer.instance == instance }) else {
            message = Self.invalidOpacityMessage
            return false
        }
        let clamped: Double = opacity.isFinite ? min(1, max(0, opacity)) : 1
        edited.layers[index].composite.opacity = clamped
        apply(edited, label: "Opacity", key: "opacity.\(instance)")
        return true
    }

    func opacity(ofLayer instance: UInt64) -> Double {
        document?.layers.first { (layer: SceneLayer) -> Bool in layer.instance == instance }?.composite.opacity ?? 1
    }

    /// Ends a slider drag or a field's editing, so the next change is its own undo step.
    func endCoalescing() { history?.endCoalescing() }

    func undo() {
        guard let state = history?.undo() else { return }
        document = state.value
    }

    func redo() {
        guard let state = history?.redo() else { return }
        document = state.value
    }

    // MARK: - Save (UIX-008-R5, R9)

    @discardableResult
    func save() -> SceneEditorSaveOutcome { write(expectedBytes: baseBytes) }

    /// Writes this window's document over a file that changed elsewhere.
    @discardableResult
    func replace() -> SceneEditorSaveOutcome { write(expectedBytes: nil) }

    /// Discards this window's edits and reads the file again (a fresh history).
    func reload() {
        conflict = false
        message = nil
        load()
    }

    // MARK: - Private

    private func load() {
        guard let stored = library.editableScene(sceneID) else {
            document = nil
            history = nil
            baseBytes = []
            cleanBytes = []
            return
        }
        document = stored.document
        baseBytes = stored.bytes
        cleanBytes = stored.document.encoded()
        history = SceneHistory(current: SceneHistoryState(stored.document))
    }

    private func apply(_ edited: SceneDocument, label: String, key: String) {
        document = edited
        message = nil
        _ = history?.record(SceneHistoryState(edited), label: label, coalescingKey: key)
    }

    private func write(expectedBytes: [UInt8]?) -> SceneEditorSaveOutcome {
        guard let document else {
            message = Self.missingMessage
            return .refused(Self.missingMessage)
        }
        history?.endCoalescing()
        let outcome: SceneEditorSaveOutcome = library.saveEditedScene(document, expectedBytes: expectedBytes)
        switch outcome {
        case let .saved(bytes):
            baseBytes = bytes
            cleanBytes = document.encoded()
            conflict = false
            message = nil
        case .conflict:
            conflict = true
        case let .refused(text):
            message = text
        }
        return outcome
    }
}
