// LibraryBackupAppTests.swift — FILE-005-T15: the app side of the library backup. The key list and folder
// names agree with the stores' own constants; the UserDefaults bridge round-trips every type; the
// coordinator backs up, deletes its temporary file, previews (nothing written), records and cancels a
// request; the launch-time restore applies settings and its result is shown once and announced.
import Foundation
import LibraryBackup
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import projectM_iOS

@MainActor
final class LibraryBackupAppTests: XCTestCase {
    private func temporaryFolder(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryBackupAppTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func suite(_ label: String) -> UserDefaults {
        let name = "LibraryBackupAppTests-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    func testIncludedKeysAndFolderNamesAgreeWithTheStores() {
        let appKeys: Set<String> = Set(AppSettings.allKeys + LatencyOffsetSetting.allKeys + ColorGradeSetting.allKeys + MotionFeedbackSetting.allKeys + EffectChainSetting.allKeys
            + [InputTrimSetting.decibelsKey, ChannelSelectionSetting.modeKey, NoiseGateSetting.enabledKey, NoiseGateSetting.thresholdKey,
               FavoritesStore.favoritesKey, FavoritesStore.lastPresetKey, PhotoStore.idKey, TextOverlayStore.key,
               MIDIMappingCoordinator.mappingsKey, RecordingAudioSetting.includeMicrophoneKey,   // MIDI-003-R9, REC-004-R3
               PlaybackBalanceSetting.positionKey,   // AUD-010-R9
               ParameterShelf.pinsKey,   // UIX-004-R10
               RecordingCountdownSetting.key,   // REC-007-R8
               RecordingTimedStopSetting.key,   // REC-008-R9
               SplitEditorSetting.key,   // UIX-007-R7 (excluded: this device's screen)
               OSCRoutesCoordinator.disabledRoutesKey, OSCRoutesCoordinator.aliasesKey]   // OSC-003-R9
            + RecentPresetsStore.allKeys)   // PRE-006-R7
        let included = Set(LibrarySettingsPolicy.includedKeys)
        let excluded = Set(LibrarySettingsPolicy.excludedKeys)
        XCTAssertEqual(included.subtracting(appKeys), [], "every included key is a key the app stores")
        XCTAssertEqual(appKeys.subtracting(included).subtracting(excluded), [], "every app key is included or deliberately left out")
        XCTAssertEqual(appKeys.intersection(excluded),
                       [AppSettings.oscEnabledKey, AppSettings.midiEnabledKey, RecordingAudioSetting.includeMicrophoneKey,
                        VideoStore.idKey, VideoStore.loopKey, VideoStore.speedKey,   // MED-004, REC-004-R3
                        RecentPresetsStore.historyKey,   // PRE-006-R7: history never travels
                        SplitEditorSetting.key])   // UIX-007-R7
        XCTAssertEqual(LibraryFolders.Folder.show.rawValue, StorageLocations.showFolderName)
        XCTAssertEqual(LibraryFolders.Folder.currentScene.rawValue, SceneAutosaveStore.folderName)
        XCTAssertEqual(LibraryFolders.Folder.presets.rawValue, UserPresetStore.directoryName)
        XCTAssertEqual(LibraryFolders.Folder.collections.rawValue, PresetCollectionStore.directoryName)
        XCTAssertEqual(LibraryFolders.Folder.photos.rawValue, PhotoStore.folderName)
        XCTAssertEqual(LibraryFolders.currentSceneFileName, SceneAutosaveStore.mainName)
        XCTAssertEqual(LibraryFolders.collectionsFileName, PresetCollectionStore.fileName)
        XCTAssertEqual(LibraryFolders.presetIndexFileName, UserPresetStore.indexFileName)
        let standard = LibraryBackupCoordinator.standardFolders()
        XCTAssertEqual(standard.url(.show).standardizedFileURL.path, (try? ShowStore.defaultDirectory())?.standardizedFileURL.path)
    }

    func testTheSettingsBridgeRoundTripsEveryType() {
        let source = suite("source")
        source.set(true, forKey: "settings.reduceFlashing")
        source.set(9_123, forKey: "settings.osc.port")
        source.set(1.75, forKey: "settings.camera.zoom")
        source.set("circularSpectrum", forKey: "settings.visual")
        source.set(["user/a", "included/b.milk"], forKey: "favorites")
        source.set(Data([1, 2, 3]), forKey: "settings.text.overlay")
        source.set(true, forKey: "settings.osc.enabled")   // never read
        let values = LibrarySettingsBridge.read(source)
        XCTAssertEqual(values["settings.reduceFlashing"], .bool(true))
        XCTAssertEqual(values["settings.osc.port"], .int(9_123))
        XCTAssertEqual(values["settings.camera.zoom"], .double(1.75))
        XCTAssertEqual(values["settings.visual"], .string("circularSpectrum"))
        XCTAssertEqual(values["favorites"], .strings(["user/a", "included/b.milk"]))
        XCTAssertEqual(values["settings.text.overlay"], .data(Data([1, 2, 3])))
        XCTAssertNil(values["settings.osc.enabled"])
        let target = suite("target")
        LibrarySettingsBridge.apply(values.merging(["settings.osc.enabled": .bool(true)]) { (a: LibrarySettingValue, _: LibrarySettingValue) in a },
                                    to: target)
        XCTAssertEqual(LibrarySettingsBridge.read(target), values)
        XCTAssertNil(target.object(forKey: "settings.osc.enabled"), "only included keys are written")
        XCTAssertEqual(target.object(forKey: "settings.reduceFlashing") as? Bool, true)
        XCTAssertEqual(target.integer(forKey: "settings.osc.port"), 9_123)
    }

    /// Back up, announce, delete the temporary file when the mover is cancelled; preview, request,
    /// launch-time restore into a fresh library, result shown once.
    func testBackUpPreviewRequestAndLaunchRestore() async throws {
        let sourceRoot = temporaryFolder("source")
        let sourceFolders = LibraryFolders(root: sourceRoot)
        let store = ShowStore(directory: sourceFolders.url(.show))
        let scene = SceneDocument(id: "5CE7E000-0000-4000-8000-000000000001", name: "Backed up",
                                  layers: [SceneLayer(instance: 1, content: .linearSpectrum, values: [:])])
        try store.saveScene(scene)
        var list = ShowCueList(name: "Show")
        try list.append(sceneID: scene.id, label: "One")
        try store.save(list)
        let sourceDefaults = suite("sourceDefaults")
        sourceDefaults.set(9_123, forKey: "settings.osc.port")
        let temp = temporaryFolder("temp")
        var spoken: [String] = []
        let backup = LibraryBackupCoordinator(folders: sourceFolders, defaults: sourceDefaults, temporaryRoot: temp.appendingPathComponent("out"))
        backup.announce = { (text: String) in spoken.append(text) }
        backup.backUp()
        await backup.work?.value
        let file = try XCTUnwrap(backup.backupFile)
        XCTAssertTrue(backup.showMover)
        XCTAssertEqual(backup.message, "Backed up 1 scene, 0 presets, 0 collections and 1 setting.")
        XCTAssertEqual(spoken.last, backup.message)
        let saved = temp.appendingPathComponent("saved.pmbackup")
        try FileManager.default.copyItem(at: file, to: saved)
        backup.moverCancelled()
        XCTAssertNil(backup.backupFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "no copy is left in the app's folders")

        let freshFolders = LibraryFolders(root: temporaryFolder("fresh"))
        let freshDefaults = suite("freshDefaults")
        let restore = LibraryBackupCoordinator(folders: freshFolders, defaults: freshDefaults, temporaryRoot: temp.appendingPathComponent("r"))
        restore.announce = { (text: String) in spoken.append(text) }
        restore.previewRestore(at: saved)
        await restore.work?.value
        let preview = try XCTUnwrap(restore.preview)
        XCTAssertEqual(preview.plan.choice, .keepBoth)
        XCTAssertEqual(preview.lines.first?.title, "Scenes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: freshFolders.url(.show).path), "the preview writes nothing")
        restore.setChoice(.replace)
        XCTAssertEqual(restore.preview?.plan.choice, .replace)
        restore.requestRestore()
        XCTAssertTrue(restore.isRestorePending)
        XCTAssertEqual(spoken.last, LibraryBackupCoordinator.pendingText)
        restore.cancelRestore()
        XCTAssertNil(LibraryRestoreRequestStore(folders: freshFolders).pending)
        restore.previewRestore(at: saved)
        await restore.work?.value
        restore.requestRestore()

        LibraryBackupCoordinator.finishPendingRestore(defaults: freshDefaults, folders: freshFolders)
        XCTAssertEqual(freshDefaults.integer(forKey: "settings.osc.port"), 9_123, "settings applied after the commit")
        XCTAssertEqual(try LibraryRecords.read(folders: freshFolders, settings: LibrarySettingsBridge.read(freshDefaults)),
                       try LibraryRecords.read(folders: sourceFolders, settings: LibrarySettingsBridge.read(sourceDefaults)))
        let screen = LibraryBackupCoordinator(folders: freshFolders, defaults: freshDefaults, temporaryRoot: temp)
        screen.announce = { (text: String) in spoken.append(text) }
        screen.refresh()
        XCTAssertFalse(screen.isRestorePending)
        XCTAssertEqual(screen.message, "Restored from backup: 1 scene, 0 presets, 0 collections and 1 setting.")
        XCTAssertEqual(spoken.last, screen.message)
        let again = LibraryBackupCoordinator(folders: freshFolders, defaults: freshDefaults, temporaryRoot: temp)
        again.refresh()
        XCTAssertNil(again.message, "the result is shown once")
    }

    /// FILE-008-T13 (FILE-008-R9, S4): a library whose two photo references share one payload backs up
    /// both references and restores them exactly; the next launch's reconcile shares the payload again.
    func testADeduplicatedPhotoLibraryBacksUpAndRestoresExactly() async throws {
        let sourceFolders = LibraryFolders(root: temporaryFolder("dedupSource"))
        let sourceDefaults = suite("dedupSourceDefaults")
        let photos = PhotoStore(directory: sourceFolders.url(.photos), defaults: sourceDefaults)
        let picked = temporaryFolder("picked").appendingPathComponent("p.png")
        try XCTUnwrap(UITestPhotoFixture.png(alpha: false)).write(to: picked)
        let first = try photos.importImage(at: picked)
        let second = try photos.importImage(at: picked)
        XCTAssertEqual(photos.folder.payloadNames().count, 1)
        let temp = temporaryFolder("dedupTemp")
        let backup = LibraryBackupCoordinator(folders: sourceFolders, defaults: sourceDefaults, temporaryRoot: temp.appendingPathComponent("out"))
        backup.backUp()
        await backup.work?.value
        let saved = temp.appendingPathComponent("saved.pmbackup")
        try FileManager.default.copyItem(at: try XCTUnwrap(backup.backupFile), to: saved)
        backup.moverCancelled()
        let contents = try LibraryBackupReader.read(try Data(contentsOf: saved)).contents
        let ext = second.url.pathExtension   // the sanitizer's choice (an opaque picture is stored as JPEG)
        XCTAssertEqual(Set(contents.photos.keys), ["\(first.id.uuidString).\(ext)", "\(second.id.uuidString).\(ext)"], "both references")
        XCTAssertEqual(contents.photos["\(first.id.uuidString).\(ext)"], try Data(contentsOf: second.url), "each with the payload's bytes")

        let freshFolders = LibraryFolders(root: temporaryFolder("dedupFresh"))
        let freshDefaults = suite("dedupFreshDefaults")
        let restore = LibraryBackupCoordinator(folders: freshFolders, defaults: freshDefaults, temporaryRoot: temp.appendingPathComponent("r"))
        restore.previewRestore(at: saved)
        await restore.work?.value
        restore.requestRestore()
        LibraryBackupCoordinator.finishPendingRestore(defaults: freshDefaults, folders: freshFolders)
        let original = try LibraryRecords.read(folders: sourceFolders, settings: LibrarySettingsBridge.read(sourceDefaults))
        XCTAssertEqual(try LibraryRecords.read(folders: freshFolders, settings: LibrarySettingsBridge.read(freshDefaults)).differences(from: original), [])
        // The next launch (FILE-008-R7): one payload, both references, the same records.
        let restored = PhotoStore(directory: freshFolders.url(.photos), defaults: freshDefaults)
        restored.prepareFolder()
        restored.reconcileFolder()
        restored.prepareFolder()
        XCTAssertEqual(restored.folder.payloadNames().count, 1)
        XCTAssertEqual(Set(restored.knownIDs()), [first.id, second.id])
        XCTAssertEqual(restored.current()?.id, second.id)
        XCTAssertEqual(try LibraryRecords.read(folders: freshFolders, settings: LibrarySettingsBridge.read(freshDefaults)).differences(from: original), [])
    }

    func testABadFileIsRefusedWithAMessage() async throws {
        let folder = temporaryFolder("bad")
        let bad = folder.appendingPathComponent("bad.pmbackup")
        try Data("not a backup".utf8).write(to: bad)
        let model = LibraryBackupCoordinator(folders: LibraryFolders(root: folder), defaults: suite("bad"), temporaryRoot: folder)
        model.previewRestore(at: bad)
        await model.work?.value
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.message, "This file is not a ZIP archive.")
    }
}
