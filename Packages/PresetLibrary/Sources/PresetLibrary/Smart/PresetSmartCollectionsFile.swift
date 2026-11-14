// PresetSmartCollectionsFile.swift — roadmap PRE-008: the saved smart collections document (spec PRE-008-R5,
// R6; research PRE-008-D1, D6; contract C2).
//
//   { "schemaVersion": 1, "smartCollections": [ { "id": "smart-…", "name": "Calm", "match": "all",
//     "conditions": [ { "kind": "tag", "values": ["Calm"] } ] } ] }
//
// The same path as PRE-007's `PresetCollectionsFile`: the bytes are checked against `schema` (FILE-007) first,
// then the version alone decides: current → decoded; newer → `newerVersion` (nothing interpreted, nothing
// rewritten); older (no version field = 0) → one pure `Data → Data` step per version; anything else →
// `unreadable`. Empty or repeated IDs are unreadable. Condition kinds are plain strings, so a newer build's
// kinds are read and written back unchanged (R4).
import Foundation
import LocalPortability

public struct PresetSmartCollectionsFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let fileName = "smart-collections.json"

    public typealias Migration = @Sendable (Data) throws -> Data

    /// The production steps, keyed by the version they read. Version 1 is the first format.
    public static let migrations: [Int: Migration] = [:]

    /// Versions 0 (migration only) to current; 1 MiB; depth 8 (a valid file has 5); strings up to 4 KiB;
    /// 4,096 elements per list or object; no duplicate keys; any top-level value (version 0 has no shape).
    public static let schema = DocumentSchema(
        name: "org.projectmios.preset-smart-collections", oldestReadableVersion: 0, currentVersion: currentVersion,
        limits: JSONLimits(maxBytes: PresetSmartLimits.maxFileBytes, maxDepth: 8, maxStringBytes: 4_096,
                           maxNumberBytes: 32, maxElements: 4_096, requiresObjectRoot: false))

    public enum ReadError: Error, Equatable, Sendable {
        case newerVersion(Int)
        case unreadable
    }

    public var schemaVersion: Int
    public var smartCollections: [PresetSmartCollection]

    public init(schemaVersion: Int = PresetSmartCollectionsFile.currentVersion, smartCollections: [PresetSmartCollection]) {
        self.schemaVersion = schemaVersion
        self.smartCollections = smartCollections
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private static func version(of data: Data) -> Int {
        (try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion ?? 0
    }

    private static func passes(_ data: Data) -> Bool {
        data.count <= PresetSmartLimits.maxFileBytes && (try? schema.validate(data)) != nil
    }

    /// Reads a saved document. `migratedFrom` is the version the data had when it was older than current.
    public static func decode(_ data: Data, migrations: [Int: Migration] = PresetSmartCollectionsFile.migrations)
        throws(ReadError) -> (file: PresetSmartCollectionsFile, migratedFrom: Int?) {
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
        guard let file = try? JSONDecoder().decode(PresetSmartCollectionsFile.self, from: data) else { throw .unreadable }
        var seen: Set<String> = []
        for collection in file.smartCollections {
            guard !collection.id.isEmpty, seen.insert(collection.id).inserted else { throw .unreadable }
        }
        return (file, migratedFrom)
    }

    /// Stable output (sorted keys), so equal documents are equal bytes.
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
