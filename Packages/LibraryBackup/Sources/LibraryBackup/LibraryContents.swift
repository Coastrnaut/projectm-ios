// LibraryContents.swift — FILE-005 (data-model "LibraryContents"; research FILE-005-D7): the logical
// library a backup holds, and the reader that builds it from the folders on disk.
//
// * Scenes, the show and the current scene are kept as canonical SCN-001 / show bytes (decoded, SCN-013
//   migrated, encoded again), so comparing them compares records, not files.
// * Presets: every record of `index.json` except copies of full-library presets (ADR-0008) and
//   quarantined ones; each with its text (checked against its SHA-256) and its check state reset to
//   "waiting" (a file never vouches for a text, FILE-005-R11). The left-out records are kept in
//   `otherPresets` for planning only (identifiers, names and texts already taken); they are never written.
// * Photos: `<UUID>.png|jpg` files only.
// * Settings: only `LibrarySettingsPolicy.includedKeys`.
// Reads only.
import Foundation
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage

public struct LibraryPreset: Sendable, Hashable {
    /// State `pending`, not proven, no quarantine reason.
    public var record: UserPreset
    public var text: Data

    public init(record: UserPreset, text: Data) {
        var record = record
        record.state = .pending
        record.provenOnScreen = false
        record.quarantine = nil
        self.record = record
        self.text = text
    }
}

/// What a backup leaves out, counted (the summary and the manifest say so).
public struct LibraryExclusions: Codable, Sendable, Hashable {
    public var fullLibraryCopies: Int
    public var quarantinedPresets: Int
    /// Records whose text is missing or does not match (unusable on this device too).
    public var unavailablePresets: Int
    /// Stored scenes that could not be read.
    public var unreadableScenes: Int
    public var videos: Int
    public var importedAudio: Int

    public init(fullLibraryCopies: Int = 0, quarantinedPresets: Int = 0, unavailablePresets: Int = 0, unreadableScenes: Int = 0,
                videos: Int = 0, importedAudio: Int = 0) {
        self.fullLibraryCopies = fullLibraryCopies
        self.quarantinedPresets = quarantinedPresets
        self.unavailablePresets = unavailablePresets
        self.unreadableScenes = unreadableScenes
        self.videos = videos
        self.importedAudio = importedAudio
    }
}

public struct LibraryContents: Sendable, Equatable {
    /// Canonical `ShowCueList` bytes; nil when there is no show file.
    public var show: Data?
    /// Scene ID → canonical SCN-001 bytes.
    public var scenes: [String: Data]
    /// Canonical SCN-001 bytes of the current scene.
    public var currentScene: Data?
    /// In index order.
    public var presets: [LibraryPreset]
    /// Nil when there is no collections file.
    public var collections: [PresetCollection]?
    public var settings: [String: LibrarySettingValue]
    /// File name → bytes.
    public var photos: [String: Data]
    public var excluded: LibraryExclusions
    /// Planning only: records of the device's index that are not in `presets` (never backed up).
    public var otherPresets: [UserPreset]

    public init(show: Data? = nil, scenes: [String: Data] = [:], currentScene: Data? = nil, presets: [LibraryPreset] = [],
                collections: [PresetCollection]? = nil, settings: [String: LibrarySettingValue] = [:], photos: [String: Data] = [:],
                excluded: LibraryExclusions = LibraryExclusions(), otherPresets: [UserPreset] = []) {
        self.show = show
        self.scenes = scenes
        self.currentScene = currentScene
        self.presets = presets
        self.collections = collections
        self.settings = settings
        self.photos = photos
        self.excluded = excluded
        self.otherPresets = otherPresets
    }

    public static let empty = LibraryContents()

    /// Cues in the show (0 without one).
    public var cueCount: Int {
        guard let show, let list = try? ShowCueList.decode(show).list else { return 0 }
        return list.cues.count
    }

    /// No cues and no stored scenes: the backup's show is written exactly (spec Clarifications).
    public var showIsEmpty: Bool { scenes.isEmpty && cueCount == 0 }

    public var counts: LibraryBackupCounts {
        LibraryBackupCounts(scenes: scenes.count, cues: cueCount, currentScene: currentScene == nil ? 0 : 1, presets: presets.count,
                            collections: collections?.count ?? 0, favorites: favoriteCount, settings: settings.count, photos: photos.count)
    }

    var favoriteCount: Int {
        if case let .strings(ids)? = settings[LibrarySettingsPolicy.favoritesKey] { return ids.count }
        return 0
    }
}

public struct LibraryBackupCounts: Codable, Sendable, Hashable {
    public var scenes: Int
    public var cues: Int
    public var currentScene: Int
    public var presets: Int
    public var collections: Int
    public var favorites: Int
    public var settings: Int
    public var photos: Int

    public init(scenes: Int, cues: Int, currentScene: Int, presets: Int, collections: Int, favorites: Int, settings: Int, photos: Int) {
        self.scenes = scenes
        self.cues = cues
        self.currentScene = currentScene
        self.presets = presets
        self.collections = collections
        self.favorites = favorites
        self.settings = settings
        self.photos = photos
    }
}

/// Why the library could not be read for a backup or a restore plan (nothing was written).
public enum LibraryReadError: Error, Sendable, Hashable {
    case showUnreadable
    case presetsUnreadable
    case presetsNewerVersion
    case collectionsUnreadable
    case collectionsNewerVersion
    case tooManyPhotos(limit: Int)

    public var message: String {
        switch self {
        case .showUnreadable: "The show could not be read."
        case .presetsUnreadable: "My Presets could not be read."
        case .presetsNewerVersion, .collectionsNewerVersion: "Your library was saved by a newer version of the app. Update the app."
        case .collectionsUnreadable: "Your collections could not be read."
        case let .tooManyPhotos(limit): "A backup holds at most \(limit) photos."
        }
    }
}

public enum LibraryContentsReader {
    /// Reads the library under `folders`. `settings` is the app's current values (filtered here);
    /// `videos` and `importedAudio` are counted for the summary only.
    public static func read(folders: LibraryFolders, settings: [String: LibrarySettingValue], videos: Int = 0,
                            importedAudio: Int = 0) throws(LibraryReadError) -> LibraryContents {
        var contents = LibraryContents()
        contents.settings = LibrarySettingsPolicy.filtered(settings)
        contents.excluded.videos = videos
        contents.excluded.importedAudio = importedAudio
        try readShow(folders, into: &contents)
        contents.currentScene = canonicalScene(at: folders.currentSceneFile)
        try readPresets(folders, into: &contents)
        try readCollections(folders, into: &contents)
        contents.photos = try readPhotos(folders.url(.photos))
        return contents
    }

    /// Canonical bytes of the scene stored at `url`, or nil when it is missing or unreadable.
    static func canonicalScene(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url),
              let result = try? SceneDocument.decode([UInt8](data), migrator: .standard) else { return nil }
        return Data(result.document.encoded())
    }

    private static func readShow(_ folders: LibraryFolders, into contents: inout LibraryContents) throws(LibraryReadError) {
        let store = ShowStore(directory: folders.url(.show))
        if let data = try? Data(contentsOf: store.showFile) {
            guard let list = try? ShowCueList.decode(data).list else { throw .showUnreadable }
            contents.show = list.encoded()
        }
        for id in store.storedSceneIDs().sorted() {
            if let document = try? store.scene(id).document {
                contents.scenes[id] = Data(document.encoded())
            } else {
                contents.excluded.unreadableScenes += 1
            }
        }
    }

    private static func readPresets(_ folders: LibraryFolders, into contents: inout LibraryContents) throws(LibraryReadError) {
        guard let data = try? Data(contentsOf: folders.presetIndexFile) else { return }
        let file: UserPresetsFile
        do {
            file = try UserPresetsFile.decode(data).file
        } catch UserPresetsFile.ReadError.newerVersion {
            throw .presetsNewerVersion
        } catch {
            throw .presetsUnreadable
        }
        for record in file.presets {
            if UserPresetExportPlan.exclusion(of: record, held: false) == .fullLibraryCopy {
                contents.excluded.fullLibraryCopies += 1
                contents.otherPresets.append(record)
                continue
            }
            if record.state == .quarantined {
                contents.excluded.quarantinedPresets += 1
                contents.otherPresets.append(record)
                continue
            }
            let url = folders.presetTextsFolder.appendingPathComponent(record.fileName, isDirectory: false)
            guard let text = try? Data(contentsOf: url), text.count == record.byteCount,
                  ContentHash.sha256Hex([UInt8](text)) == record.sha256 else {
                contents.excluded.unavailablePresets += 1
                contents.otherPresets.append(record)
                continue
            }
            contents.presets.append(LibraryPreset(record: record, text: text))
        }
    }

    private static func readCollections(_ folders: LibraryFolders, into contents: inout LibraryContents) throws(LibraryReadError) {
        guard let data = try? Data(contentsOf: folders.collectionsFile) else { return }
        do {
            contents.collections = try PresetCollectionsFile.decode(data).file.collections
        } catch PresetCollectionsFile.ReadError.newerVersion {
            throw .collectionsNewerVersion
        } catch {
            throw .collectionsUnreadable
        }
    }

    private static func readPhotos(_ folder: URL) throws(LibraryReadError) -> [String: Data] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter(LibraryBackupFormat.isPhotoName).sorted()
        guard names.count <= LibraryBackupFormat.maxPhotos else { throw .tooManyPhotos(limit: LibraryBackupFormat.maxPhotos) }
        var photos: [String: Data] = [:]
        for name in names {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name, isDirectory: false)) { photos[name] = data }
        }
        return photos
    }
}
