// FolderBackupSafetyTests.swift — FILE-006-T07 (FILE-006-S3; FILE-006-R5, R6, R7): a damaged, newer or
// crafted manifest is never trusted (full backup); an interrupted backup leaves the previous manifest
// naming only files that exist with their hash; leftovers are collected; a FILE-005-only folder and a
// hashless manifest get a full pass; a truncated copy is recopied; pruning stays inside our own names.
import Foundation
import XCTest
@testable import LibraryBackup

final class FolderBackupSafetyTests: XCTestCase {
    private struct Abort: Error {}

    private var manifestURL: (MediaLibraryFixture) -> URL {
        { (fixture: MediaLibraryFixture) -> URL in fixture.backupFolder.appendingPathComponent(BackupFolderLayout.manifestName) }
    }

    func testACorruptOrNewerManifestGivesAFullBackup() throws {
        let fixture = try MediaLibraryFixture.make(self, "corrupt")
        let access = CountingFileAccess()
        try fixture.backUp(access)
        let url = manifestURL(fixture)
        let good = try Data(contentsOf: url)
        let newer = Data(String(decoding: good, as: UTF8.self).replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":2").utf8)
        for damaged in [Data(good.prefix(good.count / 2)), newer, Data()] {
            try damaged.write(to: url)
            access.reset()
            let report = try fixture.backUp(access)
            XCTAssertTrue(report.fullBackup)
            XCTAssertEqual(report.copied, 5, "every asset hashed and copied again")
            XCTAssertEqual(access.bytesRead(fixture.videoURL), Int64(MediaLibraryFixture.videoBytes))
            fixture.assertManifestConsistent()
        }
    }

    func testACraftedManifestIsNotTrusted() throws {
        let fixture = try MediaLibraryFixture.make(self, "crafted")
        try fixture.backUp(CountingFileAccess())
        let url = manifestURL(fixture)
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        try Data(text.replacingOccurrences(of: "\"location\":\"media/", with: "\"location\":\"../").utf8).write(to: url)
        let access = CountingFileAccess()
        let report = try fixture.backUp(access)
        XCTAssertTrue(report.fullBackup)
        XCTAssertEqual(report.copied, 5)
    }

    func testAFaultAtAnyStepLeavesThePreviousManifestConsistent() throws {
        let steps: [(FolderBackupStep, String)] = [(.copy, ".mov"), (.copy, ".png"), (.writeArchive, ""), (.writeManifest, "")]
        for (step, match) in steps {
            let fixture = try MediaLibraryFixture.make(self, "fault-\(step.rawValue)")
            let first = try fixture.backUp(CountingFileAccess())
            // Change two assets, then abort the next backup at the step.
            try fixture.videos.release([MediaLibraryFixture.video])
            let scratch = fixture.root.appendingPathComponent("new.mov")
            try Data(repeating: 0x33, count: 100_000).write(to: scratch)
            _ = try fixture.videos.intern(scratch, as: UUID(), consumingSource: true)
            try BackupFixtures.png(12).write(to: fixture.legacyPhotoURL)
            try FileManager.default.setAttributes([.modificationDate: BackupFixtures.now], ofItemAtPath: fixture.legacyPhotoURL.path)
            let fault: @Sendable (FolderBackupStep, String) throws -> Void = { (at: FolderBackupStep, name: String) in
                if at == step && (match.isEmpty || name.hasSuffix(match)) { throw Abort() }
            }
            XCTAssertThrowsError(try fixture.backUp(CountingFileAccess(), fault: fault), "\(step)")
            let kept = try XCTUnwrap(BackupFolderManifest.read(folder: fixture.backupFolder))
            XCTAssertEqual(kept.assets, first.manifest.assets, "\(step): the previous manifest stays")
            fixture.assertManifestConsistent()
            // The next backup completes and collects anything the interruption left.
            let report = try fixture.backUp(CountingFileAccess())
            fixture.assertManifestConsistent()
            XCTAssertFalse(fixture.mediaNames().contains { (n: String) -> Bool in n.hasPrefix(BackupFolderLayout.partialPrefix) })
            XCTAssertEqual(Set(fixture.mediaNames().map { (n: String) -> String in "media/" + n }),
                           Set(report.manifest.assets.map(\.location)), "\(step): only named copies remain")
        }
    }

    func testAFaultWhilePruningKeepsTheNewManifestConsistent() throws {
        let fixture = try MediaLibraryFixture.make(self, "prune")
        try fixture.backUp(CountingFileAccess())
        try fixture.videos.release([MediaLibraryFixture.video])
        let fault: @Sendable (FolderBackupStep, String) throws -> Void = { (at: FolderBackupStep, _: String) in
            if at == .prune { throw Abort() }
        }
        let report = try fixture.backUp(CountingFileAccess(), fault: fault)
        XCTAssertEqual(report.removed, 0)
        fixture.assertManifestConsistent()
        let next = try fixture.backUp(CountingFileAccess())
        XCTAssertEqual(next.removed, 1, "the unnamed copy is collected by the next backup")
    }

    func testAFile005OnlyFolderAndAHashlessManifestGetAFullPass() throws {
        let fixture = try MediaLibraryFixture.make(self, "migration")
        try FileManager.default.createDirectory(at: fixture.backupFolder, withIntermediateDirectories: true)
        try Data("older archive".utf8).write(to: fixture.backupFolder.appendingPathComponent(BackupFolderLayout.archiveName))
        let first = try fixture.backUp(CountingFileAccess())
        XCTAssertTrue(first.fullBackup)
        XCTAssertEqual(first.copied, 5)
        // An older manifest whose entries carry no hash: every entry is treated as changed.
        var hashless = first.manifest
        hashless.assets = hashless.assets.map { (e: BackupAssetEntry) -> BackupAssetEntry in
            var copy = e
            copy.sha256 = nil
            return copy
        }
        try hashless.encoded().write(to: manifestURL(fixture))
        let access = CountingFileAccess()
        let second = try fixture.backUp(access)
        XCTAssertFalse(second.fullBackup)
        XCTAssertEqual(second.copied, 2, "the legacy photo and the index have no address and are rehashed")
        XCTAssertEqual(second.unchanged, 3, "content-addressed copies named by the manifest are reused by name")
        XCTAssertTrue(second.manifest.assets.allSatisfy { (e: BackupAssetEntry) -> Bool in e.sha256 != nil })
        fixture.assertManifestConsistent()
    }

    func testATruncatedCopyIsCopiedAgain() throws {
        let fixture = try MediaLibraryFixture.make(self, "truncated")
        let first = try fixture.backUp(CountingFileAccess())
        let video = try XCTUnwrap(first.manifest.assets.first { (e: BackupAssetEntry) -> Bool in e.kind == BackupAssetKind.video })
        try Data(count: 10).write(to: fixture.backupFolder.appendingPathComponent(video.location))
        let access = CountingFileAccess()
        let second = try fixture.backUp(access)
        XCTAssertEqual(second.copied, 1)
        XCTAssertEqual(access.bytesRead(fixture.videoURL), Int64(MediaLibraryFixture.videoBytes))
        fixture.assertManifestConsistent()
    }

    func testPruningNeverTouchesFilesItDidNotCreate() throws {
        let fixture = try MediaLibraryFixture.make(self, "foreign")
        try fixture.backUp(CountingFileAccess())
        let foreign = [fixture.media.appendingPathComponent("holiday.mov"), fixture.backupFolder.appendingPathComponent("notes.txt"),
                       fixture.destination.appendingPathComponent(String(repeating: "ef", count: 32) + ".mov")]
        for url in foreign { try Data("mine".utf8).write(to: url) }
        try fixture.videos.release([MediaLibraryFixture.video])
        let report = try fixture.backUp(CountingFileAccess())
        XCTAssertEqual(report.removed, 1)
        for url in foreign { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent) }
    }

    func testAnUnwritableFolderFailsWithoutAManifest() throws {
        let fixture = try MediaLibraryFixture.make(self, "unwritable")
        try Data("a file".utf8).write(to: fixture.backupFolder)   // a file where the folder should be
        XCTAssertThrowsError(try fixture.backUp(CountingFileAccess())) { (error: any Error) in
            XCTAssertEqual(error as? FolderBackupError, .folderUnavailable)
        }
    }
}
