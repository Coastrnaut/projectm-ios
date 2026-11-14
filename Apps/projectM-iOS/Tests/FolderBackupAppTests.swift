// FolderBackupAppTests.swift — FILE-006-T12: the app side of the folder backup. The summary text; a
// backup into a folder then a second one reporting every asset unchanged; the audio folder name agrees
// with the audio library; staging a media restore, its pending state and the launch-time install with
// the result shown once and announced; a pending erase blocks the restore (and the reverse).
import Foundation
import LibraryBackup
import LocalPortability
import XCTest
@testable import projectM_iOS

@MainActor
final class FolderBackupAppTests: XCTestCase {
    private func temporaryFolder(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FolderBackupAppTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func suite(_ label: String) -> UserDefaults {
        let name = "FolderBackupAppTests-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func seededRoot(_ label: String) -> URL {
        let root = temporaryFolder(label)
        FolderBackupCoordinator.seedMedia(root: root)
        return root
    }

    func testTheSummaryNamesCopiedUnchangedAndRemoved() {
        let manifest = BackupFolderManifest(appVersion: "1", createdAt: "2026-11-14T00:00:00Z", library: nil, assets: [])
        let report = FolderBackupReport(copied: 1, unchanged: 3, removed: 2, bytesCopied: 10, fullBackup: false, manifest: manifest)
        XCTAssertEqual(FolderBackupCoordinator.summary(report), "Backed up to the folder: 1 copied, 3 unchanged, 2 removed.")
        let none = FolderBackupReport(copied: 0, unchanged: 2, removed: 0, bytesCopied: 0, fullBackup: false, manifest: manifest)
        XCTAssertEqual(FolderBackupCoordinator.summary(none), "Backed up to the folder: 0 copied, 2 unchanged.")
        XCTAssertEqual(LibraryErasePolicy.audioFolderName, StorageLocations.audioLibraryFolderName)
    }

    func testASecondBackupReportsEveryAssetUnchanged() async {
        let root = seededRoot("backup")
        let drive = temporaryFolder("drive")
        let model = FolderBackupCoordinator(folders: LibraryFolders(root: root), defaults: suite("backup"))
        var spoken: [String] = []
        model.announce = { (text: String) in spoken.append(text) }
        model.backUp(to: drive)
        await model.work?.value
        XCTAssertEqual(model.message, "Backed up to the folder: 2 copied, 0 unchanged.")
        model.backUp(to: drive)
        await model.work?.value
        XCTAssertEqual(model.message, "Backed up to the folder: 0 copied, 2 unchanged.")
        XCTAssertEqual(spoken.count, 2, "each result is announced on the library lane")
        let folder = drive.appendingPathComponent(BackupFolderLayout.folderName, isDirectory: true)
        XCTAssertNotNil(BackupFolderManifest.read(folder: folder))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(BackupFolderLayout.archiveName).path))
    }

    func testAStagedRestoreIsInstalledAtTheNextLaunch() async throws {
        let source = seededRoot("source")
        let drive = temporaryFolder("drive2")
        let backup = FolderBackupCoordinator(folders: LibraryFolders(root: source), defaults: suite("source"))
        backup.backUp(to: drive)
        await backup.work?.value

        let device = temporaryFolder("device")
        let defaults = suite("device")
        let model = FolderBackupCoordinator(folders: LibraryFolders(root: device), defaults: defaults)
        model.stageRestore(from: drive)
        await model.work?.value
        XCTAssertTrue(model.isRestorePending)
        XCTAssertEqual(model.message, FolderBackupCoordinator.pendingText)

        LibraryBackupCoordinator.finishPendingRestore(defaults: defaults, folders: LibraryFolders(root: device))   // the next launch
        let relaunched = FolderBackupCoordinator(folders: LibraryFolders(root: device), defaults: defaults)
        relaunched.refresh()
        XCTAssertFalse(relaunched.isRestorePending)
        XCTAssertEqual(relaunched.message, "Media restored: 2 added, 0 already on this device.")
        relaunched.refresh()
        XCTAssertEqual(relaunched.message, "Media restored: 2 added, 0 already on this device.", "unchanged: the result is taken once")
        let videos = ContentAddressedMediaFolder(directory: MediaBackupInventory.videosFolder(device), extensions: [VideoStore.fileExtension])
        let restored = try XCTUnwrap(videos.resolve(UUID(uuidString: "F1E00600-0000-4000-8000-000000000001")!))
        XCTAssertEqual(try Data(contentsOf: restored).count, 1 << 20)
    }

    func testAPendingEraseBlocksTheMediaRestoreAndTheReverse() async {
        let root = temporaryFolder("exclusive")
        let defaults = suite("exclusive")
        let backup = LibraryBackupCoordinator(folders: LibraryFolders(root: root), defaults: defaults, temporaryRoot: temporaryFolder("tmp"))
        backup.folder.isOtherWorkPending = { () -> Bool in true }
        backup.folder.restoreTapped()
        XCTAssertEqual(backup.folder.message, FolderBackupCoordinator.otherPendingNote)
        XCTAssertFalse(backup.folder.showPicker)
        // A staged media restore keeps Erase Data… from starting.
        let source = seededRoot("exclusive-source")
        let drive = temporaryFolder("exclusive-drive")
        let writer = FolderBackupCoordinator(folders: LibraryFolders(root: source), defaults: suite("exclusive-source"))
        writer.backUp(to: drive)
        await writer.work?.value
        backup.folder.isOtherWorkPending = { () -> Bool in false }
        backup.folder.stageRestore(from: drive)
        await backup.folder.work?.value
        XCTAssertTrue(backup.folder.isRestorePending)
        XCTAssertFalse(backup.erase.canStart)
        backup.folder.cancelRestore()
        XCTAssertFalse(backup.folder.isRestorePending)
    }
}
