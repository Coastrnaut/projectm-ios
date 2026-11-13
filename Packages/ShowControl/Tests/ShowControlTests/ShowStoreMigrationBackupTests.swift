// ShowStoreMigrationBackupTests.swift — a show scene of an older format version keeps its original
// bytes once before it is replaced (SCN-013-T07; SCN-013-R7 to R9, R15; contract M4).
//
// The v0→v1 step here is SYNTHETIC and test-only: version 1 is the only scene format version ever
// written, so the app's chain is empty (research SCN-013-D1).
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class ShowStoreMigrationBackupTests: XCTestCase {
    /// A made-up "version 0" with the name under "title".
    private static let testChain = SceneMigrator(steps: [
        SceneMigrationStep(fromVersion: 0, identifier: "test-v0-to-v1", summary: "title to name") {
            (object: [String: SceneJSON], recorder: inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON] in
            var o = object
            o["name"] = o.removeValue(forKey: "title") ?? .string("Untitled")
            recorder.renamed("$.title", to: "$.name", "title renamed to name")
            return o
        },
    ], targetVersion: 1)

    private func makeStore() throws -> ShowStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShowStoreMigration-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = ShowStore(directory: folder, migrator: Self.testChain)
        try FileManager.default.createDirectory(at: store.scenesFolder, withIntermediateDirectories: true)
        return store
    }

    private func v0Bytes(_ id: String, title: String) -> Data {
        Data("{\"format\":\"projectm-ios.scene\",\"version\":0,\"id\":\"\(id)\",\"title\":\"\(title)\",\"layers\":[]}".utf8)
    }

    func testReadingMigratesInMemoryAndWritesNothing() throws {
        let store = try makeStore()
        let id = ShowFixtures.sceneID(1)
        let original = v0Bytes(id, title: "Old")
        try original.write(to: store.sceneFile(id))
        let read = try store.scene(id)
        XCTAssertEqual(read.document.name, "Old")
        XCTAssertTrue(read.migration.migrated)
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(id)), original, "opening never writes")
        XCTAssertEqual(store.backups(of: id), [])
    }

    func testRenameKeepsTheOriginalOnceAndNeverOverwritesIt() throws {
        let store = try makeStore()
        let id = ShowFixtures.sceneID(1)
        let original = v0Bytes(id, title: "Old")
        try original.write(to: store.sceneFile(id))

        try store.renameScene(id, to: "New")
        let backup = store.scenesFolder.appendingPathComponent(id + ".scene.json.v0.backup")
        XCTAssertEqual(store.backups(of: id), [backup])
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try store.scene(id).document.name, "New")
        XCTAssertFalse(try store.scene(id).migration.migrated, "the replaced file is current")

        // A later older-version file under the same name does not replace the first backup.
        try v0Bytes(id, title: "Other").write(to: store.sceneFile(id))
        try store.renameScene(id, to: "Newer")
        XCTAssertEqual(try Data(contentsOf: backup), original, "never overwritten")
        // Current files get no backup.
        try store.renameScene(id, to: "Newest")
        XCTAssertEqual(store.backups(of: id).count, 1)
    }

    func testAFailedBackupRefusesTheSaveAndKeepsTheOriginal() throws {
        let store = try makeStore()
        let id = ShowFixtures.sceneID(2)
        let original = v0Bytes(id, title: "Old")
        try original.write(to: store.sceneFile(id))
        // A folder in the backup's place makes the backup write fail.
        try FileManager.default.createDirectory(at: store.scenesFolder.appendingPathComponent(id + ".scene.json.v0.backup"),
                                                withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.renameScene(id, to: "New"))
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(id)), original)
    }

    func testBackupsAreRemovedWithTheirScene() throws {
        let store = try makeStore()
        let id = ShowFixtures.sceneID(3)
        try v0Bytes(id, title: "Old").write(to: store.sceneFile(id))
        try store.renameScene(id, to: "New")
        XCTAssertEqual(store.backups(of: id).count, 1)
        XCTAssertEqual(store.storedSceneIDs(), [id], "a backup is not a stored scene")
        try store.save(ShowCueList())   // no cue refers to the scene
        XCTAssertEqual(store.storedSceneIDs(), [])
        XCTAssertEqual(store.backups(of: id), [])
    }

    func testBackupNames() {
        XCTAssertTrue(SceneMigrationRecord.isBackup("A.scene.json.v12.backup", of: "A.scene.json"))
        XCTAssertFalse(SceneMigrationRecord.isBackup("A.scene.json.v.backup", of: "A.scene.json"))
        XCTAssertFalse(SceneMigrationRecord.isBackup("A.scene.json.vx.backup", of: "A.scene.json"))
        XCTAssertFalse(SceneMigrationRecord.isBackup("B.scene.json.v1.backup", of: "A.scene.json"))
        XCTAssertEqual(SceneMigrationRecord.backupName(for: "current.scene", version: 1), "current.scene.v1.backup")
    }
}
