// LibraryEraser.swift — FILE-011 contracts E3-E5 (FILE-011-R4-R6; research FILE-011-D2, D3; ADR-0045):
// plans an erase and runs it all or nothing.
//
//   1. Plan (reads only): the chosen categories' folders that exist, the keys to remove, and — when
//      scenes go but photos and videos stay — the photo and video references named only by the erased
//      scenes (stored and current), minus the current photo and video.
//   2. Write `LibraryErase/erase.journal.json` (phase "prepared").
//   3. Move each folder to `LibraryErase/trash/<name>` (a rename on one volume).
//   4. Rewrite the journal as "committed" — the commit point.
//   5. Remove the keys (the app's callback), release the media references (FILE-008: a payload goes
//      with its last reference), delete `trash/`, then the journal.
// A failure in 2-4 moves every folder back and removes the journal: the library is byte for byte as
// before. A failure in 5 keeps the committed journal; `recover` (at launch, before anything reads the
// library) finishes it, and rolls a "prepared" journal back. Every file operation of 2-5 goes through
// `perform`, which a test hook can make fail. Only folder names from `LibraryErasePolicy` are touched.
import Foundation
import LocalPortability
import SceneFormat
import ShowStorage

public struct LibraryErasePlan: Sendable, Equatable, Codable {
    public var categories: [LibraryEraseCategory]
    /// Folder names under the root that exist and will be removed.
    public var folders: [String]
    public var settingKeys: [String]
    public var releasedPhotos: [String]
    public var releasedVideos: [String]

    public init(categories: [LibraryEraseCategory], folders: [String], settingKeys: [String], releasedPhotos: [String] = [],
                releasedVideos: [String] = []) {
        self.categories = categories
        self.folders = folders
        self.settingKeys = settingKeys
        self.releasedPhotos = releasedPhotos
        self.releasedVideos = releasedVideos
    }
}

public enum LibraryErasePlanner {
    /// `settings`: the app's current values (at least `LibraryErasePolicy.planningKeys`).
    public static func plan(_ chosen: Set<LibraryEraseCategory>, root: URL, settings: [String: LibrarySettingValue]) -> LibraryErasePlan {
        let categories: [LibraryEraseCategory] = chosen.sorted()
        var folders: [String] = []
        var keys: Set<String> = []
        for category in categories {
            for name in LibraryErasePolicy.folders(category)
            where FileManager.default.fileExists(atPath: root.appendingPathComponent(name, isDirectory: true).path) {
                folders.append(name)
            }
            keys.formUnion(LibraryErasePolicy.settingKeys(category))
        }
        if chosen.contains(.presets), case let .string(last)? = settings[LibrarySettingsPolicy.lastPresetKey], last.hasPrefix("user/") {
            keys.insert(LibrarySettingsPolicy.lastPresetKey)
        }
        var plan = LibraryErasePlan(categories: categories, folders: folders, settingKeys: keys.sorted())
        if chosen.contains(.scenes) && !chosen.contains(.media) {
            let named = sceneMedia(root: root)
            let currentPhoto: String? = stringValue(settings[LibrarySettingsPolicy.photoKey])
            let currentVideo: String? = stringValue(settings[LibraryErasePolicy.videoKey])
            plan.releasedPhotos = named.photos.filter { (id: String) -> Bool in !same(id, currentPhoto) }.sorted()
            plan.releasedVideos = named.videos.filter { (id: String) -> Bool in !same(id, currentVideo) }.sorted()
        }
        return plan
    }

    /// Photo and video IDs named by the stored scenes and the current scene.
    static func sceneMedia(root: URL) -> StoredMediaReferences {
        let folders = LibraryFolders(root: root)
        var references = ShowStore(directory: folders.url(.show)).referencedMediaIDs()
        if let data = try? Data(contentsOf: folders.currentSceneFile),
           let document = try? SceneDocument.decode([UInt8](data), migrator: .standard).document {
            for asset in document.assets.values {
                switch asset.kind {
                case let .photo(storeID): references.photos.insert(storeID)
                case let .video(storeID): references.videos.insert(storeID)
                default: break
                }
            }
        }
        return references
    }

    private static func stringValue(_ value: LibrarySettingValue?) -> String? {
        if case let .string(text)? = value { return text }
        return nil
    }

    private static func same(_ id: String, _ other: String?) -> Bool {
        guard let other else { return false }
        return id.uppercased() == other.uppercased()
    }
}

public enum LibraryEraseOutcome: Sendable, Equatable {
    case erased([LibraryEraseCategory])
    /// Nothing was erased.
    case failed
    /// Nothing was erased; the words say why.
    case refused(String)
}

public enum LibraryEraseText {
    public static let failed = "The erase did not finish. Nothing was erased."
    public static let unreadable = "The erase request could not be read. Nothing was erased."
    public static let interrupted = "An earlier erase did not finish."

    /// "Erased: scenes and show, photos and videos."
    public static func erased(_ categories: [LibraryEraseCategory]) -> String {
        "Erased: " + categories.sorted().map { (category: LibraryEraseCategory) -> String in category.phrase }.joined(separator: ", ") + "."
    }
}

public final class LibraryEraser {
    public enum FileOperation: String, Sendable, Equatable {
        case createDirectory, write, move, remove, release
    }

    static let journalFileName = "erase.journal.json"
    static let trashFolderName = "trash"

    struct Journal: Codable, Equatable {
        enum Phase: String, Codable { case prepared, committed }
        var schemaVersion = 1
        var phase: Phase
        var plan: LibraryErasePlan
    }

    private struct EraseFailure: Error {}

    public let root: URL
    /// Tests: may throw before an operation is performed (an injected fault).
    var fault: ((FileOperation, URL) throws -> Void)?
    /// Tests: sees every operation that is performed.
    var observer: ((FileOperation, URL) -> Void)?

    public init(root: URL) {
        self.root = root
    }

    var workFolder: URL { root.appendingPathComponent(LibraryErasePolicy.workFolderName, isDirectory: true) }
    var journalFile: URL { workFolder.appendingPathComponent(Self.journalFileName, isDirectory: false) }
    var trash: URL { workFolder.appendingPathComponent(Self.trashFolderName, isDirectory: true) }

    public var hasInterruptedErase: Bool { FileManager.default.fileExists(atPath: journalFile.path) }

    // MARK: - Run

    /// `removeSettings` runs after the commit point with the keys to remove.
    public func run(_ plan: LibraryErasePlan, removeSettings: ([String]) -> Void) -> LibraryEraseOutcome {
        if hasInterruptedErase { return .refused(LibraryEraseText.interrupted) }
        guard isSafe(plan) else { return .refused(LibraryEraseText.unreadable) }
        var moved: [String] = []
        do {
            try? FileManager.default.removeItem(at: trash)
            try writeJournal(Journal(phase: .prepared, plan: plan))
            try perform(.createDirectory, trash) { (url: URL) in try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            for name in plan.folders {
                let live = root.appendingPathComponent(name, isDirectory: true)
                guard FileManager.default.fileExists(atPath: live.path) else { continue }
                try perform(.move, live) { (url: URL) in
                    try FileManager.default.moveItem(at: url, to: self.trash.appendingPathComponent(name, isDirectory: true))
                }
                moved.append(name)
            }
            try writeJournal(Journal(phase: .committed, plan: plan))
        } catch {
            rollBack(moved)
            try? FileManager.default.removeItem(at: journalFile)
            try? FileManager.default.removeItem(at: trash)
            removeWorkFolderIfEmpty()
            return .failed
        }
        finish(plan, removeSettings: removeSettings)
        return .erased(plan.categories)
    }

    // MARK: - Recovery

    /// Rolls an interrupted erase back ("prepared") or forward ("committed"). True when there was one.
    @discardableResult
    public func recover(removeSettings: ([String]) -> Void) -> Bool {
        guard let data = try? Data(contentsOf: journalFile) else {
            if FileManager.default.fileExists(atPath: trash.path) { try? FileManager.default.removeItem(at: trash) }
            return false
        }
        guard let journal = try? JSONDecoder().decode(Journal.self, from: data), isSafe(journal.plan) else {
            // An unreadable journal cannot say whether the commit happened: roll back (nothing is lost).
            rollBack(LibraryErasePolicy.allFolders)
            try? FileManager.default.removeItem(at: trash)
            try? FileManager.default.removeItem(at: journalFile)
            removeWorkFolderIfEmpty()
            return true
        }
        switch journal.phase {
        case .prepared:
            rollBack(journal.plan.folders)
            try? FileManager.default.removeItem(at: trash)
            try? FileManager.default.removeItem(at: journalFile)
            removeWorkFolderIfEmpty()
        case .committed:
            finish(journal.plan, removeSettings: removeSettings)
        }
        return true
    }

    // MARK: - Steps

    /// After the commit: keys, media references, the trash, then the journal. A failure leaves the
    /// committed journal for `recover`.
    private func finish(_ plan: LibraryErasePlan, removeSettings: ([String]) -> Void) {
        removeSettings(plan.settingKeys)
        do {
            try release(plan.releasedPhotos, folder: LibraryFolders.Folder.photos.rawValue, extensions: LibraryErasePolicy.photoExtensions)
            try release(plan.releasedVideos, folder: LibraryErasePolicy.videosFolderName, extensions: LibraryErasePolicy.videoExtensions)
            if FileManager.default.fileExists(atPath: trash.path) {
                try perform(.remove, trash) { (url: URL) in try FileManager.default.removeItem(at: url) }
            }
            try perform(.remove, journalFile) { (url: URL) in try FileManager.default.removeItem(at: url) }
            removeWorkFolderIfEmpty()
        } catch {
            return   // the committed journal stays; the next launch finishes
        }
    }

    private func release(_ ids: [String], folder: String, extensions: [String]) throws {
        let uuids: Set<UUID> = Set(ids.compactMap { (id: String) -> UUID? in UUID(uuidString: id) })
        guard !uuids.isEmpty else { return }
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try perform(.release, directory) { (url: URL) in
            try ContentAddressedMediaFolder(directory: url, extensions: extensions).release(uuids)
        }
    }

    /// Moves trashed folders back where the live one is missing.
    private func rollBack(_ names: [String]) {
        for name in names.reversed() {
            let live = root.appendingPathComponent(name, isDirectory: true)
            let aside = trash.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: aside.path) && !FileManager.default.fileExists(atPath: live.path) {
                try? FileManager.default.moveItem(at: aside, to: live)
            }
        }
    }

    /// Only the policy's folder names (no path separators, nothing outside the root).
    private func isSafe(_ plan: LibraryErasePlan) -> Bool {
        let allowed: Set<String> = Set(LibraryErasePolicy.allFolders)
        return plan.folders.allSatisfy { (name: String) -> Bool in allowed.contains(name) }
    }

    private func writeJournal(_ journal: Journal) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(journal)
        if !FileManager.default.fileExists(atPath: workFolder.path) {
            try perform(.createDirectory, workFolder) { (url: URL) in try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        }
        try perform(.write, journalFile) { (url: URL) in try data.write(to: url, options: .atomic) }
    }

    private func perform(_ operation: FileOperation, _ url: URL, _ body: (URL) throws -> Void) throws {
        try fault?(operation, url)
        observer?(operation, url)
        try body(url)
    }

    /// The work folder exists only while it holds something (a request, a result, a journal).
    func removeWorkFolderIfEmpty() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: workFolder.path)) ?? ["?"]
        if names.isEmpty { try? FileManager.default.removeItem(at: workFolder) }
    }
}
