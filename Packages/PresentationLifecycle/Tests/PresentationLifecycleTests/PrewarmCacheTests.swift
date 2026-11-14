// PrewarmCacheTests.swift — PERF-005-T06: the eviction order of the prewarm cache (PERF-005-R3, R4; research
// PERF-005-D4): least recently used first among entries no more important than the incoming one, live keys
// pinned, oversized items refused, and held bytes never above the budget.
import PresentationLifecycle
import XCTest

final class PrewarmCacheTests: XCTestCase {
    private final class Blob {}

    private func asset(_ id: String, _ bytes: Int) -> PrewarmedAsset {
        PrewarmedAsset(key: PrewarmKey(kind: .photo, id: id), bytes: bytes, payload: Blob())
    }

    private func key(_ id: String) -> PrewarmKey { PrewarmKey(kind: .photo, id: id) }

    private func admitted(_ result: Result<[PrewarmedAsset], PrewarmCache.Refusal>) -> [String]? {
        guard case .success(let evicted) = result else { return nil }
        return evicted.map(\.key.id)
    }

    func testEvictionOrderIsLeastRecentlyUsedAmongNoMoreImportantEntries() {
        var cache = PrewarmCache(budgetBytes: 100)
        XCTAssertEqual(admitted(cache.admit(asset("a", 30), rank: 1, live: [])), [])
        XCTAssertEqual(admitted(cache.admit(asset("b", 30), rank: 1, live: [])), [])
        XCTAssertEqual(admitted(cache.admit(asset("c", 30), rank: 0, live: [])), [])
        cache.touch(key("a"), rank: 1)   // a is now more recent than b

        // d (rank 1, 30) needs 20 more bytes: c (rank 0) is more important, so b (oldest rank-1) goes.
        XCTAssertEqual(admitted(cache.admit(asset("d", 30), rank: 1, live: [])), ["b"])
        XCTAssertEqual(cache.keys, [key("a"), key("c"), key("d")])
        XCTAssertLessThanOrEqual(cache.heldBytes, 100)

        // e (rank 0, 60): candidates a, d (rank 1) and c (rank 0) in LRU order a, c, d; the live c is pinned.
        XCTAssertEqual(admitted(cache.admit(asset("e", 60), rank: 0, live: [key("c")])), ["a", "d"])
        XCTAssertEqual(cache.keys, [key("c"), key("e")])
        XCTAssertEqual(cache.heldBytes, 90)
        XCTAssertEqual(cache.evictions, 3)
        XCTAssertLessThanOrEqual(cache.peakBytes, 100)
    }

    func testRefusalsChangeNothing() {
        var cache = PrewarmCache(budgetBytes: 100)
        _ = cache.admit(asset("next", 70), rank: 0, live: [])
        // A later cue's item may not evict the next cue's entry.
        guard case .failure(.cannotFit) = cache.admit(asset("later", 40), rank: 1, live: []) else { return XCTFail("must refuse") }
        guard case .failure(.largerThanBudget) = cache.admit(asset("huge", 101), rank: 0, live: []) else { return XCTFail("must refuse") }
        // Only live entries are left as candidates: refused, nothing evicted.
        guard case .failure(.cannotFit) = cache.admit(asset("other", 40), rank: 0, live: [key("next")]) else { return XCTFail("must refuse") }
        XCTAssertEqual(cache.keys, [key("next")])
        XCTAssertEqual(cache.heldBytes, 70)
        XCTAssertEqual(cache.evictions, 0)
    }

    func testTakeAndReleaseKeepLiveEntries() {
        var cache = PrewarmCache(budgetBytes: 100)
        _ = cache.admit(asset("a", 10), rank: 0, live: [])
        _ = cache.admit(asset("b", 20), rank: 1, live: [])
        _ = cache.admit(asset("c", 30), rank: 1, live: [])
        XCTAssertEqual(cache.take(key("a"))?.bytes, 10)
        XCTAssertEqual(cache.heldBytes, 50)
        let released = cache.release(keeping: [key("b")], live: [key("c")])
        XCTAssertEqual(released.map(\.key.id), [])
        XCTAssertEqual(cache.release(keeping: [], live: [key("c")]).map(\.key.id), ["b"])
        XCTAssertEqual(cache.keys, [key("c")])
    }
}
