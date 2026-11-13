// ShowSceneEditCoordinatorTests.swift — SCN-003-T11 in the app: Duplicate Scene inserts a cue for a copy
// with a new scene ID right after its source without applying anything or moving the position;
// stepping then applies the original and the copy as two scenes with distinct IDs; Rename Scene keeps
// the ID and every cue; refusals (missing scene, invalid name, a full show) set the editor message and
// write no scene file. Each store is a fresh temporary folder; nothing reads the wall clock.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class ShowSceneEditCoordinatorTests: XCTestCase {
    static let copyID = "C0B1E5CE-0000-4000-8000-0000000000AA"

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShowSceneEditCoordinatorTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    /// Three cues (Circular "Opening", Linear "Build", Circular "Drop") over a temporary store; returns
    /// the coordinator, the scene IDs and what it applied.
    private func show(at url: URL) throws -> (ShowCoordinator, [String], () -> [String]) {
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        var applied: [String] = []
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            applied.append(document.id)
            return []
        }
        show.announce = { (_: String) in }
        show.makeSceneID = { () -> String in Self.copyID }
        var ids: [String] = []
        let cues: [(VisualChoice, String)] = [(.circularSpectrum, "Opening"), (.linearSpectrum, "Build"), (.circularSpectrum, "Drop")]
        for (visual, label) in cues {
            let document = ShowSceneSnapshot.document(look(visual), id: UUID().uuidString, name: label)
            ids.append(document.id)
            XCTAssertTrue(show.addScene(document, label: label))
        }
        return (show, ids, { applied })
    }

    func testDuplicateInsertsACopyAfterItsCueAndBothApplyWithDistinctIDs() throws {
        let url = folder()
        let (show, ids, applied) = try show(at: url)
        show.next()   // cue 1
        XCTAssertEqual(applied(), [ids[0]])

        let inserted = try XCTUnwrap(show.duplicateScene(of: show.list.cues[1].id))
        XCTAssertEqual(inserted.sceneID, Self.copyID)
        XCTAssertNotEqual(inserted.sceneID, ids[1])
        XCTAssertEqual(show.list.cues.map(\.label), ["Opening", "Build", "Build copy", "Drop"])
        XCTAssertEqual(show.list.cues[1].sceneID, ids[1], "the source cue still shows the original")
        XCTAssertEqual(show.sceneName(of: inserted), "Build copy")
        XCTAssertEqual(show.list.positionText, "Cue 1 of 4", "the position did not move")
        XCTAssertEqual(applied(), [ids[0]], "duplicating never applies")
        XCTAssertNil(show.editorMessage)

        show.next()
        show.next()
        XCTAssertEqual(applied(), [ids[0], ids[1], Self.copyID], "the original and the copy are two scenes")
        XCTAssertNil(show.notice, "both validate and apply")

        // Relaunch: both scenes and the new cue come back.
        let again = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        XCTAssertEqual(again.list, show.list)
        XCTAssertEqual(again.unreadableScenes, [])
        XCTAssertEqual(again.sceneName(of: again.list.cues[2]), "Build copy")
    }

    func testRenameSceneKeepsTheIDAndEveryCue() throws {
        let url = folder()
        let (show, ids, applied) = try show(at: url)
        let cues = show.list.cues
        XCTAssertTrue(show.renameScene(of: cues[1].id, to: "  Build B "))
        XCTAssertEqual(show.list.cues, cues, "cue IDs, scene IDs and labels unchanged")
        XCTAssertEqual(show.sceneName(of: cues[1]), "Build B")
        XCTAssertEqual(try ShowStore(directory: url).scene(ids[1]).document.name, "Build B")
        XCTAssertEqual(applied(), [], "renaming never applies")

        XCTAssertFalse(show.renameScene(of: cues[1].id, to: "Two\nlines"))
        XCTAssertEqual(show.editorMessage, SceneEditError.invalidName.description)
        XCTAssertEqual(show.sceneName(of: cues[1]), "Build B")
    }

    func testRefusalsSetTheEditorMessageAndWriteNoSceneFile() throws {
        let url = folder()
        let (show, ids, _) = try show(at: url)
        let store = ShowStore(directory: url)
        try FileManager.default.removeItem(at: store.sceneFile(ids[2]))
        XCTAssertNil(show.duplicateScene(of: show.list.cues[2].id))
        XCTAssertEqual(show.editorMessage, ShowCoordinator.sceneUnreadableMessage)
        XCTAssertTrue(show.isSceneMissing(show.list.cues[2]))
        XCTAssertFalse(show.renameScene(of: show.list.cues[2].id, to: "x"))
        XCTAssertEqual(store.storedSceneIDs(), Set(ids[0...1]))

        // A full show: refused before any file is written.
        show.dismissEditorMessage()
        var full = ShowCueList(id: UUID(), name: "Full")
        for n in 0..<ShowCueList.maximumCues { try full.append(sceneID: ids[0], label: "Cue \(n)") }
        show.replaceForUITests(full)
        XCTAssertNil(show.duplicateScene(of: full.cues[0].id))
        XCTAssertEqual(show.editorMessage, ShowEditError.tooManyCues(limit: ShowCueList.maximumCues).description)
        XCTAssertEqual(store.storedSceneIDs(), [ids[0]])
        XCTAssertEqual(show.list.cues.count, ShowCueList.maximumCues)
    }
}
