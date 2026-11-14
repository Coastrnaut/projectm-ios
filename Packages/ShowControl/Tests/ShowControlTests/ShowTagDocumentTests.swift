// ShowTagDocumentTests.swift — SCN-005-T06: the `sceneTags` key of show.json (spec SCN-005-R6 to R8;
// research SCN-005-D4, D5; contract T1, T2): round trip, determinism, byte-identical legacy encoding,
// damaged data repaired with a warning, a store reload, and FILE-004's import keeping the tags.
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class ShowTagDocumentTests: XCTestCase {
    private func tagged() throws -> ShowCueList {
        var list = try ShowFixtures.fiveCues()
        try list.addTag("Intro", toScene: ShowFixtures.sceneID(1))
        try list.addTag("Loud", toScene: ShowFixtures.sceneID(1))
        try list.addTag("intro", toScene: ShowFixtures.sceneID(5))
        return list
    }

    func testAShowWithoutTagsKeepsItsBytes() throws {
        let plain = try ShowFixtures.fiveCues()
        let data = plain.encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("sceneTags"), "no key without tags")
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertTrue(decoded.list.tags.isEmpty)
        XCTAssertEqual(decoded.list.encoded(), data, "byte-identical")
        var emptied = try tagged()
        for scene in [1, 5] {
            for tag in emptied.tags(ofScene: ShowFixtures.sceneID(scene)) { try emptied.removeTag(tag, fromScene: ShowFixtures.sceneID(scene)) }
        }
        XCTAssertEqual(emptied.encoded(), data, "removing every tag gives the original bytes")
    }

    func testTagsRoundTripDeterministically() throws {
        let list = try tagged()
        let data = list.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"sceneTags\":{\"\(ShowFixtures.sceneID(1))\":[\"Intro\",\"Loud\"],\"\(ShowFixtures.sceneID(5))\":[\"Intro\"]}"), text)
        XCTAssertEqual(text.components(separatedBy: "\"version\":1").count, 2, "version stays 1")
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list, list)
        XCTAssertEqual(decoded.list.encoded(), data, "decode → encode is byte-identical")
        XCTAssertEqual(try tagged().encoded(), data, "the same show gives the same bytes")
    }

    func testTagsOfScenesNoCueShowsAreNotWritten() throws {
        var list = try tagged()
        try list.remove(ShowFixtures.uuid(1))   // scene 1's only cue
        XCTAssertEqual(list.tagVocabulary, ["Intro"], "Loud left with the scene")
        let decoded = try ShowCueList.decode(list.encoded())
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertNil(decoded.list.tags.tags[ShowFixtures.sceneID(1)])
        XCTAssertEqual(decoded.list.tags(ofScene: ShowFixtures.sceneID(5)), ["Intro"])
    }

    func testDamagedTagDataIsRepairedWithAWarningNeverRefused() throws {
        let s = { (n: Int) -> String in ShowFixtures.sceneID(n) }
        let tooMany = (1...17).map { (n: Int) -> String in "\"t\(String(format: "%02d", n))\"" }.joined(separator: ",")
        let tags = """
        {"\(s(1))":["Intro"," padded ","","intro","Loud"],"\(s(2))":[\(tooMany)],"\(s(3))":"not a list",\
        "\(s(4))":[],"\(s(9))":["Ghost","Ghost2"],"\(s(5))":[1,2]}
        """
        var text = String(decoding: try ShowFixtures.fiveCues().encoded(), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"format\":", with: "\"sceneTags\":\(tags),\"format\":")
        let result = try ShowCueList.decode(Data(text.utf8))
        XCTAssertEqual(result.list.cues.count, 5, "the show loads")
        XCTAssertEqual(result.list.tags(ofScene: s(1)), ["Intro", "Loud"])
        XCTAssertEqual(result.list.tags(ofScene: s(2)).count, 16, "the first 16 are kept")
        XCTAssertEqual(result.list.tags(ofScene: s(3)), [])
        // s1: padded, empty, duplicate (3); s2: one over (1); s3: not a list (1); s4: empty (1);
        // s9: unknown scene (2); s5: numbers, not a list of strings (1).
        XCTAssertEqual(result.warnings, [.droppedTags(9)])

        var notObject = String(decoding: try ShowFixtures.fiveCues().encoded(), as: UTF8.self)
        notObject = notObject.replacingOccurrences(of: "\"format\":", with: "\"sceneTags\":[\"x\"],\"format\":")
        let second = try ShowCueList.decode(Data(notObject.utf8))
        XCTAssertEqual(second.warnings, [.droppedTags(1)])
        XCTAssertTrue(second.list.tags.isEmpty)
        XCTAssertEqual(second.list.encoded(), try ShowFixtures.fiveCues().encoded(), "rewritten without the damaged key")
    }

    func testAStoreReloadKeepsTagsAndImportKeepsThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShowTagDocumentTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = ShowStore(directory: folder)
        for n in 1...5 {
            try store.saveScene(SceneDocument(id: ShowFixtures.sceneID(n), name: "Scene \(n)",
                                              layers: [SceneLayer(instance: 1, content: .linearSpectrum)]))
        }
        let sceneBytes = try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(1)))
        let list = try tagged()
        try store.save(list)
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(1))), sceneBytes, "tagging never writes a scene file")
        let loaded = store.load()
        XCTAssertNil(loaded.refusal)
        XCTAssertEqual(loaded.list.tags, list.tags)

        // FILE-004 (and merge restore): existing tags stay; the incoming scene arrives untagged.
        let incoming = SceneDocument(id: ShowFixtures.sceneID(9), name: "Scene 9", layers: [SceneLayer(instance: 1, content: .circularSpectrum)])
        let plan = store.planSceneImport([incoming])
        guard case let .installed(imported, _) = store.installImportedScenes([incoming], plan: plan) else { return XCTFail("installed") }
        XCTAssertEqual(imported.tags, list.tags)
        XCTAssertEqual(imported.tags(ofScene: ShowFixtures.sceneID(9)), [])
        XCTAssertEqual(store.load().list.tags(ofScene: ShowFixtures.sceneID(1)), ["Intro", "Loud"])
    }

    func testTaggingASceneThatNoCueShowsIsRefused() throws {
        var list = try tagged()
        XCTAssertThrowsError(try list.addTag("X", toScene: ShowFixtures.sceneID(42))) { (error: any Error) in
            XCTAssertEqual(error as? SceneTagError, .sceneNotInShow(ShowFixtures.sceneID(42)))
        }
    }
}
