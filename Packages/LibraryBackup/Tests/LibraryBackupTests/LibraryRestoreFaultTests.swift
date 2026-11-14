// LibraryRestoreFaultTests.swift — FILE-005-T11 (FILE-005-R7, S2): nothing half-restored.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

private struct InjectedFault: Error {}

/// Counts operations and throws at one of them.
private final class FaultCounter: @unchecked Sendable {
    var seen = 0
    let failAt: Int
    init(failAt: Int) { self.failAt = failAt }
    func check() throws {
        seen += 1
        if seen == failAt { throw InjectedFault() }
    }
}

final class LibraryRestoreFaultTests: XCTestCase {
    private func clashingPair() throws -> (backup: Data, device: LibraryFolders, sink: BackupFixtures.SettingsSink) {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let backup = try BackupFixtures.backup(of: source)
        let device = BackupFixtures.sandbox(self, "device")
        // A device library with a different current scene, one preset and a collection, so several folders swap.
        try FileManager.default.createDirectory(at: device.url(.currentScene), withIntermediateDirectories: true)
        try BackupFixtures.sceneBytes(8).write(to: device.currentSceneFile)
        let text = BackupFixtures.presetText("Device only")
        let mine = BackupFixtures.record(40, name: "Device only", text: text)
        try FileManager.default.createDirectory(at: device.presetTextsFolder, withIntermediateDirectories: true)
        try text.write(to: device.presetTextsFolder.appendingPathComponent(mine.fileName))
        try UserPresetsFile(presets: [mine]).encode().write(to: device.presetIndexFile)
        return (backup, device, BackupFixtures.SettingsSink(["settings.osc.port": .int(8_000)]))
    }

    /// A fault at each file operation before the commit leaves the library byte for byte as before and
    /// the settings untouched; the operation count is found from a clean run.
    func testAFaultAtEveryOperationRollsBack() throws {
        let probe = try clashingPair()
        let counter = FaultCounter(failAt: 0)
        _ = try BackupFixtures.restore(probe.backup, into: probe.device, sink: probe.sink, choice: .replace) { (installer: LibraryRestoreInstaller) in
            installer.observer = { (_: LibraryRestoreInstaller.FileOperation, _: URL) in counter.seen += 1 }
        }
        let total = counter.seen
        XCTAssertGreaterThan(total, 10)
        var rolledBack = 0
        for failAt in 1...total {
            let pair = try clashingPair()
            let before = LibraryTreeSnapshot.take(pair.device.libraryRoots + [pair.device.restore])
            let fault = FaultCounter(failAt: failAt)
            let outcome = try BackupFixtures.restore(pair.backup, into: pair.device, sink: pair.sink, choice: .replace) { (installer: LibraryRestoreInstaller) in
                installer.fault = { (_: LibraryRestoreInstaller.FileOperation, _: URL) in try fault.check() }
            }
            if case .restored = outcome { continue }   // the fault hit the clean-up after the commit
            XCTAssertEqual(outcome, .refused(LibraryRestoreText.failed), "fault at \(failAt)")
            let after = LibraryTreeSnapshot.take(pair.device.libraryRoots + [pair.device.restore])
            XCTAssertEqual(after.differences(from: before), [], "fault at \(failAt) changed the library")
            XCTAssertEqual(pair.sink.values, ["settings.osc.port": .int(8_000)], "fault at \(failAt) applied settings")
            rolledBack += 1
        }
        XCTAssertGreaterThan(rolledBack, total / 2)
    }

    /// A fault in the clean-up after the commit: the restore counts as done, and recovery finishes it.
    func testAFailedCleanupIsFinishedByRecovery() throws {
        let pair = try clashingPair()
        var failedRemove = false
        let outcome = try BackupFixtures.restore(pair.backup, into: pair.device, sink: pair.sink, choice: .replace) { (installer: LibraryRestoreInstaller) in
            installer.fault = { (operation: LibraryRestoreInstaller.FileOperation, url: URL) in
                if operation == .remove && url.lastPathComponent == "previous" && !failedRemove {
                    failedRemove = true
                    throw InjectedFault()
                }
            }
        }
        guard case .restored = outcome else { return XCTFail("\(outcome)") }
        let installer = LibraryRestoreInstaller(folders: pair.device)
        XCTAssertTrue(installer.hasInterruptedRestore)
        let sink = BackupFixtures.SettingsSink()
        XCTAssertTrue(installer.recover { (values: [String: LibrarySettingValue]) in sink.apply(values) })
        XCTAssertFalse(installer.hasInterruptedRestore)
        XCTAssertEqual(sink.values["settings.osc.port"], .int(9_000), "the committed settings are applied again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pair.device.restore.appendingPathComponent("previous").path))
    }

    /// The app was killed after some folders moved: a "prepared" journal is rolled back at launch.
    func testAPreparedJournalIsRolledBackAtLaunch() throws {
        let pair = try clashingPair()
        let before = LibraryTreeSnapshot.take(pair.device.libraryRoots)
        struct Kill: Error {}
        var moves = 0
        let outcome = try BackupFixtures.restore(pair.backup, into: pair.device, sink: pair.sink, choice: .replace) { (installer: LibraryRestoreInstaller) in
            installer.fault = { (operation: LibraryRestoreInstaller.FileOperation, url: URL) in
                if operation == .move { moves += 1 }
                if moves == 3 { throw Kill() }
            }
        }
        XCTAssertEqual(outcome, .refused(LibraryRestoreText.failed))
        XCTAssertEqual(LibraryTreeSnapshot.take(pair.device.libraryRoots).differences(from: before), [], "in-process roll-back")
        // Simulate a kill instead: rebuild a half-moved state by hand from a fresh pair.
        let killed = try clashingPair()
        let killedBefore = LibraryTreeSnapshot.take(killed.device.libraryRoots)
        let journal = LibraryRestoreInstaller.Journal(phase: .prepared, folders: [.init(name: "Scenes", hadLive: true),
                                                                                  .init(name: "Photos", hadLive: false)], settings: [:])
        let installer = LibraryRestoreInstaller(folders: killed.device)
        let previous = killed.device.restore.appendingPathComponent("previous", isDirectory: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: killed.device.url(.currentScene), to: previous.appendingPathComponent("Scenes"))
        try FileManager.default.createDirectory(at: killed.device.url(.currentScene), withIntermediateDirectories: true)
        try BackupFixtures.sceneBytes(9).write(to: killed.device.currentSceneFile)   // the new folder had moved in
        try FileManager.default.createDirectory(at: killed.device.url(.photos), withIntermediateDirectories: true)
        try BackupFixtures.png(1).write(to: killed.device.url(.photos).appendingPathComponent(BackupFixtures.photoName(1)))
        try JSONEncoder().encode(journal).write(to: killed.device.restore.appendingPathComponent("restore.journal.json"))
        XCTAssertTrue(installer.recover { (_: [String: LibrarySettingValue]) in XCTFail("no settings on roll-back") })
        XCTAssertEqual(LibraryTreeSnapshot.take(killed.device.libraryRoots).differences(from: killedBefore), [])
        XCTAssertFalse(installer.hasInterruptedRestore)
    }

    /// FILE-005-R7: Install plans again; a library changed since the preview gets a new plan, nothing written.
    func testAChangedLibraryReturnsANewPlanWithNothingWritten() throws {
        let pair = try clashingPair()
        let backup = try LibraryBackupReader.read(pair.backup).contents
        let plan = LibraryRestorePlanner.plan(backup: backup, library: try LibraryContentsReader.read(folders: pair.device, settings: pair.sink.values))
        try BackupFixtures.sceneBytes(7).write(to: pair.device.currentSceneFile)   // changed meanwhile
        let before = LibraryTreeSnapshot.take(pair.device.libraryRoots)
        let outcome = LibraryRestoreInstaller(folders: pair.device).install(backup: backup, plan: plan, settings: pair.sink.values) { _ in
            XCTFail("no settings")
        }
        guard case .changed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(LibraryTreeSnapshot.take(pair.device.libraryRoots).differences(from: before), [])
    }

    /// Cancel (no install, or a cancelled request) leaves the library byte for byte unchanged.
    func testPreviewAndCancelledRequestChangeNothing() throws {
        let pair = try clashingPair()
        let before = LibraryTreeSnapshot.take(pair.device.libraryRoots)
        let backup = try LibraryBackupReader.read(pair.backup).contents
        _ = LibraryRestorePlanner.plan(backup: backup, library: try LibraryContentsReader.read(folders: pair.device, settings: pair.sink.values))
        let requests = LibraryRestoreRequestStore(folders: pair.device)
        try requests.save(backup: pair.backup, choice: .replace)
        XCTAssertEqual(requests.pending?.choice, .replace)
        requests.cancel()
        XCTAssertNil(requests.pending)
        XCTAssertNil(LibraryRestoreLaunch.run(folders: pair.device, settings: pair.sink.values) { _ in XCTFail("no settings") })
        XCTAssertEqual(LibraryTreeSnapshot.take(pair.device.libraryRoots).differences(from: before), [])
    }
}
