// PresetTagsFile.swift — PRE-003: the saved tags document (research PRE-003-D4; contract C2).
//
//   { "schemaVersion": 1, "tags": { "<preset ID>": ["Calm", "Slow"], … } }
//
// Reading first checks the bytes against `schema` (FILE-007: 4 MiB, depth 4, strings ≤ 4 KiB, at most
// 20,000 elements per list or object, no duplicate keys, strict UTF-8; any refusal is `unreadable`),
// then decides by the version before the body is interpreted: 1 is read; a newer version is
// `newerVersion` (nothing interpreted, so a re-save cannot lose anything); no version or an older one
// is `unreadable` (version 1 is the first format). The body is read leniently: every entry breaking a
// rule is dropped and counted (`PresetTagMap.repaired`), and a `tags` value that is not an object
// drops everything it held as one. Encoding is stable (sorted keys), so equal maps are equal bytes.
import Foundation
import LocalPortability

public enum PresetTagsFile {
    public static let currentVersion = 1
    public static let maxFileBytes = 4 * 1_024 * 1_024

    public static let schema = DocumentSchema(
        name: "org.projectmios.preset-tags", oldestReadableVersion: 1, currentVersion: currentVersion,
        limits: JSONLimits(maxBytes: maxFileBytes, maxDepth: 4, maxStringBytes: 4_096, maxNumberBytes: 32,
                           maxElements: PresetTagMap.maximumTaggedPresets))

    public enum ReadError: Error, Equatable, Sendable {
        case newerVersion(Int)
        case unreadable
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    /// One stored value: a list of strings, or nil for anything else.
    private struct LenientList: Decodable {
        let value: [String]?
        init(from decoder: any Decoder) throws {
            value = try? decoder.singleValueContainer().decode([String].self)
        }
    }

    private struct Body: Decodable {
        let tags: [String: LenientList]
    }

    /// Reads a saved document: the repaired map and how many entries or tags were dropped.
    public static func decode(_ data: Data) throws(ReadError) -> (map: PresetTagMap, dropped: Int) {
        guard data.count <= maxFileBytes, (try? schema.validate(data)) != nil,
              let header = try? JSONDecoder().decode(Header.self, from: data) else { throw .unreadable }
        switch schema.verdict(for: header.schemaVersion) {
        case .current: break
        case .newer: throw .newerVersion(header.schemaVersion)
        case .older, .unsupported: throw .unreadable
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            return (PresetTagMap(), 1)   // `tags` missing or not an object: nothing usable
        }
        var stored: [String: [String]?] = [:]
        for (id, entry) in body.tags { stored[id] = entry.value }
        return PresetTagMap.repaired(stored)
    }

    private struct Document: Encodable {
        let schemaVersion: Int
        let tags: [String: [String]]
    }

    /// Stable output (sorted keys, unescaped slashes).
    public static func encode(_ map: PresetTagMap) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Document(schemaVersion: currentVersion, tags: map.tags))
    }
}
