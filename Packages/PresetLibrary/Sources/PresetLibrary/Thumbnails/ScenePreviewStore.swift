// ScenePreviewStore.swift — roadmap SCN-006: the scene browser's preview pictures (specs/153-scn-006-
// scene-preview; research SCN-006-D1, D2; contract P1). The app captures a still of the live output
// (REC-001's frame grab) and hands it here as PNG bytes; this store keeps it under a key made of the
// scene ID and the SHA-256 of the scene file's bytes, so any change to the file names a different
// picture and the old one is removed.
//
// It reuses PRE-001/PRE-002's `PresetThumbnailIndex` unchanged: the versioned `index.json`, its
// open-time repair, stale selection (`staleIDs`, `unlistedIDs`) and file removal (`removeEntries`). In
// the index an entry's `presetID` holds the scene ID and `rendererVersion` the preview format version.
// PRE-001's cache and its render queue are not involved (scenes push pictures; presets pull renders).
//
// Foundation only, so it builds and is tested on Linux.
import Foundation
import LocalPortability

/// Names one scene preview: the scene, the exact bytes of its file, and the picture format.
public struct ScenePreviewKey: Sendable, Hashable {
    public let sceneID: String
    public let contentHash: String
    public let formatVersion: Int

    public init(sceneID: String, contentHash: String, formatVersion: Int = ScenePreviewStore.formatVersion) {
        self.sceneID = sceneID
        self.contentHash = contentHash
        self.formatVersion = formatVersion
    }

    /// SHA-256 hex (lowercase) of a scene file's bytes.
    public static func contentHash(of data: Data) -> String { PortableSHA256.hex(data) }

    /// The first 32 hex digits of SHA-256 over "scene\n<sceneID>\n<contentHash>\n<formatVersion>".
    public var stableID: String {
        let text: String = "scene\n" + sceneID + "\n" + contentHash + "\n" + String(formatVersion)
        return String(PortableSHA256.hex(Data(text.utf8)).prefix(32))
    }

    public var fileName: String { stableID + "." + PresetThumbnailIndex.fileExtension }
}

public enum ScenePreviewError: Error, Sendable, Equatable {
    /// The picture could not be written (disk full, folder not writable).
    case writeFailed
}

public actor ScenePreviewStore {
    /// `Library/Caches/<folderName>` in the app (FILE-009's "Caches" category, FILE-010's Clear Caches).
    public static let folderName = "ScenePreviews"
    /// Bumped when the picture's size or crop changes; opening drops entries of any other version.
    public static let formatVersion = 1
    /// 16:9, three times the rows' 64 × 36 pt tile.
    public static let width = 192
    public static let height = 108

    public nonisolated let directory: URL
    private var index = PresetThumbnailIndex(rendererVersion: ScenePreviewStore.formatVersion)
    private var opened = false
    private var repair: PresetThumbnailIndex.Repair = .none

    public init(directory: URL) {
        self.directory = directory
    }

    /// Reads and repairs the index (PRE-001-R8); later calls do nothing. Never fails.
    public func open() {
        guard !opened else { return }
        opened = true
        let result = PresetThumbnailIndex.openRepairing(directory: directory, rendererVersion: Self.formatVersion)
        index = result.index
        repair = result.repair
    }

    /// What opening repaired (opens first).
    public var lastRepair: PresetThumbnailIndex.Repair {
        open()
        return repair
    }

    public var entryCount: Int {
        open()
        return index.entries.count
    }

    /// The scene's entries (normally at most one), as stored.
    public func entries(forScene sceneID: String) -> [PresetThumbnailIndex.Entry] {
        open()
        return index.entries.values.filter { (entry: PresetThumbnailIndex.Entry) -> Bool in entry.presetID == sceneID }
    }

    /// The picture's file when its entry exists and the file is on disk; an entry whose file has gone
    /// (Clear Caches) is dropped.
    public func cachedURL(for key: ScenePreviewKey) -> URL? {
        open()
        let id: String = key.stableID
        guard let entry = index.entries[id] else { return nil }
        let url: URL = directory.appendingPathComponent(entry.file)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        index.entries[id] = nil
        return nil
    }

    public func hasPreview(for key: ScenePreviewKey) -> Bool { cachedURL(for: key) != nil }

    /// Stores `png` as the scene's preview for this key: writes the file, records the entry and
    /// removes the scene's entries for any other content hash. Returns the file.
    @discardableResult
    public func store(_ png: Data, for key: ScenePreviewKey) throws(ScenePreviewError) -> URL {
        open()
        let url: URL = directory.appendingPathComponent(key.fileName)
        do {
            try prepareDirectory()
            try png.write(to: url, options: .atomic)
        } catch {
            throw .writeFailed
        }
        _ = index.removeEntries(index.staleIDs(presetID: key.sceneID, keepingContentHash: key.contentHash), in: directory)
        index.entries[key.stableID] = PresetThumbnailIndex.Entry(presetID: key.sceneID, contentHash: key.contentHash,
                                                                 rendererVersion: key.formatVersion, file: key.fileName,
                                                                 width: Self.width, height: Self.height)
        index.save(in: directory)   // a failed index write leaves a file the next open removes
        return url
    }

    /// Removes every entry of `sceneID` whose content hash is not `keepingContentHash` (all of them
    /// when nil) with its file. Other scenes are not touched; the index is saved only when an entry
    /// was removed. Returns the number removed.
    @discardableResult
    public func invalidate(sceneID: String, keepingContentHash: String?) -> Int {
        open()
        let removed: Int = index.removeEntries(index.staleIDs(presetID: sceneID, keepingContentHash: keepingContentHash), in: directory)
        if removed > 0 { index.save(in: directory) }
        return removed
    }

    /// Launch and cue-removal collection: removes entries whose scene is not in `listing` (scene ID →
    /// current content hash) or is listed with another hash. Returns the number removed.
    @discardableResult
    public func retainOnly(_ listing: [String: String]) -> Int {
        open()
        let removed: Int = index.removeEntries(index.unlistedIDs(listing), in: directory)
        if removed > 0 { index.save(in: directory) }
        return removed
    }

    /// Creates the folder (again, after Clear Caches) and keeps it out of backups.
    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if canImport(Darwin)
        var marked: URL = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? marked.setResourceValues(values)
        #endif
    }
}
