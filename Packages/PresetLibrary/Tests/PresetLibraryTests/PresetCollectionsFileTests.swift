// PRE-007-T04: the versioned collections document (PRE-007-R15, S6): the immutable v1 golden
// fixture, newer versions, unreadable data and the migration path.
import Foundation
import XCTest
@testable import PresetLibrary

enum Golden {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden"))
        return try Data(contentsOf: url)
    }
}

/// A synthetic "version 0": a bare array of `{ "title": …, "items": […] }`, used only to prove the
/// migration path. No such format ever shipped.
enum LegacyV0 {
    static let data = Data(#"[{"title":"Old one","items":["frontend-uwp/a.milk","x/y.milk"]},{"title":"Old two","items":[]}]"#.utf8)

    static let step: PresetCollectionsFile.Migration = { data in
        struct Old: Decodable { let title: String; let items: [String] }
        let old = try JSONDecoder().decode([Old].self, from: data)
        let collections = old.enumerated().map { PresetCollection(id: "legacy-\($0.offset)", name: $0.element.title, presetIDs: $0.element.items) }
        return try PresetCollectionsFile(schemaVersion: 1, collections: collections).encode()
    }
}

final class PresetCollectionsFileTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func assertUnreadable(_ data: Data, migrations: [Int: PresetCollectionsFile.Migration] = [:],
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PresetCollectionsFile.decode(data, migrations: migrations), file: file, line: line) {
            XCTAssertEqual($0 as? PresetCollectionsFile.ReadError, .unreadable, file: file, line: line)
        }
    }

    func testTheGoldenVersion1FixtureDecodesIntact() throws {
        let (file, migratedFrom) = try PresetCollectionsFile.decode(Golden.data("collections-v1"))
        XCTAssertNil(migratedFrom)
        XCTAssertEqual(file.schemaVersion, 1)
        XCTAssertEqual(file.collections.map(\.name), ["Zebra set", "Café 🎉 late", "Empty"])
        XCTAssertEqual(file.collections.map(\.id), ["6F1C2B9E-0001-4000-8000-000000000003", "6F1C2B9E-0001-4000-8000-000000000001",
                                                   "6F1C2B9E-0001-4000-8000-000000000002"])
        XCTAssertEqual(file.collections[0].presetIDs, ["cream-of-the-crop/Fractal/Nested Spiral/Geiss - Spiral 1.milk",
                                                       "frontend-uwp/b.milk", "removed-pack/Gone - Missing.milk", "frontend-uwp/a.milk"])
        XCTAssertEqual(file.collections[1].presetIDs, ["projectm-classic/tryptonaut/Tryptonaut - Café.milk"])
        XCTAssertEqual(file.collections[2].presetIDs, [])
    }

    func testEncodingTheGoldenFixtureGivesTheSameDocument() throws {
        let golden = try Golden.data("collections-v1")
        let encoded = try PresetCollectionsFile.decode(golden).file.encode()
        let a = try JSONSerialization.jsonObject(with: golden) as? NSDictionary
        let b = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertEqual(try PresetCollectionsFile.decode(encoded).file, try PresetCollectionsFile.decode(golden).file)
    }

    func testEncodingIsStable() throws {
        let file = PresetCollectionsFile(schemaVersion: 1, collections: [PresetCollection(id: "1", name: "A", presetIDs: ["p/q.milk"])])
        XCTAssertEqual(try file.encode(), try file.encode())
        XCTAssertEqual(String(decoding: try file.encode(), as: UTF8.self),
                       #"{"collections":[{"id":"1","name":"A","presets":["p/q.milk"]}],"schemaVersion":1}"#)
    }

    func testANewerVersionIsNotInterpreted() {
        // The body is deliberately of an unknown shape: only the version is read.
        let data = json(#"{"schemaVersion":2,"collections":{"shape":"unknown"},"tags":[1,2]}"#)
        XCTAssertThrowsError(try PresetCollectionsFile.decode(data)) {
            XCTAssertEqual($0 as? PresetCollectionsFile.ReadError, .newerVersion(2))
        }
    }

    func testUnreadableDocuments() {
        assertUnreadable(json("not json"))
        assertUnreadable(Data())
        assertUnreadable(json("[]"))                                             // no version, no step for 0
        assertUnreadable(json(#"{"schemaVersion":1}"#))                         // missing key
        assertUnreadable(json(#"{"schemaVersion":"1","collections":[]}"#))      // wrong type
        assertUnreadable(json(#"{"schemaVersion":0,"collections":[]}"#))        // older, no step
        assertUnreadable(json(#"{"schemaVersion":-4,"collections":[]}"#))
        assertUnreadable(json(#"{"schemaVersion":1,"collections":[{"id":"","name":"A","presets":[]}]}"#))
        assertUnreadable(json(#"{"schemaVersion":1,"collections":[{"id":"1","name":"A","presets":[]},{"id":"1","name":"B","presets":[]}]}"#))
        assertUnreadable(json(#"{"schemaVersion":1,"collections":[{"id":"1","name":"A","presets":[3]}]}"#))
    }

    func testDataOverTheSizeLimitIsUnreadable() {
        assertUnreadable(Data(count: PresetCollectionLimits.maxFileBytes + 1))
    }

    func testDuplicatePresetIDsAreReducedToTheFirstAndUnknownKeysIgnored() throws {
        let data = json(#"{"schemaVersion":1,"note":"x","collections":[{"id":"1","name":"A","color":"red","presets":["a","b","a","c","b"]}]}"#)
        XCTAssertEqual(try PresetCollectionsFile.decode(data).file.collections[0].presetIDs, ["a", "b", "c"])
    }

    func testAnInjectedStepMigratesAnOlderDocument() throws {
        let (file, migratedFrom) = try PresetCollectionsFile.decode(LegacyV0.data, migrations: [0: LegacyV0.step])
        XCTAssertEqual(migratedFrom, 0)
        XCTAssertEqual(file.schemaVersion, PresetCollectionsFile.currentVersion)
        XCTAssertEqual(file.collections, [PresetCollection(id: "legacy-0", name: "Old one", presetIDs: ["frontend-uwp/a.milk", "x/y.milk"]),
                                          PresetCollection(id: "legacy-1", name: "Old two", presetIDs: [])])
    }

    func testAFailingOrNonAdvancingStepIsUnreadable() {
        assertUnreadable(LegacyV0.data, migrations: [0: { _ in throw CocoaError(.fileReadCorruptFile) }])
        assertUnreadable(LegacyV0.data, migrations: [0: { $0 }])   // still version 0: no progress
    }

    func testTheProductionMigrationTableIsEmptyForVersion1() {
        XCTAssertEqual(PresetCollectionsFile.currentVersion, 1)
        XCTAssertTrue(PresetCollectionsFile.migrations.isEmpty)
    }
}
