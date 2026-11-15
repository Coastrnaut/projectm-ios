// LibraryBackupPresetVersionTests.swift — PRE-017-T12 (spec PRE-017-R9, S4; research PRE-017-D8): restore points
// are local. A backup carries a preset's live text only (no `history.json`, no `versions/`); a restore that replaces
// the preset keeps the device's versions, and the preset's text is the backup's.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryBackupPresetVersionTests: XCTestCase {
    private func replaceText(of id: String, with tag: String, in folders: LibraryFolders, at minute: Double) throws {
        let store = UserPresetStore(directory: folders.url(.presets))
        let old = try XCTUnwrap(store.preset(id: id))
        let text = BackupFixtures.presetText(tag)
        let bytes = [UInt8](text)
        var new = old
        new.sha256 = ContentHash.sha256Hex(bytes)
        new.blobHash = ContentHash.gitBlobSHA1Hex(bytes)
        new.byteCount = bytes.count
        try store.replaceContents(id, with: new, contents: text, replacedAt: BackupFixtures.now.addingTimeInterval(minute * 60))
    }

    func testABackupRoundTripKeepsTheDevicesVersionsAndRestoresTheBackupsText() throws {
        let device = BackupFixtures.sandbox(self, "versions")
        try BackupFixtures.populate(device)
        let alpha = BackupFixtures.presetID(1)
        try replaceText(of: alpha, with: "Alpha edited", in: device, at: 1)
        let backup = try BackupFixtures.backup(of: device)
        let paths: [String] = try LibraryBackupReader.read(backup).manifest.files.map(\.path)
        XCTAssertFalse(paths.contains { (path: String) -> Bool in path.contains("history") || path.contains("versions") }, "\(paths)")

        try replaceText(of: alpha, with: "Alpha edited again", in: device, at: 2)
        let historyFile = device.url(.presets).appendingPathComponent(UserPresetHistoryFile.fileName)
        let versionsFolder = device.url(.presets).appendingPathComponent("versions", isDirectory: true)
        let historyBefore = try Data(contentsOf: historyFile)
        let versionNames = try FileManager.default.contentsOfDirectory(atPath: versionsFolder.path).sorted()
        XCTAssertEqual(versionNames.count, 2)

        let outcome = try BackupFixtures.restore(backup, into: device, sink: BackupFixtures.SettingsSink(), choice: .replace)
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }
        XCTAssertEqual(try Data(contentsOf: historyFile), historyBefore, "the device's version list is kept")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: versionsFolder.path).sorted(), versionNames)
        let store = UserPresetStore(directory: device.url(.presets))
        XCTAssertEqual(store.preset(id: alpha)?.sha256, ContentHash.sha256Hex([UInt8](BackupFixtures.presetText("Alpha edited"))))
        XCTAssertEqual(store.versions(of: alpha).count, 2)

        // A fresh install gets the presets and no versions.
        let fresh = BackupFixtures.sandbox(self, "fresh")
        guard case .restored = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink()) else { return XCTFail() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.url(.presets).appendingPathComponent(UserPresetHistoryFile.fileName).path))
    }
}
