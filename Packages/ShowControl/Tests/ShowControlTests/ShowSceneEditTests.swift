// ShowSceneEditTests.swift — SCN-003-T06, T09: duplicate and rename of a show's scenes (SCN-003-S1,
// the row's acceptance "Both scenes load independently and have distinct IDs"; S2; R4, R8, R9;
// contract D2, D3).
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class ShowSceneEditTests: XCTestCase {
    static let photoID = "0A1B2C3D-4E5F-4071-8293-A4B5C6D7E8F9"
    static let videoID = "F0E1D2C3-B4A5-4687-8869-5A4B3C2D1E0F"
    static let copyID = "C0B1E5CE-0000-4000-8000-000000000001"
    static let copyCueID = ShowFixtures.uuid(77)

    private func makeStore() -> ShowStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShowSceneEditTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return ShowStore(directory: folder)
    }

    /// Scene n: a spectrum, the stored photo and video (shared media) and an unknown top-level field.
    private func scene(_ n: Int) -> SceneDocument {
        SceneDocument(id: ShowFixtures.sceneID(n), name: "Scene \(n)",
                      layers: [SceneLayer(instance: 1, content: .photo(asset: "photo")),
                               SceneLayer(instance: 2, content: .video(asset: "clip"), values: ["rate": 0.5]),
                               SceneLayer(instance: 7, content: n % 2 == 0 ? .linearSpectrum : .circularSpectrum)],
                      assets: ["photo": .photo(storeID: Self.photoID), "clip": .video(storeID: Self.videoID)],
                      extra: ["futureField": .string("kept \(n)")])
    }

    /// The five-cue fixture stored with its scenes, standing on cue 2.
    private func storedShow(_ store: ShowStore) throws -> ShowCueList {
        var list = try ShowFixtures.fiveCues()
        for n in 1...5 { try store.saveScene(scene(n)) }
        list.go(to: ShowFixtures.uuid(2))
        try store.save(list)
        return list
    }

    private func registry() throws -> ParameterRegistry { try ParameterRegistry(descriptors: []) }

    // MARK: S1 — the acceptance

    func testDuplicateGivesTwoScenesThatLoadIndependentlyWithDistinctIDs() throws {
        let store = makeStore()
        var list = try storedShow(store)
        let source = ShowFixtures.sceneID(2)
        let copy = try store.duplicateScene(source, newID: Self.copyID, name: SceneDocument.copyName("Scene 2"))
        try list.insert(sceneID: copy.id, label: ShowCueList.copyLabel("Cue B"), after: ShowFixtures.uuid(2), cueID: Self.copyCueID)
        try store.save(list)

        // Two files, distinct IDs.
        XCTAssertNotEqual(copy.id, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sceneFile(source).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sceneFile(Self.copyID).path))
        XCTAssertEqual(store.storedSceneIDs().count, 6)

        // Reload from disk: the original's cues still resolve to the original; the new cue to the copy.
        let loaded = store.load()
        XCTAssertEqual(loaded.unreadableScenes, [])
        XCTAssertEqual(loaded.list.cues.map(\.label), ["Cue A", "Cue B", "Cue B copy", "Cue C", "Cue D", "Cue E"])
        XCTAssertEqual(loaded.list.cues[1].sceneID, source)
        XCTAssertEqual(loaded.list.cues[2].sceneID, Self.copyID)
        XCTAssertEqual(loaded.list.activeCue?.id, ShowFixtures.uuid(2), "the position did not move")

        // Each loads on its own (SCN-001 decode + liveState), the other file removed first.
        let original = try store.scene(source).document
        let copied = try store.scene(Self.copyID).document
        XCTAssertEqual(copied.name, "Scene 2 copy")
        XCTAssertEqual(copied.extra, original.extra, "unknown content kept")
        let originalBytes = try Data(contentsOf: store.sceneFile(source))
        try FileManager.default.removeItem(at: store.sceneFile(source))
        let copyAlone = try store.scene(Self.copyID).document.liveState(registry: try registry())
        try originalBytes.write(to: store.sceneFile(source))
        try FileManager.default.removeItem(at: store.sceneFile(Self.copyID))
        let originalAlone = try store.scene(source).document.liveState(registry: try registry())
        XCTAssertEqual(copyAlone.state, originalAlone.state, "the same look")
        XCTAssertEqual(Data(original.encoded()), originalBytes, "the original's file was not rewritten")
    }

    func testInsertGoesRightAfterItsCueAndKeepsThePosition() throws {
        var list = try ShowFixtures.fiveCues()
        list.go(to: ShowFixtures.uuid(4))
        try list.insert(sceneID: Self.copyID, label: "  Copy ", after: ShowFixtures.uuid(5), cueID: Self.copyCueID)
        XCTAssertEqual(list.cues.last?.id, Self.copyCueID)
        XCTAssertEqual(list.cues.last?.label, "Copy")
        try list.insert(sceneID: Self.copyID, label: "First copy", after: ShowFixtures.uuid(1), cueID: ShowFixtures.uuid(78))
        XCTAssertEqual(list.cues[1].id, ShowFixtures.uuid(78))
        XCTAssertEqual(list.activeCue?.id, ShowFixtures.uuid(4))
        XCTAssertEqual(list.positionText, "Cue 5 of 7")
        XCTAssertThrowsError(try list.insert(sceneID: Self.copyID, label: "x", after: ShowFixtures.uuid(99))) { (e: Error) in
            XCTAssertEqual(e as? ShowEditError, .unknownCue(ShowFixtures.uuid(99)))
        }
        XCTAssertThrowsError(try list.insert(sceneID: Self.copyID, label: "x", after: ShowFixtures.uuid(1), cueID: Self.copyCueID)) { (e: Error) in
            XCTAssertEqual(e as? ShowEditError, .duplicateCueID(Self.copyCueID))
        }
        XCTAssertThrowsError(try list.insert(sceneID: "nope", label: "x", after: ShowFixtures.uuid(1))) { (e: Error) in
            XCTAssertEqual(e as? ShowEditError, .invalidSceneID("nope"))
        }
        XCTAssertEqual(ShowCueList.copyLabel("Build"), "Build copy")
        XCTAssertEqual(ShowCueList.copyLabel(String(repeating: "x", count: 80)).count, ShowCueList.maximumLabelLength)
        XCTAssertNotNil(ShowCueList.normalizedLabel(ShowCueList.copyLabel(String(repeating: "x", count: 80))))
    }

    func testRefusedDuplicatesWriteNothing() throws {
        let store = makeStore()
        _ = try storedShow(store)
        let before = store.storedSceneIDs()
        XCTAssertThrowsError(try store.duplicateScene(ShowFixtures.sceneID(9), newID: Self.copyID, name: "x")) { (e: Error) in
            XCTAssertEqual(e as? ShowSceneEditError, .unreadable(.missing))
        }
        XCTAssertThrowsError(try store.duplicateScene(ShowFixtures.sceneID(1), newID: ShowFixtures.sceneID(3), name: "x")) { (e: Error) in
            XCTAssertEqual(e as? ShowSceneEditError, .sceneIDTaken(ShowFixtures.sceneID(3)), "never replaces another scene")
        }
        XCTAssertThrowsError(try store.duplicateScene(ShowFixtures.sceneID(1), newID: Self.copyID, name: " ")) { (e: Error) in
            XCTAssertEqual(e as? ShowSceneEditError, .invalid(.invalidName))
        }
        XCTAssertThrowsError(try store.duplicateScene(ShowFixtures.sceneID(1), newID: ShowFixtures.sceneID(1), name: "x")) { (e: Error) in
            XCTAssertEqual(e as? ShowSceneEditError, .invalid(.sameSceneID))
        }
        XCTAssertEqual(store.storedSceneIDs(), before)
        XCTAssertEqual(try store.scene(ShowFixtures.sceneID(3)).document, scene(3), "scene 3 untouched")
    }

    // MARK: S2 — rename keeps every reference

    func testRenameKeepsTheIDTheFileAndEveryCueReference() throws {
        let store = makeStore()
        var list = try storedShow(store)
        try list.append(sceneID: ShowFixtures.sceneID(2), label: "Cue B again", cueID: ShowFixtures.uuid(6))   // two cues share scene 2
        try store.save(list)
        let showBytes = try Data(contentsOf: store.showFile)

        let renamed = try store.renameScene(ShowFixtures.sceneID(2), to: "  Build B ")
        XCTAssertEqual(renamed.id, ShowFixtures.sceneID(2))
        XCTAssertEqual(renamed.name, "Build B")
        XCTAssertEqual(try Data(contentsOf: store.showFile), showBytes, "the show file is not touched")

        let loaded = store.load()
        XCTAssertEqual(loaded.unreadableScenes, [])
        XCTAssertEqual(loaded.list, list, "cue IDs, scene IDs and labels unchanged")
        for cue in loaded.list.cues where cue.sceneID == ShowFixtures.sceneID(2) {
            XCTAssertEqual(try store.scene(cue.sceneID).document.name, "Build B", cue.label)
        }
        var expected = scene(2)
        expected.name = "Build B"
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(2))), Data(expected.encoded()),
                       "only the name differs, canonical bytes")
    }

    func testRefusedRenamesLeaveTheFile() throws {
        let store = makeStore()
        _ = try storedShow(store)
        let file = store.sceneFile(ShowFixtures.sceneID(1))
        let bytes = try Data(contentsOf: file)
        for bad in ["", "   ", "a\nb", String(repeating: "n", count: 121)] {
            XCTAssertThrowsError(try store.renameScene(ShowFixtures.sceneID(1), to: bad)) { (e: Error) in
                XCTAssertEqual(e as? ShowSceneEditError, .invalid(.invalidName))
            }
        }
        XCTAssertThrowsError(try store.renameScene(ShowFixtures.sceneID(8), to: "x")) { (e: Error) in
            XCTAssertEqual(e as? ShowSceneEditError, .unreadable(.missing))
        }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sceneFile(ShowFixtures.sceneID(8)).path))
    }

    // MARK: R9 — shared media

    func testTheCopySharesStoredMediaAndDeletingTheOriginalKeepsTheReference() throws {
        let store = makeStore()
        var list = try ShowCueList(id: ShowFixtures.showID, name: "Media", cues: [], position: .standby)
        try store.saveScene(scene(1))
        try list.append(sceneID: ShowFixtures.sceneID(1), label: "Original", cueID: ShowFixtures.uuid(1))
        try store.save(list)
        let copy = try store.duplicateScene(ShowFixtures.sceneID(1), newID: Self.copyID, name: "Copy")
        try list.insert(sceneID: copy.id, label: "Copy", after: ShowFixtures.uuid(1), cueID: Self.copyCueID)
        try store.save(list)
        XCTAssertEqual(copy.assets, scene(1).assets, "the same store IDs: no second copy of the media")
        XCTAssertEqual(store.referencedMediaIDs(), StoredMediaReferences(photos: [Self.photoID], videos: [Self.videoID]))

        // Removing the original's only cue removes the original's file; the copy still names the media.
        try list.remove(ShowFixtures.uuid(1))
        try store.save(list)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sceneFile(ShowFixtures.sceneID(1)).path))
        XCTAssertEqual(store.referencedMediaIDs(), StoredMediaReferences(photos: [Self.photoID], videos: [Self.videoID]))
        XCTAssertNoThrow(try store.scene(Self.copyID).document.liveState(registry: try registry()))

        // With no scene left, nothing is referenced.
        try list.remove(Self.copyCueID)
        try store.save(list)
        XCTAssertEqual(store.referencedMediaIDs(), StoredMediaReferences())
    }
}
