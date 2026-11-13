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

    public init(directory: URL) {
        self.directory = directory
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
            try Data(document.encoded()).write(to: sceneFile(document.id), options: .atomic)
        } catch {
            throw .writeFailed
        }
    }

    /// Reads and decodes a stored scene (SCN-001 decode; validation against a registry is the caller's).
    public func scene(_ sceneID: String) throws(ShowSceneReadError) -> SceneDecodeResult {
        guard ShowCueList.isSceneID(sceneID), let data = try? Data(contentsOf: sceneFile(sceneID)) else { throw .missing }
        let result: SceneDecodeResult
        do {
            result = try SceneDocument.decode([UInt8](data))
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

    // MARK: - Private

    private func removeUnreferencedScenes(keeping referenced: Set<String>) {
        for id in storedSceneIDs().subtracting(referenced) {
            try? FileManager.default.removeItem(at: sceneFile(id))
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
