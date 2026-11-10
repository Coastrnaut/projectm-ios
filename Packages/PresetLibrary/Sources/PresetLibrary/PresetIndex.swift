// PresetIndex.swift — the records written by scripts/build_preset_index.py (feature 002 data-model.md,
// contracts/preset-index.schema.json).
import Foundation

/// One unique preset.
public struct IndexedPreset: Sendable, Hashable, Identifiable, Codable {
    /// `<source>/<path in source>`; Included ids are unchanged from release 1.0 (FR-104).
    public let id: String
    public let name: String
    public let author: String
    /// `included` or a pack id.
    public let source: String
    /// Path inside the source, without the file name.
    public let folder: [String]
    /// Included: bundle-relative file path. Packs: the archive key (equal to `id`).
    public let path: String
    public let hash: String

    public var isIncluded: Bool { source == PresetLibrary.includedSource }

    public init(id: String, name: String, author: String, source: String, folder: [String], path: String, hash: String) {
        self.id = id; self.name = name; self.author = author; self.source = source
        self.folder = folder; self.path = path; self.hash = hash
    }
}

/// One source of presets (Included, a pack, or the texture pack).
public struct PresetPackInfo: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let sourceURL: String
    public let commit: String
    public let license: String
    public let presetCount: Int
    public let authors: [String]
    public let locked: Bool
}

struct IndexFile: Decodable {
    let version: Int
    let presets: [IndexedPreset]
}

struct PacksFile: Decodable {
    let version: Int
    let packs: [PresetPackInfo]
}

public enum PresetLibraryError: Error, Equatable {
    case unsupportedVersion(Int)
    case missingResource(String)
}
