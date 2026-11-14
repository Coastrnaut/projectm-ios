// LibraryRestoreChoiceTests.swift — FILE-005-T10 (FILE-005-R10, S3): restore over an existing library
// with each choice; deterministic plans; limits.
import Foundation
import LocalPortability
import PresetLibrary
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

final class LibraryRestoreChoiceTests: XCTestCase {
    private var backupData = Data()

    /// The fixture library's backup, and a device library that clashes with it: scene 1 changed, the
    /// preset "Alpha" with another text under the same identifier, collection "Party" with another list,
    /// two settings changed, the photo with other bytes, and the current scene changed.
    private func makeClashingDevice(sink: BackupFixtures.SettingsSink) throws -> LibraryFolders {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        backupData = try BackupFixtures.backup(of: source)
        let device = BackupFixtures.sandbox(self, "device")
        let store = ShowStore(directory: device.url(.show))
        var list = ShowCueList(id: BackupFixtures.uuid(998), name: "Device show")
        try store.saveScene(BackupFixtures.scene(1, variant: 5, name: "Mine"))
        try list.append(sceneID: BackupFixtures.sceneID(1), label: "Mine", cueID: BackupFixtures.uuid(70))
        try store.save(list)
        try FileManager.default.createDirectory(at: device.url(.currentScene), withIntermediateDirectories: true)
        try BackupFixtures.sceneBytes(8).write(to: device.currentSceneFile)
        let text = BackupFixtures.presetText("Alpha on the device")
        let mine = BackupFixtures.record(1, name: "Alpha", text: text)
        try FileManager.default.createDirectory(at: device.presetTextsFolder, withIntermediateDirectories: true)
        try text.write(to: device.presetTextsFolder.appendingPathComponent(mine.fileName))
        try UserPresetsFile(presets: [mine]).encode().write(to: device.presetIndexFile)
        try FileManager.default.createDirectory(at: device.url(.collections), withIntermediateDirectories: true)
        try PresetCollectionsFile(collections: [PresetCollection(id: BackupFixtures.uuid(50).uuidString, name: "Party", presetIDs: [])])
            .encode().write(to: device.collectionsFile)
        try FileManager.default.createDirectory(at: device.url(.photos), withIntermediateDirectories: true)
        try BackupFixtures.png(9).write(to: device.url(.photos).appendingPathComponent(BackupFixtures.photoName(1)))
        sink.values = ["settings.osc.port": .int(8_000), "favorites": .strings(["included/Zeta.milk"]), "settings.visual": .string("circularSpectrum")]
        return device
    }

    private func contents(_ folders: LibraryFolders, _ sink: BackupFixtures.SettingsSink) throws -> LibraryContents {
        try LibraryContentsReader.read(folders: folders, settings: sink.values)
    }

    func testSkipLeavesEveryClashingRecordUnchanged() throws {
        let sink = BackupFixtures.SettingsSink()
        let device = try makeClashingDevice(sink: sink)
        let before = try contents(device, sink)
        let outcome = try BackupFixtures.restore(backupData, into: device, sink: sink, choice: .skip)
        guard case .restored = outcome else { return XCTFail("\(outcome)") }
        let after = try contents(device, sink)
        XCTAssertEqual(after.scenes[BackupFixtures.sceneID(1)], before.scenes[BackupFixtures.sceneID(1)])
        XCTAssertEqual(after.currentScene, before.currentScene)
        XCTAssertEqual(after.presets.first { (p: LibraryPreset) -> Bool in p.record.id == BackupFixtures.presetID(1) }?.text,
                       before.presets[0].text)
        XCTAssertEqual(after.collections?.first?.presetIDs, [])
        XCTAssertEqual(after.photos, before.photos)
        XCTAssertEqual(sink.values["settings.osc.port"], .int(8_000))
        XCTAssertEqual(sink.values["favorites"], .strings(["included/Zeta.milk"]))
        // New records still arrive: scenes 2 and 3 with cues, presets Beta and Gamma, collection Calm, new settings.
        XCTAssertNotNil(after.scenes[BackupFixtures.sceneID(2)])
        XCTAssertEqual(after.cueCount, 3)
        XCTAssertEqual(Set(after.presets.map(\.record.name)), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(after.collections?.map(\.name), ["Party", "Calm"])
        XCTAssertEqual(sink.values["settings.camera.zoom"], .double(1.75))
    }

    func testReplaceTakesTheBackupsContentUnderTheDevicesIdentifiers() throws {
        let sink = BackupFixtures.SettingsSink()
        let device = try makeClashingDevice(sink: sink)
        let backup = try LibraryBackupReader.read(backupData).contents
        let outcome = try BackupFixtures.restore(backupData, into: device, sink: sink, choice: .replace)
        guard case .restored = outcome else { return XCTFail("\(outcome)") }
        let after = try contents(device, sink)
        XCTAssertEqual(after.scenes[BackupFixtures.sceneID(1)], backup.scenes[BackupFixtures.sceneID(1)])
        XCTAssertEqual(ShowStore(directory: device.url(.show)).load().list.cues.first?.id, BackupFixtures.uuid(70),
                       "the device's cue still points at the replaced scene")
        XCTAssertEqual(after.currentScene, backup.currentScene)
        let alpha = try XCTUnwrap(after.presets.first { (p: LibraryPreset) -> Bool in p.record.id == BackupFixtures.presetID(1) })
        XCTAssertEqual(alpha.text, BackupFixtures.presetText("Alpha"))
        XCTAssertEqual(alpha.record.state, .pending)
        let oldText = BackupFixtures.presetText("Alpha on the device")
        XCTAssertFalse(FileManager.default.fileExists(atPath: device.presetTextsFolder
            .appendingPathComponent(ContentHash.sha256Hex([UInt8](oldText)) + ".milk").path), "the replaced text is removed")
        XCTAssertEqual(after.collections?.first?.presetIDs, backup.collections?.first?.presetIDs)
        XCTAssertEqual(after.photos, backup.photos)
        XCTAssertEqual(sink.values["settings.osc.port"], .int(9_000))
        XCTAssertEqual(sink.values["favorites"], backup.settings["favorites"])
    }

    func testKeepBothAddsCopiesUnderDeterministicIdentifiers() throws {
        let sink = BackupFixtures.SettingsSink()
        let device = try makeClashingDevice(sink: sink)
        let before = try contents(device, sink)
        let backup = try LibraryBackupReader.read(backupData).contents
        let plan = LibraryRestorePlanner.plan(backup: backup, library: before)
        XCTAssertEqual(plan, LibraryRestorePlanner.plan(backup: backup, library: before), "planning twice gives the same plan")
        let outcome = try BackupFixtures.restore(backupData, into: device, sink: sink)
        guard case .restored = outcome else { return XCTFail("\(outcome)") }
        let after = try contents(device, sink)
        // Scenes: the device's scene 1 is unchanged; the backup's is added under FILE-004's derived ID with a cue.
        XCTAssertEqual(after.scenes[BackupFixtures.sceneID(1)], before.scenes[BackupFixtures.sceneID(1)])
        let sceneEntry = try XCTUnwrap(plan.entries.first { (e: LibraryRestoreEntry) -> Bool in e.key == "scene/" + BackupFixtures.sceneID(1) })
        guard case let .addCopy(copyID, copyName) = sceneEntry.action else { return XCTFail("\(sceneEntry.action)") }
        XCTAssertNotNil(after.scenes[copyID])
        XCTAssertEqual(copyName, "Scene 1")
        XCTAssertEqual(after.cueCount, 4)
        // Presets: Alpha kept; the backup's Alpha added under the FILE-005 derived identifier as "Alpha copy".
        let alphaHash = ContentHash.sha256Hex([UInt8](BackupFixtures.presetText("Alpha")))
        let derived = LibraryRestorePlanner.derivedPresetID(BackupFixtures.presetID(1), textSHA256: alphaHash,
                                                            avoiding: [BackupFixtures.presetID(1)])
        let copy = try XCTUnwrap(after.presets.first { (p: LibraryPreset) -> Bool in p.record.id == derived })
        XCTAssertEqual(copy.record.name, "Alpha copy")
        XCTAssertEqual(after.presets.first { (p: LibraryPreset) -> Bool in p.record.id == BackupFixtures.presetID(1) }?.text,
                       before.presets[0].text)
        // Collections: "Party" kept; the backup's added as "Party copy" under a derived UUID.
        XCTAssertEqual(after.collections?.map(\.name), ["Party", "Party copy", "Calm"])
        XCTAssertEqual(after.collections?[0].presetIDs, [])
        // Single values keep the device's value (fell back); favorites are the union.
        XCTAssertEqual(after.currentScene, before.currentScene)
        XCTAssertEqual(after.photos, before.photos)
        XCTAssertEqual(sink.values["settings.osc.port"], .int(8_000))
        XCTAssertEqual(sink.values["favorites"], .strings([BackupFixtures.presetID(1), "included/Alpha.milk", "included/Zeta.milk"].sorted()))
        let fellBack = plan.entries.filter(\.fellBack).map(\.key).sorted()
        XCTAssertEqual(fellBack, ["current-scene", "photo/" + BackupFixtures.photoName(1), "setting/settings.osc.port"])
    }

    func testOverridesApplyPerRecord() throws {
        let sink = BackupFixtures.SettingsSink()
        let device = try makeClashingDevice(sink: sink)
        let overrides: [String: LibraryRestoreChoice] = ["setting/settings.osc.port": .replace, "preset/" + BackupFixtures.presetID(1): .skip]
        let outcome = try BackupFixtures.restore(backupData, into: device, sink: sink, choice: .keepBoth, overrides: overrides)
        guard case .restored = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(sink.values["settings.osc.port"], .int(9_000))
        let after = try contents(device, sink)
        XCTAssertFalse(after.presets.contains { (p: LibraryPreset) -> Bool in p.record.name == "Alpha copy" })
    }

    func testARestorePastTheCollectionLimitIsRefusedWithNothingWritten() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let backup = try BackupFixtures.backup(of: source)
        let device = BackupFixtures.sandbox(self, "device")
        try FileManager.default.createDirectory(at: device.url(.collections), withIntermediateDirectories: true)
        let full: [PresetCollection] = (0..<PresetCollectionLimits.maxCollections).map { (n: Int) -> PresetCollection in
            PresetCollection(id: BackupFixtures.uuid(1_000 + n).uuidString, name: "C\(n)", presetIDs: [])
        }
        try PresetCollectionsFile(collections: full).encode().write(to: device.collectionsFile)
        let before = LibraryTreeSnapshot.take(device.libraryRoots)
        let outcome = try BackupFixtures.restore(backup, into: device, sink: BackupFixtures.SettingsSink())
        XCTAssertEqual(outcome, .refused("There would be more than 100 collections."))
        XCTAssertEqual(LibraryTreeSnapshot.take(device.libraryRoots).differences(from: before), [])
    }

    func testDerivedIdentifiersAreStable() {
        let id = LibraryRestorePlanner.derivedPresetID("user/x", textSHA256: String(repeating: "a", count: 64), avoiding: [])
        XCTAssertEqual(id, LibraryRestorePlanner.derivedPresetID("user/x", textSHA256: String(repeating: "a", count: 64), avoiding: []))
        XCTAssertNotEqual(id, LibraryRestorePlanner.derivedPresetID("user/x", textSHA256: String(repeating: "b", count: 64), avoiding: []))
        XCTAssertNotEqual(id, LibraryRestorePlanner.derivedPresetID("user/x", textSHA256: String(repeating: "a", count: 64), avoiding: [id]))
        XCTAssertTrue(id.hasPrefix("user/"))
        XCTAssertEqual(id.count, 37)
        let collection = LibraryRestorePlanner.derivedCollectionID("C", contentSHA256: "00", avoiding: [])
        XCTAssertNotNil(UUID(uuidString: collection))
        XCTAssertEqual(LibraryRestorePlanner.collectionCopyName("Party", takenKeys: [PresetCollectionName.key("Party copy")]), "Party copy 2")
    }
}
