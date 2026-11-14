// PERF-009 warm cache core (contracts/warm-cache.md W1-W4; PERF-009-S1): every key-field change makes an entry
// stale, every kind of damage is detected, both are deleted and rebuilt, the loader runs the expensive step only
// on a cold path (counted, not timed), and the launch timeline reads an injected clock. Runs on Linux too.
import Foundation
import XCTest
@testable import LocalPortability

final class WarmCacheStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf009-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let key = WarmCacheKey(appVersion: "1.1", build: "2", osVersion: "Version 27.2 (Build 24B1)", gpuFamily: "Apple A16 GPU/apple8",
                                   formatVersion: 1, contentHash: WarmCacheHash.sha256Hex(Data("index".utf8)))

    private func store(max: Int = WarmCacheStore.defaultMaxPayloadBytes) -> WarmCacheStore {
        WarmCacheStore(directory: folder.appendingPathComponent("WarmStart", isDirectory: true), maxPayloadBytes: max)
    }

    private func changed(_ field: WarmCacheKey.Field) -> WarmCacheKey {
        var other = key
        switch field {
        case .appVersion: other.appVersion = "1.2"
        case .build: other.build = "3"
        case .osVersion: other.osVersion = "Version 27.3 (Build 24C1)"
        case .gpuFamily: other.gpuFamily = "Apple M5 GPU/apple10"
        case .formatVersion: other.formatVersion = 2
        case .contentHash: other.contentHash = WarmCacheHash.sha256Hex(Data("index v2".utf8))
        }
        return other
    }

    func testHitReturnsThePayloadWrittenForTheSameKey() throws {
        let store = store()
        XCTAssertEqual(store.read("preset-library", key: key).outcome, .miss)
        try store.write("preset-library", key: key, payload: Data("payload".utf8))
        let read = store.read("preset-library", key: key)
        XCTAssertEqual(read.outcome, .hit)
        XCTAssertEqual(read.payload, Data("payload".utf8))
        XCTAssertEqual(store.lookup("preset-library", key: key).url, store.payloadURL("preset-library"))
    }

    /// S1: each of the six fields alone makes the entry stale; it is deleted and never returned.
    func testEveryKeyFieldChangeIsStaleAndDeletesTheEntry() throws {
        let store = store()
        for field in WarmCacheKey.Field.allCases {
            try store.write("native-pipelines", key: key, payload: Data([1, 2, 3]))
            let read = store.read("native-pipelines", key: changed(field))
            XCTAssertEqual(read.outcome, .stale(field), "\(field)")
            XCTAssertNil(read.payload)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.payloadURL("native-pipelines").path), "\(field)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.keyURL("native-pipelines").path), "\(field)")
            XCTAssertEqual(read.outcome.label, "stale-" + field.rawValue)
        }
    }

    /// S1: truncation, a flipped byte, a damaged key file, an oversized or missing payload: damaged and deleted.
    func testDamagedEntriesAreDetectedAndDeleted() throws {
        let store = store(max: 64)
        let payload = Data((0..<32).map { (i: Int) -> UInt8 in UInt8(i) })
        let cases: [(WarmCacheOutcome.Damage, (WarmCacheStore) throws -> Void)] = [
            (.size, { (s: WarmCacheStore) throws in try payload.prefix(20).write(to: s.payloadURL("e")) }),
            (.checksum, { (s: WarmCacheStore) throws in
                var flipped = payload
                flipped[5] ^= 0xFF
                try flipped.write(to: s.payloadURL("e"))
            }),
            (.keyFile, { (s: WarmCacheStore) throws in try Data("{\"schema\":1".utf8).write(to: s.keyURL("e")) }),
            (.tooLarge, { (s: WarmCacheStore) throws in try Data(count: 65).write(to: s.payloadURL("e")) }),
            (.missingPayload, { (s: WarmCacheStore) throws in try FileManager.default.removeItem(at: s.payloadURL("e")) }),
        ]
        for (damage, spoil) in cases {
            try store.write("e", key: key, payload: payload)
            try spoil(store)
            let read = store.read("e", key: key)
            XCTAssertEqual(read.outcome, .damaged(damage), "\(damage)")
            XCTAssertNil(read.payload)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.keyURL("e").path), "\(damage)")
        }
    }

    func testAKeyFileOfAnotherSchemaIsDamaged() throws {
        let store = store()
        try store.write("e", key: key, payload: Data([9]))
        let text = try String(contentsOf: store.keyURL("e"), encoding: .utf8).replacingOccurrences(of: "\"schema\":1", with: "\"schema\":2")
        try Data(text.utf8).write(to: store.keyURL("e"))
        XCTAssertEqual(store.read("e", key: key).outcome, .damaged(.keyFile))
    }

    func testALinkedFolderIsNeverUsed() throws {
        let target = folder.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("WarmStart"), withDestinationURL: target)
        let store = store()
        XCTAssertEqual(store.read("e", key: key).outcome, .unavailable)
        XCTAssertThrowsError(try store.write("e", key: key, payload: Data([1])))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
    }

    func testNamesAreRestricted() {
        XCTAssertTrue(WarmCacheStore.isValidName("preset-library"))
        for bad in ["", "../x", "A", "a/b", "a.b", String(repeating: "a", count: 65)] {
            XCTAssertFalse(WarmCacheStore.isValidName(bad), bad)
        }
        XCTAssertEqual(store().read("../escape", key: key).outcome, .unavailable)
    }

    func testCommitMovesAFileIntoPlaceAndClearEmptiesTheFolder() throws {
        let store = store()
        let scratch = try store.temporaryURL(for: "native-pipelines")
        try Data([4, 5, 6]).write(to: scratch)
        try store.commit("native-pipelines", key: key, fileAt: scratch)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
        XCTAssertEqual(store.read("native-pipelines", key: key).payload, Data([4, 5, 6]))
        store.clear()
        XCTAssertEqual(store.read("native-pipelines", key: key).outcome, .miss)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.path))
    }

    // MARK: - Loader (W3)

    private struct Counter { var builds = 0; var decodes = 0 }

    private func load(_ store: WarmCacheStore?, _ key: WarmCacheKey, _ counter: inout Counter,
                      decode: ((Data) throws -> String)? = nil) throws -> WarmStartResult<String> {
        var builds = counter.builds
        var decodes = counter.decodes
        let result = try WarmStartLoader.load("e", key: key, store: store,
                                          decode: { (data: Data) throws -> String in
                                              decodes += 1
                                              if let decode { return try decode(data) }
                                              return String(decoding: data, as: UTF8.self)
                                          },
                                          build: { () -> String in builds += 1; return "prepared" },
                                          encode: { (value: String) -> Data in Data(value.utf8) })
        counter.builds = builds
        counter.decodes = decodes
        return result
    }

    /// S2 core: cold builds once and stores; warm builds zero times and returns the same value.
    func testWarmLoadSkipsTheExpensiveStep() throws {
        let store = store()
        var counter = Counter()
        let cold = try load(store, key, &counter)
        XCTAssertEqual(cold.outcome, .miss)
        XCTAssertTrue(cold.built)
        XCTAssertTrue(cold.stored)
        let warm = try load(store, key, &counter)
        XCTAssertEqual(warm.outcome, .hit)
        XCTAssertFalse(warm.built)
        XCTAssertEqual(warm.value, cold.value)
        XCTAssertEqual(counter.builds, 1)
        XCTAssertEqual(counter.decodes, 1)
        let stale = try load(store, changed(.contentHash), &counter)
        XCTAssertEqual(stale.outcome, .stale(.contentHash))
        XCTAssertTrue(stale.built)
        XCTAssertEqual(counter.builds, 2)
    }

    func testAnUndecodableEntryIsRebuilt() throws {
        struct Bad: Error {}
        let store = store()
        var counter = Counter()
        _ = try load(store, key, &counter)
        let result = try load(store, key, &counter, decode: { (_: Data) throws -> String in throw Bad() })
        XCTAssertEqual(result.outcome, .damaged(.decode))
        XCTAssertTrue(result.built)
        XCTAssertTrue(result.stored)
        XCTAssertEqual(try load(store, key, &counter).outcome, .hit)
    }

    /// R7: a cache that cannot be written (or none at all) still yields the built value.
    func testAnUnwritableOrMissingStoreNeverFailsTheLoad() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a file, not a folder".utf8).write(to: folder.appendingPathComponent("WarmStart"))
        var counter = Counter()
        let blocked = try load(store(), key, &counter)
        XCTAssertEqual(blocked.value, "prepared")
        XCTAssertFalse(blocked.stored)
        let none = try load(nil, key, &counter)
        XCTAssertEqual(none.outcome, .unavailable)
        XCTAssertEqual(none.value, "prepared")
    }

    func testIdentityComesFromTheInfoDictionary() {
        let identity = WarmStartIdentity(infoDictionary: ["CFBundleShortVersionString": "1.1", "CFBundleVersion": "2"], osVersion: "27.2")
        XCTAssertEqual(identity.key(gpuFamily: WarmCacheKey.noGPU, formatVersion: 1, contentHash: "h"),
                       WarmCacheKey(appVersion: "1.1", build: "2", osVersion: "27.2", gpuFamily: "none", formatVersion: 1, contentHash: "h"))
        XCTAssertEqual(WarmStartIdentity(infoDictionary: nil, osVersion: "x").build, "unknown")
    }

    func testHashMatchesThePortableDigestAndSeparatesTexts() {
        let data = Data("PERF-009".utf8)
        XCTAssertEqual(WarmCacheHash.sha256Hex(data), PortableSHA256.hex(data))
        XCTAssertEqual(WarmCacheHash.sha256Hex([Data("PERF".utf8), Data("-009".utf8)]), PortableSHA256.hex(data))
        XCTAssertNotEqual(WarmCacheHash.sha256Hex(texts: ["ab", "c"]), WarmCacheHash.sha256Hex(texts: ["a", "bc"]))
    }

    // MARK: - Timeline

    private final class FakeClock: WarmStartClock, @unchecked Sendable {
        var now: UInt64 = 1_000
        func nowNanoseconds() -> UInt64 { now }
    }

    func testTimelineReadsTheInjectedClock() {
        let clock = FakeClock()
        var timeline = LaunchTimeline(clock: clock)
        timeline.begin("library")
        clock.now += 12_500_000
        XCTAssertEqual(timeline.end("library"), 12.5)
        XCTAssertNil(timeline.end("never"))
        XCTAssertEqual(timeline.milliseconds, ["library": 12.5])
    }
}
