// PRE-007-T06: the collections store over a real directory (PRE-007-R1-R8, R10, R14, R15;
// S1, S2, S5, S6, S7, S9). Every test gets a fresh temporary directory and deterministic ids.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetCollectionStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent(PresetCollectionStore.fileName) }
    private var asideURL: URL { directory.appendingPathComponent(PresetCollectionStore.unreadableFileName) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetCollectionStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("PresetCollections", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    /// Ids "c1", "c2", … in creation order.
    private func makeStore(failingWrites: Bool = false, migrations: [Int: PresetCollectionsFile.Migration] = [:]) -> PresetCollectionStore {
        var next = 0
        let write: (Data, URL) throws -> Void = failingWrites
            ? { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
            : { try $0.write(to: $1, options: .atomic) }
        return PresetCollectionStore(directory: directory, makeID: { next += 1; return "c\(next)" }, write: write, migrations: migrations)
    }

    private func put(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    private func assertThrows(_ expected: PresetCollectionError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? PresetCollectionError, expected, file: file, line: line)
        }
    }

    // MARK: - Create, rename, delete (R1-R3, R9)

    func testANewStoreIsEmptyAndWritesNothing() {
        let store = makeStore()
        XCTAssertEqual(store.collections, [])
        XCTAssertEqual(store.availability, .available)
        XCTAssertEqual(store.loadNotice, .none)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "nothing is created until the first save")
    }

    func testCreateAppendsAnEmptyCollection() throws {
        let store = makeStore()
        let first = try store.create(name: "  Friday set ")
        XCTAssertEqual(first, PresetCollection(id: "c1", name: "Friday set", presetIDs: []))
        try store.create(name: "Ambient")
        XCTAssertEqual(store.collections.map(\.name), ["Friday set", "Ambient"], "new collections go last, not alphabetically")
        XCTAssertEqual(store.collection(id: "c2")?.name, "Ambient")
        XCTAssertNil(store.collection(id: "nope"))
    }

    func testInvalidAndDuplicateNamesAreRefusedAndChangeNothing() throws {
        let store = makeStore()
        try store.create(name: "Chill")
        let before = try Data(contentsOf: fileURL)
        assertThrows(.emptyName) { try store.create(name: "   ") }
        assertThrows(.nameTooLong(limit: 60)) { try store.create(name: String(repeating: "x", count: 61)) }
        assertThrows(.duplicateName) { try store.create(name: " chíll ") }
        XCTAssertEqual(store.collections.count, 1)
        XCTAssertEqual(try Data(contentsOf: fileURL), before)
    }

    func testNameProblemMatchesWhatCreateAndRenameRefuse() throws {
        let store = makeStore()
        try store.create(name: "Chill")
        XCTAssertNil(store.nameProblem("New"))
        XCTAssertEqual(store.nameProblem("  "), .emptyName)
        XCTAssertEqual(store.nameProblem(String(repeating: "x", count: 61)), .nameTooLong(limit: 60))
        XCTAssertEqual(store.nameProblem("chíll"), .duplicateName)
        XCTAssertNil(store.nameProblem("CHILL", renaming: "c1"))
    }

    func testRenameKeepsIdContentsAndPosition() throws {
        let store = makeStore()
        try store.create(name: "A")
        try store.create(name: "B")
        try store.add("p/1.milk", to: "c1")
        try store.rename("c1", to: "Renamed")
        XCTAssertEqual(store.collections, [PresetCollection(id: "c1", name: "Renamed", presetIDs: ["p/1.milk"]),
                                           PresetCollection(id: "c2", name: "B", presetIDs: [])])
        try store.rename("c1", to: "RENAMED")   // its own name, in another case, is accepted
        XCTAssertEqual(store.collection(id: "c1")?.name, "RENAMED")
        assertThrows(.duplicateName) { try store.rename("c1", to: "b") }
        assertThrows(.emptyName) { try store.rename("c1", to: "") }
        assertThrows(.unknownCollection) { try store.rename("zz", to: "X") }
        XCTAssertEqual(store.collection(id: "c1")?.name, "RENAMED")
    }

    func testDeleteRemovesOnlyThatCollection() throws {
        let store = makeStore()
        try store.create(name: "A")
        try store.create(name: "B")
        try store.create(name: "C")
        try store.add("p/shared.milk", to: "c1")
        try store.add("p/shared.milk", to: "c3")
        try store.add("p/only-c.milk", to: "c3")
        let others = store.collections.filter { $0.id != "c1" }
        try store.delete("c1")
        XCTAssertEqual(store.collections, others, "S2: the other collections are exactly as before")
        XCTAssertEqual(makeStore().collections, others)
        assertThrows(.unknownCollection) { try store.delete("c1") }
    }

    // MARK: - Add and remove (R4, R5)

    func testAddAppendsOnceAndRemoveKeepsTheOrderOfTheRest() throws {
        let store = makeStore()
        try store.create(name: "A")
        XCTAssertTrue(try store.add("p/1.milk", to: "c1"))
        XCTAssertTrue(try store.add("p/2.milk", to: "c1"))
        XCTAssertTrue(try store.add("p/3.milk", to: "c1"))
        let before = try Data(contentsOf: fileURL)
        XCTAssertFalse(try store.add("p/2.milk", to: "c1"), "already there")
        XCTAssertEqual(store.collection(id: "c1")?.presetIDs, ["p/1.milk", "p/2.milk", "p/3.milk"])
        XCTAssertEqual(try Data(contentsOf: fileURL), before)
        try store.remove(["p/2.milk", "p/not-there.milk"], from: "c1")
        XCTAssertEqual(store.collection(id: "c1")?.presetIDs, ["p/1.milk", "p/3.milk"])
        assertThrows(.unknownCollection) { try store.add("p/1.milk", to: "zz") }
        assertThrows(.unknownCollection) { try store.remove(["p/1.milk"], from: "zz") }
    }

    func testThePresetIDsAndNamesDictionaries() throws {
        let store = makeStore()
        try store.create(name: "A")
        try store.create(name: "B")
        try store.add("p/1.milk", to: "c2")
        XCTAssertEqual(store.presetIDsByCollection, ["c1": [], "c2": ["p/1.milk"]])
        XCTAssertEqual(store.namesByCollection, ["c1": "A", "c2": "B"])
    }

    // MARK: - Reordering persists (R6-R8, S1)

    func testReorderedPresetsPersistAcrossANewStore() throws {
        let store = makeStore()
        try store.create(name: "A")
        for id in ["a", "b", "c"] { try store.add(id, to: "c1") }
        try store.reorderPresets(in: "c1", visibleOrder: ["c", "a", "b"])
        XCTAssertEqual(store.collection(id: "c1")?.presetIDs, ["c", "a", "b"])
        XCTAssertEqual(makeStore().collection(id: "c1")?.presetIDs, ["c", "a", "b"])
        assertThrows(.invalidOrder) { try store.reorderPresets(in: "c1", visibleOrder: ["c", "zzz"]) }
        assertThrows(.unknownCollection) { try store.reorderPresets(in: "zz", visibleOrder: []) }
    }

    func testReorderedCollectionsPersistAcrossANewStore() throws {
        let store = makeStore()
        for name in ["X", "Y", "Z"] { try store.create(name: name) }
        try store.reorderCollections(["c3", "c1", "c2"])
        XCTAssertEqual(store.collections.map(\.name), ["Z", "X", "Y"])
        XCTAssertEqual(makeStore().collections.map(\.name), ["Z", "X", "Y"])
        for bad in [["c3", "c1"], ["c3", "c1", "c1"], ["c3", "c1", "c2", "c9"]] {
            assertThrows(.invalidOrder) { try store.reorderCollections(bad) }
        }
        XCTAssertEqual(store.collections.map(\.name), ["Z", "X", "Y"])
    }

    func testEverythingPersistsAcrossANewStore() throws {
        let store = makeStore()
        try store.create(name: "Café 🎉")
        try store.create(name: "Second")
        try store.add("frontend-uwp/a.milk", to: "c1")
        try store.add("cream-of-the-crop/F/x.milk", to: "c1")
        try store.rename("c2", to: "Zweite")
        let reopened = makeStore()
        XCTAssertEqual(reopened.collections, store.collections)
        XCTAssertEqual(reopened.availability, .available)
        let document = try PresetCollectionsFile.decode(Data(contentsOf: fileURL)).file
        XCTAssertEqual(document.schemaVersion, 1)
    }

    // MARK: - Missing presets are kept (R14, S7)

    func testEntriesTheStoreCannotResolveSurviveEveryOperation() throws {
        let store = makeStore()
        try store.create(name: "A")
        for id in ["a", "gone/1.milk", "b", "gone/2.milk", "c"] { try store.add(id, to: "c1") }
        try store.reorderPresets(in: "c1", visibleOrder: ["c", "b", "a"])   // the UI passes only what it shows
        XCTAssertEqual(store.collection(id: "c1")?.presetIDs, ["c", "gone/1.milk", "b", "gone/2.milk", "a"])
        try store.remove(["b"], from: "c1")
        try store.rename("c1", to: "B")
        try store.add("d", to: "c1")
        XCTAssertEqual(makeStore().collection(id: "c1")?.presetIDs, ["c", "gone/1.milk", "gone/2.milk", "a", "d"])
    }

    // MARK: - Limits (R10)

    func testTheCollectionLimit() throws {
        let store = makeStore()
        for index in 0..<PresetCollectionLimits.maxCollections { try store.create(name: "Collection \(index)") }
        assertThrows(.tooManyCollections(limit: 100)) { try store.create(name: "One too many") }
        XCTAssertEqual(store.collections.count, 100)
        XCTAssertEqual(makeStore().collections.count, 100)
    }

    func testThePresetLimit() throws {
        var ids = (0..<PresetCollectionLimits.maxPresetsPerCollection).map { "pack/\($0).milk" }
        try put(PresetCollectionsFile(schemaVersion: 1, collections: [PresetCollection(id: "big", name: "Big", presetIDs: ids)]).encode())
        let store = makeStore()
        assertThrows(.collectionFull(limit: 1_000)) { try store.add("pack/extra.milk", to: "big") }
        XCTAssertFalse(try store.add("pack/5.milk", to: "big"), "an entry already present is not a limit error")
        XCTAssertEqual(store.collection(id: "big")?.presetIDs.count, 1_000)
        // S9 (host figure, not device evidence): reordering and saving the largest collection.
        ids.reverse()
        let start = Date()
        try store.reorderPresets(in: "big", visibleOrder: ids)
        let reopened = makeStore()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(reopened.collection(id: "big")?.presetIDs, ids)
    }

    // MARK: - A failed save changes nothing (R8, S5)

    func testAFailedWriteLeavesMemoryAndDiskAsTheyWere() throws {
        let good = makeStore()
        try good.create(name: "A")
        try good.create(name: "B")
        try good.add("p/1.milk", to: "c1")
        try good.add("p/2.milk", to: "c1")
        let bytes = try Data(contentsOf: fileURL)
        let failing = makeStore(failingWrites: true)
        let before = failing.collections
        XCTAssertEqual(before, good.collections)
        assertThrows(.saveFailed) { try failing.create(name: "C") }
        assertThrows(.saveFailed) { try failing.rename("c1", to: "Z") }
        assertThrows(.saveFailed) { try failing.delete("c1") }
        assertThrows(.saveFailed) { try failing.add("p/3.milk", to: "c1") }
        assertThrows(.saveFailed) { try failing.remove(["p/1.milk"], from: "c1") }
        assertThrows(.saveFailed) { try failing.reorderPresets(in: "c1", visibleOrder: ["p/2.milk", "p/1.milk"]) }
        assertThrows(.saveFailed) { try failing.reorderCollections(["c2", "c1"]) }
        XCTAssertEqual(failing.collections, before)
        XCTAssertEqual(try Data(contentsOf: fileURL), bytes, "S5: byte-for-byte unchanged")
    }

    func testARealWriteFailureIsReportedAndChangesNothing() throws {
        // The store's directory path is occupied by a regular file, so nothing can be written there.
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("in the way".utf8).write(to: directory)
        let store = makeStore()
        XCTAssertEqual(store.collections, [])
        assertThrows(.saveFailed) { try store.create(name: "A") }
        XCTAssertEqual(store.collections, [])
        XCTAssertEqual(try Data(contentsOf: directory), Data("in the way".utf8))
    }

    func testTheRealWriterLeavesNoTemporaryFiles() throws {
        let store = makeStore()
        try store.create(name: "A")
        try store.add("p/1.milk", to: "c1")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [PresetCollectionStore.fileName])
    }

    // MARK: - Loading (R15, S6)

    func testTheGoldenFixtureLoads() throws {
        try put(Golden.data("collections-v1"))
        let store = makeStore()
        XCTAssertEqual(store.collections.map(\.name), ["Zebra set", "Café 🎉 late", "Empty"])
        XCTAssertEqual(store.availability, .available)
        XCTAssertEqual(store.loadNotice, .none)
        XCTAssertEqual(try Data(contentsOf: fileURL), try Golden.data("collections-v1"), "loading does not rewrite the file")
    }

    func testANewerFormatIsLeftUntouchedAndReadOnly() throws {
        let newer = Data(#"{"schemaVersion":2,"collections":[{"id":"n1","title":"Future"}],"tags":{"a":1}}"#.utf8)
        try put(newer)
        let store = makeStore()
        XCTAssertEqual(store.availability, .newerFormat(version: 2))
        XCTAssertEqual(store.collections, [])
        XCTAssertEqual(store.loadNotice, .none)
        assertThrows(.newerFormat(version: 2)) { try store.create(name: "A") }
        assertThrows(.newerFormat(version: 2)) { try store.rename("n1", to: "A") }
        assertThrows(.newerFormat(version: 2)) { try store.delete("n1") }
        assertThrows(.newerFormat(version: 2)) { try store.add("p", to: "n1") }
        assertThrows(.newerFormat(version: 2)) { try store.remove(["p"], from: "n1") }
        assertThrows(.newerFormat(version: 2)) { try store.reorderPresets(in: "n1", visibleOrder: []) }
        assertThrows(.newerFormat(version: 2)) { try store.reorderCollections([]) }
        XCTAssertEqual(try Data(contentsOf: fileURL), newer, "S6: byte-for-byte unchanged")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [PresetCollectionStore.fileName])
    }

    func testAnUnreadableFileIsSetAsideNotDeleted() throws {
        let damaged = Data("{ this is not a collections document".utf8)
        try put(damaged)
        let store = makeStore()
        XCTAssertEqual(store.availability, .available)
        XCTAssertEqual(store.loadNotice, .unreadableSetAside)
        XCTAssertEqual(store.collections, [])
        XCTAssertEqual(try Data(contentsOf: asideURL), damaged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        try store.create(name: "Fresh start")
        XCTAssertEqual(try Data(contentsOf: asideURL), damaged, "saving does not touch the set-aside copy")
        let reopened = makeStore()
        XCTAssertEqual(reopened.loadNotice, .none, "the notice is given once")
        XCTAssertEqual(reopened.collections.map(\.name), ["Fresh start"])
        // A second unreadable file replaces the earlier set-aside copy: one copy is kept.
        let second = Data("[1,2,3]".utf8)
        try put(second)
        XCTAssertEqual(makeStore().loadNotice, .unreadableSetAside)
        XCTAssertEqual(try Data(contentsOf: asideURL), second)
    }

    func testAnEmptyDirectoryLoadsAsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = makeStore()
        XCTAssertEqual(store.collections, [])
        XCTAssertEqual(store.availability, .available)
    }

    // MARK: - Migration (R15)

    func testAnOlderDocumentIsMigratedSavedAndTheBackupRemoved() throws {
        try put(LegacyV0.data)
        let store = makeStore(migrations: [0: LegacyV0.step])
        XCTAssertEqual(store.availability, .available)
        XCTAssertEqual(store.collections.map(\.name), ["Old one", "Old two"])
        let saved = try PresetCollectionsFile.decode(Data(contentsOf: fileURL))
        XCTAssertNil(saved.migratedFrom, "the saved document is the current version")
        XCTAssertEqual(saved.file.collections, store.collections)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [PresetCollectionStore.fileName],
                       "the backup is removed once the migrated document is saved")
    }

    func testAMigrationWhoseSaveFailsKeepsTheOriginal() throws {
        try put(LegacyV0.data)
        let store = makeStore(failingWrites: true, migrations: [0: LegacyV0.step])
        XCTAssertEqual(store.collections.map(\.name), ["Old one", "Old two"], "the store runs on the migrated list")
        XCTAssertEqual(try Data(contentsOf: fileURL), LegacyV0.data, "the original is untouched")
        let backup = directory.appendingPathComponent("collections.v0.backup.json")
        XCTAssertEqual(try Data(contentsOf: backup), LegacyV0.data, "and its backup is kept")
        // The next launch (writes working again) migrates again and cleans up.
        let next = makeStore(migrations: [0: LegacyV0.step])
        XCTAssertEqual(next.collections.map(\.name), ["Old one", "Old two"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [PresetCollectionStore.fileName])
    }

    func testTheDefaultDirectoryIsInApplicationSupport() {
        let url = PresetCollectionStore.defaultDirectory()
        XCTAssertEqual(url.lastPathComponent, "PresetCollections")
        XCTAssertTrue(url.path.contains("Application Support") || url.path.contains(".local/share") || url.path.contains("/tmp"),
                      url.path)
    }
}
