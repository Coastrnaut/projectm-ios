// LibraryBackupHostileTests.swift — FILE-005-T12 (FILE-005-R2, R3, S4): damaged, foreign, newer and
// malicious backups are refused before anything is written; an older record inside is migrated.
import Foundation
import LocalPortability
import PresetLibrary
import SceneFormat
import XCTest
@testable import LibraryBackup

final class LibraryBackupHostileTests: XCTestCase {
    private func validBackup() throws -> Data {
        let folders = BackupFixtures.sandbox(self)
        try BackupFixtures.populate(folders)
        return try BackupFixtures.backup(of: folders)
    }

    /// Writes an archive with a correct checksummed manifest around `files` (so only the layer under test fails).
    private func archive(_ files: [(String, Data)], version: Int = 1, format: String = LibraryBackupFormat.name) throws -> Data {
        var output = Data()
        let writer = PortableArchiveWriter(modified: BackupFixtures.now) { (chunk: Data) in output.append(chunk) }
        var records: [PortableFileRecord] = []
        for (path, data) in files { records.append(try writer.add(path: path, data: data)) }
        let manifest = LibraryBackupManifest(format: format, formatVersion: version, files: records, appVersion: "9", createdAt: "2026-11-13T00:00:00Z",
                                             counts: LibraryBackupCounts(scenes: 0, cues: 0, currentScene: 0, presets: 0, collections: 0,
                                                                         favorites: 0, settings: 0, photos: 0),
                                             excluded: LibraryExclusions())
        try writer.finish(manifest: try JSONEncoder().encode(manifest))
        return output
    }

    private func assertRefused(_ data: Data, _ expected: LibraryBackupError? = nil, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try LibraryBackupReader.read(data)
            XCTFail("accepted", file: file, line: line)
        } catch {
            if let expected { XCTAssertEqual(error, expected, file: file, line: line) }
            XCTAssertFalse(error.message.isEmpty, file: file, line: line)
        }
    }

    func testTruncatedAndCorruptedBackupsAreRefused() throws {
        let data = try validBackup()
        assertRefused(data.prefix(data.count / 2))
        assertRefused(Data())
        var flipped = data
        flipped[200] ^= 0xFF
        assertRefused(flipped)
        assertRefused(Data("not a zip at all".utf8))
    }

    func testForeignNewerAndOlderVersionsAreHandled() throws {
        assertRefused(try archive([("settings.json", Data("{}".utf8))], format: "org.projectmios.scene-archive"), .archive(.wrongFormat))
        assertRefused(try archive([("settings.json", Data("{}".utf8))], version: 2), .archive(.newerVersion(2)))
        assertRefused(try archive([("settings.json", Data("{}".utf8))], version: 0))
        XCTAssertEqual(LibraryBackupError.archive(.newerVersion(2)).message,
                       "This archive was made by a newer version of the app. Update the app to read it.")
        XCTAssertEqual(LibraryBackupFormat.readableVersions, [1])
        XCTAssertEqual(LibraryBackupError.archive(.wrongFormat).message, "This file is not a projectM-iOS library backup.")
    }

    func testUnexpectedUnsafeAndMismatchedEntriesAreRefused() throws {
        assertRefused(try archive([("notes.txt", Data("x".utf8))]), .unexpectedEntry("notes.txt"))
        XCTAssertFalse(LibraryBackupReader.isKnownPath("show/scenes/../../evil.scene.json"))   // the ZIP layer refuses it first
        XCTAssertFalse(LibraryBackupReader.isKnownPath("presets/texts/ABC.milk"))
        let scene = BackupFixtures.sceneBytes(1)
        let path = LibraryBackupFormat.scenePath(BackupFixtures.sceneID(2))
        assertRefused(try archive([(path, scene)]), .unreadableRecord(path))
        let text = BackupFixtures.presetText("Stray")
        let stray = LibraryBackupFormat.presetTextPath(ContentHash.sha256Hex([UInt8](text)))
        assertRefused(try archive([(stray, text)]), .unexpectedEntry(stray))
        assertRefused(try archive([("photos/" + BackupFixtures.photoName(1), Data("GIF89a".utf8))]))
    }

    func testExcludedRecordsAreRefused() throws {
        let paid = BackupFixtures.presetText("Paid")
        let record = BackupFixtures.record(4, name: "Paid", text: paid, fullLibrary: true)
        let path = LibraryBackupFormat.presetTextPath(record.sha256)
        assertRefused(try archive([(LibraryBackupFormat.presetIndexPath, try UserPresetsFile(presets: [record]).encode()), (path, paid)]),
                      .excludedRecord(path))
        let settings = Data("{\"schemaVersion\":1,\"values\":{\"settings.osc.enabled\":{\"type\":\"bool\",\"value\":true}}}".utf8)
        assertRefused(try archive([(LibraryBackupFormat.settingsPath, settings)]), .excludedRecord("settings.json#settings.osc.enabled"))
    }

    func testATamperedPresetTextIsRefused() throws {
        let text = BackupFixtures.presetText("Alpha")
        let record = BackupFixtures.record(1, name: "Alpha", text: text)
        let path = LibraryBackupFormat.presetTextPath(record.sha256)
        assertRefused(try archive([(LibraryBackupFormat.presetIndexPath, try UserPresetsFile(presets: [record]).encode()),
                                   (path, Data("[preset00]\nother".utf8))]), .unreadableRecord(path))
    }

    func testOversizeBackupsAreRefusedBeforeReading() {
        XCTAssertEqual(LibraryBackupFormat.maxFileBytes, 536_870_912)
        XCTAssertEqual(LibraryBackupFormat.limits.maxFiles, 4_096)
        XCTAssertEqual(LibraryBackupFormat.limits.maxFileBytes, 67_108_864)
        XCTAssertEqual(LibraryBackupError.tooLarge(limit: LibraryBackupFormat.maxFileBytes).message,
                       "This backup is larger than 512 MB and cannot be read.")
    }

    func testTooManyPhotosAreRefused() throws {
        var files: [(String, Data)] = []
        for n in 1...(LibraryBackupFormat.maxPhotos + 1) { files.append(("photos/" + BackupFixtures.photoName(n), BackupFixtures.png(UInt8(n)))) }
        assertRefused(try archive(files), .tooManyPhotos(limit: 64))
    }

    /// FILE-005-R3: an older record inside a backup is read through its own migration (here a
    /// version-1 preset index, PRE-012); SCN-001 has a single format version today.
    func testAnOlderRecordInsideABackupIsMigrated() throws {
        let text = BackupFixtures.presetText("Alpha")
        let record = BackupFixtures.record(1, name: "Alpha", text: text)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try UserPresetsFile(presets: [record]).encode()) as? [String: Any])
        json["schemaVersion"] = 1
        let older = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let backup = try LibraryBackupReader.read(try archive([(LibraryBackupFormat.presetIndexPath, older),
                                                               (LibraryBackupFormat.presetTextPath(record.sha256), text)]))
        XCTAssertEqual(backup.contents.presets.map(\.record.id), [record.id])
        XCTAssertEqual(LibraryRecords(backup.contents).digests["preset/" + record.id],
                       LibraryRecords(LibraryContents(presets: [LibraryPreset(record: record, text: text)])).digests["preset/" + record.id])
    }
}
