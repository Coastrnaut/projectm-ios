// FolderBackupCoordinator.swift — FILE-006 (contract B6; FILE-006-R1, R8, R9): Settings › Storage ›
// Backup › Back Up to Folder… and Restore Media from Folder….
//
// * Back Up to Folder…: the system folder picker; then, off the main thread and under the folder's
//   security scope, the FILE-005 archive and the media (LibraryBackup's FolderBackupWriter: unchanged
//   media are neither read nor copied) go into `projectM Backup/` there. The result line ("Backed up to
//   the folder: 1 copied, 3 unchanged.") is shown and announced on the shared announcer's `library` lane.
// * Restore Media from Folder…: every copy is verified and staged in the app; the media are installed
//   at the next launch (`finishPendingRestore`), before any store loads. Cancel Media Restore removes
//   the staging. Not while a FILE-005 restore or a FILE-011 erase is pending (and they check this one).
// DEBUG: `-uitestBackupFolder <path>` backs up into that folder without the picker,
// `-uitestMediaRestoreFrom <path>` stages from it, `-uitestMediaSeed` stores a fake video and photo at the first Back Up to Folder….
// No networking.
import Foundation
import LibraryBackup
import LocalPortability
import Observation

@MainActor
@Observable
final class FolderBackupCoordinator {
    enum PickerPurpose: Equatable {
        case backUp, restore
    }

    static let pendingText = "Media restore ready. Close projectM-iOS and open it again to finish."
    static let otherPendingNote = "Finish or cancel the pending restore or erase first."

    private(set) var isWorking = false
    /// The folder picker is open; `pickerPurpose` says what the picked folder is for.
    var showPicker = false
    private(set) var pickerPurpose: PickerPurpose = .backUp
    private(set) var isRestorePending = false
    private(set) var message: String?

    /// The shared announcer's `library` lane (forwarded by LibraryBackupCoordinator).
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?
    /// True while a FILE-005 restore or a FILE-011 erase waits for the next launch.
    @ObservationIgnored var isOtherWorkPending: (@MainActor () -> Bool)?
    @ObservationIgnored private let folders: LibraryFolders
    @ObservationIgnored private let defaults: UserDefaults
    #if DEBUG
    @ObservationIgnored private var seeded = false
    #endif
    /// The running step (tests await it).
    @ObservationIgnored private(set) var work: Task<Void, Never>?

    init(folders: LibraryFolders, defaults: UserDefaults) {
        self.folders = folders
        self.defaults = defaults
    }

    /// At launch, after FILE-005's restore and before FILE-008's reconcile (no store has loaded).
    nonisolated static func finishPendingRestore(root: URL) {
        MediaRestoreLaunch.run(root: root)
    }

    /// The section appeared: the pending state and the launch result (once).
    func refresh() {
        let store = MediaRestoreRequestStore(root: folders.root)
        isRestorePending = store.isPending
        if let result = store.takeResult() { show(result.message) }
    }

    private func show(_ text: String) {
        message = text
        announce?(text)
    }

    // MARK: - Back up

    /// Back Up to Folder…: the picker, or in DEBUG the `-uitestBackupFolder` folder.
    func backUpTapped() {
        #if DEBUG
        if !seeded, ProcessInfo.processInfo.arguments.contains("-uitestMediaSeed") {   // after the launch reset
            seeded = true
            Self.seedMedia(root: folders.root)
        }
        if let path = defaults.string(forKey: "uitestBackupFolder") {
            backUp(to: URL(fileURLWithPath: path, isDirectory: true))
            return
        }
        #endif
        pickerPurpose = .backUp
        showPicker = true
    }

    func backUp(to picked: URL) {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        let folders = folders
        let settings = LibrarySettingsBridge.read(defaults)
        let version = UserPresetsCoordinator.bundleVersion(.main)
        let now = Date()
        work = Task { @MainActor [weak self] in
            let text: String = await Task.detached(priority: .userInitiated) { () -> String in
                Self.writeFolderBackup(picked: picked, folders: folders, settings: settings, version: version, now: now)
            }.value
            self?.isWorking = false
            self?.show(text)
        }
    }

    nonisolated static func writeFolderBackup(picked: URL, folders: LibraryFolders, settings: [String: LibrarySettingValue], version: String,
                                              now: Date) -> String {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        do {
            let contents = try LibraryContentsReader.read(folders: folders, settings: settings)
            let archive = try LibraryBackupWriter.write(contents, appVersion: version, createdAt: now)
            let report = try FolderBackupWriter().write(archive: archive, assets: MediaBackupInventory.assets(root: folders.root),
                                                        to: BackupFolderLayout.backupFolder(in: picked), appVersion: version, createdAt: now)
            return summary(report)
        } catch let error as LibraryReadError {
            return error.message
        } catch let error as LibraryBackupError {
            return error.message
        } catch let error as FolderBackupError {
            return error.message
        } catch {
            return FolderBackupError.writeFailed.message
        }
    }

    /// "Backed up to the folder: 1 copied, 3 unchanged, 1 removed."
    nonisolated static func summary(_ report: FolderBackupReport) -> String {
        var text: String = "Backed up to the folder: " + String(report.copied) + " copied, " + String(report.unchanged) + " unchanged"
        if report.removed > 0 { text += ", " + String(report.removed) + " removed" }
        return text + "."
    }

    // MARK: - Restore

    /// Restore Media from Folder…: the picker, or in DEBUG the `-uitestMediaRestoreFrom` folder.
    func restoreTapped() {
        if isOtherWorkPending?() == true {
            show(Self.otherPendingNote)
            return
        }
        #if DEBUG
        if let path = defaults.string(forKey: "uitestMediaRestoreFrom") {
            stageRestore(from: URL(fileURLWithPath: path, isDirectory: true))
            return
        }
        #endif
        pickerPurpose = .restore
        showPicker = true
    }

    func stageRestore(from picked: URL) {
        guard !isWorking, isOtherWorkPending?() != true else { return }
        isWorking = true
        message = nil
        let root = folders.root
        work = Task { @MainActor [weak self] in
            let failure: String? = await Task.detached(priority: .userInitiated) { () -> String? in
                let scoped = picked.startAccessingSecurityScopedResource()
                defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
                do {
                    _ = try MediaRestoreStager().stage(from: picked, root: root)
                    return nil
                } catch let error as MediaRestoreError {
                    return error.message
                } catch {
                    return MediaRestoreError.stagingFailed.message
                }
            }.value
            guard let self else { return }
            self.isWorking = false
            if let failure {
                self.show(failure)
            } else {
                self.isRestorePending = true
                self.show(Self.pendingText)
            }
        }
    }

    func cancelRestore() {
        MediaRestoreRequestStore(root: folders.root).cancel()
        isRestorePending = false
        show("The media restore was cancelled. Nothing was changed.")
    }

    /// The picker returned a folder.
    func picked(_ url: URL, for purpose: PickerPurpose) {
        switch purpose {
        case .backUp: backUp(to: url)
        case .restore: stageRestore(from: url)
        }
    }

    #if DEBUG
    /// `-uitestMediaSeed`: a fake 1 MiB video and a photo in the real stores (UI tests reset them first).
    nonisolated static func seedMedia(root: URL) {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FolderBackupSeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let video = scratch.appendingPathComponent("seed.mov")
        let photo = scratch.appendingPathComponent("seed.png")
        try? Data(repeating: 0x6D, count: 1 << 20).write(to: video)
        try? Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0x42, count: 64)).write(to: photo)
        let videos = ContentAddressedMediaFolder(directory: MediaBackupInventory.videosFolder(root), extensions: LibraryErasePolicy.videoExtensions)
        let photos = ContentAddressedMediaFolder(directory: MediaBackupInventory.photosFolder(root), extensions: LibraryErasePolicy.photoExtensions)
        for folder in [videos.directory, photos.directory] { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        _ = try? videos.intern(video, as: UUID(uuidString: "F1E00600-0000-4000-8000-000000000001")!, consumingSource: true)
        _ = try? photos.intern(photo, as: UUID(uuidString: "F1E00600-0000-4000-8000-000000000002")!, consumingSource: true)
    }
    #endif
}
