// LibraryBackupSceneFolderTests.swift — SCN-004-T13 (SCN-004-R9, S6): the library backup carries the
// show's scene folders; restoring into a fresh sandbox recreates the same tree and assignments.
import Foundation
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

final class LibraryBackupSceneFolderTests: XCTestCase {
    private static func fid(_ n: Int) -> UUID { UUID(uuidString: String(format: "F01DE000-0000-4000-8000-%012d", n))! }

    func testABackupRoundTripKeepsEveryFolderAndAssignment() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let store = ShowStore(directory: source.url(.show))
        var list = store.load().list
        try list.createFolder(named: "Set A", in: nil, id: Self.fid(1))
        try list.createFolder(named: "Encore", in: Self.fid(1), id: Self.fid(2))
        try list.createFolder(named: "Empty", in: nil, id: Self.fid(3))
        try list.moveScene(BackupFixtures.sceneID(2), to: Self.fid(2))
        try store.save(list)

        let backup = try BackupFixtures.backup(of: source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }

        let restored = ShowStore(directory: fresh.url(.show)).load()
        XCTAssertNil(restored.refusal)
        XCTAssertEqual(restored.warnings, [])
        XCTAssertEqual(restored.list.folders, list.folders)
        XCTAssertEqual(restored.list.folders.pathText(of: restored.list.folderID(ofScene: BackupFixtures.sceneID(2))), "Set A / Encore")
        XCTAssertNotNil(restored.list.folders.folder(Self.fid(3)), "an empty folder survives")
        XCTAssertEqual(try Data(contentsOf: ShowStore(directory: fresh.url(.show)).showFile), list.encoded())
    }
}
