// PRE-003-T07: the roadmap acceptance, "Tag filter returns correct IDs after app relaunch" (spec
// PRE-003-S1, S2, S5; R3, R7-R10, R14). Tags several presets of the fixture library, filters by one
// and two tags (the expected ID sets), recreates the store and index from disk (what a relaunch does)
// and filters again. Also: search matches tags, the tagged scope, hidden orphans, bundled bytes
// unchanged, and the index's cost as an operation count (no wall-clock assertion). The timing bench
// runs only with PRE003_BENCH=1.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetTagAcceptanceTests: XCTestCase {
    private var directory: URL!

    private let beta = "frontend-uwp/b.milk"
    private let alpha = "frontend-uwp/a.milk"
    private let spiral1 = "cream-of-the-crop/Fractal/Nested Spiral/Geiss - Spiral 1.milk"
    private let wave = "cream-of-the-crop/Reaction/Liquid/Zylot - Wave.milk"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetTagAcceptance-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func index(_ store: PresetTagStore, _ library: PresetLibrary) -> PresetTagIndex {
        PresetTagIndex(map: store.map) { (id: String) -> Bool in library.preset(id: id) != nil }
    }

    func testTagFilterReturnsTheSameIDsAfterTheStoreIsRecreatedFromDisk() throws {
        let library = try Fixtures.library()
        let store = PresetTagStore(directory: directory)
        try store.add("Calm", to: beta)
        try store.add("calm", to: alpha)        // adopts "Calm"
        try store.add("Calm", to: spiral1)      // a locked pack's preset
        try store.add("Slow", to: spiral1)
        try store.add("Loud", to: wave)
        try store.add("Calm", to: "cream-of-the-crop/gone.milk")   // not listed: kept, hidden

        func check(_ index: PresetTagIndex, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(index.matching(all: ["Calm"]), [beta, alpha, spiral1], file: file, line: line)
            XCTAssertEqual(index.matching(all: ["calm", "SLOW"]), [spiral1], file: file, line: line)
            XCTAssertEqual(index.matching(all: ["Calm", "Loud"]), [], file: file, line: line)
            XCTAssertEqual(index.vocabulary, ["Calm", "Loud", "Slow"], file: file, line: line)
            XCTAssertEqual(index.count(of: "calm"), 3, file: file, line: line)
            // Alphabetical across packs, locked included.
            XCTAssertEqual(library.taggedListing(["Calm"], index: index).map(\.id), [alpha, beta, spiral1], file: file, line: line)
        }
        check(index(store, library))

        // Relaunch: a new store reads tags.json, a new library and index are built.
        let relaunched = PresetTagStore(directory: directory)
        XCTAssertEqual(relaunched.loadNotice, .none)
        XCTAssertEqual(relaunched.map.tags(of: "cream-of-the-crop/gone.milk"), ["Calm"], "orphans are kept")
        check(index(relaunched, try Fixtures.library()))
    }

    func testSearchMatchesTagsAndTheTaggedScopeWalksPlayablePresets() throws {
        let library = try Fixtures.library()
        let store = PresetTagStore(directory: directory)
        try store.add("Ambient", to: beta)
        try store.add("Ambient", to: spiral1)
        let tagIndex = index(store, library)

        let hits = library.search("amb", limit: 200, tagMatches: tagIndex.presetIDs(tagContaining: "amb"))
        XCTAssertEqual(Set(hits.groups.flatMap(\.presets).map(\.id)), [beta, spiral1])
        // Chips narrow search results.
        let narrowed = library.search("a", limit: 200, within: [alpha])
        XCTAssertEqual(narrowed.groups.flatMap(\.presets).map(\.id), [alpha])

        let scope = PresetScope.tagged(["Ambient"])
        XCTAssertEqual(scope.storageValue, "all")
        XCTAssertEqual(library.title(of: scope), "Tagged: Ambient")
        // Before purchase only the Included one plays; after, both (alphabetical).
        XCTAssertEqual(library.members(of: scope, unlocked: false, favorites: [], excluded: [], tags: tagIndex).map(\.id), [beta])
        XCTAssertEqual(library.members(of: scope, unlocked: true, favorites: [], excluded: [], tags: tagIndex).map(\.id), [beta, spiral1])
        XCTAssertEqual(library.members(of: .search("amb"), unlocked: true, favorites: [], excluded: [], tags: tagIndex).count, 2)
    }

    /// PRE-003-S2: tagging never writes the bundled index or packs (the library's inputs): their bytes
    /// hash the same before and after, and the store writes only `tags.json` in its own folder.
    func testBundledInputsAreUnchanged() throws {
        let bundled = FileManager.default.temporaryDirectory.appendingPathComponent("PresetTagBundle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: bundled) }
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        let indexURL = bundled.appendingPathComponent("PresetIndex.json")
        let packsURL = bundled.appendingPathComponent("PresetPacks.json")
        try JSONSerialization.data(withJSONObject: ["version": 1, "presets": Fixtures.records]).write(to: indexURL)
        try JSONSerialization.data(withJSONObject: ["version": 1, "packs": Fixtures.packs()]).write(to: packsURL)
        func hashes() throws -> [String] {
            try [indexURL, packsURL].map { (url: URL) -> String in ContentHash.sha256Hex([UInt8](try Data(contentsOf: url))) }
        }
        let before = try hashes()
        let library = try PresetLibrary(index: Data(contentsOf: indexURL), packs: Data(contentsOf: packsURL))
        let store = PresetTagStore(directory: directory)
        for preset in library.presets { try store.add("Calm", to: preset.id) }
        try store.remove("Calm", from: beta)
        XCTAssertEqual(try hashes(), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bundled.path).sorted(), ["PresetIndex.json", "PresetPacks.json"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [PresetTagStore.fileName])
    }

    /// PRE-003-S5, R14: on a 13,000-preset library with every preset tagged "Common", intersecting with
    /// a 5-preset tag visits only the small set and the result, never the library.
    func testFilteringCostIsBoundedByTheSmallestSet() throws {
        let library = try Fixtures.large()
        var stored: [String: [String]?] = [:]
        for (i, preset) in library.presets.enumerated() {
            stored[preset.id] = i % 2_600 == 0 ? ["Common", "Rare"] : ["Common"]
        }
        let map = PresetTagMap.repaired(stored).map
        let tagIndex = PresetTagIndex(map: map) { (id: String) -> Bool in library.preset(id: id) != nil }
        let (ids, visited) = tagIndex.matchingWithCost(all: ["Common", "Rare"])
        XCTAssertEqual(ids.count, 6)
        XCTAssertLessThanOrEqual(visited, 12, "visited \(visited) IDs for a 6-preset tag")
        XCTAssertEqual(library.taggedListing(["Rare", "Common"], index: tagIndex).count, 6)
    }

    /// On demand: `PRE003_BENCH=1 swift test --filter PresetTagAcceptanceTests/testBench` prints timings.
    func testBench() throws {
        guard ProcessInfo.processInfo.environment["PRE003_BENCH"] == "1" else { throw XCTSkip("PRE003_BENCH=1 runs the bench") }
        let library = try Fixtures.large()
        var stored: [String: [String]?] = [:]
        for (i, preset) in library.presets.enumerated() { stored[preset.id] = ["T\(i % 200)", "Common"] }
        let map = PresetTagMap.repaired(stored).map
        let start = Date()
        let tagIndex = PresetTagIndex(map: map) { (id: String) -> Bool in library.preset(id: id) != nil }
        let built = Date()
        let listing = library.taggedListing(["T7", "Common"], index: tagIndex)
        let filtered = Date()
        print("PRE-003 bench: index \(Int(built.timeIntervalSince(start) * 1_000)) ms, filter \(listing.count) in \(Int(filtered.timeIntervalSince(built) * 1_000)) ms")
    }
}
