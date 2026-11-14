// PresetMotionIndex.swift — roadmap PRE-005: the versioned motion index and its open-time repair (spec
// PRE-005-R5, R6; research PRE-005-D5; contract C4), built like PRE-004's PresetColorIndex. The index
// can always be rebuilt from the thumbnails' PNG fields, so opening never fails: anything that is not
// exactly this schema and score version starts empty and is rewritten in the current schema.
import Foundation

public struct PresetMotionIndex: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        /// The PRE-001 thumbnail's stable ID the score came from.
        public var thumbnailID: String
        /// Thousandths of a brightness level (PresetMotionScore).
        public var score: Int

        public init(thumbnailID: String, score: Int) {
            self.thumbnailID = thumbnailID
            self.score = score
        }
    }

    public static let currentSchemaVersion = 1
    public static let fileName = "motion.json"

    public var schemaVersion: Int
    public var scoreVersion: Int
    /// Preset ID → its score.
    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        schemaVersion = Self.currentSchemaVersion
        scoreVersion = PresetMotionScore.version
        self.entries = entries
    }

    public enum Repair: Sendable, Equatable {
        case none
        case missing
        case unreadable
        /// Another schema version (0 when absent, older or newer): rebuilt.
        case schema(Int)
        /// Another score version: rebuilt.
        case scoreVersion(Int)
        /// Current, but invalid entries (negative score, no thumbnail ID) were dropped.
        case dropped(Int)
    }

    /// Reads `directory/motion.json`. A rebuilt or repaired index is saved. Never throws.
    public static func openRepairing(directory: URL) -> (index: PresetMotionIndex, repair: Repair) {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return (PresetMotionIndex(), .missing) }
        let rebuilt: (Repair) -> (index: PresetMotionIndex, repair: Repair) = { (repair: Repair) in
            let empty = PresetMotionIndex()
            empty.save(in: directory)
            return (empty, repair)
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return rebuilt(.unreadable) }
        let schema: Int = header.schemaVersion ?? 0
        guard schema == currentSchemaVersion else { return rebuilt(.schema(schema)) }
        let version: Int = header.scoreVersion ?? 0
        guard version == PresetMotionScore.version else { return rebuilt(.scoreVersion(version)) }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return rebuilt(.unreadable) }
        var index = PresetMotionIndex()
        var dropped = 0
        for (id, entry) in stored.entries {
            if entry.score >= 0, !entry.thumbnailID.isEmpty {
                index.entries[id] = entry
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
            try PresetMotionStore.prepare(directory)
            try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private struct Header: Decodable {
        let schemaVersion: Int?
        let scoreVersion: Int?
    }

    private struct Stored: Decodable {
        let entries: [String: Entry]
    }
}
