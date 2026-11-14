// SceneAutosaveMigrationTests.swift — SCN-013-T08: the autosave keeps the original of a migrated file
// once before a save replaces or removes it, refuses the save if it cannot, writes nothing on load, and
// logs versions and counts only (SCN-013-R7 to R10, S2, S4; contract M4, M5). Temporary folders only.
//
// The v0→v1 step is SYNTHETIC and test-only: version 1 is the only scene format version ever written,
// so the app's chain is empty (research SCN-013-D1).
import Foundation
import ParameterGraph
import SceneFormat
import XCTest
@testable import projectM_iOS

final class SceneAutosaveMigrationTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    /// A made-up "version 0": the scene name is stored as "title".
    private static let testChain = SceneMigrator(steps: [
        SceneMigrationStep(fromVersion: 0, identifier: "test-v0-to-v1", summary: "title to name") {
            (object: [String: SceneJSON], recorder: inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON] in
            var o = object
            o["name"] = o.removeValue(forKey: "title") ?? .string("Untitled")
            recorder.renamed("$.title", to: "$.name", "title renamed to name")
            return o
        },
    ], targetVersion: 1)

    private static let secretName = "Secret Set Nine"

    /// Version-0 bytes of the autosave fixture with a recognisable name.
    private static func v0(bars: Int) -> Data {
        var document = F.document(bars: bars)
        document.name = secretName
        // Rewrite the top level only: the object's "name" becomes "title" and "version" becomes 0.
        guard case var .object(o) = document.json else { return Data() }
        o["title"] = o.removeValue(forKey: "name")
        o["version"] = .integer(0)
        return Data(SceneJSON.object(o).canonicalBytes)
    }

    private func withFolder(_ body: (URL, ParameterRegistry) throws -> Void) throws {
        let folder = F.folder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder, try F.registry())
    }

    private func names(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func testLoadMigratesInMemoryLogsCountsOnlyAndWritesNothing() throws {
        try withFolder { (folder: URL, registry: ParameterRegistry) in
            let original = Self.v0(bars: 16)
            let store = SceneAutosaveStore(directory: folder, migrator: Self.testChain)
            try original.write(to: store.main)
            let load = store.load(registry: registry, assets: nil)
            XCTAssertEqual(load.source, .main)
            XCTAssertEqual(load.document?.name, Self.secretName)
            XCTAssertEqual(F.bars(load.document), "16")
            XCTAssertEqual(load.events, [.migrated(from: 0, to: 1, steps: 1, changes: 1)])
            XCTAssertEqual(try names(folder), [SceneAutosaveStore.mainName], "loading writes nothing")
            XCTAssertEqual(try Data(contentsOf: store.main), original)
            // The production chain refuses the same file as before SCN-013 (and sets nothing aside: not newer).
            let production = SceneAutosaveStore(directory: folder).load(registry: registry, assets: nil)
            XCTAssertNil(production.document)
        }
    }

    func testFirstSaveKeepsTheOriginalOnceAndLaterSavesNeverOverwriteIt() throws {
        try withFolder { (folder: URL, registry: ParameterRegistry) in
            let original = Self.v0(bars: 16)
            let store = SceneAutosaveStore(directory: folder, migrator: Self.testChain)
            try original.write(to: store.main)
            _ = store.load(registry: registry, assets: nil)

            try store.save(F.document(bars: 32).encoded())
            let backup = folder.appendingPathComponent("current.scene.v0.backup")
            XCTAssertEqual(try Data(contentsOf: backup), original)
            XCTAssertEqual(store.takeKeptOriginals(), ["current.scene.v0.backup"])

            try store.save(F.document(bars: 64).encoded())
            try store.save(F.document(bars: 128).encoded())
            XCTAssertEqual(try Data(contentsOf: backup), original, "never overwritten")
            XCTAssertEqual(store.takeKeptOriginals(), [])
            let reloaded = SceneAutosaveStore(directory: folder, migrator: Self.testChain).load(registry: registry, assets: nil)
            XCTAssertEqual(F.bars(reloaded.document), "128")
            XCTAssertEqual(reloaded.events, [], "current files: nothing migrated")
        }
    }

    func testAFailedBackupRefusesTheSaveAndKeepsTheOriginal() throws {
        try withFolder { (folder: URL, registry: ParameterRegistry) in
            let original = Self.v0(bars: 16)
            let store = SceneAutosaveStore(directory: folder, migrator: Self.testChain)
            try original.write(to: store.main)
            _ = store.load(registry: registry, assets: nil)
            // A folder in the backup's place makes the backup write fail.
            let blocker = folder.appendingPathComponent("current.scene.v0.backup")
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: false)
            XCTAssertThrowsError(try store.save(F.document(bars: 32).encoded())) { (error: Error) in
                XCTAssertEqual((error as? SceneAutosaveWriteError)?.step, .keepOriginal)
            }
            XCTAssertEqual(try Data(contentsOf: store.main), original, "the original is not replaced")
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.temporary.path))

            // An injected failure at the step behaves the same; once the backup can be written, the save goes on.
            try FileManager.default.removeItem(at: blocker)
            store.fault = { (step: SceneAutosaveStep) throws -> Void in
                if step == .keepOriginal { throw CocoaError(.fileWriteUnknown) }
            }
            XCTAssertThrowsError(try store.save(F.document(bars: 32).encoded()))
            XCTAssertEqual(try Data(contentsOf: store.main), original)
            store.fault = nil
            try store.save(F.document(bars: 32).encoded())
            XCTAssertEqual(try Data(contentsOf: blocker), original)
        }
    }

    func testAMigratedBackupFileIsKeptBeforeTheSaveThatRemovesIt() throws {
        try withFolder { (folder: URL, registry: ParameterRegistry) in
            let store = SceneAutosaveStore(directory: folder, migrator: Self.testChain)
            let olderBackup = Self.v0(bars: 8)
            try Data(F.document(bars: 16).encoded()).write(to: store.main)
            try olderBackup.write(to: store.backup)
            let load = store.load(registry: registry, assets: nil)
            XCTAssertEqual(load.source, .main)
            XCTAssertEqual(load.events, [], "the backup is not opened, only its version is checked")
            try store.save(F.document(bars: 32).encoded())   // removes and relinks the backup
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("current.scene.bak.v0.backup")), olderBackup)
        }
    }

    func testRestoredFromAMigratedBackup() throws {
        try withFolder { (folder: URL, registry: ParameterRegistry) in
            let store = SceneAutosaveStore(directory: folder, migrator: Self.testChain)
            try Data("{".utf8).write(to: store.main)
            let olderBackup = Self.v0(bars: 8)
            try olderBackup.write(to: store.backup)
            let load = store.load(registry: registry, assets: nil)
            XCTAssertEqual(load.source, .backup)
            XCTAssertEqual(load.events.suffix(2), [.restoredFromBackup, .migrated(from: 0, to: 1, steps: 1, changes: 1)])
            try store.save(F.document(bars: 32).encoded())
            try store.save(F.document(bars: 64).encoded())   // the second save removes the old backup
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("current.scene.bak.v0.backup")), olderBackup)
        }
    }

    func testCurrentFilesGetNoBackup() throws {
        try withFolder { (folder: URL, registry: ParameterRegistry) in
            let store = SceneAutosaveStore(directory: folder)
            try store.save(F.document(bars: 16).encoded())
            _ = SceneAutosaveStore(directory: folder).load(registry: registry, assets: nil)
            try store.save(F.document(bars: 32).encoded())
            try store.save(F.document(bars: 64).encoded())
            XCTAssertEqual(try names(folder), [SceneAutosaveStore.mainName, SceneAutosaveStore.backupName])
        }
    }

    /// S4: the diagnostics text names versions, counts and fixed file names only.
    func testEventsCarryNoSceneContent() {
        let events: [SceneAutosaveEvent] = [.migrated(from: 0, to: 1, steps: 1, changes: 1), .keptOriginal("current.scene.v0.backup")]
        XCTAssertEqual(events.map(\.description), ["migrated scene from version 0 to 1 (1 steps, 1 changes)",
                                                   "kept original as current.scene.v0.backup"])
        let change = SceneMigrationLogEntry(step: "test-v0-to-v1", fromVersion: 0, toVersion: 1,
                                            change: SceneMigrationChange(.renamed, path: "$.title", newPath: "$.name", detail: "renamed"))
        let record = SceneMigrationRecord(sourceVersion: 0, targetVersion: 1, log: [change])
        XCTAssertEqual(record.summary, events[0].description)
        for text in events.map(\.description) {
            XCTAssertFalse(text.contains(Self.secretName))
            XCTAssertFalse(text.contains(F.carry.id))
            XCTAssertFalse(text.contains("$."), "no JSON paths")
        }
    }
}
