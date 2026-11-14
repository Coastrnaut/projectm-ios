// LibraryRecords.swift — FILE-005-R9 (research FILE-005-D2): what "exact local logical records" means.
//
// A library's records are a map from record key to the SHA-256 of the record's canonical encoding:
//   show                → canonical ShowCueList bytes (cue IDs, labels, order, position, show ID and name)
//   scene/<ID>          → canonical SCN-001 bytes (after SCN-013 migration)
//   current-scene       → canonical SCN-001 bytes
//   preset/<id>         → sorted-key JSON of the logical fields (identifier, name, author, file name,
//                          text SHA-256 and size, blob hash, licence, origin, import and edit dates,
//                          warnings) + the SHA-256 of the text bytes; never the check state
//   collections         → canonical PresetCollectionsFile bytes (order kept); absent when there are none
//   preset-tags         → canonical PresetTagsFile bytes (PRE-003); absent when there are none
//   setting/<key>       → the typed value's canonical JSON (favorites and the last preset included)
//   photo/<name>        → the file's bytes
// File dates, store-chosen file names and recovery copies are not records. Two libraries hold the same
// records exactly when their maps are equal; `differences` names the keys that differ.
import Foundation
import LocalPortability
import PresetLibrary

public struct LibraryRecords: Sendable, Equatable, CustomStringConvertible {
    public let digests: [String: String]

    public init(digests: [String: String]) {
        self.digests = digests
    }

    public init(_ contents: LibraryContents) {
        var map: [String: String] = [:]
        if let show = contents.show { map["show"] = PortableSHA256.hex(show) }
        for (id, bytes) in contents.scenes { map["scene/" + id] = PortableSHA256.hex(bytes) }
        if let current = contents.currentScene { map["current-scene"] = PortableSHA256.hex(current) }
        for preset in contents.presets { map["preset/" + preset.record.id] = Self.presetDigest(preset) }
        if let collections = contents.collections, !collections.isEmpty,
           let bytes = try? PresetCollectionsFile(collections: collections).encode() {
            map["collections"] = PortableSHA256.hex(bytes)
        }
        if let tags = contents.presetTags, !tags.isEmpty, let bytes = try? PresetTagsFile.encode(tags) {
            map["preset-tags"] = PortableSHA256.hex(bytes)
        }
        for (key, value) in contents.settings { map["setting/" + key] = PortableSHA256.hex(value.canonicalBytes) }
        for (name, bytes) in contents.photos { map["photo/" + name] = PortableSHA256.hex(bytes) }
        digests = map
    }

    /// Reads the library on disk (the same reader a backup uses, exclusions included).
    public static func read(folders: LibraryFolders, settings: [String: LibrarySettingValue]) throws(LibraryReadError) -> LibraryRecords {
        LibraryRecords(try LibraryContentsReader.read(folders: folders, settings: settings))
    }

    /// The record keys whose content differs, or that one side lacks; sorted.
    public func differences(from other: LibraryRecords) -> [String] {
        let keys = Set(digests.keys).union(other.digests.keys)
        return keys.filter { (key: String) -> Bool in digests[key] != other.digests[key] }.sorted()
    }

    /// SHA-256 of the sorted map: one value for plans and probes.
    public var digest: String {
        let lines: [String] = digests.keys.sorted().map { (key: String) -> String in key + " " + (digests[key] ?? "") }
        return PortableSHA256.hex(Array(lines.joined(separator: "\n").utf8))
    }

    public var count: Int { digests.count }

    public var description: String { "\(digests.count) records, digest \(digest.prefix(12))" }

    /// The logical fields of a preset (not `state`, `provenOnScreen`, `quarantine`).
    private struct PresetFields: Encodable {
        let id: String
        let name: String
        let author: String
        let originalFileName: String
        let sha256: String
        let blobHash: String
        let byteCount: Int
        let importedAt: Date
        let warnings: [PresetImportWarning]
        let license: PresetLicenseMetadata
        let duplicateOf: PresetDuplicateOrigin?
        let modifiedAt: Date?
        let textSHA256: String
    }

    static func presetDigest(_ preset: LibraryPreset) -> String {
        let record = preset.record
        let fields = PresetFields(id: record.id, name: record.name, author: record.author, originalFileName: record.originalFileName,
                                  sha256: record.sha256, blobHash: record.blobHash, byteCount: record.byteCount,
                                  importedAt: record.importedAt, warnings: record.warnings, license: record.license,
                                  duplicateOf: record.duplicateOf, modifiedAt: record.modifiedAt,
                                  textSHA256: PortableSHA256.hex(preset.text))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601   // as the index stores them
        let bytes = (try? encoder.encode(fields)) ?? Data()
        return PortableSHA256.hex(bytes)
    }
}
