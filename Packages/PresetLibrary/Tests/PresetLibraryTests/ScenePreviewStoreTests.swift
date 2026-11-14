// ScenePreviewStoreTests.swift — roadmap SCN-006-T03 (specs/153-scn-006-scene-preview; contract P1):
// the scene preview store over PRE-001's index. Keys follow the file's bytes, a store keeps one entry
// per scene, invalidation and the launch collection touch only the stale scene, reopening keeps
// everything (relaunch), and damage is repaired. Fake PNG bytes; no clock.
import Foundation
import XCTest
@testable import PresetLibrary

final class ScenePreviewStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScenePreviewStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func key(_ scene: String, _ bytes: String) -> ScenePreviewKey {
        ScenePreviewKey(sceneID: scene, contentHash: ScenePreviewKey.contentHash(of: Data(bytes.utf8)))
    }

    private func png(_ text: String) -> Data { Data("PNG:\(text)".utf8) }

    private var pictureFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
    }

    func testKeyFollowsTheFileBytesAndIsStable() {
        let a = key("S", "{\"name\":\"A\"}")
        XCTAssertEqual(a, key("S", "{\"name\":\"A\"}"))
        XCTAssertEqual(a.stableID, key("S", "{\"name\":\"A\"}").stableID)
        XCTAssertEqual(a.contentHash.count, 64)
        XCTAssertNotEqual(a.stableID, key("S", "{\"name\":\"B\"}").stableID, "an edited file names another picture")
        XCTAssertNotEqual(a.stableID, key("T", "{\"name\":\"A\"}").stableID, "another scene names another picture")
        XCTAssertNotEqual(a.stableID, ScenePreviewKey(sceneID: "S", contentHash: a.contentHash, formatVersion: 2).stableID)
        XCTAssertEqual(a.fileName, a.stableID + ".png")
    }

    func testStoreKeepsOnePicturePerSceneAndLeavesNeighbours() async throws {
        let store = ScenePreviewStore(directory: folder)
        let s1 = key("S", "v1"), s2 = key("S", "v2"), t = key("T", "t1")
        let url = try await store.store(png("s1"), for: s1)
        try await store.store(png("t"), for: t)
        XCTAssertEqual(try Data(contentsOf: url), png("s1"))
        let tURL = await store.cachedURL(for: t)
        try await store.store(png("s2"), for: s2)
        let s1URL = await store.cachedURL(for: s1)
        XCTAssertNil(s1URL, "the old content's picture is gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let s2URL = await store.cachedURL(for: s2)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(s2URL)), png("s2"))
        let tNow = await store.cachedURL(for: t)
        XCTAssertEqual(tNow, tURL)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(tNow)), png("t"))
        let count = await store.entryCount
        XCTAssertEqual(count, 2)
        XCTAssertEqual(pictureFiles.count, 2)
        #if canImport(Darwin)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        #endif
    }

    func testInvalidateRemovesOnlyTheChangedScene() async throws {
        let store = ScenePreviewStore(directory: folder)
        try await store.store(png("s"), for: key("S", "v1"))
        try await store.store(png("t"), for: key("T", "t1"))
        let kept = await store.invalidate(sceneID: "S", keepingContentHash: key("S", "v1").contentHash)
        XCTAssertEqual(kept, 0, "the current content keeps its picture")
        let removed = await store.invalidate(sceneID: "S", keepingContentHash: key("S", "v2").contentHash)
        XCTAssertEqual(removed, 1)
        let s = await store.hasPreview(for: key("S", "v1"))
        let t = await store.hasPreview(for: key("T", "t1"))
        XCTAssertFalse(s)
        XCTAssertTrue(t)
        XCTAssertEqual(pictureFiles.count, 1)
    }

    func testRetainOnlyPrunesRemovedAndChangedScenesAndReopenKeepsTheRest() async throws {
        let store = ScenePreviewStore(directory: folder)
        try await store.store(png("s"), for: key("S", "v1"))
        try await store.store(png("t"), for: key("T", "t1"))
        try await store.store(png("u"), for: key("U", "u1"))
        let removed = await store.retainOnly(["S": key("S", "v1").contentHash, "T": key("T", "t2").contentHash])
        XCTAssertEqual(removed, 2, "U left the show and T's file changed")
        XCTAssertEqual(pictureFiles.count, 1)

        let reopened = ScenePreviewStore(directory: folder)   // relaunch
        let repair = await reopened.lastRepair
        XCTAssertEqual(repair, .none)
        let url = await reopened.cachedURL(for: key("S", "v1"))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(url)), png("s"))
        let entries = await reopened.entries(forScene: "S")
        XCTAssertEqual(entries.map(\.width), [ScenePreviewStore.width])
    }

    func testDamagedIndexAndClearedFolderAreRepaired() async throws {
        let store = ScenePreviewStore(directory: folder)
        try await store.store(png("s"), for: key("S", "v1"))
        try Data("not json".utf8).write(to: folder.appendingPathComponent(PresetThumbnailIndex.fileName))
        let reopened = ScenePreviewStore(directory: folder)
        let repair = await reopened.lastRepair
        XCTAssertEqual(repair, .unreadable)
        XCTAssertEqual(pictureFiles, [], "an untrusted index discards its pictures")

        try FileManager.default.removeItem(at: folder)   // Clear Caches
        let missing = await reopened.cachedURL(for: key("S", "v1"))
        XCTAssertNil(missing)
        try await reopened.store(png("again"), for: key("S", "v1"))
        let back = await reopened.hasPreview(for: key("S", "v1"))
        XCTAssertTrue(back, "the folder is recreated")
    }
}
