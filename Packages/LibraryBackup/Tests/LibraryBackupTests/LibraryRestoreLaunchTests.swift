// LibraryRestoreLaunchTests.swift — FILE-005-T13 (contract C6, FILE-005-R6): the pending request and
// the launch-time runner.
import Foundation
import XCTest
@testable import LibraryBackup

final class LibraryRestoreLaunchTests: XCTestCase {
    func testAPendingRequestIsInstalledAtLaunchAndItsResultReadOnce() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let backup = try BackupFixtures.backup(of: source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let requests = LibraryRestoreRequestStore(folders: fresh)
        try requests.save(backup: backup, choice: .keepBoth)
        XCTAssertEqual(requests.pending?.choice, .keepBoth)
        let sink = BackupFixtures.SettingsSink()
        let note = LibraryRestoreLaunch.run(folders: fresh, settings: sink.values) { (values: [String: LibrarySettingValue]) in sink.apply(values) }
        XCTAssertEqual(note?.restored, true)
        XCTAssertEqual(note?.message, "Restored from backup: 4 scenes, 3 presets, 2 collections and 8 settings, plus 1 photo.")
        XCTAssertNil(requests.pending, "the request is removed")
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: sink.values),
                       try LibraryRecords.read(folders: source, settings: BackupFixtures.settings))
        XCTAssertEqual(requests.takeResult(), note)
        XCTAssertNil(requests.takeResult(), "shown once")
        XCTAssertNil(LibraryRestoreLaunch.run(folders: fresh, settings: sink.values) { _ in XCTFail("nothing pending") })
    }

    func testADamagedPendingBackupChangesNothingAndIsRemoved() throws {
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let requests = LibraryRestoreRequestStore(folders: fresh)
        try requests.save(backup: Data("not a backup".utf8), choice: .replace)
        let note = LibraryRestoreLaunch.run(folders: fresh, settings: [:]) { _ in XCTFail("no settings") }
        XCTAssertEqual(note?.restored, false)
        XCTAssertTrue(note?.message.hasSuffix("Nothing was changed.") ?? false, note?.message ?? "")
        XCTAssertNil(requests.pending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.url(.show).path))
    }

    func testABackupChangedAfterTheRequestIsRefused() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let requests = LibraryRestoreRequestStore(folders: fresh)
        try requests.save(backup: try BackupFixtures.backup(of: source), choice: .keepBoth)
        try Data("swapped".utf8).write(to: requests.backupFile)
        let note = LibraryRestoreLaunch.run(folders: fresh, settings: [:]) { _ in XCTFail("no settings") }
        XCTAssertEqual(note, LibraryRestoreResultNote(restored: false, message: LibraryRestoreText.failed))
    }
}
