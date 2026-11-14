// MediaRestoreTests.swift — FILE-006-T09 (FILE-006-S4; FILE-006-R8; research FILE-006-D6): media back
// from a folder backup. Round trip into an empty library root (every photo and video identifier resolves
// to equal bytes; the audio assets and index are equal); a device file is never replaced; imported audio
// is skipped when the device has its own; a tampered or missing copy refuses with nothing staged; an
// interrupted install runs again; a newer request is ignored.
import Foundation
import LocalPortability
import XCTest
@testable import LibraryBackup

final class MediaRestoreTests: XCTestCase {
    private func freshRoot(_ fixture: MediaLibraryFixture) throws -> URL {
        let root = fixture.destination.deletingLastPathComponent().appendingPathComponent("new-device", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func logical(_ root: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        for asset in MediaBackupInventory.assets(root: root) { result[asset.key] = try? Data(contentsOf: asset.url) }
        return result
    }

    func testARestoreRoundTripRecreatesEveryAsset() throws {
        let fixture = try MediaLibraryFixture.make(self, "roundtrip")
        try fixture.backUp(CountingFileAccess())
        let root = try freshRoot(fixture)
        let summary = try MediaRestoreStager().stage(from: fixture.destination, root: root)
        XCTAssertEqual(summary.assets, 5)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertTrue(MediaRestoreRequestStore(root: root).isPending)
        XCTAssertEqual(logical(root), [:], "nothing is installed before the next launch")

        let result = try XCTUnwrap(MediaRestoreLaunch.run(root: root))
        XCTAssertEqual(result, MediaRestoreResult(installed: 5, alreadyHere: 0, skipped: 0))
        XCTAssertEqual(logical(root), logical(fixture.root), "every photo, video and audio file comes back byte for byte")
        let store = MediaRestoreRequestStore(root: root)
        XCTAssertFalse(store.isPending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.staged.path))
        XCTAssertEqual(store.takeResult(), result)
        XCTAssertNil(store.takeResult(), "the result is shown once")
        // FILE-008's launch migration registers the legacy files the restore wrote.
        let photos = ContentAddressedMediaFolder(directory: MediaBackupInventory.photosFolder(root), extensions: LibraryErasePolicy.photoExtensions)
        _ = try photos.reconcile()
        XCTAssertNotNil(photos.resolve(MediaLibraryFixture.photo))
        XCTAssertNil(MediaRestoreLaunch.run(root: root), "nothing pending any more")
    }

    func testTheDeviceKeepsItsOwnFilesAndAudio() throws {
        let fixture = try MediaLibraryFixture.make(self, "keep")
        try fixture.backUp(CountingFileAccess())
        let root = try freshRoot(fixture)
        // The device already holds the photo identifier (other bytes) and its own audio library.
        let photos = ContentAddressedMediaFolder(directory: MediaBackupInventory.photosFolder(root), extensions: LibraryErasePolicy.photoExtensions)
        try FileManager.default.createDirectory(at: photos.directory, withIntermediateDirectories: true)
        let mine = photos.payloadURL(MediaLibraryFixture.photo.uuidString + ".png")
        try BackupFixtures.png(42).write(to: mine)
        let audio = MediaBackupInventory.audioFolder(root)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"tracks":["mine"]}"#.utf8).write(to: audio.appendingPathComponent("index.json"))
        _ = try MediaRestoreStager().stage(from: fixture.destination, root: root)
        let result = try XCTUnwrap(MediaRestoreLaunch.run(root: root))
        XCTAssertEqual(result.installed, 2, "the video and the legacy photo")
        XCTAssertEqual(result.alreadyHere, 1)
        XCTAssertEqual(result.skipped, 2, "the audio asset and the index")
        XCTAssertEqual(try Data(contentsOf: mine), BackupFixtures.png(42), "the device's photo is not replaced")
        XCTAssertEqual(try Data(contentsOf: audio.appendingPathComponent("index.json")), Data(#"{"schemaVersion":1,"tracks":["mine"]}"#.utf8))
        XCTAssertTrue(result.message.contains("2 added, 1 already on this device"), result.message)
    }

    func testATamperedOrMissingCopyRefusesWithNothingStaged() throws {
        let fixture = try MediaLibraryFixture.make(self, "tampered")
        let report = try fixture.backUp(CountingFileAccess())
        let video = try XCTUnwrap(report.manifest.assets.first { (e: BackupAssetEntry) -> Bool in e.kind == BackupAssetKind.video })
        let url = fixture.backupFolder.appendingPathComponent(video.location)
        var bytes = try Data(contentsOf: url)
        bytes[100] ^= 0xFF   // same size, other content
        try bytes.write(to: url)
        let root = try freshRoot(fixture)
        XCTAssertThrowsError(try MediaRestoreStager().stage(from: fixture.destination, root: root)) { (error: any Error) in
            XCTAssertEqual(error as? MediaRestoreError, .unverifiable(video.name))
        }
        let store = MediaRestoreRequestStore(root: root)
        XCTAssertFalse(store.isPending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.staged.path), "nothing staged")
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try MediaRestoreStager().stage(from: fixture.destination, root: root))
        XCTAssertThrowsError(try MediaRestoreStager().stage(from: root, root: root)) { (error: any Error) in
            XCTAssertEqual(error as? MediaRestoreError, .noManifest)
        }
    }

    func testAnInterruptedInstallRunsAgainAndANewerRequestIsIgnored() throws {
        let fixture = try MediaLibraryFixture.make(self, "rerun")
        try fixture.backUp(CountingFileAccess())
        let root = try freshRoot(fixture)
        _ = try MediaRestoreStager().stage(from: fixture.destination, root: root)
        let store = MediaRestoreRequestStore(root: root)
        // Simulate a kill after part of the install: run the installer without finishing the launch step.
        let request = try XCTUnwrap(store.request)
        _ = MediaRestoreInstaller.install(MediaRestoreRequest(schemaVersion: 1, assets: Array(request.assets.prefix(2))), store: store)
        let result = try XCTUnwrap(MediaRestoreLaunch.run(root: root))
        XCTAssertEqual(result.installed + result.alreadyHere, 5)
        XCTAssertEqual(logical(root), logical(fixture.root))

        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":2,"assets":[]}"#.utf8).write(to: store.requestFile)
        XCTAssertNil(MediaRestoreLaunch.run(root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.requestFile.path), "a newer request is removed")
    }

    func testCancelRemovesTheRequest() throws {
        let fixture = try MediaLibraryFixture.make(self, "cancel")
        try fixture.backUp(CountingFileAccess())
        let root = try freshRoot(fixture)
        _ = try MediaRestoreStager().stage(from: fixture.backupFolder, root: root)   // the backup folder itself can be picked
        let store = MediaRestoreRequestStore(root: root)
        XCTAssertTrue(store.isPending)
        store.cancel()
        XCTAssertFalse(store.isPending)
        XCTAssertNil(MediaRestoreLaunch.run(root: root))
        XCTAssertEqual(logical(root), [:])
    }
}
