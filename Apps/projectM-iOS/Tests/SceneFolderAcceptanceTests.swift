// SceneFolderAcceptanceTests.swift — SCN-004-T10, T12: the roadmap acceptance in the app ("Move scene
// between folders; references remain valid"; SCN-004-S1, S2, S4). Nested folders A and B/C; a scene
// moved from A to B/C keeps its scene ID and file bytes, its cue still resolves and applies the same
// scene, the switcher entry resolves with the new folder path, and a coordinator reloaded from the same
// store keeps the assignment. Also: refusals change nothing and announce, deletion re-parents, a no-op
// move writes nothing, a duplicate lands in its source's folder, and an unreadable scene stays movable.
// Each store is a fresh temporary folder; nothing reads the wall clock.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneFolderAcceptanceTests: XCTestCase {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneFolderAcceptanceTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    private final class Log {
        var applied: [String] = []
        var spoken: [String] = []
    }

    /// Three cues ("Opening", "Build", "Drop") over a store at `url`.
    private func show(at url: URL, log: Log) throws -> (ShowCoordinator, [String]) {
        let show = coordinator(at: url, log: log)
        var ids: [String] = []
        let cues: [(VisualChoice, String)] = [(.circularSpectrum, "Opening"), (.linearSpectrum, "Build"), (.circularSpectrum, "Drop")]
        for (visual, label) in cues {
            let document = ShowSceneSnapshot.document(look(visual), id: UUID().uuidString, name: label)
            ids.append(document.id)
            XCTAssertTrue(show.addScene(document, label: label))
        }
        return (show, ids)
    }

    private func coordinator(at url: URL, log: Log) -> ShowCoordinator {
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try? SceneArchiveService.appRegistry())
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            log.applied.append(document.id)
            return []
        }
        show.announce = { (_: String) in }
        show.announceLibrary = { (message: String) in log.spoken.append(message) }
        return show
    }

    private func entry(_ show: ShowCoordinator, cue index: Int) -> SceneSwitcherEntry {
        SceneSwitcherEntry.entries(list: show.list, sceneNames: show.sceneNames, unreadable: show.unreadableScenes)[index]
    }

    // MARK: - The acceptance (SCN-004-S1, S2)

    func testMovingASceneBetweenNestedFoldersKeepsEveryReferenceValid() throws {
        let url = folder()
        let log = Log()
        let (show, ids) = try show(at: url, log: log)
        let a = try XCTUnwrap(show.createFolder(named: "A", in: nil))
        let b = try XCTUnwrap(show.createFolder(named: "B", in: nil))
        let c = try XCTUnwrap(show.createFolder(named: "C", in: b.id))
        let build = ids[1]
        XCTAssertTrue(show.moveScene(build, to: a.id))
        XCTAssertEqual(show.scenes(in: a.id), [build])
        let store = ShowStore(directory: url)
        let fileBefore = try Data(contentsOf: store.sceneFile(build))
        let cueBefore = show.list.cues[1]
        show.next()   // stand on cue 1, so the move happens mid-show

        XCTAssertTrue(show.moveScene(build, to: c.id))

        // The scene ID, the file and the cue are unchanged; the position did not move.
        XCTAssertEqual(show.list.cues[1], cueBefore)
        XCTAssertEqual(show.list.cues[1].sceneID, build, "the scene ID is unchanged")
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(build)), fileBefore, "the scene file is unchanged")
        XCTAssertEqual(show.list.positionText, "Cue 1 of 3")
        XCTAssertEqual(show.scenes(in: a.id), [])
        XCTAssertEqual(show.scenes(in: c.id), [build])
        XCTAssertEqual(show.folderPath(ofScene: build), "B / C")
        XCTAssertEqual(log.spoken.last, "Moved Build to B / C.")
        // The switcher still resolves the cue to the scene and shows the new folder.
        let row = entry(show, cue: 1)
        XCTAssertEqual(row.cueID, cueBefore.id)
        XCTAssertEqual(row.folderPath, "B / C")
        XCTAssertEqual(row.accessibilityValue, "Cue 2, folder B / C")
        XCTAssertEqual(SceneSwitcherFilter.results([entry(show, cue: 0), row], query: "C").map(\.cueID), [cueBefore.id],
                       "search matches the folder path")
        // The cue still applies the same scene (through Next and through Go to Cue for the scene).
        show.next()
        XCTAssertEqual(log.applied, [ids[0], build])
        XCTAssertNil(show.notice, "validated and applied")
        XCTAssertEqual(show.appliedSceneID, build)
        show.goToScene(ids[0])
        show.goToScene(build)
        XCTAssertEqual(log.applied.suffix(2), [ids[0], build])

        // Relaunch: the assignment, the tree and the stored position (last scene) come back.
        let again = coordinator(at: url, log: Log())
        XCTAssertEqual(again.list, show.list)
        XCTAssertEqual(again.folderPath(ofScene: build), "B / C")
        XCTAssertEqual(again.list.activeSceneID, build, "the last scene still resolves")
        XCTAssertEqual(again.unreadableScenes, [])
        XCTAssertEqual(entry(again, cue: 1).folderPath, "B / C")
    }

    // MARK: - Refusals, deletion, no-op moves (SCN-004-T12, S4)

    func testRefusedFolderEditsChangeNothingAndAreAnnounced() throws {
        let url = folder()
        let log = Log()
        let (show, _) = try show(at: url, log: log)
        let a = try XCTUnwrap(show.createFolder(named: "A", in: nil))
        let b = try XCTUnwrap(show.createFolder(named: "B", in: a.id))
        let before = show.list
        let showFile = try Data(contentsOf: ShowStore(directory: url).showFile)

        XCTAssertFalse(show.moveFolder(a.id, to: b.id))
        XCTAssertEqual(show.editorMessage, "A folder cannot be moved into itself.")
        XCTAssertNil(show.createFolder(named: "a", in: nil))
        XCTAssertEqual(log.spoken.last, "A folder named a already exists here.")
        XCTAssertFalse(show.renameFolder(b.id, to: "  "))
        XCTAssertEqual(show.list, before, "nothing changed")
        XCTAssertEqual(try Data(contentsOf: ShowStore(directory: url).showFile), showFile, "nothing was written")

        XCTAssertTrue(show.renameFolder(b.id, to: "Encore"))
        XCTAssertEqual(show.folderPath(ofScene: show.list.cues[0].sceneID), nil)
        XCTAssertEqual(log.spoken.last, "Renamed folder to Encore.")
    }

    func testDeletingAFolderMovesItsContentsUpAndEveryCueStillApplies() throws {
        let url = folder()
        let log = Log()
        let (show, ids) = try show(at: url, log: log)
        let a = try XCTUnwrap(show.createFolder(named: "A", in: nil))
        let b = try XCTUnwrap(show.createFolder(named: "B", in: a.id))
        show.moveScene(ids[0], to: a.id)
        show.moveScene(ids[1], to: b.id)

        let deletion = try XCTUnwrap(show.deleteFolder(a.id))
        XCTAssertEqual(deletion.movedScenes, [ids[0]])
        XCTAssertNil(show.folderPath(ofScene: ids[0]), "to the top level")
        XCTAssertEqual(show.folderPath(ofScene: ids[1]), "B", "the subfolder moved up with its scene")
        XCTAssertEqual(log.spoken.last, "Deleted folder A; its contents moved to Top Level.")
        XCTAssertEqual(show.list.cues.count, 3, "no cue or scene removed")
        for id in ids { XCTAssertTrue(ShowStore(directory: url).sceneIsReadable(id)) }
        show.next(); show.next(); show.next()
        XCTAssertEqual(log.applied, ids)
    }

    func testAMoveToTheCurrentFolderWritesNothing() throws {
        let url = folder()
        let log = Log()
        let (show, ids) = try show(at: url, log: log)
        let a = try XCTUnwrap(show.createFolder(named: "A", in: nil))
        show.moveScene(ids[2], to: a.id)
        let file = ShowStore(directory: url).showFile
        try FileManager.default.removeItem(at: file)   // any save would write it again
        let spoken = log.spoken.count
        XCTAssertTrue(show.moveScene(ids[2], to: a.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "nothing written")
        XCTAssertEqual(log.spoken.count, spoken, "nothing announced")
    }

    // MARK: - Duplicate and unreadable scenes

    func testADuplicateGoesIntoItsSourcesFolder() throws {
        let url = folder()
        let (show, ids) = try show(at: url, log: Log())
        let a = try XCTUnwrap(show.createFolder(named: "Set A", in: nil))
        show.moveScene(ids[1], to: a.id)
        let copy = try XCTUnwrap(show.duplicateScene(of: show.list.cues[1].id))
        XCTAssertNotEqual(copy.sceneID, ids[1])
        XCTAssertEqual(show.folderPath(ofScene: copy.sceneID), "Set A")
        XCTAssertEqual(coordinator(at: url, log: Log()).folderPath(ofScene: copy.sceneID), "Set A")
    }

    func testAnUnreadableSceneKeepsItsFolderAndCanBeMoved() throws {
        let url = folder()
        let (show, ids) = try show(at: url, log: Log())
        let a = try XCTUnwrap(show.createFolder(named: "A", in: nil))
        show.moveScene(ids[0], to: a.id)
        try Data("not a scene".utf8).write(to: ShowStore(directory: url).sceneFile(ids[0]))
        let again = coordinator(at: url, log: Log())
        XCTAssertTrue(again.unreadableScenes.contains(ids[0]))
        XCTAssertEqual(again.scenes(in: a.id), [ids[0]], "listed in its folder")
        XCTAssertTrue(again.moveScene(ids[0], to: nil))
        XCTAssertEqual(again.scenes(in: nil).count, 3)
    }
}
