// PresetNoteTests.swift — PRE-011-T05 (spec PRE-011-R1, R2, R5; S1; contract C1): notes survive a simulated
// relaunch (a new store on the same folder), trimming, empty-removes, the 2,000-character limit, the lenient
// read, newer and unreadable files, an injected migration, a failed save and the folded search.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetNoteTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PRE011-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Acceptance: notes survive relaunch

    func testANoteSurvivesRelaunch() throws {
        let directory = try folder()
        let store = PresetNoteStore(directory: directory)
        XCTAssertEqual(try store.set("  Slow build — good for the intro 🎉\n", for: "included/Alpha.milk"), "Slow build — good for the intro 🎉")
        try store.set("Second", for: "user/abc")

        let relaunched = PresetNoteStore(directory: directory)   // a new process reading the file
        XCTAssertEqual(relaunched.availability, .available)
        XCTAssertEqual(relaunched.loadNotice, .none)
        XCTAssertEqual(relaunched.note(for: "included/Alpha.milk"), "Slow build — good for the intro 🎉")
        XCTAssertEqual(relaunched.map, store.map)
        XCTAssertEqual(try Data(contentsOf: relaunched.fileURL), try PresetNotesFile.encode(store.map), "stable bytes")
    }

    // MARK: - Rules

    func testEmptyRemovesAndTheLimitIsCharacters() throws {
        let store = PresetNoteStore(directory: try folder())
        try store.set("Keep", for: "p")
        XCTAssertNil(try store.set(" \n\t ", for: "p"), "whitespace only removes the note")
        XCTAssertNil(store.note(for: "p"))
        XCTAssertFalse(try store.remove("p"))

        let emoji = String(repeating: "👩‍👩‍👧‍👦", count: PresetNoteMap.maximumCharacters)   // 2,000 characters, 50 KB
        XCTAssertEqual(try store.set(emoji, for: "p")?.count, 2_000)
        XCTAssertEqual(PresetNoteStore(directory: store.fileURL.deletingLastPathComponent()).note(for: "p"), emoji, "long clusters fit the schema")
        XCTAssertThrowsError(try store.set(emoji + "x", for: "p")) { error in
            XCTAssertEqual(error as? PresetNoteError, .tooLong(limit: 2_000))
            XCTAssertEqual((error as? PresetNoteError)?.message, "A note can be at most 2,000 characters.")
        }
        XCTAssertEqual(store.note(for: "p"), emoji, "a refused change leaves the note")
        XCTAssertThrowsError(try store.set("x", for: "")) { XCTAssertEqual($0 as? PresetNoteError, .invalidPreset) }
    }

    func testSearchIsFolded() throws {
        var map = PresetNoteMap()
        try map.set("Great for the Café opening", for: "a")
        try map.set("calm", for: "b")
        XCTAssertEqual(map.presetIDs(containing: "cafe"), ["a"])
        XCTAssertEqual(map.presetIDs(containing: "CALM"), ["b"])
        XCTAssertEqual(map.presetIDs(containing: "  "), [])
    }

    // MARK: - Files

    func testDamagedEntriesAreDroppedAndCounted() throws {
        let directory = try folder()
        let long = String(repeating: "a", count: 2_001)
        let json = #"{"schemaVersion":1,"notes":{"ok":" fine ","num":5,"blank":"  ","long":"\#(long)","":"no id"}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("notes.json"))
        let store = PresetNoteStore(directory: directory)
        XCTAssertEqual(store.map.notes, ["ok": "fine"])
        XCTAssertEqual(store.loadNotice, .repaired(dropped: 4))
    }

    func testNewerFileIsNeverInterpretedOrWritten() throws {
        let directory = try folder()
        let bytes = Data(#"{"schemaVersion":2,"notes":{"a":"future"},"extra":true}"#.utf8)
        let url = directory.appendingPathComponent("notes.json")
        try bytes.write(to: url)
        let store = PresetNoteStore(directory: directory)
        XCTAssertEqual(store.availability, .newerFormat(version: 2))
        XCTAssertNil(store.note(for: "a"))
        XCTAssertThrowsError(try store.set("x", for: "a")) { XCTAssertEqual($0 as? PresetNoteError, .newerFormat) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testUnreadableFileIsSetAside() throws {
        let directory = try folder()
        try Data("not json".utf8).write(to: directory.appendingPathComponent("notes.json"))
        let store = PresetNoteStore(directory: directory)
        XCTAssertEqual(store.loadNotice, .unreadableSetAside)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(PresetNoteStore.unreadableFileName).path))
        try store.set("new", for: "a")
        XCTAssertEqual(PresetNoteStore(directory: directory).note(for: "a"), "new")
    }

    func testOlderFileIsMigratedThroughTheTable() throws {
        let directory = try folder()
        try Data(#"{"byPreset":{"a":"old"}}"#.utf8).write(to: directory.appendingPathComponent("notes.json"))
        let step: PresetNotesFile.Migration = { (data: Data) throws -> Data in
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "notes": object["byPreset"] ?? [:]])
        }
        let store = PresetNoteStore(directory: directory, migrations: [0: step])
        XCTAssertEqual(store.note(for: "a"), "old")
        let saved = try PresetNotesFile.decode(Data(contentsOf: store.fileURL))
        XCTAssertNil(saved.migratedFrom, "the migrated document was saved at the current version")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("notes.v0.backup.json").path))
        XCTAssertThrowsError(try PresetNotesFile.decode(Data(#"{"byPreset":{}}"#.utf8))) { XCTAssertEqual($0 as? PresetNotesFile.ReadError, .unreadable) }
    }

    func testAFailedSaveChangesNothing() throws {
        struct DiskFull: Error {}
        let directory = try folder()
        try PresetNoteStore(directory: directory).set("kept", for: "a")
        let store = PresetNoteStore(directory: directory, write: { (_: Data, _: URL) throws -> Void in throw DiskFull() })
        XCTAssertThrowsError(try store.set("changed", for: "a")) { XCTAssertEqual($0 as? PresetNoteError, .saveFailed) }
        XCTAssertEqual(store.note(for: "a"), "kept")
        XCTAssertEqual(PresetNoteStore(directory: directory).note(for: "a"), "kept")
    }
}
