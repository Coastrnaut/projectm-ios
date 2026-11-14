// ShowStore.swift — the show's folder (SHOW-001-R11, R12; contract S2, S5; data-model "Stored files").
//
//   <directory>/show.json                     the show (ShowCueList.encoded())
//   <directory>/show.damaged-<n>.json         a refused show file, set aside (never deleted)
//   <directory>/Scenes/<SCENE-ID>.scene.json  canonical SCN-001 bytes; the document's id is the name
//
// Every file is written whole (`.atomic`: a temporary file renamed over the old one), scenes before
// the show that refers to them; after the show is saved, scene files no cue refers to are removed.
// A scene file that is missing, unreadable or whose document id differs from its name is reported
// per scene, never fatal for the show. No networking; nothing read is executed.
// SCN-003: Duplicate writes a copy under a new ID (never over another file) and Rename rewrites a scene
// under its own ID; scenes share stored photos and videos by store ID (`referencedMediaIDs`).
// SCN-013: scenes are migrated in memory when read (`migrator`); before `saveScene` replaces a file whose
// content is an older format version, its original bytes are kept once as
// `<SCENE-ID>.scene.json.v<N>.backup` (never overwritten; a failed backup refuses the save). Backups are
// removed only with their scene.
import Foundation
import SceneFormat
import ShowControl

public enum ShowStoreError: Error, Sendable, Hashable {
    case writeFailed
}

/// Why a cue's scene cannot be read (the cue is flagged "Scene missing").
public enum ShowSceneReadError: Error, Sendable, Hashable, CustomStringConvertible {
    case missing
    case unreadable(SceneDecodeError)
    /// The file holds a document whose id is not the file's scene ID.
    case mismatchedID(found: String)

    public var description: String {
        switch self {
        case .missing: "The scene is not stored."
        case let .unreadable(error): "The scene could not be read: \(error)"
        case let .mismatchedID(found): "The scene file holds scene \(found)."
        }
    }
}

/// Why a duplicate or rename was refused (SCN-003; nothing was written).
public enum ShowSceneEditError: Error, Sendable, Hashable, CustomStringConvertible {
    case unreadable(ShowSceneReadError)
    case invalid(SceneEditError)
    /// A scene file with the copy's ID already exists.
    case sceneIDTaken(String)
    case writeFailed

    public var description: String {
        switch self {
        case let .unreadable(error): error.description
        case let .invalid(error): error.description
        case let .sceneIDTaken(id): "A scene \(id) is already stored."
        case .writeFailed: "The scene could not be saved."
        }
    }
}

/// Stored photo and video IDs that scenes refer to (SCN-003-R9).
public struct StoredMediaReferences: Sendable, Hashable {
    public var photos: Set<String>
    public var videos: Set<String>

    public init(photos: Set<String> = [], videos: Set<String> = []) {
        self.photos = photos
        self.videos = videos
    }
}

/// What `load()` found.
public struct ShowStoreLoad: Sendable {
    public let list: ShowCueList
    public let warnings: [ShowDecodeWarning]
    /// The refused file's new name, when the stored show was set aside (the show is then empty).
    public let setAside: URL?
    /// Why the stored show was refused.
    public let refusal: ShowDecodeError?
    /// Scene IDs the cues refer to that cannot be read.
    public let unreadableScenes: Set<String>
}

public struct ShowStore: Sendable {
    public static let showFileName = "show.json"
    public static let scenesFolderName = "Scenes"
    public static let sceneFileSuffix = ".scene.json"

    public let directory: URL
    /// The scene migration chain (the app's; tests pass synthetic chains, SCN-013).
    public let migrator: SceneMigrator

    public init(directory: URL) {
        self.init(directory: directory, migrator: .standard)
    }

    public init(directory: URL, migrator: SceneMigrator) {
        self.directory = directory
        self.migrator = migrator
    }

    /// `Application Support/Show`.
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Show", isDirectory: true)
    }

    public var showFile: URL { directory.appendingPathComponent(Self.showFileName, isDirectory: false) }
    public var scenesFolder: URL { directory.appendingPathComponent(Self.scenesFolderName, isDirectory: true) }

    public func sceneFile(_ sceneID: String) -> URL {
        scenesFolder.appendingPathComponent(sceneID + Self.sceneFileSuffix, isDirectory: false)
    }

    // MARK: - Show

    /// The stored show; an empty show when there is none. A refused file is renamed aside and an
    /// empty show returned (contract S5).
    public func load() -> ShowStoreLoad {
        guard let data = try? Data(contentsOf: showFile) else {
            return ShowStoreLoad(list: ShowCueList(), warnings: [], setAside: nil, refusal: nil, unreadableScenes: [])
        }
        do {
            let result = try ShowCueList.decode(data)
            let unreadable = Set(result.list.sceneIDs.filter { (id: String) -> Bool in !sceneIsReadable(id) })
            return ShowStoreLoad(list: result.list, warnings: result.warnings, setAside: nil, refusal: nil, unreadableScenes: unreadable)
        } catch {
            let aside = setAsideShowFile()
            return ShowStoreLoad(list: ShowCueList(), warnings: [], setAside: aside, refusal: error, unreadableScenes: [])
        }
    }

    /// Writes the show whole, then removes scene files no cue refers to.
    public func save(_ list: ShowCueList) throws(ShowStoreError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try list.encoded().write(to: showFile, options: .atomic)
        } catch {
            throw .writeFailed
        }
        removeUnreferencedScenes(keeping: Set(list.sceneIDs))
    }

    // MARK: - Scenes

    /// Stores a scene under its own id (canonical bytes). Call before saving a show that refers to it.
    public func saveScene(_ document: SceneDocument) throws(ShowStoreError) {
        guard ShowCueList.isSceneID(document.id) else { throw .writeFailed }
        do {
            try FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)
            try keepOriginalIfMigrated(sceneFile(document.id))
            try Data(document.encoded()).write(to: sceneFile(document.id), options: .atomic)
        } catch {
            throw .writeFailed
        }
    }

    /// SCN-013-R8, R9: an older-version file about to be replaced keeps its original bytes once. An
    /// existing backup is never overwritten; any other failure throws (the file is not replaced).
    private func keepOriginalIfMigrated(_ file: URL) throws {
        guard let data = try? Data(contentsOf: file),
              let root = try? SceneJSON.parse([UInt8](data)),
              let record = try? migrator.migrate(root).record, record.migrated else { return }
        let backup = file.deletingLastPathComponent().appendingPathComponent(record.backupName(for: file.lastPathComponent), isDirectory: false)
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: backup.path, isDirectory: &isFolder), !isFolder.boolValue { return }   // kept, never overwritten
        try data.write(to: backup, options: .withoutOverwriting)
    }

    /// The original backups of a scene file (SCN-013).
    public func backups(of sceneID: String) -> [URL] {
        let fileName = sceneID + Self.sceneFileSuffix
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scenesFolder.path)) ?? []
        return names.filter { (name: String) -> Bool in SceneMigrationRecord.isBackup(name, of: fileName) }.sorted()
            .map { (name: String) -> URL in scenesFolder.appendingPathComponent(name, isDirectory: false) }
    }

    /// Reads and decodes a stored scene (SCN-001 decode; validation against a registry is the caller's).
    public func scene(_ sceneID: String) throws(ShowSceneReadError) -> SceneDecodeResult {
        guard ShowCueList.isSceneID(sceneID), let data = try? Data(contentsOf: sceneFile(sceneID)) else { throw .missing }
        let result: SceneDecodeResult
        do {
            result = try SceneDocument.decode([UInt8](data), migrator: migrator)
        } catch {
            throw .unreadable(error)
        }
        guard result.document.id == sceneID else { throw .mismatchedID(found: result.document.id) }
        return result
    }

    public func sceneIsReadable(_ sceneID: String) -> Bool {
        (try? scene(sceneID)) != nil
    }

    /// Scene IDs with a file in the scenes folder.
    public func storedSceneIDs() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scenesFolder.path)) ?? []
        return Set(names.compactMap { (name: String) -> String? in
            guard name.hasSuffix(Self.sceneFileSuffix) else { return nil }
            let id = String(name.dropLast(Self.sceneFileSuffix.count))
            return ShowCueList.isSceneID(id) ? id : nil
        })
    }

    // MARK: - Duplicate and rename (SCN-003; contract D3)

    /// Reads `sceneID`, stores a copy under `newID` named `name` (written whole), and returns it. The
    /// original's file is never written. Refuses an unreadable original, an invalid name or ID, and an
    /// ID that already has a file (a duplicate never replaces another scene). Call before saving the
    /// show whose new cue refers to the copy.
    @discardableResult
    public func duplicateScene(_ sceneID: String, newID: String, name: String) throws(ShowSceneEditError) -> SceneDocument {
        let original = try readForEdit(sceneID)
        let copy: SceneDocument
        do {
            copy = try original.duplicated(newID: newID, name: name)
        } catch {
            throw .invalid(error)
        }
        guard !FileManager.default.fileExists(atPath: sceneFile(newID).path) else { throw .sceneIDTaken(newID) }
        do throws(ShowStoreError) {
            try saveScene(copy)
        } catch {
            throw .writeFailed
        }
        return copy
    }

    /// Rewrites `sceneID`'s file (written whole) with the new name and returns the scene; its ID, file
    /// name and every cue that refers to it are unchanged. An invalid name leaves the file as it was.
    @discardableResult
    public func renameScene(_ sceneID: String, to name: String) throws(ShowSceneEditError) -> SceneDocument {
        let original = try readForEdit(sceneID)
        let renamed: SceneDocument
        do {
            renamed = try original.renamed(to: name)
        } catch {
            throw .invalid(error)
        }
        do throws(ShowStoreError) {
            try saveScene(renamed)
        } catch {
            throw .writeFailed
        }
        return renamed
    }

    /// Every photo and video store ID named by a readable stored scene, read from the files on each
    /// call (never a stored count, so it cannot drift). Scenes share stored media by ID (SCN-003-R9):
    /// whatever deletes stored media (FILE-011 erase) must keep the IDs listed here or accept the
    /// "no longer stored" notice on those scenes. Removing a scene file never deletes media.
    public func referencedMediaIDs() -> StoredMediaReferences {
        var references = StoredMediaReferences()
        for id in storedSceneIDs() {
            guard let document = try? scene(id).document else { continue }
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

    private func readForEdit(_ sceneID: String) throws(ShowSceneEditError) -> SceneDocument {
        do {
            return try scene(sceneID).document
        } catch {
            throw .unreadable(error)
        }
    }

    // MARK: - Private

    private func removeUnreferencedScenes(keeping referenced: Set<String>) {
        for id in storedSceneIDs().subtracting(referenced) {
            try? FileManager.default.removeItem(at: sceneFile(id))
            for backup in backups(of: id) { try? FileManager.default.removeItem(at: backup) }   // SCN-013-R15
        }
    }

    /// Renames `show.json` to the first free `show.damaged-<n>.json`.
    private func setAsideShowFile() -> URL? {
        var n = 1
        while n < 1_000 {
            let target = directory.appendingPathComponent("show.damaged-\(n).json", isDirectory: false)
            if !FileManager.default.fileExists(atPath: target.path) {
                do {
                    try FileManager.default.moveItem(at: showFile, to: target)
                    return target
                } catch {
                    return nil
                }
            }
            n += 1
        }
        return nil
    }
}
