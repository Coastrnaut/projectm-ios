// PresetOverridesFile.swift — PRE-016: the saved overrides document (spec PRE-016-R8; research D4;
// contract C2), modelled on PresetTagsFile (PRE-003).
//
//   { "schemaVersion": 1, "overrides": { "<preset ID>": { "fDecay": 0.95, "zoom": 1.05 } } }
//
// Reading checks the bytes against `schema` first (FILE-007: 1 MiB, depth 4, 20,000 elements per
// object, no duplicate keys, strict UTF-8; a refusal is `unreadable`), then the version: 1 is read, a
// newer one is `newerVersion` (nothing interpreted, so nothing is lost by a re-save), anything else is
// `unreadable`. The body is lenient: damaged entries are dropped and counted. Encoding is stable
// (sorted keys), so equal maps are equal bytes.
import Foundation
import LocalPortability

public enum PresetOverridesFile {
    public static let currentVersion = 1
    public static let maxFileBytes = 1_024 * 1_024

    public static let schema = DocumentSchema(
        name: "org.projectmios.preset-overrides", oldestReadableVersion: 1, currentVersion: currentVersion,
        limits: JSONLimits(maxBytes: maxFileBytes, maxDepth: 4, maxStringBytes: 4_096, maxNumberBytes: 32,
                           maxElements: PresetOverrideMap.maximumPresets))

    public enum ReadError: Error, Equatable, Sendable {
        case newerVersion(Int)
        case unreadable
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    /// One stored entry: an object of numbers, or nil for anything else.
    private struct LenientEntry: Decodable {
        let value: [String: Double]?
        init(from decoder: any Decoder) throws {
            value = try? decoder.singleValueContainer().decode([String: Double].self)
        }
    }

    private struct Body: Decodable {
        let overrides: [String: LenientEntry]
    }

    /// Reads a saved document: the repaired map and how many entries or values were dropped.
    public static func decode(_ data: Data) throws(ReadError) -> (map: PresetOverrideMap, dropped: Int) {
        guard data.count <= maxFileBytes, (try? schema.validate(data)) != nil,
              let header = try? JSONDecoder().decode(Header.self, from: data) else { throw .unreadable }
        switch schema.verdict(for: header.schemaVersion) {
        case .current: break
        case .newer: throw .newerVersion(header.schemaVersion)
        case .older, .unsupported: throw .unreadable
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            return (PresetOverrideMap(), 1)   // `overrides` missing or not an object
        }
        var stored: [String: [String: Double]?] = [:]
        for (id, entry) in body.overrides { stored[id] = entry.value }
        return PresetOverrideMap.repaired(stored)
    }

    private struct Document: Encodable {
        let schemaVersion: Int
        let overrides: [String: [String: Double]]
    }

    /// Stable output (sorted keys, unescaped slashes).
    public static func encode(_ map: PresetOverrideMap) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Document(schemaVersion: currentVersion, overrides: map.values))
    }
}
