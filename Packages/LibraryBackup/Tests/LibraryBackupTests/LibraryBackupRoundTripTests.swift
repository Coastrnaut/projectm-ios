// LibraryBackupRoundTripTests.swift — FILE-005-T09, the roadmap acceptance (FILE-005-S1): "Restore on
// fresh sandbox recreates exact local logical records."
import Foundation
import LocalPortability
import PresetLibrary
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

final class LibraryBackupRoundTripTests: XCTestCase {
    func testRestoreIntoAFreshSandboxRecreatesEveryIncludedRecordExactly() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let original = try LibraryRecords.read(folders: source, settings: BackupFixtures.settings)
        let backup = try BackupFixtures.backup(of: source)

        let fresh = BackupFixtures.sandbox(self, "fresh")
        let sink = BackupFixtures.SettingsSink()
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: sink)
        guard case let .restored(summary) = outcome else { return XCTFail("not restored: \(outcome)") }

        let restored = try LibraryRecords.read(folders: fresh, settings: sink.values)
        XCTAssertEqual(restored.differences(from: original), [], "every included record is recreated exactly")
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored, LibraryRecords(try LibraryBackupReader.read(backup).contents), "the restore holds what the backup holds")
        // Every record kind is present: the show, 3 scenes, the current scene, 3 presets, collections, 8 settings, 1 photo.
        let kinds: [String] = ["show", "scene/", "current-scene", "preset/", "collections", "setting/", "photo/"]
        for kind in kinds {
            XCTAssertTrue(original.digests.keys.contains { (key: String) -> Bool in key.hasPrefix(kind) }, "fixture holds \(kind)")
        }
        XCTAssertEqual(original.digests.keys.filter { (key: String) -> Bool in key.hasPrefix("preset/") }.count, 3)
        XCTAssertEqual(original.digests.keys.filter { (key: String) -> Bool in key.hasPrefix("setting/") }.count, 8)
        XCTAssertEqual(summary.scenes, 4)
        XCTAssertEqual(summary.presets, 3)
        XCTAssertEqual(summary.collections, 2)
        XCTAssertEqual(summary.settings, 8)
        XCTAssertEqual(summary.photos, 1)
        XCTAssertEqual(summary.message, "Restored from backup: 4 scenes, 3 presets, 2 collections and 8 settings, plus 1 photo.")
        // The stores read the restored folders.
        let show = ShowStore(directory: fresh.url(.show)).load()
        XCTAssertNil(show.refusal)
        XCTAssertEqual(show.list.cues.map(\.label), ["Cue 1", "Cue 2", "Cue 3"])
        XCTAssertTrue(show.unreadableScenes.isEmpty)
        // FILE-005-R11: restored presets wait for their check.
        let index = try UserPresetsFile.decode(Data(contentsOf: fresh.presetIndexFile)).file
        XCTAssertEqual(index.presets.map(\.state), [.pending, .pending, .pending])
        XCTAssertEqual(index.presets.map(\.id), [BackupFixtures.presetID(1), BackupFixtures.presetID(2), BackupFixtures.presetID(3)])
        // The work folders are gone; nothing else was created.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.restore.appendingPathComponent("staging").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.restore.appendingPathComponent("restore.journal.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.root.appendingPathComponent("Videos").path))
    }

    func testABackupOfTheRestoredLibraryHasTheSameRecords() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let first = try BackupFixtures.backup(of: source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let sink = BackupFixtures.SettingsSink()
        _ = try BackupFixtures.restore(first, into: fresh, sink: sink)
        let second = try BackupFixtures.backup(of: fresh, settings: sink.values)
        XCTAssertEqual(LibraryRecords(try LibraryBackupReader.read(second).contents), LibraryRecords(try LibraryBackupReader.read(first).contents))
    }

    func testRestoringTheSameBackupAgainChangesNothing() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let backup = try BackupFixtures.backup(of: source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let sink = BackupFixtures.SettingsSink()
        _ = try BackupFixtures.restore(backup, into: fresh, sink: sink)
        let before = LibraryTreeSnapshot.take(fresh.libraryRoots)
        let again = try BackupFixtures.restore(backup, into: fresh, sink: sink)
        XCTAssertEqual(again, .refused(LibraryRestoreText.nothingToRestore))
        XCTAssertEqual(LibraryTreeSnapshot.take(fresh.libraryRoots).differences(from: before), [])
    }

    func testTheEqualityFunctionSeesEachKindOfChange() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let base = try LibraryContentsReader.read(folders: source, settings: BackupFixtures.settings)
        let records = LibraryRecords(base)
        var changed = base
        changed.presets[0].record.name = "Renamed"
        XCTAssertEqual(LibraryRecords(changed).differences(from: records), ["preset/" + BackupFixtures.presetID(1)])
        changed = base
        changed.collections?.swapAt(0, 1)
        XCTAssertEqual(LibraryRecords(changed).differences(from: records), ["collections"], "collection order is a record")
        changed = base
        changed.settings["settings.osc.port"] = .int(9_001)
        XCTAssertEqual(LibraryRecords(changed).differences(from: records), ["setting/settings.osc.port"])
        changed = base
        changed.settings["settings.osc.port"] = .double(9_000)
        XCTAssertEqual(LibraryRecords(changed).differences(from: records), ["setting/settings.osc.port"], "the type is part of the value")
        changed = base
        changed.scenes[BackupFixtures.sceneID(1)] = BackupFixtures.sceneBytes(1, variant: 3)
        XCTAssertEqual(LibraryRecords(changed).differences(from: records), ["scene/" + BackupFixtures.sceneID(1)])
        changed = base
        changed.presets[0].record.state = .playable
        changed.presets[0].record.provenOnScreen = true
        XCTAssertEqual(LibraryRecords(changed), records, "the check state is not a logical record")
    }
}
