// ShowMediaRelinkTests.swift — MED-013-T06 (contract L4; MED-013-S2, S3): media usage across stored scenes
// and the all-or-nothing rewrite of one identifier, with a fault at every step for every scene.
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class ShowMediaRelinkTests: XCTestCase {
    private struct Abort: Error {}

    private var root: URL!
    private let p = "11111111-1111-4111-8111-111111111111"
    private let q = "22222222-2222-4222-8222-222222222222"
    private let v = "44444444-4444-4444-8444-444444444444"
    private let sceneA = "5CE7E000-0000-4000-8000-00000000000A"
    private let sceneB = "5CE7E000-0000-4000-8000-00000000000B"
    private let sceneC = "5CE7E000-0000-4000-8000-00000000000C"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ShowMediaRelink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A uses P as its photo; B uses another photo with P in its slideshow, and video V; C uses neither.
    private func seededStore() throws -> ShowStore {
        let store = ShowStore(directory: root)
        let a = SceneDocument(id: sceneA, name: "A", layers: [SceneLayer(instance: 1, content: .photo(asset: "photo"))],
                              assets: ["photo": .photo(storeID: p)])
        var slides = SceneAsset.photo(storeID: "33333333-3333-4333-8333-333333333333")
        slides.photoSlideshow = SceneSlideshow(enabled: true, storeIDs: [p], mode: "beats", seconds: 5, beats: 8)
        let b = SceneDocument(id: sceneB, name: "B", layers: [SceneLayer(instance: 1, content: .photo(asset: "photo"))],
                              assets: ["photo": slides, "video": .video(storeID: v)])
        let c = SceneDocument(id: sceneC, name: "C", layers: [SceneLayer(instance: 1, content: .circularSpectrum)])
        for document in [a, b, c] { try store.saveScene(document) }
        return store
    }

    private func snapshot() throws -> [String: Data] {
        let folder = root.appendingPathComponent(ShowStore.scenesFolderName)
        var files: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            files[name] = try Data(contentsOf: folder.appendingPathComponent(name))
        }
        return files
    }

    func testUsageListsEachIdentifierWithItsScenes() throws {
        let usage = try seededStore().mediaUsage()
        XCTAssertEqual(usage.scenes[ShowMediaKey(store: .photos, storeID: p)], [sceneA, sceneB])
        XCTAssertEqual(usage.scenes[ShowMediaKey(store: .videos, storeID: v)], [sceneB])
        XCTAssertTrue(usage.unreadableScenes.isEmpty)
    }

    func testRewriteReplacesEveryReferenceAndPersists() throws {
        let store = try seededStore()
        let untouched = try snapshot()[sceneC + ShowStore.sceneFileSuffix]
        let report = try store.rewriteMediaReferences(store: .photos, from: p, to: q)
        XCTAssertEqual(report.scenes, [sceneA, sceneB])
        XCTAssertEqual(report.references, 2)
        let reloaded = ShowStore(directory: root)
        XCTAssertEqual(try reloaded.scene(sceneA).document.mediaIDs(in: .photos), [q])
        XCTAssertEqual(try reloaded.scene(sceneB).document.assets["photo"]?.photoSlideshow?.storeIDs, [q])
        XCTAssertEqual(try reloaded.scene(sceneB).document.mediaIDs(in: .videos), [v])
        XCTAssertNil(reloaded.mediaUsage().scenes[ShowMediaKey(store: .photos, storeID: p)])
        XCTAssertEqual(try snapshot()[sceneC + ShowStore.sceneFileSuffix], untouched, "a scene without P is not written")
        XCTAssertEqual(try snapshot().keys.filter { (n: String) -> Bool in n.contains(".relink") }, [], "no temporary file left")
    }

    func testAFaultAtEveryStepForEverySceneLeavesEveryFileAsItWas() throws {
        for step in ShowMediaRewriteStep.allCases {
            for victim in [sceneA, sceneB] {
                try? FileManager.default.removeItem(at: root)
                let store = try seededStore()
                let before = try snapshot()
                XCTAssertThrowsError(try store.rewriteMediaReferences(store: .photos, from: p, to: q) { (s: ShowMediaRewriteStep, id: String) throws in
                    if s == step && id == victim { throw Abort() }
                }) { (error: Error) in
                    XCTAssertEqual(error as? ShowMediaRewriteError, .failed(step))
                }
                XCTAssertEqual(try snapshot(), before, "fault at \(step) for \(victim == sceneA ? "A" : "B")")
            }
        }
    }

    func testUnreadableScenesAreCountedAndLeftAloneAndLeftoversAreCleaned() throws {
        let store = try seededStore()
        let broken = "5CE7E000-0000-4000-8000-00000000000D"
        let brokenFile = store.sceneFile(broken)
        try Data("{not json".utf8).write(to: brokenFile)
        // A leftover of an interrupted run: a kept original whose scene file is gone goes back.
        let folder = root.appendingPathComponent(ShowStore.scenesFolderName)
        let aFile = store.sceneFile(sceneA)
        let aBytes = try Data(contentsOf: aFile)
        try FileManager.default.moveItem(at: aFile, to: URL(fileURLWithPath: aFile.path + ".relink-old"))
        try Data("x".utf8).write(to: folder.appendingPathComponent(sceneB + ShowStore.sceneFileSuffix + ".relink-new"))
        XCTAssertEqual(store.mediaUsage().unreadableScenes, [broken])
        let report = try store.rewriteMediaReferences(store: .photos, from: p, to: q)
        XCTAssertEqual(report.unreadable, [broken])
        XCTAssertEqual(report.scenes, [sceneA, sceneB], "A was put back first, then rewritten")
        XCTAssertNotEqual(try Data(contentsOf: aFile), aBytes)
        XCTAssertEqual(try Data(contentsOf: brokenFile), Data("{not json".utf8))
        XCTAssertEqual(try snapshot().keys.filter { (n: String) -> Bool in n.contains(".relink") }, [])
        XCTAssertThrowsError(try store.rewriteMediaReferences(store: .photos, from: "nope", to: q))
    }
}
