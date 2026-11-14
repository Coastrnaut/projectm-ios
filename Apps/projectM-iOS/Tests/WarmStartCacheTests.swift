// WarmStartCacheTests.swift — PERF-009-T13 (PERF-009-R1, R5, R8): the app's warm cache on a temporary folder. The
// bundled library loads cold (miss) then warm (hit, equal library); clearing makes the next load cold; Clear Caches
// (FILE-010's cleanup on a fixture container laid out by `StorageLocations.make`) empties the warm cache; the
// identity carries only the app version, build and OS version. No clock assertions.
import Foundation
import LocalPortability
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class WarmStartCacheTests: XCTestCase {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PERF009-\(UUID().uuidString)", isDirectory: true)
    }

    func testBundledLibraryLoadsColdThenWarmAndClearMakesItColdAgain() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = WarmStartCache(store: WarmCacheStore(directory: folder), identity: WarmStartCache.identity(bundle: .main))
        let cold = try await cache.loadLibrary()
        XCTAssertEqual(cache.libraryOutcome, .miss)
        let warm = try await cache.loadLibrary()
        XCTAssertEqual(cache.libraryOutcome, .hit)
        XCTAssertEqual(warm.presets, cold.presets)
        XCTAssertEqual(warm.home, cold.home)
        XCTAssertEqual(warm.archiveOrder, cold.archiveOrder)
        XCTAssertNotNil(cache.libraryLoadMs)
        cache.clear()
        _ = try await cache.loadLibrary()
        XCTAssertEqual(cache.libraryOutcome, .miss)
    }

    func testIdentityHasOnlyVersionBuildAndOS() {
        let identity = WarmStartCache.identity(bundle: .main)
        XCTAssertEqual(identity.appVersion, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(identity.build, Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
        XCTAssertEqual(identity.osVersion, ProcessInfo.processInfo.operatingSystemVersionString)
        XCTAssertFalse(WarmStartCache.archivedShaderSources.isEmpty)
    }

    /// R8: the standard folder lies in the Caches root, and Clear Caches empties it.
    func testClearCachesEmptiesTheWarmCache() throws {
        let standard = try XCTUnwrap(WarmStartCache.standard().store)
        let cachesRoot = try XCTUnwrap(StorageLocations.standard().roots[.caches]?.first)
        XCTAssertEqual(standard.directory.deletingLastPathComponent().standardizedFileURL.path, cachesRoot.standardizedFileURL.path)

        let base = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let caches = base.appendingPathComponent("Library/Caches", isDirectory: true)
        let layout = StorageLocations.make(applicationSupport: base.appendingPathComponent("Library/Application Support", isDirectory: true),
                                           temporary: base.appendingPathComponent("tmp", isDirectory: true), caches: caches, container: base)
        let store = WarmCacheStore(directory: caches.appendingPathComponent(WarmStartCache.folderName, isDirectory: true))
        let key = WarmCacheKey(appVersion: "1", build: "1", osVersion: "x", gpuFamily: WarmCacheKey.noGPU, formatVersion: 1,
                               contentHash: WarmCacheHash.sha256Hex(Data([1])))
        try store.write(PresetLibrary.warmCacheEntry, key: key, payload: Data([1, 2, 3]))
        let cleaner = CacheCleaner()
        let plan = try cleaner.plan(layout.cleanupRequest(inUse: []))
        XCTAssertTrue(plan.items.contains { (item: CacheCleanupItem) -> Bool in item.path.hasSuffix("/" + WarmStartCache.folderName) })
        _ = cleaner.execute(plan)
        XCTAssertEqual(store.read(PresetLibrary.warmCacheEntry, key: key).outcome, .miss)
    }
}
