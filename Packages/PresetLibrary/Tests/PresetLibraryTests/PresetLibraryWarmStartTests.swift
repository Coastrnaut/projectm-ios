// PERF-009 warm library (contracts/warm-cache.md W5; PERF-009-S1, S2): a cold load prepares once and stores the
// snapshot; a warm load prepares nothing (counted through `built`) and equals the cold library; a changed index,
// app build or damaged snapshot is never used. On-demand bench (PERF009_BENCH=1): cold vs warm on 13,000 presets
// (host numbers, not evidence).
import Foundation
import LocalPortability
import XCTest
@testable import PresetLibrary

final class PresetLibraryWarmStartTests: XCTestCase {
    private var folder: URL!
    private let identity = WarmStartIdentity(appVersion: "1.1", build: "2", osVersion: "27.2")

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf009-lib-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var store: WarmCacheStore { WarmCacheStore(directory: folder) }

    private func inputs(_ records: [[String: Any]] = Fixtures.records) throws -> (index: Data, packs: Data) {
        var withFlash = records
        withFlash[0]["flash"] = ["strobe"]
        let index = try JSONSerialization.data(withJSONObject: ["version": 1, "presets": withFlash, "archive": [8, 2, 3]])
        let packs = try JSONSerialization.data(withJSONObject: ["version": 1, "packs": Fixtures.packs()])
        return (index, packs)
    }

    private func assertSame(_ a: PresetLibrary, _ b: PresetLibrary, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.presets, b.presets, file: file, line: line)
        XCTAssertEqual(a.packs, b.packs, file: file, line: line)
        XCTAssertEqual(a.home, b.home, file: file, line: line)
        XCTAssertEqual(a.archiveOrder, b.archiveOrder, file: file, line: line)
        XCTAssertEqual(a.searchKeys, b.searchKeys, file: file, line: line)
        XCTAssertEqual(a.byId, b.byId, file: file, line: line)
        for query in ["spiral", "CAFE", "geiss"] {
            XCTAssertEqual(a.search(query, limit: 10).groups.map(\.presets), b.search(query, limit: 10).groups.map(\.presets),
                           file: file, line: line)
        }
        XCTAssertEqual(a.members(of: .all, unlocked: false, favorites: [], excluded: []),
                       b.members(of: .all, unlocked: false, favorites: [], excluded: []), file: file, line: line)
    }

    /// S2: cold prepares once and stores; warm prepares zero times and equals the cold library.
    func testWarmLoadSkipsPreparationAndEqualsCold() throws {
        let (index, packs) = try inputs()
        let cold = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity)
        XCTAssertEqual(cold.outcome, .miss)
        XCTAssertTrue(cold.built)
        XCTAssertTrue(cold.stored)
        let warm = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity)
        XCTAssertEqual(warm.outcome, .hit)
        XCTAssertFalse(warm.built)
        assertSame(warm.value, cold.value)
        assertSame(warm.value, try PresetLibrary(index: index, packs: packs))
        XCTAssertTrue(warm.value.preset(id: "frontend-uwp/b.milk")?.mayFlash ?? false)
    }

    /// S1: a changed index or a new app build is stale; the library is rebuilt from the new input, never the old.
    func testChangedInputsOrBuildAreStale() throws {
        let (index, packs) = try inputs()
        _ = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity)
        var records = Fixtures.records
        records.append(Fixtures.record("en-d/Episode 2/En D - New.milk", "New", "En D", "en-d", ["Episode 2"]))
        let (newIndex, _) = try inputs(records)
        let changed = try PresetLibrary.loadWarm(index: newIndex, packs: packs, store: store, identity: identity)
        XCTAssertEqual(changed.outcome, .stale(.contentHash))
        XCTAssertTrue(changed.built)
        XCTAssertNotNil(changed.value.preset(id: "en-d/Episode 2/En D - New.milk"))
        var rebuilt = identity
        rebuilt.build = "3"
        let update = try PresetLibrary.loadWarm(index: newIndex, packs: packs, store: store, identity: rebuilt)
        XCTAssertEqual(update.outcome, .stale(.build))
        XCTAssertTrue(update.built)
    }

    /// S1: a snapshot that passes its checksum but does not decode (a format bug) is rebuilt; truncations throw.
    func testUndecodableSnapshotIsRebuilt() throws {
        let (index, packs) = try inputs()
        let key = PresetLibrary.warmCacheKey(index: index, packs: packs, identity: identity)
        try store.write(PresetLibrary.warmCacheEntry, key: key, payload: Data("PMWS garbage".utf8))
        let result = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity)
        XCTAssertEqual(result.outcome, .damaged(.decode))
        XCTAssertTrue(result.built)
        XCTAssertEqual(try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity).outcome, .hit)

        let snapshot = try result.value.snapshotData()
        for cut in [3, 10, snapshot.count / 2, snapshot.count - 1] {
            XCTAssertThrowsError(try PresetLibrary(snapshot: snapshot.prefix(cut)), "cut \(cut)")
        }
        XCTAssertThrowsError(try PresetLibrary(snapshot: snapshot + Data([0])))
    }

    /// R1: the user's imported presets never enter the snapshot, and add to a warm library as to a cold one.
    func testUserPresetsAreNeverCachedAndAddAsBefore() throws {
        let (index, packs) = try inputs()
        let cold = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity).value
        let mine = IndexedPreset(id: "user/mine.milk", name: "Mine", author: "Me", source: PresetLibrary.userSource,
                                 folder: [], path: "user/mine.milk", hash: String(repeating: "b", count: 40))
        let withMine = cold.withUserPresets([mine])
        let snapshot = try withMine.snapshotData()
        XCTAssertNil(try PresetLibrary(snapshot: snapshot).preset(id: mine.id))
        let warm = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity).value
        assertSame(warm.withUserPresets([mine]), withMine)
    }

    /// On demand only: PERF009_BENCH=1 swift test --filter PresetLibraryWarmStartTests/testBench
    func testBenchColdVersusWarm() throws {
        guard ProcessInfo.processInfo.environment["PERF009_BENCH"] == "1" else { throw XCTSkip("bench: set PERF009_BENCH=1") }
        let (index, packs) = try Fixtures.largeData()
        let start = Date()
        let cold = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity)
        let middle = Date()
        let warm = try PresetLibrary.loadWarm(index: index, packs: packs, store: store, identity: identity)
        let end = Date()
        XCTAssertFalse(warm.built)
        print("PERF009 bench (host, not evidence): \(cold.value.presets.count) presets, cold \(Int(middle.timeIntervalSince(start) * 1000)) ms, warm \(Int(end.timeIntervalSince(middle) * 1000)) ms")
    }
}
