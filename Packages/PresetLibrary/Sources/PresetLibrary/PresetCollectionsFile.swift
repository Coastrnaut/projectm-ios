// PresetCollectionsFile.swift — the saved collections document: a version field, the collections in
// the user's order, and the migration path (PRE-007-R15; contracts/preset-collections.md).
//
// Reading decides by the version alone before the body is interpreted:
//   current  → decoded and validated;
//   newer    → `ReadError.newerVersion`: nothing is interpreted, so nothing can be lost by a re-save;
//   older    → one pure `Data → Data` step per version until the current one;
//   no version field → treated as version 0 (only a migration step can read it).
// Everything else is `ReadError.unreadable`; the store sets such a file aside.
import Foundation

public struct PresetCollectionsFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    /// Converts a document of one version into the next. Pure: no I/O.
    public typealias Migration = @Sendable (Data) throws -> Data

    /// The production steps, keyed by the version they read. Version 1 is the first format, so
    /// there are none yet; a format change adds a step here and a golden fixture in the tests.
    public static let migrations: [Int: Migration] = [:]

    public enum ReadError: Error, Equatable, Sendable {
        case newerVersion(Int)
        case unreadable
    }

    public var schemaVersion: Int
    public var collections: [PresetCollection]

    public init(schemaVersion: Int = PresetCollectionsFile.currentVersion, collections: [PresetCollection]) {
        self.schemaVersion = schemaVersion
        self.collections = collections
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private static func version(of data: Data) -> Int {
        (try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion ?? 0
    }

    /// Reads a saved document. `migratedFrom` is the version the data had when it was older than
    /// `currentVersion` (the caller then saves the result), else nil.
    public static func decode(_ data: Data, migrations: [Int: Migration] = PresetCollectionsFile.migrations)
        throws -> (file: PresetCollectionsFile, migratedFrom: Int?) {
        guard data.count <= PresetCollectionLimits.maxFileBytes else { throw ReadError.unreadable }
        var data = data
        var version = version(of: data)
        var migratedFrom: Int?
        while version < currentVersion {
            guard let step = migrations[version], let next = try? step(data) else { throw ReadError.unreadable }
            let nextVersion = Self.version(of: next)
            guard nextVersion > version, next.count <= PresetCollectionLimits.maxFileBytes else { throw ReadError.unreadable }
            migratedFrom = migratedFrom ?? version
            data = next
            version = nextVersion
        }
        guard version == currentVersion else { throw ReadError.newerVersion(version) }
        guard var file = try? JSONDecoder().decode(PresetCollectionsFile.self, from: data) else { throw ReadError.unreadable }
        var seen: Set<String> = []
        for index in file.collections.indices {
            let id = file.collections[index].id
            guard !id.isEmpty, seen.insert(id).inserted else { throw ReadError.unreadable }
            var entries: Set<String> = []
            file.collections[index].presetIDs.removeAll { !entries.insert($0).inserted }   // keeps the first of each
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
