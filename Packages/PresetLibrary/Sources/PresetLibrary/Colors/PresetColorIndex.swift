// PresetColorIndex.swift — roadmap PRE-004: the versioned colour index and its open-time repair
// (spec PRE-004-R4, R5; research PRE-004-D4; contract C2). The index can always be rebuilt from the
// thumbnails, so opening never fails: anything that is not exactly this schema and palette version
// starts empty and is rewritten in the current schema.
import Foundation

public struct PresetColorIndex: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        /// The PRE-001 thumbnail's stable ID the colours were computed from.
        public var thumbnailID: String
        public var colors: [PresetColorFamily]

        public init(thumbnailID: String, colors: [PresetColorFamily]) {
            self.thumbnailID = thumbnailID
            self.colors = colors
        }
    }

    public static let currentSchemaVersion = 1
    public static let fileName = "colors.json"

    public var schemaVersion: Int
    public var paletteVersion: Int
    /// Preset ID → its colours.
    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        schemaVersion = Self.currentSchemaVersion
        paletteVersion = PresetColorPalette.version
        self.entries = entries
    }

    public enum Repair: Sendable, Equatable {
        /// Read as is.
        case none
        /// No file: a fresh index.
        case missing
        /// Bytes that are not an index: rebuilt.
        case unreadable
        /// Another schema version (0 when absent, older or newer): rebuilt.
        case schema(Int)
        /// Another palette version: rebuilt.
        case palette(Int)
        /// Current, but entries with unknown colours or none were dropped.
        case dropped(Int)
    }

    /// Reads `directory/colors.json` (contract C2). A rebuilt or repaired index is saved. Never throws.
    public static func openRepairing(directory: URL) -> (index: PresetColorIndex, repair: Repair) {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return (PresetColorIndex(), .missing) }
        let rebuilt: (Repair) -> (index: PresetColorIndex, repair: Repair) = { (repair: Repair) in
            let empty = PresetColorIndex()
            empty.save(in: directory)
            return (empty, repair)
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return rebuilt(.unreadable) }
        let schema: Int = header.schemaVersion ?? 0
        guard schema == currentSchemaVersion else { return rebuilt(.schema(schema)) }
        let palette: Int = header.paletteVersion ?? 0
        guard palette == PresetColorPalette.version else { return rebuilt(.palette(palette)) }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return rebuilt(.unreadable) }
        var index = PresetColorIndex()
        var dropped = 0
        for (id, entry) in stored.entries {
            let families: [PresetColorFamily] = entry.colors.compactMap { (raw: String) -> PresetColorFamily? in PresetColorFamily(rawValue: raw) }
            if families.count == entry.colors.count, !families.isEmpty, !entry.thumbnailID.isEmpty {
                index.entries[id] = Entry(thumbnailID: entry.thumbnailID, colors: families)
            } else {
                dropped += 1
            }
        }
        guard dropped > 0 else { return (index, .none) }
        index.save(in: directory)
        return (index, .dropped(dropped))
    }

    /// Writes atomically, creating the folder; false when it could not be written.
    @discardableResult
    public func save(in directory: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return false }
        do {
            try PresetColorStore.prepare(directory)
            try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private struct Header: Decodable {
        let schemaVersion: Int?
        let paletteVersion: Int?
    }

    /// The current schema with colours as strings, so one unknown name drops one entry, not the file.
    private struct Stored: Decodable {
        struct StoredEntry: Decodable {
            let thumbnailID: String
            let colors: [String]
        }
        let entries: [String: StoredEntry]
    }
}
