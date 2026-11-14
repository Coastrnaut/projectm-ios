// PresetThumbnailCacheTests.swift — roadmap PRE-001 (specs/132-pre-001-thumbnail-cache): the
// acceptance "first browse creates thumbnails; second browse uses cache with stable IDs" through a
// counting renderer, the relaunch, the migration fixtures (ThumbnailFixtures/), cancellation, the
// queue bound and order, failures, and determinism. The cache's pause is injected (no clock waits).
import Foundation
import XCTest
@testable import PresetLibrary

/// Counts renders and returns fake PNG bytes; a preset ID listed in `unavailable` or `failing`
/// throws; with `gated` each render waits for `release()`.
private actor FakeThumbnailRenderer: PresetThumbnailRendering {
    private(set) var rendered: [String] = []
    var unavailable: Set<String> = []
    var failing: Set<String> = []
    private let gated: Bool
    private var gates: [CheckedContinuation<Void, Never>] = []

    init(gated: Bool = false) { self.gated = gated }

    func render(_ contents: Data, spec: PresetThumbnailSpec) async throws -> Data {
        let id = String(decoding: contents, as: UTF8.self)
        rendered.append(id)
        if gated { await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in gates.append(gate) } }
        if unavailable.contains(id) { throw PresetThumbnailError.unavailable("not now") }
        if failing.contains(id) { throw NSError(domain: "engine", code: 1) }
        return Data("PNG:\(id):\(spec.rendererVersion)".utf8)
    }

    func setUnavailable(_ ids: Set<String>) { unavailable = ids }
    func setFailing(_ ids: Set<String>) { failing = ids }
    var waiting: Int { gates.count }

    func release() {
        let open = gates
        gates.removeAll()
        open.forEach { $0.resume() }
    }
}

final class PresetThumbnailCacheTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PresetThumbnailCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func key(_ name: String, hash: String? = nil, version: Int = 1) -> PresetThumbnailKey {
        PresetThumbnailKey(presetID: "fixture/\(name).milk", contentHash: hash ?? "hash\(name)", rendererVersion: version)
    }

    private func makeCache(_ renderer: FakeThumbnailRenderer, maxPending: Int = 32) -> PresetThumbnailCache {
        PresetThumbnailCache(directory: folder, renderer: renderer, maxPending: maxPending, sleep: { _ in })
    }

    /// The contents loader the app would pass: here the preset ID, so the fake knows which it draws.
    private func contents(_ key: PresetThumbnailKey) -> PresetThumbnailCache.ContentsLoader {
        let id = key.presetID
        return { Data(id.utf8) }
    }

    private func browse(_ cache: PresetThumbnailCache, _ keys: [PresetThumbnailKey]) async throws -> [URL] {
        var urls: [URL] = []
        for key in keys { urls.append(try await cache.thumbnail(for: key, contents: contents(key))) }
        return urls
    }

    /// Polls (bounded) until `condition` holds; not a timing assertion.
    private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("condition never held")
    }

    private func copyFixture(_ name: String) throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "ThumbnailFixtures"))
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(PresetThumbnailIndex.fileName))
    }

    private func touch(_ key: PresetThumbnailKey) throws {
        try Data("old".utf8).write(to: folder.appendingPathComponent(key.fileName))
    }

    private func pngFiles() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") })
    }

    // MARK: - Acceptance (PRE-001-S1, S2)

    func testFirstBrowseCreatesThumbnailsSecondBrowseUsesTheCacheWithStableIDs() async throws {
        let renderer = FakeThumbnailRenderer()
        let cache = makeCache(renderer)
        let keys = ["A", "B", "C", "D", "E"].map { key($0) }

        let first = try await browse(cache, keys)
        let renderedFirst = await renderer.rendered.count
        XCTAssertEqual(renderedFirst, keys.count, "first browse renders every preset once")
        XCTAssertEqual(first.map(\.lastPathComponent), keys.map(\.fileName))
        XCTAssertEqual(try pngFiles(), Set(keys.map(\.fileName)))

        let second = try await browse(cache, keys)
        let renderedTotal = await renderer.rendered.count
        XCTAssertEqual(renderedTotal, keys.count, "second browse renders nothing")
        XCTAssertEqual(second, first, "same IDs and files")
        let cacheCount = await cache.renderCount
        XCTAssertEqual(cacheCount, keys.count)
    }

    func testTheIndexSurvivesARelaunch() async throws {
        let keys = ["A", "B", "C"].map { key($0) }
        let first = try await browse(makeCache(FakeThumbnailRenderer()), keys)

        let renderer = FakeThumbnailRenderer()
        let relaunched = makeCache(renderer)
        let second = try await browse(relaunched, keys)
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, [], "after a relaunch nothing renders again")
        XCTAssertEqual(second, first)
        let repair = await relaunched.lastRepair
        XCTAssertEqual(repair, .none)
        let stored = try JSONDecoder().decode(PresetThumbnailIndex.self,
                                              from: Data(contentsOf: folder.appendingPathComponent(PresetThumbnailIndex.fileName)))
        XCTAssertEqual(Set(stored.entries.keys), Set(keys.map(\.stableID)))
        XCTAssertEqual(stored.schemaVersion, 1)
    }

    // MARK: - Stable IDs and determinism (S6)

    func testStableIDsAndSyntheticAudioAreDeterministic() {
        XCTAssertEqual(key("A").stableID, key("A").stableID)
        XCTAssertEqual(key("A").stableID, "21cd8f60f83c92fb2d2f40e48b21925e", "SHA-256 of id, hash and version")
        XCTAssertEqual(key("A").stableID.count, 32)
        XCTAssertNotEqual(key("A").stableID, key("A", hash: "changed").stableID, "a changed preset is a new picture")
        XCTAssertNotEqual(key("A").stableID, key("A", version: 2).stableID, "a new renderer is a new picture")
        let preset = IndexedPreset(id: "fixture/A.milk", name: "A", author: "", source: "included", folder: [], path: "A.milk", hash: "hashA")
        XCTAssertEqual(PresetThumbnailKey(preset: preset), key("A"))

        let spec = PresetThumbnailSpec.standard
        let audio = SyntheticPCM.frames(spec)
        XCTAssertEqual(audio, SyntheticPCM.frames(spec))
        XCTAssertEqual(audio.count, 45)
        XCTAssertEqual(audio[0].count, 735 * 2)
        XCTAssertTrue(audio.allSatisfy { block in block.allSatisfy { abs($0) <= 1 } })
        XCTAssertGreaterThan(audio[0].map { abs($0) }.max() ?? 0, 0.3, "audible")
        var other = spec
        other.seed = 7
        XCTAssertNotEqual(SyntheticPCM.frames(other), audio, "the seed matters")
    }

    // MARK: - Concurrency, cancellation, bound (R3, R6, S4)

    func testTheSamePresetRequestedTwiceAtOnceRendersOnce() async throws {
        let renderer = FakeThumbnailRenderer(gated: true)
        let cache = makeCache(renderer)
        let a = key("A")
        let loader = contents(a)
        async let first = cache.thumbnail(for: a, contents: loader)
        async let second = cache.thumbnail(for: a, contents: loader)
        try await eventually { await renderer.waiting == 1 }
        await renderer.release()
        let urls = try await [first, second]
        XCTAssertEqual(urls[0], urls[1])
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, [a.presetID])
    }

    func testARequestCancelledBeforeItsRenderRendersNothing() async throws {
        let renderer = FakeThumbnailRenderer(gated: true)
        let cache = makeCache(renderer)
        let a = key("A"), b = key("B")
        let loaderA = contents(a), loaderB = contents(b)
        let busy = Task { try await cache.thumbnail(for: a, contents: loaderA) }
        try await eventually { await renderer.waiting == 1 }
        let scrolledAway = Task { try await cache.thumbnail(for: b, contents: loaderB) }
        try await eventually { await cache.pendingCount == 1 }
        scrolledAway.cancel()
        do {
            _ = try await scrolledAway.value
            XCTFail("expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        let pending = await cache.pendingCount
        XCTAssertEqual(pending, 0, "a request left without waiters leaves the queue")
        await renderer.release()
        _ = try await busy.value
        try await Task.sleep(for: .milliseconds(20))
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, [a.presetID], "B was never rendered")
        let cached = await cache.cachedURL(for: b)
        XCTAssertNil(cached)
    }

    func testTheQueueIsBoundedAndServesTheNewestFirst() async throws {
        let renderer = FakeThumbnailRenderer(gated: true)
        let cache = makeCache(renderer, maxPending: 2)
        let keys = ["A", "B", "C", "D"].map { key($0) }
        let loaders = keys.map { contents($0) }
        let a = Task { try await cache.thumbnail(for: keys[0], contents: loaders[0]) }
        try await eventually { await renderer.waiting == 1 }
        var waiting: [Task<URL, any Error>] = []
        for index in 1...3 {
            waiting.append(Task { try await cache.thumbnail(for: keys[index], contents: loaders[index]) })
            try await eventually { await cache.pendingCount == min(index, 2) }
        }
        do {
            _ = try await waiting[0].value
            XCTFail("B should have been dropped")
        } catch {
            XCTAssertEqual(error as? PresetThumbnailError, .dropped)
        }
        await renderer.release()   // A done; D (newest) starts
        try await eventually { await renderer.waiting == 1 }
        await renderer.release()   // D done; C starts
        try await eventually { await renderer.waiting == 1 }
        await renderer.release()   // C done
        _ = try await a.value
        _ = try await waiting[1].value
        _ = try await waiting[2].value
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, ["A", "D", "C"].map { key($0).presetID }, "the newest waiting request first; B dropped")
    }

    // MARK: - Failures (R11)

    func testUnavailableIsForgottenButAFailureIsRememberedForTheSession() async throws {
        let renderer = FakeThumbnailRenderer()
        let cache = makeCache(renderer)
        let a = key("A"), b = key("B")
        await renderer.setUnavailable([a.presetID])
        await renderer.setFailing([b.presetID])
        do { _ = try await cache.thumbnail(for: a, contents: contents(a)); XCTFail() } catch {
            guard case .unavailable = error as? PresetThumbnailError else { return XCTFail("\(error)") }
        }
        do { _ = try await cache.thumbnail(for: b, contents: contents(b)); XCTFail() } catch {
            guard case .failed = error as? PresetThumbnailError else { return XCTFail("\(error)") }
        }
        await renderer.setUnavailable([])
        await renderer.setFailing([])
        _ = try await cache.thumbnail(for: a, contents: contents(a))
        do { _ = try await cache.thumbnail(for: b, contents: contents(b)); XCTFail() } catch {
            guard case .failed = error as? PresetThumbnailError else { return XCTFail("\(error)") }
        }
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, [a.presetID, b.presetID, a.presetID], "B is not retried in this session")
        let failures = await cache.failureCount
        XCTAssertEqual(failures, 1)
        let stored = try String(contentsOf: folder.appendingPathComponent(PresetThumbnailIndex.fileName), encoding: .utf8)
        XCTAssertFalse(stored.contains("fixture/B.milk"), "failures are never written")
    }

    // MARK: - Migration fixtures (R8, S3)

    func testAnIndexFromAnOlderRendererVersionIsDroppedWithItsFiles() async throws {
        try copyFixture("index-renderer-v0")
        try touch(key("A", version: 0))
        try touch(key("B", version: 0))
        let renderer = FakeThumbnailRenderer()
        let cache = makeCache(renderer)
        let entries = await cache.entryCount
        XCTAssertEqual(entries, 0)
        let repair = await cache.lastRepair
        XCTAssertEqual(repair, .dropped(entries: 2, files: 2))
        XCTAssertEqual(try pngFiles(), [])
        _ = try await browse(cache, [key("A"), key("B")])
        let rendered = await renderer.rendered.count
        XCTAssertEqual(rendered, 2)
    }

    func testAnIndexFromANewerSchemaIsDiscarded() async throws {
        try copyFixture("index-schema-v99")
        try touch(key("A"))
        let renderer = FakeThumbnailRenderer()
        let cache = makeCache(renderer)
        let repair = await cache.lastRepair
        let entries = await cache.entryCount
        XCTAssertEqual(entries, 0)
        XCTAssertEqual(repair, .newerSchema(99))
        XCTAssertEqual(try pngFiles(), [])
        _ = try await browse(cache, [key("A")])
        let rendered = await renderer.rendered.count
        XCTAssertEqual(rendered, 1)
    }

    func testACorruptIndexStartsEmptyAndRemovesStaleFiles() async throws {
        try copyFixture("index-corrupt")
        try touch(key("A"))
        try Data("orphan".utf8).write(to: folder.appendingPathComponent("orphan.png"))
        let renderer = FakeThumbnailRenderer()
        let cache = makeCache(renderer)
        let entries = await cache.entryCount
        let repair = await cache.lastRepair
        XCTAssertEqual(entries, 0)
        XCTAssertEqual(repair, .unreadable)
        XCTAssertEqual(try pngFiles(), [])
        _ = try await browse(cache, [key("A")])
        let rendered = await renderer.rendered.count
        XCTAssertEqual(rendered, 1)
        let reopened = makeCache(FakeThumbnailRenderer())
        let reopenedEntries = await reopened.entryCount
        XCTAssertEqual(reopenedEntries, 1, "the rebuilt index is readable")
    }

    func testAnEntryWhoseFileIsMissingIsRegeneratedAlone() async throws {
        try copyFixture("index-missing-file")
        try touch(key("A"))   // B's file is missing
        let renderer = FakeThumbnailRenderer()
        let cache = makeCache(renderer)
        let entries = await cache.entryCount
        let repair = await cache.lastRepair
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(repair, .dropped(entries: 1, files: 0))
        _ = try await browse(cache, [key("A"), key("B")])
        let rendered = await renderer.rendered
        XCTAssertEqual(rendered, [key("B").presetID], "only the preset whose file was missing")
    }

    func testClearingTheFolderWhileOpenRendersAgainAndRecreatesIt() async throws {
        let renderer = FakeThumbnailRenderer()
        let cache = makeCache(renderer)
        _ = try await browse(cache, [key("A")])
        try FileManager.default.removeItem(at: folder)   // FILE-010 Clear Caches
        let url = try await cache.thumbnail(for: key("A"), contents: contents(key("A")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let rendered = await renderer.rendered.count
        XCTAssertEqual(rendered, 2)
    }
}
