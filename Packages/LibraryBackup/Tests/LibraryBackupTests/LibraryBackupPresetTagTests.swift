// LibraryBackupPresetTagTests.swift — PRE-003-T17 (PRE-003-R13, S4; research PRE-003-D6): the
// library backup carries preset tags; restore merges them per preset by the choice (Keep both =
// union capped at 16, Replace, Skip); a Keep-both copy of a user preset takes its tags along; the
// FILE-011 erase of "Collections, tags and favorites" leaves no tags.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryBackupPresetTagTests: XCTestCase {
    private func writeTags(_ folders: LibraryFolders, _ entries: [String: [String]]) throws {
        var map = PresetTagMap()
        for (id, tags) in entries { for tag in tags { try map.add(tag, to: id) } }
        try FileManager.default.createDirectory(at: folders.url(.collections), withIntermediateDirectories: true)
        try PresetTagsFile.encode(map).write(to: folders.tagsFile)
    }

    private func tags(_ folders: LibraryFolders) throws -> PresetTagMap {
        try PresetTagsFile.decode(Data(contentsOf: folders.tagsFile)).map
    }

    func testABackupRoundTripKeepsEveryTag() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        try writeTags(source, ["included/Alpha.milk": ["Calm", "Slow"], BackupFixtures.presetID(1): ["Loud"]])
        let backup = try BackupFixtures.backup(of: source)
        XCTAssertTrue(try LibraryBackupReader.read(backup).manifest.files.contains { $0.path == LibraryBackupFormat.tagsPath })

        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }
        XCTAssertEqual(try tags(fresh), try tags(source))
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: [:]).digests["preset-tags"],
                       try LibraryRecords.read(folders: source, settings: [:]).digests["preset-tags"])
    }

    func testRestoreMergesTagsByChoice() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        try writeTags(source, ["included/Alpha.milk": ["Calm", "Slow"], "included/Beta.milk": ["Loud"]])
        let backup = try BackupFixtures.backup(of: source)

        func device(_ label: String) throws -> LibraryFolders {
            let folders = BackupFixtures.sandbox(self, label)
            try BackupFixtures.populate(folders)
            try writeTags(folders, ["included/Alpha.milk": ["Ambient", "calm"]])
            return folders
        }
        let union = try device("union")
        _ = try BackupFixtures.restore(backup, into: union, sink: BackupFixtures.SettingsSink(), choice: .keepBoth)
        XCTAssertEqual(try tags(union).tags(of: "included/Alpha.milk"), ["Ambient", "calm", "Slow"])
        XCTAssertEqual(try tags(union).tags(of: "included/Beta.milk"), ["Loud"])

        let replaced = try device("replace")
        _ = try BackupFixtures.restore(backup, into: replaced, sink: BackupFixtures.SettingsSink(), choice: .replace)
        XCTAssertEqual(try tags(replaced).tags(of: "included/Alpha.milk"), ["Calm", "Slow"], "the backup's tags and spellings")

        let skipped = try device("skip")
        _ = try BackupFixtures.restore(backup, into: skipped, sink: BackupFixtures.SettingsSink(), choice: .skip)
        XCTAssertEqual(try tags(skipped).tags(of: "included/Alpha.milk"), ["Ambient", "calm"])
        XCTAssertEqual(try tags(skipped).tags(of: "included/Beta.milk"), ["Loud"], "a new entry is added under Skip too")
    }

    func testUnionIsCappedAtSixteenAndFallsBack() throws {
        var backupTags = PresetTagMap()
        var deviceTags = PresetTagMap()
        for i in 0..<10 { try backupTags.add("b\(i)", to: "p") }
        for i in 0..<10 { try deviceTags.add("d\(i)", to: "p") }
        let plan = LibraryRestorePlanner.plan(backup: LibraryContents(presetTags: backupTags), library: LibraryContents(presetTags: deviceTags))
        XCTAssertEqual(plan.presetTags?.tags(of: "p").count, 16)
        XCTAssertEqual(plan.entries.first { $0.key == "tags/p" }?.fellBack, true)
        XCTAssertEqual(plan.changedFolders, [.collections])
        XCTAssertEqual(plan.count(.tags, .clash), 1)
    }

    func testEraseOfCollectionsRemovesTags() throws {
        let sandbox = try EraseFixtures.sandbox(self, "tags")
        try writeTags(sandbox.folders, ["included/Alpha.milk": ["Calm"]])
        XCTAssertEqual(LibraryEraseInventory.count(.collections, root: sandbox.root, settings: [:]), 3, "two collections and one tagged preset")
        try EraseFixtures.erase([.collections], in: sandbox, defaults: EraseFixtures.Defaults())
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.folders.tagsFile.path))
        XCTAssertEqual(LibraryEraseCategory.collections.title, "Collections, tags and favorites")
    }
}
