// UserPresetsFile.swift — the saved record of the user's imported presets: a version field, the
// presets in import order, and the migration path (PRE-012-R25, R26; data-model.md;
// contracts/user-presets.schema.json). Same reading rules as PresetCollectionsFile:
//   current → decoded and checked; newer → `newerVersion`, nothing interpreted; older → one pure
//   `Data → Data` step per version; anything else → `unreadable` (the store sets the file aside).
import Foundation

public struct UserPresetsFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public typealias Migration = @Sendable (Data) throws -> Data

    /// Keyed by the version a step reads. Version 1 is the first format, so there are none yet;
    /// a format change adds a step here and a golden fixture in the tests.
    public static let migrations: [Int: Migration] = [:]

    public enum ReadError: Error, Equatable, Sendable {
        case newerVersion(Int)
        case unreadable
    }

    public var schemaVersion: Int
    public var presets: [UserPreset]

    public init(schemaVersion: Int = UserPresetsFile.currentVersion, presets: [UserPreset]) {
        self.schemaVersion = schemaVersion
        self.presets = presets
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private static func version(of data: Data) -> Int {
        (try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion ?? 0
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func decode(_ data: Data, migrations: [Int: Migration] = UserPresetsFile.migrations)
        throws -> (file: UserPresetsFile, migratedFrom: Int?) {
        guard data.count <= PresetImportLimits.maxIndexBytes else { throw ReadError.unreadable }
        var data = data
        var version = version(of: data)
        var migratedFrom: Int?
        while version < currentVersion {
            guard let step = migrations[version], let next = try? step(data) else { throw ReadError.unreadable }
            let nextVersion = Self.version(of: next)
            guard nextVersion > version, next.count <= PresetImportLimits.maxIndexBytes else { throw ReadError.unreadable }
            migratedFrom = migratedFrom ?? version
            data = next
            version = nextVersion
        }
        guard version == currentVersion else { throw ReadError.newerVersion(version) }
        guard let file = try? decoder().decode(UserPresetsFile.self, from: data) else { throw ReadError.unreadable }
        var ids: Set<String> = []
        var hashes: Set<String> = []
        var quarantined = 0
        for preset in file.presets {
            guard preset.isWellFormed, ids.insert(preset.id).inserted, hashes.insert(preset.sha256).inserted else {
                throw ReadError.unreadable
            }
            if preset.state == .quarantined { quarantined += 1 }
        }
        guard quarantined <= PresetImportLimits.maxQuarantined,
              file.presets.count - quarantined <= PresetImportLimits.maxUserPresets else { throw ReadError.unreadable }
        return (file, migratedFrom)
    }

    /// Stable output (sorted keys), so equal documents are equal bytes.
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
