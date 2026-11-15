// SceneDocumentEditorTests.swift — UIX-008-T07: the roadmap acceptance "Two scenes edit independently and save to
// separate files" (UIX-008-S1, S2) and the safe-saving rules (UIX-008-R9, R12; contract W4). Two editors over two
// library scenes in a temporary SHOW-001 store: edits and undo stay in their own editor; each save writes only its
// own file, whose bytes equal that editor's document; the library lists both names. Also: unsaved edits never
// reach the stored file (what the main window reads), the lock refuses, a file changed elsewhere is a conflict
// (Replace and Reload), and a scene no longer stored is refused. Nothing reads the wall clock.
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneDocumentEditorTests: XCTestCase {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneDocumentEditorTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    /// A show with two scenes, "Alpha" and "Beta".
    private func library() throws -> (show: ShowCoordinator, a: String, b: String) {
        let show = ShowCoordinator(store: ShowStore(directory: folder()), registry: try? SceneArchiveService.appRegistry())
        show.announce = { (_: String) in }
        let alpha = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "Alpha")
        let beta = ShowSceneSnapshot.document(look(.linearSpectrum), id: UUID().uuidString, name: "Beta")
        XCTAssertTrue(show.addScene(alpha, label: "Alpha"))
        XCTAssertTrue(show.addScene(beta, label: "Beta"))
        return (show, alpha.id, beta.id)
    }

    private func fileBytes(_ show: ShowCoordinator, _ id: String) throws -> [UInt8] {
        try XCTUnwrap(show.storedSceneBytes(id))
    }

    private func firstLayer(_ editor: SceneDocumentEditor) throws -> UInt64 {
        try XCTUnwrap(editor.document?.layers.first?.instance, "the scene has a layer")
    }

    // MARK: - The acceptance (UIX-008-S1, S2)

    func testTwoScenesEditIndependentlyAndSaveToSeparateFiles() throws {
        let (show, a, b) = try library()
        let editorA = SceneDocumentEditor(sceneID: a, library: show)
        let editorB = SceneDocumentEditor(sceneID: b, library: show)
        let bBefore: [UInt8] = try XCTUnwrap(editorB.document).encoded()
        let layerB: UInt64 = try firstLayer(editorB)
        let layerA: UInt64 = try firstLayer(editorA)
        let opacityA: Double = editorA.opacity(ofLayer: layerA)

        XCTAssertTrue(editorA.rename("Alpha Live"))
        XCTAssertEqual(try XCTUnwrap(editorB.document).encoded(), bBefore, "A's rename leaves B untouched")
        XCTAssertTrue(editorB.setOpacity(0.4, ofLayer: layerB))
        XCTAssertEqual(editorA.opacity(ofLayer: layerA), opacityA, "B's opacity leaves A untouched")
        XCTAssertEqual(editorA.document?.name, "Alpha Live")
        XCTAssertEqual(editorB.document?.name, "Beta")
        XCTAssertTrue(editorA.isDirty)
        XCTAssertTrue(editorB.isDirty)

        // UIX-008-R12: unsaved edits are not in the files the main window reads.
        XCTAssertEqual(try show.store?.scene(a).document.name, "Alpha")

        guard case .saved = editorA.save() else { return XCTFail("A saved") }
        guard case .saved = editorB.save() else { return XCTFail("B saved") }
        XCTAssertEqual(try fileBytes(show, a), try XCTUnwrap(editorA.document).encoded(), "A's file is A's document")
        XCTAssertEqual(try fileBytes(show, b), try XCTUnwrap(editorB.document).encoded(), "B's file is B's document")
        XCTAssertNotEqual(show.store?.sceneFile(a), show.store?.sceneFile(b), "two separate files")
        XCTAssertEqual(try show.store?.scene(b).document.layers.first?.composite.opacity, 0.4)
        XCTAssertFalse(editorA.isDirty)
        XCTAssertFalse(editorB.isDirty)
        // The library index lists both scenes under their saved names.
        XCTAssertEqual(Set(show.list.sceneIDs), [a, b])
        XCTAssertEqual(show.sceneNames[a], "Alpha Live")
        XCTAssertEqual(show.sceneNames[b], "Beta")
    }

    func testEachEditorHasItsOwnUndoHistory() throws {
        let (show, a, b) = try library()
        let editorA = SceneDocumentEditor(sceneID: a, library: show)
        let editorB = SceneDocumentEditor(sceneID: b, library: show)
        let layerA: UInt64 = try firstLayer(editorA)
        let start: Double = editorA.opacity(ofLayer: layerA)
        editorA.setOpacity(0.2, ofLayer: layerA)
        editorA.setOpacity(0.3, ofLayer: layerA)   // coalesced with the first (one drag)
        editorA.endCoalescing()
        XCTAssertTrue(editorB.rename("Beta 2"))
        XCTAssertEqual(editorA.history?.undoSteps.count, 1, "a drag is one step")

        editorA.undo()
        XCTAssertEqual(editorA.opacity(ofLayer: layerA), start, "A is back")
        XCTAssertEqual(editorB.document?.name, "Beta 2", "B's edit stays")
        XCTAssertTrue(editorB.canUndo, "B's history is untouched")
        XCTAssertFalse(editorA.isDirty)
        editorA.redo()
        XCTAssertEqual(editorA.opacity(ofLayer: layerA), 0.3)
    }

    // MARK: - Safe saving (UIX-008-R9; contract W4)

    func testTheSceneLockRefusesSaving() throws {
        let (show, a, _) = try library()
        let suite = "SceneDocumentEditorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let lock = SceneLock(defaults: defaults)
        lock.lock()
        show.sceneLock = lock
        let before: [UInt8] = try fileBytes(show, a)
        let editor = SceneDocumentEditor(sceneID: a, library: show)
        editor.rename("Locked")
        XCTAssertEqual(editor.save(), .refused(SceneLock.refusalMessage))
        XCTAssertEqual(try fileBytes(show, a), before, "nothing written")
        XCTAssertTrue(editor.isDirty)
    }

    func testAFileChangedElsewhereIsAConflictThenReplaceOrReload() throws {
        let (show, a, _) = try library()
        let editor = SceneDocumentEditor(sceneID: a, library: show)
        editor.rename("From the window")
        // The main window renames the same scene (SCN-003) after the editor read it.
        let cue = try XCTUnwrap(show.firstCue(ofScene: a))
        XCTAssertTrue(show.renameScene(of: cue.id, to: "From the main window"))
        let elsewhere: [UInt8] = try fileBytes(show, a)

        XCTAssertEqual(editor.save(), .conflict)
        XCTAssertTrue(editor.conflict)
        XCTAssertEqual(try fileBytes(show, a), elsewhere, "a conflict writes nothing")

        guard case .saved = editor.replace() else { return XCTFail("Replace writes") }
        XCTAssertEqual(try show.store?.scene(a).document.name, "From the window")
        XCTAssertFalse(editor.conflict)

        XCTAssertTrue(show.renameScene(of: cue.id, to: "Again elsewhere"))
        editor.rename("Lost")
        XCTAssertEqual(editor.save(), .conflict)
        editor.reload()
        XCTAssertEqual(editor.document?.name, "Again elsewhere", "Reload reads the file")
        XCTAssertFalse(editor.isDirty)
        XCTAssertFalse(editor.canUndo, "a fresh history")
    }

    func testASceneNoLongerStoredIsRefused() throws {
        let (show, a, _) = try library()
        let editor = SceneDocumentEditor(sceneID: a, library: show)
        editor.rename("Gone")
        let cue = try XCTUnwrap(show.firstCue(ofScene: a))
        show.remove(cue.id)   // the scene's last cue: its file is removed
        XCTAssertEqual(editor.save(), .refused(SceneDocumentEditor.missingMessage))
        XCTAssertNil(show.storedSceneBytes(a))
        XCTAssertTrue(SceneDocumentEditor(sceneID: a, library: show).isMissing, "a restored window shows missing")
    }

    func testAnInvalidNameIsRefusedAndOpacityIsClamped() throws {
        let (show, a, _) = try library()
        let editor = SceneDocumentEditor(sceneID: a, library: show)
        XCTAssertFalse(editor.rename("   "))
        XCTAssertNotNil(editor.message)
        XCTAssertEqual(editor.document?.name, "Alpha")
        let layer: UInt64 = try firstLayer(editor)
        editor.setOpacity(4, ofLayer: layer)
        XCTAssertEqual(editor.opacity(ofLayer: layer), 1)
        editor.setOpacity(-1, ofLayer: layer)
        XCTAssertEqual(editor.opacity(ofLayer: layer), 0)
        XCTAssertFalse(editor.setOpacity(0.5, ofLayer: 999_999))
    }
}
