// FolderBackupAcceptanceTests.swift — FILE-006-T06 (FILE-006-S1, S2; roadmap acceptance "Second backup
// identifies unchanged assets without rereading video payload").
// * A second backup with no changes reads 0 bytes from the 4 MiB fake video and from every other media
//   file (IO-counting access), copies nothing, and writes equal asset entries.
// * A changed photo is the only file hashed and copied; a deleted asset's copy is pruned.
// * Two references to one payload give one copy and two entries.
import Foundation
import LocalPortability
import XCTest
@testable import LibraryBackup

final class FolderBackupAcceptanceTests: XCTestCase {
    func testASecondBackupDoesNotRereadTheVideoOrAnyUnchangedAsset() throws {
        let fixture = try MediaLibraryFixture.make(self, "unchanged")
        let access = CountingFileAccess()
        let first = try fixture.backUp(access)
        XCTAssertTrue(first.fullBackup)
        XCTAssertEqual(first.copied, 5, "video, two photos, audio asset, audio index")
        XCTAssertEqual(first.unchanged, 0)
        XCTAssertEqual(access.bytesRead(fixture.videoURL), Int64(MediaLibraryFixture.videoBytes), "the first backup reads the video once")
        fixture.assertManifestConsistent()
        let archive = fixture.backupFolder.appendingPathComponent(BackupFolderLayout.archiveName)
        XCTAssertEqual(try Data(contentsOf: archive), Data("archive".utf8))

        access.reset()
        let second = try fixture.backUp(access)
        XCTAssertFalse(second.fullBackup)
        XCTAssertEqual(access.bytesRead(fixture.videoURL), 0, "the video payload is not reread")
        XCTAssertEqual(access.totalBytesRead, 0, "no media file is read at all")
        XCTAssertEqual(access.copied, [], "nothing is copied")
        XCTAssertEqual(second.copied, 0)
        XCTAssertEqual(second.unchanged, 5)
        XCTAssertEqual(second.removed, 0)
        XCTAssertEqual(second.manifest.assets, first.manifest.assets, "the result is identical")
        XCTAssertEqual(second.manifest.library, first.manifest.library)
        fixture.assertManifestConsistent()
    }

    func testOnlyAChangedPhotoIsRehashedAndCopied() throws {
        let fixture = try MediaLibraryFixture.make(self, "changed")
        let access = CountingFileAccess()
        let first = try fixture.backUp(access)
        // The legacy photo (no content address) gets new bytes of the same size and a new date.
        let photo = fixture.legacyPhotoURL
        try BackupFixtures.png(9).write(to: photo)
        try FileManager.default.setAttributes([.modificationDate: BackupFixtures.now.addingTimeInterval(60)], ofItemAtPath: photo.path)
        access.reset()
        let second = try fixture.backUp(access)
        XCTAssertEqual(access.copied, [photo.lastPathComponent], "exactly the changed photo is copied")
        XCTAssertEqual(access.totalBytesRead, Int64(BackupFixtures.png(9).count), "and only it is read")
        XCTAssertEqual(access.bytesRead(fixture.videoURL), 0)
        XCTAssertEqual(second.copied, 1)
        XCTAssertEqual(second.unchanged, 4)
        XCTAssertEqual(second.removed, 1, "the photo's old copy is no longer named")
        let name = MediaLibraryFixture.legacyPhoto.uuidString + ".png"
        let before = first.manifest.assets.first { (e: BackupAssetEntry) -> Bool in e.name == name }
        let after = second.manifest.assets.first { (e: BackupAssetEntry) -> Bool in e.name == name }
        XCTAssertNotEqual(before?.sha256, after?.sha256)
        XCTAssertEqual(after?.sha256, PortableSHA256.hex(BackupFixtures.png(9)))
        fixture.assertManifestConsistent()
    }

    func testANewPayloadUnderTheSameIdentifierIsCopiedWithoutHashingTheRest() throws {
        let fixture = try MediaLibraryFixture.make(self, "reimport")
        let access = CountingFileAccess()
        try fixture.backUp(access)
        // Re-importing different photo bytes under a new identifier and releasing the old one (FILE-008).
        let scratch = fixture.root.appendingPathComponent("new.png")
        try BackupFixtures.png(11).write(to: scratch)
        let replacement = UUID(uuidString: "0A000000-0000-4000-8000-0000000000F8")!
        _ = try fixture.photos.intern(scratch, as: replacement, consumingSource: true)
        try fixture.photos.release([MediaLibraryFixture.photo])
        access.reset()
        let second = try fixture.backUp(access)
        XCTAssertEqual(second.copied, 1)
        XCTAssertEqual(access.totalBytesRead, Int64(BackupFixtures.png(11).count))
        XCTAssertEqual(second.removed, 1, "the released photo's copy is pruned")
        XCTAssertFalse(second.manifest.assets.contains { (e: BackupAssetEntry) -> Bool in e.name.hasPrefix(MediaLibraryFixture.photo.uuidString) })
        fixture.assertManifestConsistent()
    }

    func testADeletedAssetIsPrunedAndDropped() throws {
        let fixture = try MediaLibraryFixture.make(self, "deleted")
        let access = CountingFileAccess()
        let first = try fixture.backUp(access)
        let videoEntry = try XCTUnwrap(first.manifest.assets.first { (e: BackupAssetEntry) -> Bool in e.kind == BackupAssetKind.video })
        try fixture.videos.release([MediaLibraryFixture.video])
        access.reset()
        let second = try fixture.backUp(access)
        XCTAssertEqual(access.totalBytesRead, 0)
        XCTAssertEqual(second.removed, 1)
        XCTAssertEqual(second.unchanged, 4)
        XCTAssertFalse(second.manifest.assets.contains { (e: BackupAssetEntry) -> Bool in e.kind == BackupAssetKind.video })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupFolder.appendingPathComponent(videoEntry.location).path))
        fixture.assertManifestConsistent()
    }

    func testTwoReferencesToOnePayloadGiveOneCopy() throws {
        let fixture = try MediaLibraryFixture.make(self, "shared")
        let scratch = fixture.root.appendingPathComponent("same.png")
        try BackupFixtures.png(6).write(to: scratch)   // the bytes of `photo`
        let twin = UUID(uuidString: "0A000000-0000-4000-8000-0000000000F9")!
        _ = try fixture.photos.intern(scratch, as: twin, consumingSource: true)
        let access = CountingFileAccess()
        let report = try fixture.backUp(access)
        XCTAssertEqual(report.copied, 5, "the shared payload is copied once")
        XCTAssertEqual(report.unchanged, 1)
        let photos = report.manifest.assets.filter { (e: BackupAssetEntry) -> Bool in e.kind == BackupAssetKind.photo }
        XCTAssertEqual(photos.count, 3)
        XCTAssertEqual(Set(photos.map { (e: BackupAssetEntry) -> String in e.location }).count, 2)
        XCTAssertEqual(fixture.mediaNames().count, 5, "video, two photo contents, the audio asset and the index")
        fixture.assertManifestConsistent()
    }
}
