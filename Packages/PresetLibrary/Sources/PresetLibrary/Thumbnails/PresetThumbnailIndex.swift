// PresetThumbnailIndex.swift — roadmap PRE-001: the thumbnail cache's versioned index and its
// open-time repair (research PRE-001-D4; data-model "Open-time repair"). The cache can always be
// rebuilt, so opening never fails: whatever cannot be trusted is discarded with its files.
import Foundation

public struct PresetThumbnailIndex: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var presetID: String
        public var contentHash: String
        public var rendererVersion: Int
        public var file: String
        public var width: Int
        public var height: Int

        public init(presetID: String, contentHash: String, rendererVersion: Int, file: String, width: Int, height: Int) {
            self.presetID = presetID; self.contentHash = contentHash; self.rendererVersion = rendererVersion
            self.file = file; self.width = width; self.height = height
        }
    }

    /// The schema this build reads and writes. A larger number was written by a newer app.
    public static let currentSchemaVersion = 1
    public static let fileName = "index.json"
    public static let fileExtension = "png"

    public var schemaVersion: Int
    public var rendererVersion: Int
    public var entries: [String: Entry]

    public init(rendererVersion: Int, entries: [String: Entry] = [:]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.rendererVersion = rendererVersion
        self.entries = entries
    }

    /// What opening found and repaired (tests and diagnostics).
    public enum Repair: Sendable, Equatable {
        /// The index was read and needed no repair.
        case none
        /// No index file: a fresh cache (stray thumbnail files removed).
        case missing
        /// Unreadable bytes or not this schema: everything discarded.
        case unreadable
        /// Written by a newer app: everything discarded.
        case newerSchema(Int)
        /// Entries dropped (older renderer version or missing file) and orphan files removed.
        case dropped(entries: Int, files: Int)
    }

    /// Reads `directory/index.json` and repairs it (PRE-001-R8): a missing file gives an empty
    /// index; unreadable bytes or a newer schema give an empty index and remove every thumbnail
    /// file; entries of another renderer version are dropped with their files; entries whose file
    /// is missing are dropped; thumbnail files no entry names are removed. A repaired index is
    /// saved. Never throws.
    public static func openRepairing(directory: URL, rendererVersion: Int,
                                     fileManager: FileManager = .default) -> (index: PresetThumbnailIndex, repair: Repair) {
        let indexURL = directory.appendingPathComponent(fileName)
        let empty = PresetThumbnailIndex(rendererVersion: rendererVersion)
        guard let data = try? Data(contentsOf: indexURL) else {
            removeThumbnailFiles(in: directory, keeping: [], fileManager: fileManager)
            return (empty, .missing)
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            removeThumbnailFiles(in: directory, keeping: [], fileManager: fileManager)
            empty.save(in: directory)
            return (empty, .unreadable)
        }
        if header.schemaVersion > currentSchemaVersion {
            removeThumbnailFiles(in: directory, keeping: [], fileManager: fileManager)
            empty.save(in: directory)
            return (empty, .newerSchema(header.schemaVersion))
        }
        guard header.schemaVersion == currentSchemaVersion,
              let stored = try? JSONDecoder().decode(PresetThumbnailIndex.self, from: data) else {
            removeThumbnailFiles(in: directory, keeping: [], fileManager: fileManager)
            empty.save(in: directory)
            return (empty, .unreadable)
        }
        var index = PresetThumbnailIndex(rendererVersion: rendererVersion)
        var droppedEntries = 0
        for (id, entry) in stored.entries {
            let fileExists = fileManager.fileExists(atPath: directory.appendingPathComponent(entry.file).path)
            if entry.rendererVersion == rendererVersion, fileExists, isSafeFileName(entry.file) {
                index.entries[id] = entry
            } else {
                droppedEntries += 1
            }
        }
        let kept = Set(index.entries.values.map { (entry: Entry) -> String in entry.file })
        let removedFiles = removeThumbnailFiles(in: directory, keeping: kept, fileManager: fileManager)
        if droppedEntries == 0 && removedFiles == 0 && stored.rendererVersion == rendererVersion {
            return (index, .none)
        }
        index.save(in: directory)
        return (index, .dropped(entries: droppedEntries, files: removedFiles))
    }

    /// Writes the index atomically; false when it could not be written (disk full, folder gone).
    @discardableResult
    public func save(in directory: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return false }
        do {
            try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// A file name from the index must name a file directly in the folder.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".." && name.hasSuffix("." + fileExtension)
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    /// Removes the folder's thumbnail files not in `keeping`; returns how many were removed.
    @discardableResult
    static func removeThumbnailFiles(in directory: URL, keeping: Set<String>, fileManager: FileManager) -> Int {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where name.hasSuffix("." + fileExtension) && !keeping.contains(name) {
            if (try? fileManager.removeItem(at: directory.appendingPathComponent(name))) != nil { removed += 1 }
        }
        return removed
    }
}
