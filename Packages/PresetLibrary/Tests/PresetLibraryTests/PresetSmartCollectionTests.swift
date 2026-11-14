// PresetSmartCollectionTests.swift — PRE-008-T06, T07 (spec PRE-008-S1, S2): smart collection membership
// follows rule changes exactly, with no duplicate entries and a stable order; the document and store keep
// rules safely (round trip, migration, newer and unreadable files, unknown kinds).
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetSmartCollectionTests: XCTestCase {
    // MARK: - Fixture

    /// Six presets; "Echo" is the same text (hash) in two packs.
    private static func library() throws -> PresetLibrary {
        func record(_ id: String, _ name: String, _ source: String, _ hash: String) -> [String: Any] {
            ["id": id, "name": name, "author": "A", "source": source, "folder": [String](),
             "path": source == "included" ? "Presets/\(id)" : id, "hash": hash]
        }
        let records: [[String: Any]] = [
            record("included/alpha.milk", "Alpha", "included", "h1"),
            record("included/bravo.milk", "Bravo", "included", "h2"),
            record("cream-of-the-crop/charlie.milk", "Charlie", "cream-of-the-crop", "h3"),
            record("cream-of-the-crop/echo.milk", "Echo", "cream-of-the-crop", "h5"),
            record("en-d/delta.milk", "Delta", "en-d", "h4"),
            record("en-d/echo.milk", "Echo", "en-d", "h5"),
        ]
        let index = try JSONSerialization.data(withJSONObject: ["version": 1, "presets": records])
        let packs = try JSONSerialization.data(withJSONObject: ["version": 1, "packs": Fixtures.packs()])
        return try PresetLibrary(index: index, packs: packs)
    }

    private static func context(_ library: PresetLibrary) throws -> PresetSmartContext {
        var map = PresetTagMap()
        try map.add("Calm", to: "included/alpha.milk")
        try map.add("calm", to: "cream-of-the-crop/charlie.milk")
        try map.add("Loud", to: "included/bravo.milk")
        try map.add("Loud", to: "included/alpha.milk")
        let tags = PresetTagIndex(map: map, isListed: { (id: String) -> Bool in library.preset(id: id) != nil })
        let energy = PresetEnergyFilter(scores: ["included/alpha.milk": 1_000, "en-d/delta.milk": 20_000, "gone/x.milk": 1_000])
        let colors = PresetColorFilter(colors: ["included/bravo.milk": [.red, .blue], "en-d/delta.milk": [.blue]])
        return PresetSmartContext(library: library, tags: tags, favorites: ["en-d/delta.milk", "gone/y.milk"],
                                  colors: colors, energy: energy)
    }

    private func members(_ match: PresetSmartMatch, _ conditions: [PresetSmartCondition], _ context: PresetSmartContext) -> [String] {
        PresetSmartMatcher.members(match: match, conditions: conditions, in: context)
    }

    // MARK: - S1: rule changes update membership exactly, without duplicates

    func testRuleChangesUpdateMembershipExactlyWithoutDuplicates() throws {
        let context = try Self.context(Self.library())
        var conditions: [PresetSmartCondition] = [PresetSmartCondition(.tag, ["Calm"])]
        // Folded spellings ("Calm", "calm") are one tag.
        XCTAssertEqual(members(.all, conditions, context), ["included/alpha.milk", "cream-of-the-crop/charlie.milk"])

        // Add a tag condition (All): only presets with both.
        conditions.append(PresetSmartCondition(.tag, ["Loud"]))
        XCTAssertEqual(members(.all, conditions, context), ["included/alpha.milk"])

        // Switch to Any: Alpha matches both conditions and still appears once.
        XCTAssertEqual(members(.any, conditions, context), ["included/alpha.milk", "included/bravo.milk", "cream-of-the-crop/charlie.milk"])

        // Remove the tag condition again.
        conditions.removeLast()
        XCTAssertEqual(members(.any, conditions, context), ["included/alpha.milk", "cream-of-the-crop/charlie.milk"])

        // Add packs (Any): the same text in two packs ("Echo", hash h5) is listed once, the first in order.
        conditions.append(PresetSmartCondition(.pack, ["en-d", "cream-of-the-crop", "en-d"]))
        let result: [String] = members(.any, conditions, context)
        XCTAssertEqual(result, ["included/alpha.milk", "cream-of-the-crop/charlie.milk", "en-d/delta.milk", "cream-of-the-crop/echo.milk"])
        XCTAssertEqual(Set(result).count, result.count, "no preset appears twice")

        // The order is stable: the same inputs give the same list.
        for _ in 0..<3 { XCTAssertEqual(members(.any, conditions, context), result) }
    }

    func testEveryKindMatchesAndUnknownKindsAreSkipped() throws {
        let context = try Self.context(Self.library())
        XCTAssertEqual(members(.all, [PresetSmartCondition(.motion, ["calm"])], context), ["included/alpha.milk"], "unlisted scores are ignored")
        XCTAssertEqual(members(.all, [PresetSmartCondition(.motion, ["energetic", "calm"])], context), ["included/alpha.milk", "en-d/delta.milk"])
        XCTAssertEqual(members(.all, [PresetSmartCondition(.color, ["blue", "red"])], context), ["included/bravo.milk", "en-d/delta.milk"])
        XCTAssertEqual(members(.all, [PresetSmartCondition(.favorite)], context), ["en-d/delta.milk"], "unlisted favorites are ignored")
        XCTAssertEqual(members(.all, [PresetSmartCondition(.pack, ["included"]), PresetSmartCondition(.notTag, ["loud"])], context), [])
        XCTAssertEqual(members(.all, [PresetSmartCondition(.notTag, ["Calm", "Loud"])], context),
                       ["en-d/delta.milk", "cream-of-the-crop/echo.milk"], "untagged presets; Echo once")
        XCTAssertEqual(members(.all, [PresetSmartCondition(.motion, ["wild"])], context), [], "no known class: nothing")

        let unknown = PresetSmartCondition(kind: "bpm", values: ["120"])
        XCTAssertEqual(members(.all, [unknown, PresetSmartCondition(.favorite)], context), ["en-d/delta.milk"], "an unknown kind is skipped")
        XCTAssertEqual(members(.any, [unknown], context), [], "no applicable condition lists nothing")
        XCTAssertEqual(members(.all, [], context), [])
    }

    // MARK: - S2: document and store

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PRE008-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testStoreRoundTripsAndKeepsUnknownKinds() throws {
        let dir = try directory()
        var n = 0
        let store = PresetSmartCollectionStore(directory: dir, makeID: { n += 1; return "smart-\(n)" })
        let unknown = PresetSmartCondition(kind: "bpm", values: ["120"])
        let created = try store.create(name: " Calm ", match: .any,
                                       conditions: [PresetSmartCondition(.tag, ["Calm", "calm"]), unknown, PresetSmartCondition(kind: "favorite", values: ["x"])])
        XCTAssertEqual(created.name, "Calm")
        XCTAssertEqual(created.conditions, [PresetSmartCondition(.tag, ["Calm"]), unknown, PresetSmartCondition(.favorite)], "normalized; unknown kept")
        XCTAssertThrowsError(try store.create(name: "CALM", match: .all, conditions: [])) {
            XCTAssertEqual($0 as? PresetCollectionError, .duplicateName)
        }
        XCTAssertThrowsError(try store.update(created.id, match: .all,
                                              conditions: Array(repeating: PresetSmartCondition(.favorite), count: 33))) {
            XCTAssertEqual($0 as? PresetSmartCollectionError, .tooManyConditions(limit: 32))
        }
        try store.update(created.id, match: .all, conditions: store.collections[0].conditions + [PresetSmartCondition(.pack, ["en-d"])])
        try store.rename(created.id, to: "Quiet")

        let reopened = PresetSmartCollectionStore(directory: dir)
        XCTAssertEqual(reopened.collections, store.collections)
        XCTAssertEqual(reopened.collections[0].unknownConditionCount, 1)
        XCTAssertEqual(reopened.collections[0].conditions[1], unknown, "the unknown kind survives an edit and a reload")
        try reopened.delete(created.id)
        XCTAssertTrue(PresetSmartCollectionStore(directory: dir).collections.isEmpty)
    }

    func testMigrationNewerAndUnreadableFiles() throws {
        // Version 0 (no field) through an injected step; the original is kept until the migrated file is saved.
        let dir = try directory()
        let file = dir.appendingPathComponent(PresetSmartCollectionsFile.fileName)
        try Data(#"[{"id":"smart-a","name":"Old","tag":"Calm"}]"#.utf8).write(to: file)
        let step: PresetSmartCollectionsFile.Migration = { (data: Data) throws -> Data in
            let old = try JSONSerialization.jsonObject(with: data) as? [[String: String]] ?? []
            let list = old.map { (entry: [String: String]) -> PresetSmartCollection in
                PresetSmartCollection(id: entry["id"] ?? "", name: entry["name"] ?? "", match: .all,
                                      conditions: [PresetSmartCondition(.tag, [entry["tag"] ?? ""])])
            }
            return try PresetSmartCollectionsFile(schemaVersion: 1, smartCollections: list).encode()
        }
        let migrated = PresetSmartCollectionStore(directory: dir, migrations: [0: step])
        XCTAssertEqual(migrated.collections.map(\.name), ["Old"])
        XCTAssertEqual(try PresetSmartCollectionsFile.decode(Data(contentsOf: file)).file.smartCollections, migrated.collections)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("smart-collections.v0.backup.json").path))

        // A newer version: unavailable, untouched, every change refused.
        let newer = Data(#"{"schemaVersion":2,"smartCollections":[],"future":true}"#.utf8)
        try newer.write(to: file)
        let blocked = PresetSmartCollectionStore(directory: dir)
        XCTAssertEqual(blocked.availability, .newerFormat(version: 2))
        XCTAssertThrowsError(try blocked.create(name: "X", match: .all, conditions: []))
        XCTAssertEqual(try Data(contentsOf: file), newer)

        // Unreadable (repeated IDs): set aside, the store starts empty.
        let dup = #"{"schemaVersion":1,"smartCollections":[{"id":"smart-a","name":"A","match":"any","conditions":[]},{"id":"smart-a","name":"B","match":"all","conditions":[]}]}"#
        try Data(dup.utf8).write(to: file)
        let fresh = PresetSmartCollectionStore(directory: dir)
        XCTAssertTrue(fresh.setAsideAtLoad)
        XCTAssertTrue(fresh.collections.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(PresetSmartCollectionStore.unreadableFileName).path))

        // An unknown match mode reads as All.
        let odd = #"{"schemaVersion":1,"smartCollections":[{"id":"smart-b","name":"B","match":"most","conditions":[]}]}"#
        XCTAssertEqual(try PresetSmartCollectionsFile.decode(Data(odd.utf8)).file.smartCollections.first?.match, .all)
    }
}
