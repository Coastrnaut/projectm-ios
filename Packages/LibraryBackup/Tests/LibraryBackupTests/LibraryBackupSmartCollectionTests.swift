// LibraryBackupSmartCollectionTests.swift — PRE-008-T09 (spec PRE-008-R10, S3; research PRE-008-D5): the
// library backup carries smart collections; restore merges them per ID by the choice; the FILE-011 erase of
// "Collections, tags, favorites and history" removes and counts them.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryBackupSmartCollectionTests: XCTestCase {
    private static let calm = PresetSmartCollection(id: "smart-1", name: "Calm", match: .all,
                                                    conditions: [PresetSmartCondition(.tag, ["Calm"]), PresetSmartCondition(kind: "bpm", values: ["120"])])
    private static let packs = PresetSmartCollection(id: "smart-2", name: "Packs", match: .any,
                                                     conditions: [PresetSmartCondition(.pack, ["en-d"])])

    private func write(_ folders: LibraryFolders, _ list: [PresetSmartCollection]) throws {
        try FileManager.default.createDirectory(at: folders.url(.collections), withIntermediateDirectories: true)
        try PresetSmartCollectionsFile(smartCollections: list).encode().write(to: folders.smartCollectionsFile)
    }

    private func read(_ folders: LibraryFolders) throws -> [PresetSmartCollection] {
        try PresetSmartCollectionsFile.decode(Data(contentsOf: folders.smartCollectionsFile)).file.smartCollections
    }

    func testABackupRoundTripKeepsEverySmartCollection() throws {
        XCTAssertEqual(LibraryFolders.smartCollectionsFileName, PresetSmartCollectionStore.fileName)
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        try write(source, [Self.calm, Self.packs])
        let backup = try BackupFixtures.backup(of: source)
        XCTAssertTrue(try LibraryBackupReader.read(backup).manifest.files.contains { $0.path == LibraryBackupFormat.smartCollectionsPath })

        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }
        XCTAssertEqual(try read(fresh), [Self.calm, Self.packs], "rules and the unknown kind come back")
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: [:]).digests["smart-collections"],
                       try LibraryRecords.read(folders: source, settings: [:]).digests["smart-collections"])
    }

    func testRestoreMergesByIDAndChoice() {
        var edited = Self.calm
        edited.match = .any
        let backup = LibraryContents(smartCollections: [Self.calm, Self.packs])
        let device = LibraryContents(smartCollections: [edited])

        let kept = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .keepBoth)
        XCTAssertEqual(kept.smartCollections, [edited, Self.packs], "the device's clash is kept; the new one is added")
        XCTAssertEqual(kept.changedFolders, [.collections])
        let replaced = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .replace)
        XCTAssertEqual(replaced.smartCollections, [Self.calm, Self.packs])
        let same = LibraryRestorePlanner.plan(backup: backup, library: LibraryContents(smartCollections: [Self.calm, Self.packs]))
        XCTAssertNil(same.smartCollections, "identical: nothing to write")
    }

    func testEraseOfCollectionsRemovesSmartCollections() throws {
        let sandbox = try EraseFixtures.sandbox(self, "smart")
        let before: Int = LibraryEraseInventory.count(.collections, root: sandbox.root, settings: [:])
        try write(sandbox.folders, [Self.calm])
        XCTAssertEqual(LibraryEraseInventory.count(.collections, root: sandbox.root, settings: [:]), before + 1)
        try EraseFixtures.erase([.collections], in: sandbox, defaults: EraseFixtures.Defaults())
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.folders.smartCollectionsFile.path))
    }
}
