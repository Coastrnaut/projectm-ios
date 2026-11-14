// PresetThumbnailInvalidationTests.swift — roadmap PRE-002 (specs/144-pre-002-thumbnail-invalidation):
// the acceptance "changed preset invalidates exactly its thumbnail and not neighbors" through a
// counting renderer (S1), removal and the launch collection (S2), the renderer v1 → v2 fixture (S3),
// rename (S4), and requests racing an invalidation (R5). The cache's pause is injected; no clock waits.
import Foundation
import XCTest
@testable import PresetLibrary

/// Counts renders per preset ID and returns fake PNG bytes; with `gated` each render waits for `release()`.
private actor CountingRenderer: PresetThumbnailRendering {
    private(set) var rendered: [String] = []
    var failing: Set<String> = []
    private let gated: Bool
    private var gates: [CheckedContinuation<Void, Never>] = []

    init(gated: Bool = false) { self.gated = gated }

    func render(_ contents: Data, spec: PresetThumbnailSpec) async throws -> Data {
        let id = String(decoding: contents, as: UTF8.self)
        rendered.append(id)
        if gated { await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in gates.append(gate) } }
        if failing.contains(id) { throw NSError(domain: "engine", code: 1) }
        return Data("PNG:\(id):\(spec.rendererVersion)".utf8)
    }

    func count(_ id: String) -> Int { rendered.filter { $0 == id }.count }
    func setFailing(_ ids: Set<String>) { failing = ids }
    var waiting: Int { gates.count }

    func release() {
        let open = gates
        gates.removeAll()
        open.forEach { $0.resume() }
    }
}

final class PresetThumbnailInvalidationTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PresetThumbnailInvalidationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func key(_ name: String, hash: String? = nil, version: Int = 1) -> PresetThumbnailKey {
        PresetThumbnailKey(presetID: "fixture/\(name).milk", contentHash: hash ?? "hash\(name)", rendererVersion: version)
    }

    private func makeCache(_ renderer: CountingRenderer, spec: PresetThumbnailSpec = .standard) -> PresetThumbnailCache {
        PresetThumbnailCache(directory: folder, renderer: renderer, spec: spec, sleep: { _ in })
    }

    private func contents(_ key: PresetThumbnailKey) -> PresetThumbnailCache.ContentsLoader {
        let id = key.presetID
        return { Data(id.utf8) }
    }

    @discardableResult
    private func browse(_ cache: PresetThumbnailCache, _ keys: [PresetThumbnailKey]) async throws -> [URL] {
        var urls: [URL] = []
        for key in keys { urls.append(try await cache.thumbnail(for: key, contents: contents(key))) }
        return urls
    }

    private func pngFiles() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") })
    }

    private func modified(_ key: PresetThumbnailKey) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(key.fileName).path)
        return try XCTUnwrap(attributes[.modificationDate] as? Date)
    }

    private func storedIndex() throws -> PresetThumbnailIndex {
        try JSONDecoder().decode(PresetThumbnailIndex.self, from: Data(contentsOf: folder.appendingPathComponent(PresetThumbnailIndex.fileName)))
    }

    /// Polls (bounded) until `condition` holds; not a timing assertion.
    private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("condition never held")
    }

    // MARK: - Acceptance (S1)

    func testAChangedPresetInvalidatesExactlyItsThumbnailAndNotItsNeighbors() async throws {
        let renderer = CountingRenderer()
        let cache = makeCache(renderer)
        let a = key("A"), b = key("B"), c = key("C")
        let first = try await browse(cache, [a, b, c])
        let datesBefore = [try modified(a), try modified(c)]

        let changedB = key("B", hash: "hashB2")
        let removed = await cache.invalidate(presetID: b.presetID, keepingContentHash: changedB.contentHash)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(b.fileName).path), "B's old file is gone")

        let second = try await browse(cache, [a, changedB, c])
        let countB = await renderer.count(b.presetID)
        let countA = await renderer.count(a.presetID)
        let countC = await renderer.count(c.presetID)
        XCTAssertEqual(countB, 2, "B is drawn again once")
        XCTAssertEqual(countA, 1, "A is not drawn again")
        XCTAssertEqual(countC, 1, "C is not drawn again")
        XCTAssertEqual(second[0], first[0], "A keeps its ID and file")
        XCTAssertEqual(second[2], first[2], "C keeps its ID and file")
        XCTAssertNotEqual(second[1], first[1], "B has a new ID")
        XCTAssertEqual([try modified(a), try modified(c)], datesBefore, "neighbors' files untouched")
        XCTAssertEqual(try pngFiles(), Set([a, changedB, c].map(\.fileName)))
        XCTAssertEqual(Set(try storedIndex().entries.keys), Set([a, changedB, c].map(\.stableID)))
    }

    // MARK: - Rename (S4) and no-op (R10)

    func testARenameWithTheSameContentKeepsTheThumbnailAndWritesNothing() async throws {
        let renderer = CountingRenderer()
        let cache = makeCache(renderer)
        let a = key("A")
        let first = try await browse(cache, [a])
        let indexURL = folder.appendingPathComponent(PresetThumbnailIndex.fileName)
        let indexDate = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: indexURL.path)[.modificationDate] as? Date)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: indexURL.path)

        let removed = await cache.invalidate(presetID: a.presetID, keepingContentHash: a.contentHash)   // renamed only
        XCTAssertEqual(removed, 0)
        let none = await cache.invalidate(presetID: "fixture/Never.milk", keepingContentHash: nil)
        XCTAssertEqual(none, 0)
        let after = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: indexURL.path)[.modificationDate] as? Date)
        XCTAssertEqual(after, Date(timeIntervalSince1970: 1_000), "nothing found, nothing written")
        XCTAssertNotEqual(indexDate, after)

        let second = try await browse(cache, [a])
        XCTAssertEqual(second, first)
        let count = await renderer.count(a.presetID)
        XCTAssertEqual(count, 1)
    }

    // MARK: - Removal and launch collection (S2, R7)

    func testRemovingOnePresetRemovesExactlyItsThumbnail() async throws {
        let cache = makeCache(CountingRenderer())
        let keys = [key("A"), key("B"), key("C")]
        try await browse(cache, keys)
        let removed = await cache.invalidate(presetID: keys[1].presetID, keepingContentHash: nil)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try pngFiles(), Set([keys[0], keys[2]].map(\.fileName)))
        let entries = await cache.entryCount
        XCTAssertEqual(entries, 2)

        let relaunched = makeCache(CountingRenderer())   // the removal was saved
        let reopened = await relaunched.entryCount
        XCTAssertEqual(reopened, 2)
    }

    func testTheLaunchCollectionDropsUnlistedAndChangedPresetsOnly() async throws {
        let cache = makeCache(CountingRenderer())
        let keys = [key("A"), key("B"), key("C")]
        try await browse(cache, keys)
        let listing = [keys[0].presetID: keys[0].contentHash, keys[1].presetID: "hashB2"]   // B changed, C gone
        let removed = await cache.retainOnly(listing)
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(try pngFiles(), [keys[0].fileName])
        XCTAssertEqual(Set(try storedIndex().entries.keys), [keys[0].stableID])
        let again = await cache.retainOnly(listing)
        XCTAssertEqual(again, 0)
    }

    // MARK: - Renderer version (S3, fixture migration v1 → v2)

    func testARendererVersionBumpMakesEveryEntryStaleAndRendersOnRequest() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "index-renderer-v1", withExtension: "json", subdirectory: "ThumbnailFixtures"))
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(PresetThumbnailIndex.fileName))
        for name in ["A", "B"] { try Data("v1".utf8).write(to: folder.appendingPathComponent(key(name).fileName)) }
        let v1 = makeCache(CountingRenderer())
        let v1Entries = await v1.entryCount
        XCTAssertEqual(v1Entries, 2, "the fixture is valid at version 1")

        var spec = PresetThumbnailSpec.standard
        spec.rendererVersion = 2
        let renderer = CountingRenderer()
        let v2 = makeCache(renderer, spec: spec)
        let entries = await v2.entryCount
        let repair = await v2.lastRepair
        XCTAssertEqual(entries, 0)
        XCTAssertEqual(repair, .dropped(entries: 2, files: 2))
        XCTAssertEqual(try pngFiles(), [], "every v1 file is gone")
        let urls = try await browse(v2, [key("A", version: 2), key("B", version: 2)])
        let rendered = await renderer.rendered.count
        XCTAssertEqual(rendered, 2, "each preset renders once")
        XCTAssertEqual(String(decoding: try Data(contentsOf: urls[0]), as: UTF8.self), "PNG:fixture/A.milk:2")
        XCTAssertEqual(try storedIndex().rendererVersion, 2)
    }

    // MARK: - Races (R5) and failures (R10)

    func testAQueuedStaleRequestIsCancelledAndARunningStaleRenderIsNotStored() async throws {
        let renderer = CountingRenderer(gated: true)
        let cache = makeCache(renderer)
        let a = key("A"), b = key("B")
        let loadA = contents(a), loadB = contents(b)
        let running = Task { try await cache.thumbnail(for: a, contents: loadA) }
        try await eventually { await renderer.waiting == 1 }
        let queued = Task { try await cache.thumbnail(for: b, contents: loadB) }
        try await eventually { await cache.pendingCount == 1 }

        await cache.invalidate(presetID: b.presetID, keepingContentHash: "hashB2")
        await cache.invalidate(presetID: a.presetID, keepingContentHash: "hashA2")
        let pending = await cache.pendingCount
        XCTAssertEqual(pending, 0)
        do {
            _ = try await queued.value
            XCTFail("the queued stale request is cancelled")
        } catch is CancellationError {}
        await renderer.release()
        do {
            _ = try await running.value
            XCTFail("the running stale render is not stored")
        } catch let error as PresetThumbnailError {
            guard case .unavailable = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try pngFiles(), [])
        let entries = await cache.entryCount
        let failures = await cache.failureCount
        XCTAssertEqual(entries, 0)
        XCTAssertEqual(failures, 0, "unavailable is not remembered")
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, [a.presetID], "B was never drawn")
    }

    func testARememberedFailureOfTheOldContentIsForgotten() async throws {
        let renderer = CountingRenderer()
        let cache = makeCache(renderer)
        let a = key("A"), b = key("B")
        await renderer.setFailing([a.presetID, b.presetID])
        _ = try? await browse(cache, [a])
        _ = try? await browse(cache, [b])
        let before = await cache.failureCount
        XCTAssertEqual(before, 2)
        await cache.invalidate(presetID: a.presetID, keepingContentHash: "hashA2")
        let after = await cache.failureCount
        XCTAssertEqual(after, 1, "only A's failure is forgotten")
    }
}
