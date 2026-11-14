// PRE-003-T06: the tags file and store over a real directory (spec PRE-003-R5, R6; research
// PRE-003-D1, D4): round trip and determinism, lenient repair, unreadable file set aside, newer
// format untouched, failed save changes nothing.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetTagStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent(PresetTagStore.fileName) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetTagStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("PresetCollections", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func put(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL)
    }

    func testRoundTripIsDeterministicAndKeepsOnlyTheTagsFile() throws {
        let store = PresetTagStore(directory: directory)
        try store.add("Calm", to: "included/b.milk")
        try store.add("slow", to: "cream-of-the-crop/x/y.milk")
        let first = try Data(contentsOf: fileURL)
        XCTAssertEqual(String(decoding: first, as: UTF8.self),
                       #"{"schemaVersion":1,"tags":{"cream-of-the-crop/x/y.milk":["slow"],"included/b.milk":["Calm"]}}"#)
        let reopened = PresetTagStore(directory: directory)
        XCTAssertEqual(reopened.map, store.map)
        XCTAssertEqual(reopened.loadNotice, .none)
        XCTAssertEqual(try PresetTagsFile.encode(reopened.map), first)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [PresetTagStore.fileName])
    }

    func testDamagedEntriesAreDroppedAndCounted() throws {
        try put(#"{"schemaVersion":1,"tags":{"a":["Calm","CALM",""],"b":"Calm","c":[1,2],"d":["Slow"]}}"#)
        let store = PresetTagStore(directory: directory)
        XCTAssertEqual(store.map.tags, ["a": ["Calm"], "d": ["Slow"]])
        XCTAssertEqual(store.loadNotice, .repaired(dropped: 4))
        // The repaired map is written by the next change.
        try store.add("Calm", to: "e")
        XCTAssertEqual(PresetTagStore(directory: directory).loadNotice, .none)
    }

    func testUnreadableFileIsSetAsideOnce() throws {
        try put("not json")
        let store = PresetTagStore(directory: directory)
        XCTAssertEqual(store.loadNotice, .unreadableSetAside)
        XCTAssertTrue(store.map.isEmpty)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(PresetTagStore.unreadableFileName), encoding: .utf8), "not json")
        XCTAssertNoThrow(try store.add("Calm", to: "a"))
        XCTAssertEqual(PresetTagStore(directory: directory).loadNotice, .none)
        // Over-deep or duplicate-key documents are unreadable too (FILE-007 bounds).
        try put(#"{"schemaVersion":1,"tags":{"a":["x"],"a":["y"]}}"#)
        XCTAssertEqual(PresetTagStore(directory: directory).loadNotice, .unreadableSetAside)
    }

    func testNewerFormatIsNeverInterpretedOrWritten() throws {
        let newer = #"{"schemaVersion":2,"tags":{"a":["Calm"]},"future":true}"#
        try put(newer)
        let store = PresetTagStore(directory: directory)
        XCTAssertEqual(store.availability, .newerFormat(version: 2))
        XCTAssertThrowsError(try store.add("Slow", to: "a")) { XCTAssertEqual($0 as? PresetTagError, .newerFormat) }
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), newer)
    }

    func testFailedSaveChangesNothing() throws {
        let good = PresetTagStore(directory: directory)
        try good.add("Calm", to: "a")
        let failing = PresetTagStore(directory: directory, write: { (_: Data, _: URL) throws -> Void in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try failing.add("Slow", to: "a")) { XCTAssertEqual($0 as? PresetTagError, .saveFailed) }
        XCTAssertThrowsError(try failing.prune("a")) { XCTAssertEqual($0 as? PresetTagError, .saveFailed) }
        XCTAssertEqual(failing.map.tags(of: "a"), ["Calm"])
        XCTAssertEqual(PresetTagStore(directory: directory).map.tags(of: "a"), ["Calm"])
    }
}
