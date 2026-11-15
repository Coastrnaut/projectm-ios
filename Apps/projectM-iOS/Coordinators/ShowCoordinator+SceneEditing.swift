// ShowCoordinator+SceneEditing.swift — UIX-008 the library side of editor windows (contract W4; research
// UIX-008-D5). The show's stored scenes are the library; each scene is its own file written whole and atomically
// by `ShowStore.saveScene` (SCN-001 bytes; SCN-013 keeps a migrated original once). The index (`show.json`) does
// not change: the scene ID, its cues and its folder stay. Nothing here applies anything to the live output.
import Foundation
import SceneFormat
import ShowControl
import ShowStorage

extension ShowCoordinator: SceneDocumentLibrary {
    /// A scene the library lists (a cue refers to it) and that reads; with the file's bytes.
    func editableScene(_ sceneID: String) -> (document: SceneDocument, bytes: [UInt8])? {
        guard list.sceneIDs.contains(sceneID), let store, let bytes = storedSceneBytes(sceneID),
              let document = try? store.scene(sceneID).document else { return nil }
        return (document: document, bytes: bytes)
    }

    /// The scene file's bytes now; nil when there is no file.
    func storedSceneBytes(_ sceneID: String) -> [UInt8]? {
        guard let store, ShowCueList.isSceneID(sceneID),
              let data = try? Data(contentsOf: store.sceneFile(sceneID)) else { return nil }
        return [UInt8](data)
    }

    func saveEditedScene(_ document: SceneDocument, expectedBytes: [UInt8]?) -> SceneEditorSaveOutcome {
        if sceneLock?.isLocked == true { return .refused(SceneLock.refusalMessage) }   // SCN-015
        guard let store, list.sceneIDs.contains(document.id) else { return .refused(SceneDocumentEditor.missingMessage) }
        let current: [UInt8]? = storedSceneBytes(document.id)
        guard let current else { return .refused(SceneDocumentEditor.missingMessage) }
        if let expectedBytes, expectedBytes != current { return .conflict }
        do throws(ShowStoreError) {
            try store.saveScene(document)
        } catch {
            return .refused(Self.saveFailedMessage)
        }
        editedSceneSaved(document)
        return .saved(storedSceneBytes(document.id) ?? document.encoded())
    }
}
