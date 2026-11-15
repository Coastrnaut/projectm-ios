// PresetNotesFile.swift — roadmap PRE-011: the saved notes document (spec PRE-011-R2; research PRE-011-D2;
// contract C1).
//
//   { "notes": { "<preset ID>": "Slow build, good for intros" }, "schemaVersion": 1 }
//
// The bytes are checked against `schema` (FILE-007) first, then the version alone decides (as PRE-008's
// smart collections file): older (no version field = 0) → one pure `Data → Data` step per version from
// `migrations`; current → read; newer → `newerVersion` (nothing interpreted, nothing rewritten); anything
// else → `unreadable`. The body is lenient like PRE-016's overrides: damaged entries are dropped and counted.
// Encoding is stable (sorted keys), so equal maps are equal bytes.
import Foundation
import LocalPortability

public enum PresetNotesFile {
    public static let currentVersion = 1
    public static let fileName = "notes.json"
    public static let maxFileBytes = 8 * 1_024 * 1_024

    public typealias Migration = @Sendable (Data) throws -> Data

    /// The production steps, keyed by the version they read. Version 1 is the first format.
    public static let migrations: [Int: Migration] = [:]

    /// Versions 0 (migration only) to current; 8 MiB; depth 3; strings up to 64 KiB (2,000 long grapheme
    /// clusters fit; analyze fix A1); 20,000 elements per object; no duplicate keys.
    public static let schema = DocumentSchema(
        name: "org.projectmios.preset-notes", oldestReadableVersion: 0, currentVersion: currentVersion,
        limits: JSONLimits(maxBytes: maxFileBytes, maxDepth: 3, maxStringBytes: 64 * 1_024, maxNumberBytes: 32,
                           maxElements: PresetNoteMap.maximumNotes, requiresObjectRoot: false))

    public enum ReadError: Error, Equatable, Sendable {
        case newerVersion(Int)
        case unreadable
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    /// One stored entry: text, or nil for anything else.
    private struct LenientEntry: Decodable {
        let value: String?
        init(from decoder: any Decoder) throws {
            value = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    private struct Body: Decodable {
        let notes: [String: LenientEntry]
    }

    private static func version(of data: Data) -> Int {
        (try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion ?? 0
    }

    private static func passes(_ data: Data) -> Bool {
        data.count <= maxFileBytes && (try? schema.validate(data)) != nil
    }

    /// Reads a saved document: the repaired map, how many entries were dropped, and the version the data had
    /// when it was older than current.
    public static func decode(_ data: Data, migrations: [Int: Migration] = PresetNotesFile.migrations)
        throws(ReadError) -> (map: PresetNoteMap, dropped: Int, migratedFrom: Int?) {
        guard passes(data) else { throw .unreadable }
        var data: Data = data
        var version: Int = version(of: data)
        var migratedFrom: Int?
        while version < currentVersion {
            guard let step = migrations[version], let next = try? step(data) else { throw .unreadable }
            let nextVersion: Int = Self.version(of: next)
            guard nextVersion > version, passes(next) else { throw .unreadable }
            migratedFrom = migratedFrom ?? version
            data = next
            version = nextVersion
        }
        guard schema.verdict(for: version) == .current else { throw .newerVersion(version) }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            return (PresetNoteMap(), 1, migratedFrom)   // `notes` missing or not an object
        }
        var stored: [String: String?] = [:]
        for (id, entry) in body.notes { stored[id] = entry.value }
        let repaired = PresetNoteMap.repaired(stored)
        return (repaired.map, repaired.dropped, migratedFrom)
    }

    private struct Document: Encodable {
        let schemaVersion: Int
        let notes: [String: String]
    }

    /// Stable output (sorted keys, unescaped slashes).
    public static func encode(_ map: PresetNoteMap) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Document(schemaVersion: currentVersion, notes: map.notes))
    }
}
