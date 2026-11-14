// LibraryBackupWriterTests.swift — FILE-005-T06 (FILE-005-R1, R2, S5): the manifest, deterministic
// bytes, and the exclusions.
import Foundation
import LocalPortability
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryBackupWriterTests: XCTestCase {
    private func entries(_ data: Data) throws -> [String: Data] {
        let list = try StoredZipReader.read(data, limits: LibraryBackupFormat.limits.zip)
        var map: [String: Data] = [:]
        for entry in list { map[entry.path] = entry.data }
        return map
    }

    func testTheManifestListsCountsExclusionsAndEveryEntry() throws {
        let folders = BackupFixtures.sandbox(self)
        try BackupFixtures.populate(folders)
        let data = try BackupFixtures.backup(of: folders)
        let backup = try LibraryBackupReader.read(data)
        let manifest = backup.manifest
        XCTAssertEqual(manifest.format, "org.projectmios.library-backup")
        XCTAssertEqual(manifest.formatVersion, 1)
        XCTAssertEqual(manifest.appVersion, "1.1 (2)")
        XCTAssertEqual(manifest.createdAt, "2026-11-13T12:00:00Z")
        XCTAssertEqual(manifest.counts, LibraryBackupCounts(scenes: 3, cues: 3, currentScene: 1, presets: 3, collections: 2, favorites: 2,
                                                            settings: 8, photos: 1))
        XCTAssertEqual(manifest.excluded.fullLibraryCopies, 1)
        XCTAssertEqual(manifest.excluded.quarantinedPresets, 1)
        XCTAssertEqual(manifest.excluded.videos, 1)
        XCTAssertEqual(manifest.excluded.importedAudio, 1)
        let paths = manifest.files.map(\.path)
        XCTAssertEqual(paths.first, "show/show.json")
        XCTAssertEqual(paths.filter { (p: String) -> Bool in p.hasPrefix("show/scenes/") }.count, 3)
        XCTAssertTrue(paths.contains("current/current.scene"))
        XCTAssertTrue(paths.contains("presets/index.json"))
        XCTAssertEqual(paths.filter { (p: String) -> Bool in p.hasPrefix("presets/texts/") }.count, 3)
        XCTAssertTrue(paths.contains("collections/collections.json"))
        XCTAssertTrue(paths.contains("settings.json"))
        XCTAssertTrue(paths.contains("photos/" + BackupFixtures.photoName(1)))
        let zipEntries = try entries(data)
        for record in manifest.files {
            XCTAssertEqual(PortableSHA256.hex(zipEntries[record.path] ?? Data()), record.sha256, record.path)
        }
        XCTAssertEqual(BackupFixtures.now.timeIntervalSince1970, 1_794_571_200)
        XCTAssertEqual(LibraryBackupFormat.fileName(createdAt: BackupFixtures.now), "projectM Library 2026-11-13.pmbackup")
    }

    func testEqualContentsGiveEqualBytes() throws {
        let folders = BackupFixtures.sandbox(self)
        try BackupFixtures.populate(folders)
        XCTAssertEqual(try BackupFixtures.backup(of: folders), try BackupFixtures.backup(of: folders))
    }

    /// FILE-005-S5: no full-library copy, quarantined text, video, imported audio, device key or entitlement.
    func testExclusionsAreEnforced() throws {
        let folders = BackupFixtures.sandbox(self)
        try BackupFixtures.populate(folders)
        let data = try BackupFixtures.backup(of: folders)
        let all = try entries(data)
        let paid = BackupFixtures.presetText("Paid")
        let broken = BackupFixtures.presetText("Broken")
        for (path, bytes) in all {
            XCTAssertNil(bytes.range(of: paid), "\(path) holds the full-library copy's text")
            XCTAssertNil(bytes.range(of: broken), "\(path) holds the quarantined text")
            XCTAssertNil(bytes.range(of: Data("VIDEO-PAYLOAD".utf8)), path)
            XCTAssertNil(bytes.range(of: Data("AUDIO-PAYLOAD".utf8)), path)
        }
        let joined = all.values.reduce(Data()) { (sum: Data, next: Data) -> Data in sum + next }
        let forbidden: [String] = ["settings.osc.enabled", "settings.midi.enabled", "settings.video.id", "settings.video.speed", "notice.photosensitivity",
                                   "cream-of-the-crop", BackupFixtures.presetID(4), BackupFixtures.presetID(5),
                                   "entitlement", "unlocked", "transaction"]
        for word in forbidden { XCTAssertNil(joined.range(of: Data(word.utf8)), "the backup mentions \(word)") }
        let contents = try LibraryBackupReader.read(data).contents
        XCTAssertEqual(Set(contents.settings.keys), Set(["favorites", "lastPresetID", "settings.visual", "settings.camera.zoom",
                                                         "settings.osc.port", "settings.reduceFlashing", "settings.text.overlay",
                                                         "settings.latencyOffset.microphone"]))
        XCTAssertTrue(Set(LibrarySettingsPolicy.includedKeys).isDisjoint(with: LibrarySettingsPolicy.excludedKeys))
        // The Included copy is kept (ADR-0008: only full-library copies stay on the device).
        XCTAssertTrue(contents.presets.contains { (p: LibraryPreset) -> Bool in p.record.id == BackupFixtures.presetID(3) })
    }

    func testAnEmptyLibraryWritesAValidBackup() throws {
        let folders = BackupFixtures.sandbox(self)
        let contents = try LibraryContentsReader.read(folders: folders, settings: [:])
        let data = try LibraryBackupWriter.write(contents, appVersion: "1.1 (2)", createdAt: BackupFixtures.now)
        let backup = try LibraryBackupReader.read(data)
        XCTAssertEqual(backup.manifest.counts, LibraryBackupCounts(scenes: 0, cues: 0, currentScene: 0, presets: 0, collections: 0,
                                                                   favorites: 0, settings: 0, photos: 0))
        XCTAssertEqual(backup.manifest.files.map(\.path), ["settings.json"])
    }
}
