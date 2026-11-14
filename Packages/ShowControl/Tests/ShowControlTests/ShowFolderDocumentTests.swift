// ShowFolderDocumentTests.swift — SCN-004-T06: the folder fields of show.json (spec SCN-004-R7 to R9;
// research SCN-004-D3 to D5; contract F1, F4): round trip, determinism, a version 1 file without
// folders re-encoding byte for byte, damaged folder data repaired with warnings, a store reload with
// scene files unchanged, and FILE-004's import keeping the folders.
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class ShowFolderDocumentTests: XCTestCase {
    private static func fid(_ n: Int) -> UUID { UUID(uuidString: String(format: "F01DE000-0000-4000-8000-%012d", n))! }

    /// The five-cue show with folders A, A/B, A/B/C and scene 1 in A/B/C, scene 2 in A.
    private func foldered() throws -> ShowCueList {
        var list = try ShowFixtures.fiveCues()
        try list.createFolder(named: "A", in: nil, id: Self.fid(1))
        try list.createFolder(named: "B", in: Self.fid(1), id: Self.fid(2))
        try list.createFolder(named: "C", in: Self.fid(2), id: Self.fid(3))
        try list.createFolder(named: "Empty", in: nil, id: Self.fid(4))
        try list.moveScene(ShowFixtures.sceneID(1), to: Self.fid(3))
        try list.moveScene(ShowFixtures.sceneID(2), to: Self.fid(1))
        return list
    }

    /// A version 1 show written before SCN-004 (sorted keys, no folder fields).
    private static let legacyShow = """
    {"cues":[{"id":"00000000-0000-4000-8000-000000000001","label":"Cue A","scene":"5CE7E000-0000-4000-8000-000000000001"},\
    {"id":"00000000-0000-4000-8000-000000000002","label":"Cue B","scene":"5CE7E000-0000-4000-8000-000000000002"}],\
    "format":"projectm-ios.show","id":"00000000-0000-4000-8000-000000000999","name":"Legacy","position":null,"version":1}
    """

    func testALegacyFileHasNoFoldersAndReencodesByteForByte() throws {
        let data = Data(Self.legacyShow.utf8)
        let result = try ShowCueList.decode(data)
        XCTAssertEqual(result.warnings, [])
        XCTAssertTrue(result.list.folders.isEmpty)
        XCTAssertNil(result.list.folderID(ofScene: ShowFixtures.sceneID(1)), "every scene at the top level")
        XCTAssertEqual(result.list.encoded(), data, "unchanged bytes")
        let plain = try ShowFixtures.fiveCues().encoded()
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("folders"), "no folder keys without folders")
    }

    func testFoldersRoundTripDeterministically() throws {
        let list = try foldered()
        let data = list.encoded()
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list, list)
        XCTAssertEqual(decoded.list.encoded(), data, "decode → encode is byte-identical")
        XCTAssertEqual(try foldered().encoded(), data, "the same show gives the same bytes")
        XCTAssertEqual(decoded.list.folders.pathText(of: decoded.list.folderID(ofScene: ShowFixtures.sceneID(1))), "A / B / C")
        XCTAssertNotNil(decoded.list.folders.folder(Self.fid(4)), "an empty folder is kept")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "\"version\":1").count, 2, "version stays 1")
    }

    func testAssignmentsOfScenesNoCueShowsAreNotWritten() throws {
        var list = try foldered()
        try list.remove(ShowFixtures.uuid(1))   // scene 1's only cue
        let decoded = try ShowCueList.decode(list.encoded())
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertNil(decoded.list.folders.assignments[ShowFixtures.sceneID(1)])
        XCTAssertEqual(decoded.list.folderID(ofScene: ShowFixtures.sceneID(2)), Self.fid(1))
    }

    func testDamagedFolderDataIsRepairedWithWarningsNeverRefused() throws {
        let f = { (n: Int) -> String in Self.fid(n).uuidString }
        let folders = """
        [{"id":"\(f(1))","name":"A","parent":null},\
        {"id":"\(f(2))","name":"Orphan","parent":"\(f(99))"},\
        {"id":"\(f(3))","name":"Loop1","parent":"\(f(4))"},{"id":"\(f(4))","name":"Loop2","parent":"\(f(3))"},\
        {"id":"\(f(5))","name":"a","parent":null},\
        {"id":"not-a-uuid","name":"Bad","parent":null},\
        {"id":"\(f(6))","name":"Child","parent":"\(f(1))"}]
        """
        let assignments = """
        {"\(ShowFixtures.sceneID(1))":"\(f(6))","\(ShowFixtures.sceneID(2))":"\(f(2))","\(ShowFixtures.sceneID(7))":"\(f(1))"}
        """
        var text = String(decoding: try ShowFixtures.fiveCues().encoded(), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"format\":", with: "\"folders\":\(folders),\"sceneFolders\":\(assignments),\"format\":")
        let result = try ShowCueList.decode(Data(text.utf8))
        XCTAssertEqual(result.list.cues.count, 5, "the show loads")
        XCTAssertEqual(Set(result.list.folders.folders.keys), [Self.fid(1), Self.fid(6)], "child listed after its parent is accepted")
        XCTAssertEqual(result.warnings, [.droppedFolders(5), .droppedFolderAssignments(2)])
        XCTAssertEqual(result.list.folderID(ofScene: ShowFixtures.sceneID(1)), Self.fid(6))
        XCTAssertNil(result.list.folderID(ofScene: ShowFixtures.sceneID(2)), "an unknown folder means the top level")
    }

    func testAStoreReloadKeepsFoldersAndSceneFilesAreUnchangedByAMove() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShowFolderDocumentTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = ShowStore(directory: folder)
        for n in 1...5 {
            try store.saveScene(SceneDocument(id: ShowFixtures.sceneID(n), name: "Scene \(n)",
                                              layers: [SceneLayer(instance: 1, content: .linearSpectrum)]))
        }
        var list = try foldered()
        try store.save(list)
        let before = try (1...5).map { (n: Int) -> Data in try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(n))) }
        try list.moveScene(ShowFixtures.sceneID(1), to: Self.fid(4))
        try store.save(list)
        let after = try (1...5).map { (n: Int) -> Data in try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(n))) }
        XCTAssertEqual(after, before, "a move never writes a scene file")
        let loaded = store.load()
        XCTAssertNil(loaded.refusal)
        XCTAssertEqual(loaded.list, list)
        XCTAssertEqual(loaded.list.folderID(ofScene: ShowFixtures.sceneID(1)), Self.fid(4))
        XCTAssertEqual(try store.scene(ShowFixtures.sceneID(1)).document.id, ShowFixtures.sceneID(1))

        // FILE-004: an imported scene lands at the top level; the existing folders stay.
        let incoming = SceneDocument(id: ShowFixtures.sceneID(9), name: "Scene 9", layers: [SceneLayer(instance: 1, content: .circularSpectrum)])
        let plan = store.planSceneImport([incoming])
        guard case let .installed(imported, _) = store.installImportedScenes([incoming], plan: plan) else { return XCTFail("installed") }
        XCTAssertEqual(imported.folders, loaded.list.folders)
        XCTAssertNil(imported.folderID(ofScene: ShowFixtures.sceneID(9)))
        XCTAssertEqual(store.load().list.folderID(ofScene: ShowFixtures.sceneID(1)), Self.fid(4))
    }

    func testMovingASceneThatNoCueShowsIsRefused() throws {
        var list = try foldered()
        XCTAssertThrowsError(try list.moveScene(ShowFixtures.sceneID(42), to: nil)) { (error: any Error) in
            XCTAssertEqual(error as? SceneFolderError, .sceneNotInShow(ShowFixtures.sceneID(42)))
        }
    }
}
