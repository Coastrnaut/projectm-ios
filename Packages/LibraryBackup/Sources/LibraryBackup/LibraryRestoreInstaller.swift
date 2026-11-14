// LibraryRestoreInstaller.swift — FILE-005 contract C5 (FILE-005-R7; research FILE-005-D4): installs a
// restore plan all or nothing.
//
//   1. Read the library again and plan again with the same choice; a different plan is returned and
//      nothing is written (the library changed since the preview).
//   2. For each folder the plan changes, copy the live folder to `LibraryRestore/staging/<name>` and
//      apply the plan there (presets, collections, the current scene and photos by direct writes; the
//      show exactly, or through FILE-004's scene installer on the staged copy).
//   3. Write `restore.journal.json` (phase "prepared", the folders).
//   4. Per folder: move the live folder to `LibraryRestore/previous/<name>`, then the staged one into place.
//   5. Replace the journal with phase "committed" and the settings to apply — the commit point.
//   6. Hand the settings to the app, then remove `staging/`, `previous/` and the journal.
// A failure in 2-5 moves every folder back and removes the work folders: the library is byte for byte
// as before. After 5 only clean-up remains. `recover` (call it at launch before anything reads the
// library) rolls a "prepared" journal back and a "committed" one forward. Every file operation in
// steps 2-6 goes through `perform`, which a test hook can make fail. Renames stay within one volume
// (all folders share the root). No networking; nothing read is executed.
import Foundation
import LocalPortability
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage

public struct LibraryRestoreSummary: Sendable, Equatable {
    public let scenes: Int
    public let presets: Int
    public let collections: Int
    public let settings: Int
    public let photos: Int

    public init(plan: LibraryRestorePlan) {
        scenes = plan.changeCount(.scenes) + plan.changeCount(.currentScene)
        presets = plan.changeCount(.presets)
        collections = plan.changeCount(.collections)
        settings = plan.changeCount(.settings)
        photos = plan.changeCount(.photos)
    }

    /// "Restored from backup: 3 scenes, 2 presets, 1 collection and 5 settings."
    public var message: String {
        let parts: [String] = [Self.phrase(scenes, "scene", "scenes"), Self.phrase(presets, "preset", "presets"),
                               Self.phrase(collections, "collection", "collections")]
        var text: String = "Restored from backup: " + parts.joined(separator: ", ") + " and " + Self.phrase(settings, "setting", "settings")
        if photos > 0 { text += ", plus " + Self.phrase(photos, "photo", "photos") }
        return text + "."
    }

    public static func phrase(_ count: Int, _ one: String, _ many: String) -> String { String(count) + " " + (count == 1 ? one : many) }
}

public enum LibraryRestoreOutcome: Sendable, Equatable {
    case restored(LibraryRestoreSummary)
    /// The library changed since the plan: the new plan; nothing was written.
    case changed(LibraryRestorePlan)
    /// Nothing was written; the words say why.
    case refused(String)
}

public enum LibraryRestoreText {
    public static let nothingToRestore = "Everything in this backup is already in your library."
    public static let failed = "The restore did not finish. Nothing was changed."
    public static let interrupted = "An earlier restore did not finish."
}

public final class LibraryRestoreInstaller {
    public enum FileOperation: String, Sendable, Equatable {
        case createDirectory, copy, write, move, remove
    }

    static let journalFileName = "restore.journal.json"
    static let stagingFolderName = "staging"
    static let previousFolderName = "previous"

    struct Journal: Codable, Equatable {
        enum Phase: String, Codable { case prepared, committed }
        struct FolderEntry: Codable, Equatable {
            var name: String
            var hadLive: Bool
        }
        var schemaVersion = 1
        var phase: Phase
        var folders: [FolderEntry]
        var settings: [String: LibrarySettingValue]
    }

    private struct InstallFailure: Error {}

    public let folders: LibraryFolders
    /// Tests: may throw before an operation is performed (an injected fault).
    var fault: ((FileOperation, URL) throws -> Void)?
    /// Tests: sees every operation that is performed.
    var observer: ((FileOperation, URL) -> Void)?

    public init(folders: LibraryFolders) {
        self.folders = folders
    }

    var journalFile: URL { folders.restore.appendingPathComponent(Self.journalFileName, isDirectory: false) }
    var stagingRoot: URL { folders.restore.appendingPathComponent(Self.stagingFolderName, isDirectory: true) }
    var previousRoot: URL { folders.restore.appendingPathComponent(Self.previousFolderName, isDirectory: true) }

    public var hasInterruptedRestore: Bool { FileManager.default.fileExists(atPath: journalFile.path) }

    // MARK: - Install

    /// `settings`: the app's current setting values (the plan is made again with them).
    /// `applySettings` runs after the commit point with the values to set.
    public func install(backup: LibraryContents, plan: LibraryRestorePlan, settings: [String: LibrarySettingValue],
                        applySettings: ([String: LibrarySettingValue]) -> Void) -> LibraryRestoreOutcome {
        if hasInterruptedRestore { return .refused(LibraryRestoreText.interrupted) }
        let library: LibraryContents
        do {
            library = try LibraryContentsReader.read(folders: folders, settings: settings)
        } catch {
            return .refused(error.message)
        }
        let current = LibraryRestorePlanner.plan(backup: backup, library: library, choice: plan.choice, overrides: plan.overrides)
        guard current == plan else { return .changed(current) }
        if let refusal = plan.refusal { return .refused(refusal.message) }
        guard plan.canRestore else { return .refused(LibraryRestoreText.nothingToRestore) }
        let changed = plan.changedFolders
        var moved: [(folder: LibraryFolders.Folder, hadLive: Bool, swapped: Bool)] = []
        do {
            removeWorkFolders()
            try stage(changed, backup: backup, plan: plan)
            let entries = changed.map { (folder: LibraryFolders.Folder) -> Journal.FolderEntry in
                Journal.FolderEntry(name: folder.rawValue, hadLive: exists(folders.url(folder)))
            }
            try writeJournal(Journal(phase: .prepared, folders: entries, settings: [:]))
            for entry in entries {
                guard let folder = LibraryFolders.Folder(rawValue: entry.name) else { throw InstallFailure() }
                moved.append((folder, entry.hadLive, false))
                if entry.hadLive {
                    try perform(.createDirectory, previousRoot) { (url: URL) in
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    }
                    try perform(.move, folders.url(folder)) { (url: URL) in
                        try FileManager.default.moveItem(at: url, to: self.previousRoot.appendingPathComponent(entry.name, isDirectory: true))
                    }
                }
                try perform(.move, stagingRoot.appendingPathComponent(entry.name, isDirectory: true)) { (url: URL) in
                    try FileManager.default.moveItem(at: url, to: self.folders.url(folder))
                }
                moved[moved.count - 1].swapped = true
            }
            try writeJournal(Journal(phase: .committed, folders: entries, settings: plan.settingsToApply))
        } catch {
            rollBack(moved)
            removeWorkFolders()
            try? FileManager.default.removeItem(at: journalFile)
            removeRestoreFolderIfEmpty()
            return .refused(LibraryRestoreText.failed)
        }
        applySettings(plan.settingsToApply)
        finishCleanup()
        return .restored(LibraryRestoreSummary(plan: plan))
    }

    // MARK: - Recovery

    /// Rolls an interrupted restore back ("prepared") or forward ("committed"). True when there was one.
    @discardableResult
    public func recover(applySettings: ([String: LibrarySettingValue]) -> Void) -> Bool {
        guard let data = try? Data(contentsOf: journalFile) else {
            if exists(stagingRoot) || exists(previousRoot) { removeWorkFolders() }
            return false
        }
        guard let journal = try? JSONDecoder().decode(Journal.self, from: data) else {
            // An unreadable journal cannot say what moved; keep the library as it is, keep previous folders.
            try? FileManager.default.removeItem(at: stagingRoot)
            try? FileManager.default.removeItem(at: journalFile)
            return true
        }
        switch journal.phase {
        case .prepared:
            for entry in journal.folders {
                guard let folder = LibraryFolders.Folder(rawValue: entry.name) else { continue }
                let live = folders.url(folder)
                let previous = previousRoot.appendingPathComponent(entry.name, isDirectory: true)
                let staged = stagingRoot.appendingPathComponent(entry.name, isDirectory: true)
                if exists(previous) {
                    try? FileManager.default.removeItem(at: live)
                    try? FileManager.default.moveItem(at: previous, to: live)
                } else if !entry.hadLive && !exists(staged) {
                    try? FileManager.default.removeItem(at: live)   // the staged folder had moved in
                }
            }
            removeWorkFolders()
            try? FileManager.default.removeItem(at: journalFile)
            removeRestoreFolderIfEmpty()
        case .committed:
            applySettings(journal.settings)
            finishCleanup()
        }
        return true
    }

    // MARK: - Staging

    private func stage(_ changed: [LibraryFolders.Folder], backup: LibraryContents, plan: LibraryRestorePlan) throws {
        let staged = folders.moved(to: stagingRoot)
        try perform(.createDirectory, stagingRoot) { (url: URL) in try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        for folder in changed {
            let live = folders.url(folder)
            if exists(live) {
                try perform(.copy, staged.url(folder)) { (url: URL) in try FileManager.default.copyItem(at: live, to: url) }
            } else {
                try perform(.createDirectory, staged.url(folder)) { (url: URL) in
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                }
            }
            switch folder {
            case .show: try stageShow(staged, backup: backup, plan: plan)
            case .currentScene:
                if let scene = plan.currentScene { try write(scene, to: staged.currentSceneFile) }
            case .presets: try stagePresets(staged, plan: plan)
            case .collections:
                if let list = plan.collections { try write(try PresetCollectionsFile(collections: list).encode(), to: staged.collectionsFile) }
            case .photos:
                for name in plan.photosToWrite.keys.sorted() {
                    guard let bytes = plan.photosToWrite[name] else { continue }
                    try write(bytes, to: staged.url(.photos).appendingPathComponent(name, isDirectory: false))
                }
            }
        }
    }

    private func stageShow(_ staged: LibraryFolders, backup: LibraryContents, plan: LibraryRestorePlan) throws {
        let store = ShowStore(directory: staged.url(.show))
        switch plan.showMode {
        case .none: return
        case .exact:
            for id in backup.scenes.keys.sorted() {
                guard let bytes = backup.scenes[id] else { continue }
                try write(bytes, to: store.sceneFile(id))
            }
            if let show = backup.show { try write(show, to: store.showFile) }
        case .merge:
            let documents = LibraryRestorePlanner.sceneDocuments(backup)
            var overrides: [String: ShowSceneImportChoice] = [:]
            for (key, value) in plan.overrides where key.hasPrefix("scene/") { overrides[String(key.dropFirst(6))] = value.sceneChoice }
            let scenePlan = store.planSceneImport(documents, defaultChoice: plan.choice.sceneChoice, overrides: overrides)
            try perform(.write, store.showFile) { (_: URL) in }
            guard case .installed = store.installImportedScenes(documents, plan: scenePlan) else { throw InstallFailure() }
        }
    }

    private func stagePresets(_ staged: LibraryFolders, plan: LibraryRestorePlan) throws {
        var records: [UserPreset] = []
        if let data = try? Data(contentsOf: staged.presetIndexFile) { records = try UserPresetsFile.decode(data).file.presets }
        var removable: [String] = []
        for replacement in plan.presetsToReplace {
            guard let index = records.firstIndex(where: { (r: UserPreset) -> Bool in r.id == replacement.record.id }) else { throw InstallFailure() }
            removable.append(records[index].fileName)
            records[index] = replacement.record
        }
        records += plan.presetsToAdd.map { (preset: LibraryPreset) -> UserPreset in preset.record }
        for preset in plan.presetsToAdd + plan.presetsToReplace {
            try write(preset.text, to: staged.presetTextsFolder.appendingPathComponent(preset.record.fileName, isDirectory: false))
        }
        let stillUsed = Set(records.map { (r: UserPreset) -> String in r.fileName })
        for name in removable where !stillUsed.contains(name) {
            let url = staged.presetTextsFolder.appendingPathComponent(name, isDirectory: false)
            if exists(url) { try perform(.remove, url) { (target: URL) in try FileManager.default.removeItem(at: target) } }
        }
        let index = UserPresetsFile(presets: records)
        let encoded = try index.encode()
        _ = try UserPresetsFile.decode(encoded)   // the index the store will read must be valid
        try write(encoded, to: staged.presetIndexFile)
    }

    // MARK: - File operations

    private func write(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        if !exists(folder) {
            try perform(.createDirectory, folder) { (target: URL) in try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
        }
        try perform(.write, url) { (target: URL) in try data.write(to: target, options: .atomic) }
    }

    private func writeJournal(_ journal: Journal) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try write(try encoder.encode(journal), to: journalFile)
    }

    private func perform(_ operation: FileOperation, _ url: URL, _ body: (URL) throws -> Void) throws {
        try fault?(operation, url)
        observer?(operation, url)
        try body(url)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func rollBack(_ moved: [(folder: LibraryFolders.Folder, hadLive: Bool, swapped: Bool)]) {
        for item in moved.reversed() {
            let live = folders.url(item.folder)
            let previous = previousRoot.appendingPathComponent(item.folder.rawValue, isDirectory: true)
            if item.swapped { try? FileManager.default.removeItem(at: live) }
            if item.hadLive && exists(previous) && !exists(live) { try? FileManager.default.moveItem(at: previous, to: live) }
        }
    }

    /// The work folder exists only while it holds something (a request, a result, a journal).
    private func removeRestoreFolderIfEmpty() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folders.restore.path)) ?? ["?"]
        if names.isEmpty { try? FileManager.default.removeItem(at: folders.restore) }
    }

    private func removeWorkFolders() {
        try? FileManager.default.removeItem(at: stagingRoot)
        try? FileManager.default.removeItem(at: previousRoot)
    }

    /// After the commit: the previous folders and the journal go; failures are completed by `recover`.
    private func finishCleanup() {
        do {
            if exists(previousRoot) { try perform(.remove, previousRoot) { (url: URL) in try FileManager.default.removeItem(at: url) } }
            if exists(stagingRoot) { try perform(.remove, stagingRoot) { (url: URL) in try FileManager.default.removeItem(at: url) } }
            try perform(.remove, journalFile) { (url: URL) in try FileManager.default.removeItem(at: url) }
            removeRestoreFolderIfEmpty()
        } catch {
            return   // the committed journal stays; the next launch finishes the clean-up
        }
    }
}
