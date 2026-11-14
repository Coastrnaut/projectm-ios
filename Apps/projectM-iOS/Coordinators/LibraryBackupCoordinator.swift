// LibraryBackupCoordinator.swift — FILE-005 (contract C7; FILE-005-R4-R6, R12): Settings › Storage ›
// Backup.
//
// * Back Up Library…: reads the library off the main thread (LibraryBackup), writes
//   `tmp/LibraryBackup/projectM Library <date>.pmbackup` and offers it to the system file mover (the
//   user picks where it goes; the file is moved, never copied elsewhere); a cancelled mover deletes it.
// * Restore from Backup…: the picked file is read once (security scope, size cap), validated and
//   planned against the library (dry run, nothing written); the preview shows counts and "Apply to
//   all". Restore at Next Launch records the request (LibraryRestoreRequestStore); Cancel Restore
//   removes it. `finishPendingRestore` runs in AppCoordinator.init before any store loads.
// * The launch-time result is shown once and announced on the shared announcer's `library` lane.
// DEBUG: `-uitestBackupTo <host path>` copies the backup there instead of opening the mover;
// `-uitestRestoreFrom <host path>` makes Restore from Backup… preview that file instead of opening the picker. No networking.
import Foundation
import LibraryBackup
import Observation

/// What the restore preview shows.
struct LibraryRestorePreview: Equatable {
    let plan: LibraryRestorePlan
    let manifest: LibraryBackupManifest

    /// One line per kind of record ("Scenes: 3 new, 1 already here, 1 clash").
    var lines: [(title: String, text: String)] {
        let sections: [(LibraryRestoreSection, String)] = [(.scenes, "Scenes"), (.currentScene, "Current scene"), (.presets, "Presets"),
                                                           (.collections, "Collections"), (.tags, "Preset tags"), (.overrides, "Preset adjustments"), (.settings, "Settings"),
                                                           (.photos, "Photos")]
        var result: [(title: String, text: String)] = []
        for (section, title) in sections {
            let new: Int = plan.count(section, .new)
            let same: Int = plan.count(section, .identical)
            let clash: Int = plan.count(section, .clash)
            guard new + same + clash > 0 else { continue }
            var parts: [String] = []
            if new > 0 { parts.append(String(new) + " new") }
            if same > 0 { parts.append(String(same) + " already here") }
            if clash > 0 { parts.append(String(clash) + (clash == 1 ? " differs" : " differ")) }
            result.append((title, parts.joined(separator: ", ")))
        }
        return result
    }

    static func == (lhs: LibraryRestorePreview, rhs: LibraryRestorePreview) -> Bool { lhs.plan == rhs.plan && lhs.manifest == rhs.manifest }
}

@MainActor
@Observable
final class LibraryBackupCoordinator {
    static let pendingText = "Restore ready. Close projectM-iOS and open it again to finish."
    static let footer = "A backup holds your show and scenes, the presets you imported or copied from Included presets, collections, favorites and settings. Videos, imported audio and copies of full-library presets stay on this device. The file goes only where you save it. Back Up to Folder… also copies your photos, videos and imported audio, and later backups to the same folder copy only what changed."

    private(set) var isWorking = false
    /// The written backup waiting for the file mover.
    private(set) var backupFile: URL?
    var showMover = false
    /// The system file picker for Restore from Backup….
    var showPicker = false
    private(set) var preview: LibraryRestorePreview?
    private(set) var isRestorePending = false
    /// The last result or error, shown in the section.
    private(set) var message: String?
    /// DEBUG probe: the library's non-volatile records ("<count> <digest prefix>").
    private(set) var recordsProbe = ""

    /// The shared announcer's `library` lane (set by AppCoordinator).
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?
    @ObservationIgnored let folders: LibraryFolders
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let temporaryRoot: URL
    @ObservationIgnored private var previewBackup: LibraryBackupContents?
    @ObservationIgnored private var previewData: Data?
    /// The running step (tests await it).
    @ObservationIgnored private(set) var work: Task<Void, Never>?

    /// FILE-011: Erase Data… (shares the folders, the defaults and the announcer).
    @ObservationIgnored let erase: LibraryEraseCoordinator
    /// FILE-006: Back Up to Folder… and Restore Media from Folder… (same sharing).
    @ObservationIgnored let folder: FolderBackupCoordinator

    init(folders: LibraryFolders = LibraryBackupCoordinator.standardFolders(), defaults: UserDefaults = .standard,
         temporaryRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryBackup", isDirectory: true)) {
        self.folders = folders
        self.defaults = defaults
        self.temporaryRoot = temporaryRoot
        erase = LibraryEraseCoordinator(root: folders.root, defaults: defaults)
        folder = FolderBackupCoordinator(folders: folders, defaults: defaults)
        erase.announce = { [weak self] (text: String) in self?.announce?(text) }
        erase.isRestorePending = { [weak self] () -> Bool in (self?.isRestorePending ?? false) || (self?.folder.isRestorePending ?? false) }
        folder.announce = { [weak self] (text: String) in self?.announce?(text) }
        folder.isOtherWorkPending = { [weak self] () -> Bool in self?.erase.pending != nil }   // FILE-006: not while an erase waits
    }

    nonisolated static func standardFolders() -> LibraryFolders {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return LibraryFolders(root: support)
    }

    /// AppCoordinator.init, before any store reads the library (research FILE-005-D3).
    /// FILE-011-R3: a pending erase runs first (research FILE-011-D1), then a pending restore.
    nonisolated static func finishPendingRestore(defaults: UserDefaults, folders: LibraryFolders = standardFolders()) {
        LibraryEraseCoordinator.finishPendingErase(defaults: defaults, root: folders.root)
        LibraryRestoreLaunch.run(folders: folders, settings: LibrarySettingsBridge.read(defaults)) { (values: [String: LibrarySettingValue]) in
            LibrarySettingsBridge.apply(values, to: defaults)
        }
        FolderBackupCoordinator.finishPendingRestore(root: folders.root)   // FILE-006-R8: media after the library records
    }

    // MARK: - Section state

    /// The section appeared: the pending state, the launch result (once) and, in DEBUG, a fixture file.
    func refresh() {
        folder.refresh()   // FILE-006
        let store = LibraryRestoreRequestStore(folders: folders)
        isRestorePending = store.pending != nil
        if let note = store.takeResult() {
            message = note.message
            say(note.message)
        }
        #if DEBUG
        updateProbe()
        #endif
    }

    /// Restore from Backup… : the system picker, or in DEBUG the `-uitestRestoreFrom` file (pickers
    /// cannot be automated). True when the picker should open.
    func restoreTapped() -> Bool {
        #if DEBUG
        if let path = defaults.string(forKey: "uitestRestoreFrom") {
            previewRestore(at: URL(fileURLWithPath: path))
            return false
        }
        #endif
        return true
    }

    #if DEBUG
    private func updateProbe() {
        let folders = folders
        let settings = LibrarySettingsBridge.read(defaults)
        Task { @MainActor [weak self] in
            let probe: String = await Task.detached(priority: .utility) { () -> String in
                guard let records = try? LibraryRecords.read(folders: folders, settings: settings) else { return "unreadable" }
                let stable = LibraryRecords(digests: records.digests.filter { (entry: (key: String, value: String)) -> Bool in
                    !entry.key.hasPrefix("current-scene") && !entry.key.hasPrefix("setting/")
                })
                let port: String = settings["settings.osc.port"].map { (value: LibrarySettingValue) -> String in
                    String(decoding: value.canonicalBytes, as: UTF8.self)
                } ?? "none"
                return String(stable.count) + " " + String(stable.digest.prefix(12)) + " port " + port
            }.value
            self?.recordsProbe = probe
        }
    }
    #endif

    private func say(_ text: String) { announce?(text) }

    // MARK: - Back up

    func backUp() {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        let folders = folders
        let settings = LibrarySettingsBridge.read(defaults)
        let root = temporaryRoot
        let version = UserPresetsCoordinator.bundleVersion(.main)
        let now = Date()
        work = Task { @MainActor [weak self] in
            let result: Result<(URL, LibraryContents), LibraryBackupFailure> = await Task.detached(priority: .userInitiated) {
                () -> Result<(URL, LibraryContents), LibraryBackupFailure> in
                Self.writeBackup(folders: folders, settings: settings, root: root, version: version, now: now)
            }.value
            self?.finishBackup(result)
        }
    }

    struct LibraryBackupFailure: Error {
        let message: String
    }

    nonisolated static func writeBackup(folders: LibraryFolders, settings: [String: LibrarySettingValue], root: URL, version: String,
                                        now: Date) -> Result<(URL, LibraryContents), LibraryBackupFailure> {
        do {
            let contents = try LibraryContentsReader.read(folders: folders, settings: settings, videos: count(folders.root, "Videos"),
                                                          importedAudio: count(folders.root, "AudioLibrary"))
            let data = try LibraryBackupWriter.write(contents, appVersion: version, createdAt: now)
            try? FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent(LibraryBackupFormat.fileName(createdAt: now), isDirectory: false)
            try data.write(to: url, options: .atomic)
            return .success((url, contents))
        } catch let error as LibraryReadError {
            return .failure(LibraryBackupFailure(message: error.message))
        } catch let error as LibraryBackupError {
            return .failure(LibraryBackupFailure(message: error.message))
        } catch {
            return .failure(LibraryBackupFailure(message: LibraryBackupError.writeFailed.message))
        }
    }

    nonisolated private static func count(_ root: URL, _ name: String) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(name, isDirectory: true).path)) ?? []
        return names.filter { (n: String) -> Bool in !n.hasPrefix(".") }.count
    }

    private func finishBackup(_ result: Result<(URL, LibraryContents), LibraryBackupFailure>) {
        isWorking = false
        switch result {
        case let .failure(failure):
            message = failure.message
            say(failure.message)
        case let .success((url, contents)):
            let text = Self.backupSummary(contents)
            message = text
            say(text)
            #if DEBUG
            if let path = defaults.string(forKey: "uitestBackupTo") {
                let target = URL(fileURLWithPath: path)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: url, to: target)
                removeTemporaryFiles()
                return
            }
            #endif
            backupFile = url
            showMover = true
        }
    }

    /// "Backed up 3 scenes, 2 presets, 1 collection and 5 settings. Not included: …"
    static func backupSummary(_ contents: LibraryContents) -> String {
        let counts = contents.counts
        let scenes: Int = counts.scenes + counts.currentScene
        let head: String = "Backed up " + LibraryRestoreSummary.phrase(scenes, "scene", "scenes") + ", "
            + LibraryRestoreSummary.phrase(counts.presets, "preset", "presets") + ", "
            + LibraryRestoreSummary.phrase(counts.collections, "collection", "collections") + " and "
            + LibraryRestoreSummary.phrase(counts.settings, "setting", "settings") + "."
        let excluded = contents.excluded
        var left: [String] = []
        if excluded.fullLibraryCopies > 0 {
            left.append(LibraryRestoreSummary.phrase(excluded.fullLibraryCopies, "copy of a full-library preset", "copies of full-library presets"))
        }
        if excluded.quarantinedPresets > 0 { left.append(LibraryRestoreSummary.phrase(excluded.quarantinedPresets, "preset in Quarantine", "presets in Quarantine")) }
        if excluded.videos > 0 { left.append(LibraryRestoreSummary.phrase(excluded.videos, "video", "videos")) }
        if excluded.importedAudio > 0 { left.append(LibraryRestoreSummary.phrase(excluded.importedAudio, "imported audio file", "imported audio files")) }
        guard !left.isEmpty else { return head }
        return head + " Kept on this device only: " + left.joined(separator: ", ") + "."
    }

    /// The mover closed: moved (the file is the user's now) or cancelled (deleted).
    func moverFinished(_ result: Result<URL, any Error>) {
        if case .failure = result {
            message = "The backup was not saved."
            say("The backup was not saved.")
        }
        removeTemporaryFiles()
    }

    func moverCancelled() {
        message = "The backup was not saved."
        removeTemporaryFiles()
    }

    private func removeTemporaryFiles() {
        backupFile = nil
        showMover = false
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    // MARK: - Restore

    /// Reads the picked file once and opens the preview. Nothing is written.
    func previewRestore(at url: URL) {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        let folders = folders
        let settings = LibrarySettingsBridge.read(defaults)
        work = Task { @MainActor [weak self] in
            let result: Result<(Data, LibraryBackupContents, LibraryRestorePlan), LibraryBackupFailure> = await Task.detached(priority: .userInitiated) {
                () -> Result<(Data, LibraryBackupContents, LibraryRestorePlan), LibraryBackupFailure> in
                Self.planRestore(url: url, folders: folders, settings: settings)
            }.value
            self?.finishPreview(result)
        }
    }

    nonisolated static func readPicked(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= LibraryBackupFormat.maxFileBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    nonisolated static func planRestore(url: URL, folders: LibraryFolders, settings: [String: LibrarySettingValue])
        -> Result<(Data, LibraryBackupContents, LibraryRestorePlan), LibraryBackupFailure> {
        guard let data = readPicked(url) else { return .failure(LibraryBackupFailure(message: "The file could not be read, or it is larger than 512 MB.")) }
        do {
            let backup = try LibraryBackupReader.read(data)
            let library = try LibraryContentsReader.read(folders: folders, settings: settings)
            return .success((data, backup, LibraryRestorePlanner.plan(backup: backup.contents, library: library)))
        } catch let error as LibraryBackupError {
            return .failure(LibraryBackupFailure(message: error.message))
        } catch let error as LibraryReadError {
            return .failure(LibraryBackupFailure(message: error.message))
        } catch {
            return .failure(LibraryBackupFailure(message: LibraryRestoreText.failed))
        }
    }

    private func finishPreview(_ result: Result<(Data, LibraryBackupContents, LibraryRestorePlan), LibraryBackupFailure>) {
        isWorking = false
        switch result {
        case let .failure(failure):
            message = failure.message
            say(failure.message)
        case let .success((data, backup, plan)):
            previewData = data
            previewBackup = backup
            preview = LibraryRestorePreview(plan: plan, manifest: backup.manifest)
            say(Self.previewAnnouncement(plan))
        }
    }

    static func previewAnnouncement(_ plan: LibraryRestorePlan) -> String {
        if let refusal = plan.refusal { return refusal.message }
        let clashes: Int = plan.clashCount
        guard clashes > 0 else { return "Backup read. Nothing in it differs from your library." }
        return "Backup read. " + String(clashes) + (clashes == 1 ? " record differs" : " records differ") + " from your library."
    }

    /// "Apply to all" changed: plans again (nothing written).
    func setChoice(_ choice: LibraryRestoreChoice) {
        guard let backup = previewBackup, let current = preview, current.plan.choice != choice else { return }
        let library = (try? LibraryContentsReader.read(folders: folders, settings: LibrarySettingsBridge.read(defaults))) ?? LibraryContents()
        preview = LibraryRestorePreview(plan: LibraryRestorePlanner.plan(backup: backup.contents, library: library, choice: choice),
                                        manifest: current.manifest)
    }

    func cancelPreview() {
        preview = nil
        previewBackup = nil
        previewData = nil
    }

    /// Records the request for the next launch.
    func requestRestore() {
        guard let data = previewData, let plan = preview?.plan, erase.pending == nil else { return }   // FILE-011: not while an erase waits
        do {
            try LibraryRestoreRequestStore(folders: folders).save(backup: data, choice: plan.choice)
            isRestorePending = true
            message = nil
            say(Self.pendingText)
        } catch {
            message = LibraryRestoreText.failed
            say(LibraryRestoreText.failed)
        }
        cancelPreview()
    }

    func cancelRestore() {
        LibraryRestoreRequestStore(folders: folders).cancel()
        isRestorePending = false
        message = "The restore was cancelled. Nothing was changed."
        say("The restore was cancelled. Nothing was changed.")
    }

    /// What "Apply to all" does, for the preview.
    static func choiceExplanation(_ choice: LibraryRestoreChoice) -> String {
        switch choice {
        case .keepBoth: "Records that differ are added as copies; for the current scene, settings and photos your version stays. Favorites are combined."
        case .replace: "Records that differ take the backup's version."
        case .skip: "Records that differ stay as they are on this device."
        }
    }

    static func choiceTitle(_ choice: LibraryRestoreChoice) -> String {
        switch choice {
        case .keepBoth: "Keep both"
        case .replace: "Replace"
        case .skip: "Skip"
        }
    }
}
