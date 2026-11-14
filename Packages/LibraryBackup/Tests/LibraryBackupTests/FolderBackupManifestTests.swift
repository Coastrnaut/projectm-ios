// FolderBackupManifestTests.swift — FILE-006-T04 (FILE-006-R2, R5; research FILE-006-D5): the folder
// manifest's schema. A valid manifest round-trips deterministically; anything outside the rules reads as
// unusable; an entry without a digest64 (an older manifest) still reads.
import Foundation
import XCTest
@testable import LibraryBackup

final class FolderBackupManifestTests: XCTestCase {
    private let digest64 = String(repeating: "ab", count: 32)

    private func entry(kind: String = "video", name: String = "0B000000-0000-4000-8000-0000000000F6.mov", sha256: String?? = .none,
                       location: String? = nil) -> BackupAssetEntry {
        let sha: String? = sha256 ?? digest64
        return BackupAssetEntry(kind: kind, name: name, byteCount: 10, modified: nil, sha256: sha,
                                location: location ?? "media/\(digest64).mov")
    }

    private func json(_ manifest: BackupFolderManifest) throws -> Data { try manifest.encoded() }

    private func manifest(_ assets: [BackupAssetEntry]) -> BackupFolderManifest {
        BackupFolderManifest(appVersion: "1.2 (3)", createdAt: "2026-11-14T00:00:00Z",
                             library: BackupArchiveRecord(path: BackupFolderLayout.archiveName, byteCount: 7, sha256: digest64), assets: assets)
    }

    func testAValidManifestRoundTripsWithEqualBytes() throws {
        let original = manifest([entry(), entry(kind: "photo", name: "0A000000-0000-4000-8000-0000000000F6.png", location: "media/\(digest64).png"),
                                 entry(kind: "scene-folder", name: "Opening")])   // an unknown kind is kept (SCN-004)
        let data = try json(original)
        let read = try XCTUnwrap(BackupFolderManifest.read(data))
        XCTAssertEqual(read, original)
        XCTAssertEqual(try read.encoded(), data, "deterministic encoding")
        XCTAssertEqual(read.assets.map(\.kind), ["photo", "scene-folder", "video"], "sorted by kind and name")
    }

    func testAnEntryWithoutAHashReads() throws {
        var legacy = entry()
        legacy.sha256 = nil
        let read = try XCTUnwrap(BackupFolderManifest.read(try json(manifest([legacy]))))
        XCTAssertNil(read.assets[0].sha256)
    }

    func testUnusableManifestsReadAsNil() throws {
        XCTAssertNil(BackupFolderManifest.read(Data("not json".utf8)))
        XCTAssertNil(BackupFolderManifest.read(Data(count: BackupFolderManifest.maxBytes + 1)))
        var wrongFormat = manifest([entry()])
        wrongFormat.format = "org.example.other"
        XCTAssertNil(BackupFolderManifest.read(try json(wrongFormat)))
        var newer = manifest([entry()])
        newer.formatVersion = 2
        XCTAssertNil(BackupFolderManifest.read(try json(newer)), "a newer version is not trusted")
        let bad: [BackupAssetEntry] = [
            entry(kind: "Video"),                                   // kind token
            entry(name: "../escape.mov"),                           // path separator
            entry(name: ".hidden"),                                 // leading dot
            entry(location: "../outside/\(digest64).mov"),              // outside media/
            entry(location: "media/\(digest64).MOV"),                   // extension token
            entry(location: "media/sub/\(digest64).mov"),               // nested
            entry(sha256: .some(String(repeating: "cd", count: 32))), // stem differs from the digest64
        ]
        for item in bad {
            XCTAssertNil(BackupFolderManifest.read(try json(manifest([item]))), "\(item)")
        }
        XCTAssertNil(BackupFolderManifest.read(try json(manifest([entry(), entry()]))), "duplicate entries")
        var badLibrary = manifest([])
        badLibrary.library = BackupArchiveRecord(path: "../x.pmbackup", byteCount: 1, sha256: digest64)
        XCTAssertNil(BackupFolderManifest.read(try json(badLibrary)))
    }

    func testTheLayoutResolvesTheBackupFolder() throws {
        let picked = FileManager.default.temporaryDirectory.appendingPathComponent("FolderBackupLayout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: picked) }
        XCTAssertEqual(BackupFolderLayout.backupFolder(in: picked).lastPathComponent, BackupFolderLayout.folderName)
        try Data("{}".utf8).write(to: picked.appendingPathComponent(BackupFolderLayout.manifestName))
        XCTAssertEqual(BackupFolderLayout.backupFolder(in: picked), picked, "a picked backup folder is used directly")
        XCTAssertEqual(BackupFolderLayout.contentAddress(of: digest64 + ".m4a"), digest64)
        XCTAssertEqual(BackupFolderLayout.contentAddress(of: digest64), digest64)
        XCTAssertNil(BackupFolderLayout.contentAddress(of: digest64 + "."))
        XCTAssertNil(BackupFolderLayout.contentAddress(of: "0A000000-0000-4000-8000-0000000000F6.png"))
    }
}
