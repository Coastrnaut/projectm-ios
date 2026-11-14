// LibraryBackupSceneTagTests.swift — SCN-005-T14 (SCN-005-R8, S4): the library backup carries the
// show's scene tags; an exact restore into a fresh sandbox gives the same tags and show bytes.
import Foundation
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

final class LibraryBackupSceneTagTests: XCTestCase {
    func testABackupRoundTripKeepsEveryTag() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let store = ShowStore(directory: source.url(.show))
        var list = store.load().list
        try list.addTag("Intro", toScene: BackupFixtures.sceneID(1))
        try list.addTag("Loud", toScene: BackupFixtures.sceneID(1))
        try list.addTag("Ambient", toScene: BackupFixtures.sceneID(2))
        try store.save(list)

        let backup = try BackupFixtures.backup(of: source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }

        let restored = ShowStore(directory: fresh.url(.show)).load()
        XCTAssertNil(restored.refusal)
        XCTAssertEqual(restored.warnings, [])
        XCTAssertEqual(restored.list.tags, list.tags)
        XCTAssertEqual(restored.list.tags(ofScene: BackupFixtures.sceneID(1)), ["Intro", "Loud"])
        XCTAssertEqual(try Data(contentsOf: ShowStore(directory: fresh.url(.show)).showFile), list.encoded())
    }
}
