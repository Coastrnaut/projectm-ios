// ShowStoreTests.swift — the show folder (SHOW-001-S2: scene IDs preserved through save and load;
// SHOW-001-R11, R12; contract S2, S5).
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class ShowStoreTests: XCTestCase {
    private func makeStore() throws -> ShowStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShowStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return ShowStore(directory: folder)
    }

    private func scene(_ n: Int) -> SceneDocument {
        SceneDocument(id: ShowFixtures.sceneID(n), name: "Scene \(n)",
                      layers: [SceneLayer(instance: 1, content: n % 2 == 0 ? .linearSpectrum : .circularSpectrum)])
    }

    func testFiveScenesAndTheShowSurviveSaveAndLoadWithTheirIDs() throws {
        let store = try makeStore()
        var list = try ShowFixtures.fiveCues()
        for n in 1...5 { try store.saveScene(scene(n)) }
        list.go(to: ShowFixtures.uuid(4))
        try store.save(list)

        let loaded = store.load()
        XCTAssertNil(loaded.refusal)
        XCTAssertEqual(loaded.list, list)
        XCTAssertEqual(loaded.unreadableScenes, [])
        for (index, cue) in loaded.list.cues.enumerated() {
            XCTAssertEqual(cue.id, ShowFixtures.uuid(index + 1))
            let stored = try store.scene(cue.sceneID)
            XCTAssertEqual(stored.document.id, ShowFixtures.sceneID(index + 1), "the stored scene keeps its ID")
            XCTAssertEqual(stored.document, scene(index + 1))
            XCTAssertEqual(try Data(contentsOf: store.sceneFile(cue.sceneID)), Data(scene(index + 1).encoded()), "canonical bytes")
        }
        XCTAssertEqual(try Data(contentsOf: store.showFile), list.encoded())
    }

    func testNoFileGivesAnEmptyShow() throws {
        let loaded = try makeStore().load()
        XCTAssertTrue(loaded.list.cues.isEmpty)
        XCTAssertNil(loaded.setAside)
        XCTAssertNil(loaded.refusal)
    }

    func testRefusedFilesAreSetAsideNeverDeleted() throws {
        let store = try makeStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let newer = Data("{\"format\":\"projectm-ios.show\",\"version\":7}".utf8)
        try newer.write(to: store.showFile)
        let first = store.load()
        XCTAssertEqual(first.refusal, .newerVersion(7))
        XCTAssertEqual(first.setAside?.lastPathComponent, "show.damaged-1.json")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(first.setAside)), newer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.showFile.path))
        XCTAssertTrue(first.list.cues.isEmpty)

        try Data("garbage".utf8).write(to: store.showFile)
        let second = store.load()
        XCTAssertEqual(second.refusal, .malformed)
        XCTAssertEqual(second.setAside?.lastPathComponent, "show.damaged-2.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.setAside!.path), "the first one is kept")
    }

    func testMissingMismatchedAndUnreadableScenesAreFlaggedNotFatal() throws {
        let store = try makeStore()
        let list = try ShowFixtures.fiveCues()
        try store.saveScene(scene(1))
        try store.saveScene(scene(2))
        // Scene 3's file holds scene 9; scene 4's file is not a scene; scene 5 has no file.
        try FileManager.default.createDirectory(at: store.scenesFolder, withIntermediateDirectories: true)
        try Data(scene(9).encoded()).write(to: store.sceneFile(ShowFixtures.sceneID(3)))
        try Data("{".utf8).write(to: store.sceneFile(ShowFixtures.sceneID(4)))
        try store.save(list)

        let loaded = store.load()
        XCTAssertEqual(loaded.list.cues.count, 5, "every cue is kept")
        XCTAssertEqual(loaded.unreadableScenes, Set([3, 4, 5].map { (n: Int) -> String in ShowFixtures.sceneID(n) }))
        XCTAssertThrowsError(try store.scene(ShowFixtures.sceneID(3))) { (error: any Error) in
            XCTAssertEqual(error as? ShowSceneReadError, .mismatchedID(found: ShowFixtures.sceneID(9)))
        }
        XCTAssertThrowsError(try store.scene(ShowFixtures.sceneID(5))) { (error: any Error) in
            XCTAssertEqual(error as? ShowSceneReadError, .missing)
        }
        XCTAssertThrowsError(try store.scene(ShowFixtures.sceneID(4))) { (error: any Error) in
            guard case .unreadable? = error as? ShowSceneReadError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try store.scene("../show")) { (error: any Error) in
            XCTAssertEqual(error as? ShowSceneReadError, .missing, "only scene IDs name files")
        }
    }

    func testSavingRemovesScenesNoCueRefersTo() throws {
        let store = try makeStore()
        var list = try ShowFixtures.fiveCues()
        for n in 1...5 { try store.saveScene(scene(n)) }
        try store.saveScene(scene(8))   // never referenced
        try store.save(list)
        XCTAssertEqual(store.storedSceneIDs(), Set((1...5).map { (n: Int) -> String in ShowFixtures.sceneID(n) }))
        try list.remove(ShowFixtures.uuid(2))
        try store.save(list)
        XCTAssertFalse(store.storedSceneIDs().contains(ShowFixtures.sceneID(2)))
        XCTAssertEqual(store.storedSceneIDs().count, 4)
    }
}
