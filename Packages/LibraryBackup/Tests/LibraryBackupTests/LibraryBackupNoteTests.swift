// LibraryBackupNoteTests.swift — PRE-011-T14 (spec PRE-011-R7, S3; research PRE-011-D5): the library backup carries
// the private preset notes (the user's own local file); restore merges them per preset by the choice; the FILE-011
// erase of "Collections, tags, favorites and history" removes and counts them.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryBackupNoteTests: XCTestCase {
    private static func notes(_ entries: [String: String]) -> PresetNoteMap {
        var map = PresetNoteMap()
        for (id, text) in entries { _ = try? map.set(text, for: id) }
        return map
    }

    private static let backupNotes = notes(["included/Alpha.milk": "Wedding intro ✨", "included/Beta.milk": "Too busy"])

    private func write(_ folders: LibraryFolders, _ map: PresetNoteMap) throws {
        try FileManager.default.createDirectory(at: folders.url(.collections), withIntermediateDirectories: true)
        try PresetNotesFile.encode(map).write(to: folders.notesFile)
    }

    func testABackupRoundTripKeepsEveryNote() throws {
        XCTAssertEqual(LibraryFolders.notesFileName, PresetNoteStore.fileName)
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        try write(source, Self.backupNotes)
        let backup = try BackupFixtures.backup(of: source)
        XCTAssertTrue(try LibraryBackupReader.read(backup).manifest.files.contains { $0.path == LibraryBackupFormat.notesPath })

        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }
        XCTAssertEqual(PresetNoteStore(directory: fresh.url(.collections)).map, Self.backupNotes)
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: [:]).digests["preset-notes"],
                       try LibraryRecords.read(folders: source, settings: [:]).digests["preset-notes"])
    }

    func testRestoreMergesByPresetAndChoice() {
        let device = LibraryContents(presetNotes: Self.notes(["included/Alpha.milk": "Mine"]))
        let backup = LibraryContents(presetNotes: Self.backupNotes)

        let kept = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .keepBoth)
        XCTAssertEqual(kept.presetNotes, Self.notes(["included/Alpha.milk": "Mine", "included/Beta.milk": "Too busy"]))
        XCTAssertEqual(kept.changedFolders, [.collections])
        XCTAssertEqual(kept.count(.notes, .clash), 1)
        XCTAssertEqual(kept.count(.notes, .new), 1)
        let replaced = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .replace)
        XCTAssertEqual(replaced.presetNotes, Self.backupNotes)
        let same = LibraryRestorePlanner.plan(backup: backup, library: LibraryContents(presetNotes: Self.backupNotes))
        XCTAssertNil(same.presetNotes, "identical: nothing to write")
    }

    func testEraseOfCollectionsRemovesAndCountsNotes() throws {
        let sandbox = try EraseFixtures.sandbox(self, "notes")
        let before: Int = LibraryEraseInventory.count(.collections, root: sandbox.root, settings: [:])
        try write(sandbox.folders, Self.backupNotes)
        XCTAssertEqual(LibraryEraseInventory.count(.collections, root: sandbox.root, settings: [:]), before + 2)
        try EraseFixtures.erase([.collections], in: sandbox, defaults: EraseFixtures.Defaults())
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.folders.notesFile.path))
    }
}
