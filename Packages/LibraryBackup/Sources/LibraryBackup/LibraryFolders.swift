// LibraryFolders.swift — FILE-005: the library's folders under one root (Application Support in the
// app; a temporary folder in tests). The names are the stores' own (an app test checks they agree:
// ShowStore, SceneAutosaveStore, UserPresetStore, PresetCollectionStore, PhotoStore).
import Foundation

public struct LibraryFolders: Sendable, Equatable {
    /// A folder the restore may replace as a whole.
    public enum Folder: String, Sendable, Hashable, CaseIterable, Codable {
        /// `Show/`: show.json and Scenes/ (SHOW-001).
        case show = "Show"
        /// `Scenes/`: current.scene (SCN-002 autosave).
        case currentScene = "Scenes"
        /// `UserPresets/`: index.json, files/ (PRE-012).
        case presets = "UserPresets"
        /// `PresetCollections/`: collections.json (PRE-007).
        case collections = "PresetCollections"
        /// `Photos/`: <UUID>.png|jpg (MED-001).
        case photos = "Photos"
    }

    /// The restore's own work folder (request, staging, previous folders, journal, last result).
    public static let restoreFolderName = "LibraryRestore"
    public static let currentSceneFileName = "current.scene"
    public static let presetIndexFileName = "index.json"
    public static let presetTextsFolderName = "files"
    public static let collectionsFileName = "collections.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(_ folder: Folder) -> URL { root.appendingPathComponent(folder.rawValue, isDirectory: true) }

    public var restore: URL { root.appendingPathComponent(Self.restoreFolderName, isDirectory: true) }

    public var currentSceneFile: URL { url(.currentScene).appendingPathComponent(Self.currentSceneFileName, isDirectory: false) }
    public var presetIndexFile: URL { url(.presets).appendingPathComponent(Self.presetIndexFileName, isDirectory: false) }
    public var presetTextsFolder: URL { url(.presets).appendingPathComponent(Self.presetTextsFolderName, isDirectory: true) }
    public var collectionsFile: URL { url(.collections).appendingPathComponent(Self.collectionsFileName, isDirectory: false) }

    /// Every folder the backup reads or the restore may replace (FILE-003 snapshots use these).
    public var libraryRoots: [URL] { Folder.allCases.map { (folder: Folder) -> URL in url(folder) } }

    /// The same layout under another root (the restore's staging area).
    public func moved(to root: URL) -> LibraryFolders { LibraryFolders(root: root) }
}
