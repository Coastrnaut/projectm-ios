// UserPresetsFile.swift — the saved record of the user's imported presets: a version field, the
// presets in import order, and the migration path (PRE-012-R25, R26; data-model.md;
// contracts/user-presets.schema.json). Same reading rules as PresetCollectionsFile:
//   current → decoded and checked; newer → `newerVersion`, nothing interpreted; older → one pure
//   `Data → Data` step per version; anything else → `unreadable` (the store sets the file aside).
import Foundation

public struct UserPresetsFile: Codable, Sendable, Equatable {
    /// Version 2 (PRE-015-R21): optional `duplicateOf` and `modifiedAt`, origin `bundledDuplicate`.
    public static let currentVersion = 2

    public typealias Migration = @Sendable (Data) throws -> Data

    /// Keyed by the version a step reads. Each format change adds a step here and a golden
    /// fixture in the tests (`Golden/user-presets-v<N>.json`).
    public static let migrations: [Int: Migration] = [1: migrateVersion1]

    /// 1 → 2: the new fields are optional and absent, so only the version changes. Pure.
    @Sendable static func migrateVersion1(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] as? Int == 1 else { throw ReadError.unreadable }
        object["schemaVersion"] = 2
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

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
