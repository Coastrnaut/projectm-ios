// LibraryBackupPresetOverrideTests.swift — PRE-016-T16 (PRE-016-R9, R10, S5; research PRE-016-D5): the
// library backup carries preset overrides; a restore onto an empty library gives the same overrides;
// a restore onto a device with overrides merges per preset by the choice (Keep both = the device's
// values plus the backup's others, Replace, Skip); the FILE-011 Collections erase leaves none.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryBackupPresetOverrideTests: XCTestCase {
    private func writeOverrides(_ folders: LibraryFolders, _ entries: [String: [String: Double]]) throws {
        var map = PresetOverrideMap()
        for (id, values) in entries { for (key, value) in values { try map.set(value, for: key, preset: id) } }
        try FileManager.default.createDirectory(at: folders.url(.collections), withIntermediateDirectories: true)
        try PresetOverridesFile.encode(map).write(to: folders.overridesFile)
    }

    private func overrides(_ folders: LibraryFolders) throws -> PresetOverrideMap {
        try PresetOverridesFile.decode(Data(contentsOf: folders.overridesFile)).map
    }

    func testABackupRoundTripKeepsEveryOverride() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        try writeOverrides(source, ["included/Alpha.milk": ["zoom": 1.05, "fDecay": 0.95], BackupFixtures.presetID(1): ["wave_r": 0.2]])
        let backup = try BackupFixtures.backup(of: source)
        XCTAssertTrue(try LibraryBackupReader.read(backup).manifest.files.contains { $0.path == LibraryBackupFormat.overridesPath })

        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }
        XCTAssertEqual(try overrides(fresh), try overrides(source))
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: [:]).digests["preset-overrides"],
                       try LibraryRecords.read(folders: source, settings: [:]).digests["preset-overrides"])
        XCTAssertNotNil(try LibraryRecords.read(folders: fresh, settings: [:]).digests["preset-overrides"])
    }

    func testRestoreMergesOverridesByChoice() throws {
        var backupMap = PresetOverrideMap()
        try backupMap.set(1.1, for: "zoom", preset: "p")
        try backupMap.set(0.95, for: "fDecay", preset: "p")
        try backupMap.set(0.5, for: "warp", preset: "q")
        var deviceMap = PresetOverrideMap()
        try deviceMap.set(0.9, for: "zoom", preset: "p")
        let backup = LibraryContents(presetOverrides: backupMap)
        let device = LibraryContents(presetOverrides: deviceMap)

        let union = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .keepBoth)
        XCTAssertEqual(union.presetOverrides?.overrides(for: "p"), ["zoom": 0.9, "fDecay": 0.95])
        XCTAssertEqual(union.presetOverrides?.overrides(for: "q"), ["warp": 0.5])
        XCTAssertEqual(union.entries.first { $0.key == "overrides/p" }?.action, .union)
        XCTAssertEqual(union.changedFolders, [.collections])

        let replaced = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .replace)
        XCTAssertEqual(replaced.presetOverrides?.overrides(for: "p"), ["zoom": 1.1, "fDecay": 0.95])

        let skipped = LibraryRestorePlanner.plan(backup: backup, library: device, choice: .skip)
        XCTAssertEqual(skipped.presetOverrides?.overrides(for: "p"), ["zoom": 0.9])
        XCTAssertEqual(skipped.presetOverrides?.overrides(for: "q"), ["warp": 0.5], "a new entry is added under Skip too")
        XCTAssertEqual(skipped.count(.overrides, .clash), 1)

        let same = LibraryRestorePlanner.plan(backup: backup, library: backup)
        XCTAssertNil(same.presetOverrides)
        XCTAssertEqual(same.count(.overrides, .identical), 2)
    }

    func testEraseOfCollectionsRemovesOverrides() throws {
        let sandbox = try EraseFixtures.sandbox(self, "overrides")
        try writeOverrides(sandbox.folders, ["included/Alpha.milk": ["zoom": 1.1]])
        XCTAssertEqual(LibraryEraseInventory.count(.collections, root: sandbox.root, settings: [:]), 3, "two collections and one adjusted preset")
        try EraseFixtures.erase([.collections], in: sandbox, defaults: EraseFixtures.Defaults())
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.folders.overridesFile.path))
    }
}
