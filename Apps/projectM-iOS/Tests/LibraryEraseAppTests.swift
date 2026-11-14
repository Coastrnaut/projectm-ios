// LibraryEraseAppTests.swift — FILE-011-T10: the app side of the erase. The policy's folders and keys
// agree with the stores' own constants and FILE-005's lists; the coordinator measures, confirms with
// words naming the categories, records and cancels a request; a pending restore blocks it; the
// launch-time erase removes the folders and UserDefaults keys and keeps the safety settings; the stores
// then load an empty library with no error (FILE-011-R7); the result is shown once and announced.
import Foundation
import LibraryBackup
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import projectM_iOS

@MainActor
final class LibraryEraseAppTests: XCTestCase {
    private func temporaryFolder(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryEraseAppTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func suite(_ label: String) -> UserDefaults {
        let name = "LibraryEraseAppTests-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    func testFoldersAndKeysAgreeWithTheStores() {
        XCTAssertEqual(LibraryErasePolicy.videosFolderName, VideoStore.folderName)
        XCTAssertEqual(LibraryErasePolicy.audioFolderName, StorageLocations.audioLibraryFolderName)
        XCTAssertEqual(LibraryErasePolicy.photoExtensions, PhotoStore.extensions)
        XCTAssertEqual(LibraryErasePolicy.videoExtensions, [VideoStore.fileExtension])
        XCTAssertEqual(LibraryErasePolicy.videoKey, VideoStore.idKey)
        XCTAssertEqual(LibraryErasePolicy.videoLoopKey, VideoStore.loopKey)
        XCTAssertEqual(LibrarySettingsPolicy.photoKey, PhotoStore.idKey)
        XCTAssertEqual(LibraryErasePolicy.oscEnabledKey, AppSettings.oscEnabledKey)
        XCTAssertEqual(LibraryErasePolicy.midiEnabledKey, AppSettings.midiEnabledKey)
        XCTAssertEqual(LibraryErasePolicy.folders(.scenes), [StorageLocations.showFolderName, SceneAutosaveStore.folderName])
        XCTAssertEqual(LibraryErasePolicy.folders(.presets), [UserPresetStore.directoryName])
        XCTAssertEqual(LibraryErasePolicy.folders(.collections), [PresetCollectionStore.directoryName])
        XCTAssertEqual(LibraryErasePolicy.folders(.media), [PhotoStore.folderName, VideoStore.folderName])
        let appKeys: Set<String> = Set(AppSettings.allKeys + LatencyOffsetSetting.allKeys
            + [InputTrimSetting.decibelsKey, ChannelSelectionSetting.modeKey, NoiseGateSetting.enabledKey, NoiseGateSetting.thresholdKey,
               FavoritesStore.favoritesKey, FavoritesStore.lastPresetKey, PhotoStore.idKey, VideoStore.idKey, VideoStore.loopKey, TextOverlayStore.key])
        let classified: Set<String> = Set(LibraryErasePolicy.erasableKeys + LibraryErasePolicy.neverErasedKeys)
        XCTAssertEqual(appKeys.subtracting(classified), [], "every app setting is erased by a category or deliberately kept")
    }

    private func populate(_ root: URL, _ defaults: UserDefaults) throws {
        let folders = LibraryFolders(root: root)
        let store = ShowStore(directory: folders.url(.show))
        let scene = SceneDocument(id: "5CE7E000-0000-4000-8000-000000000001", name: "Erase me",
                                  layers: [SceneLayer(instance: 1, content: .linearSpectrum, values: [:])])
        try store.saveScene(scene)
        var list = ShowCueList(name: "Show")
        try list.append(sceneID: scene.id, label: "One")
        try store.save(list)
        try FileManager.default.createDirectory(at: folders.url(.collections), withIntermediateDirectories: true)
        try PresetCollectionsFile(collections: [PresetCollection(id: UUID().uuidString, name: "Party", presetIDs: ["included/a.milk"])]).encode()
            .write(to: folders.collectionsFile)
        defaults.set(["included/a.milk"], forKey: FavoritesStore.favoritesKey)
        defaults.set(9_123, forKey: "settings.osc.port")
        defaults.set(true, forKey: AppSettings.oscEnabledKey)
        defaults.set(true, forKey: LibraryErasePolicy.reduceFlashingKey)
        defaults.set(true, forKey: "notice.photosensitivityAcknowledged")
    }

    func testMeasureConfirmRequestCancelAndLaunchErase() async throws {
        let root = temporaryFolder("root")
        let defaults = suite("defaults")
        try populate(root, defaults)
        var spoken: [String] = []
        let backup = LibraryBackupCoordinator(folders: LibraryFolders(root: root), defaults: defaults,
                                              temporaryRoot: temporaryFolder("temp"))
        backup.announce = { (text: String) in spoken.append(text) }
        let model = backup.erase
        model.refresh()
        await model.work?.value
        XCTAssertEqual(model.inventory?.item(.scenes).count, 1)
        XCTAssertEqual(model.inventory?.item(.collections).count, 2, "one collection and one favorite")
        XCTAssertEqual(model.inventory?.item(.settings).count, 2, "the OSC port and OSC on")

        model.openSheet()
        XCTAssertTrue(model.showSheet)
        model.continueTapped()
        XCTAssertFalse(model.showConfirmation, "nothing chosen: no confirmation")
        model.toggle(.scenes)
        model.toggle(.settings)
        model.continueTapped()
        XCTAssertTrue(model.showConfirmation)
        XCTAssertEqual(LibraryEraseCoordinator.confirmationTitle(model.selection), "Erase 2 categories?")
        let message = LibraryEraseCoordinator.confirmationMessage(model.selection, inventory: model.inventory)
        XCTAssertTrue(message.hasPrefix("Scenes and show (1 item) and Settings (2 items) will be erased the next time projectM-iOS opens."), message)
        XCTAssertTrue(message.contains("Bundled presets, the full library purchase and caches are kept."))
        model.showConfirmation = false   // Cancel
        XCTAssertNil(LibraryEraseRequestStore(root: root).pending, "Cancel records nothing")
        model.continueTapped()
        model.requestErase()
        XCTAssertEqual(model.pending, [.scenes, .settings])
        XCTAssertFalse(model.showSheet)
        XCTAssertEqual(spoken.last, LibraryEraseCoordinator.pendingText)
        XCTAssertFalse(model.canStart, "one erase at a time")
        model.cancelErase()
        XCTAssertNil(LibraryEraseRequestStore(root: root).pending)
        XCTAssertEqual(spoken.last, LibraryEraseCoordinator.cancelledText)
        model.openSheet()
        model.toggleAll()
        XCTAssertTrue(model.allSelected)
        model.toggleAll()
        model.toggle(.scenes)
        model.toggle(.collections)
        model.toggle(.settings)
        model.requestErase()

        // Next launch.
        LibraryBackupCoordinator.finishPendingRestore(defaults: defaults, folders: LibraryFolders(root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Show").path))
        XCTAssertNil(defaults.object(forKey: FavoritesStore.favoritesKey))
        XCTAssertNil(defaults.object(forKey: "settings.osc.port"))
        XCTAssertNil(defaults.object(forKey: AppSettings.oscEnabledKey))
        XCTAssertEqual(defaults.object(forKey: LibraryErasePolicy.reduceFlashingKey) as? Bool, true, "Reduce flashing is kept")
        XCTAssertEqual(defaults.object(forKey: "notice.photosensitivityAcknowledged") as? Bool, true)
        // FILE-011-R7: the stores load an empty library with no error.
        let collections = PresetCollectionStore(directory: root.appendingPathComponent(PresetCollectionStore.directoryName))
        XCTAssertEqual(collections.collections, [])
        XCTAssertEqual(collections.loadNotice, .none)
        XCTAssertEqual(ShowStore(directory: root.appendingPathComponent("Show")).storedSceneIDs(), [])
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertFalse(settings.oscEnabled, "OSC is back to off")
        XCTAssertTrue(settings.reduceFlashing)

        let screen = LibraryBackupCoordinator(folders: LibraryFolders(root: root), defaults: defaults, temporaryRoot: temporaryFolder("t2"))
        screen.announce = { (text: String) in spoken.append(text) }
        screen.erase.refresh()
        XCTAssertNil(screen.erase.pending)
        XCTAssertEqual(screen.erase.message, "Erased: scenes and show, collections and favorites, settings.")
        XCTAssertEqual(spoken.last, screen.erase.message)
        let again = LibraryBackupCoordinator(folders: LibraryFolders(root: root), defaults: defaults, temporaryRoot: temporaryFolder("t3"))
        again.erase.refresh()
        XCTAssertNil(again.erase.message, "the result is shown once")
        await screen.erase.work?.value
        await again.erase.work?.value
    }

    func testAPendingRestoreBlocksAnEraseAndAPendingEraseBlocksARestore() throws {
        let root = temporaryFolder("exclusive")
        let folders = LibraryFolders(root: root)
        let backup = LibraryBackupCoordinator(folders: folders, defaults: suite("exclusive"), temporaryRoot: temporaryFolder("t"))
        try LibraryRestoreRequestStore(folders: folders).save(backup: Data("x".utf8), choice: .keepBoth)
        backup.refresh()
        XCTAssertTrue(backup.isRestorePending)
        XCTAssertFalse(backup.erase.canStart)
        backup.erase.openSheet()
        XCTAssertFalse(backup.erase.showSheet)
        backup.cancelRestore()
        XCTAssertTrue(backup.erase.canStart)
        backup.erase.openSheet()
        backup.erase.toggle(.presets)
        backup.erase.requestErase()
        XCTAssertEqual(backup.erase.pending, [.presets])
        backup.requestRestore()   // no preview: nothing happens, and an erase is pending anyway
        XCTAssertNil(LibraryRestoreRequestStore(folders: folders).pending)
    }
}
