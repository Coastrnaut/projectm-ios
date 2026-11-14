// LibraryBackupDedupTests.swift — FILE-008-T12 (FILE-008-R9, S4): a content-addressed Photos folder
// (two references to one payload) backs up exactly like the same photos stored as separate files, and
// its restore into an empty library is exact; the next launch's reconcile deduplicates what the restore
// wrote.
import Foundation
import LocalPortability
import XCTest
@testable import LibraryBackup

final class LibraryBackupDedupTests: XCTestCase {
    private func photosFolder(_ folders: LibraryFolders) -> ContentAddressedMediaFolder {
        ContentAddressedMediaFolder(directory: folders.url(.photos), extensions: ["png", "jpg"])
    }

    func testADeduplicatedFolderBacksUpTheSameEntriesAndRestoresExactly() throws {
        // Plain layout: the fixture's photo 1 plus photo 2 with the same bytes, as two files.
        let plain = BackupFixtures.sandbox(self, "plain")
        try BackupFixtures.populate(plain)
        try BackupFixtures.png(7).write(to: plain.url(.photos).appendingPathComponent(BackupFixtures.photoName(2)))
        // Deduplicated layout of the same library: migrate the two files into one payload.
        let dedup = BackupFixtures.sandbox(self, "dedup")
        try BackupFixtures.populate(dedup)
        try BackupFixtures.png(7).write(to: dedup.url(.photos).appendingPathComponent(BackupFixtures.photoName(2)))
        let folder = photosFolder(dedup)
        try folder.reconcile()
        folder.prepare()
        XCTAssertEqual(folder.payloadNames().count, 1, "one physical payload")
        XCTAssertEqual(folder.references().count, 2, "two references")

        XCTAssertEqual(try BackupFixtures.backup(of: dedup), try BackupFixtures.backup(of: plain), "byte-identical backups")
        let original = try LibraryRecords.read(folders: dedup, settings: BackupFixtures.settings)
        XCTAssertEqual(original.digests.keys.filter { (key: String) -> Bool in key.hasPrefix("photo/") }.count, 2)

        let fresh = BackupFixtures.sandbox(self, "fresh")
        let sink = BackupFixtures.SettingsSink()
        guard case .restored = try BackupFixtures.restore(try BackupFixtures.backup(of: dedup), into: fresh, sink: sink) else {
            return XCTFail("not restored")
        }
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: sink.values).differences(from: original), [])
        // The next launch deduplicates the restored plain files; the records stay exact.
        let restored = photosFolder(fresh)
        try restored.reconcile()
        restored.prepare()
        XCTAssertEqual(restored.payloadNames().count, 1)
        XCTAssertEqual(try LibraryRecords.read(folders: fresh, settings: sink.values).differences(from: original), [])
    }
}
