// UserPresetArchive.swift — the user preset archive, format `org.projectmios.user-presets`
// version 1 (roadmap PRE-014, specs/012-pre-014-bulk-preset-export; PRE-014-R7-R14;
// contracts/preset-archive.md §4, contracts/preset-archive-manifest-v1.schema.json).
//
// The container is LocalPortability's stored ZIP with a checksummed manifest. This file adds the
// preset part of the manifest, the writer and the validating reader that PRE-013 (bulk import)
// will reuse:
//   * texts at `presets/<uuid>.milk`, the path built from the stable id alone;
//   * per preset the portable part of the record: never the check state on this device, the
//     store's file names, or anything about the purchase;
//   * the reader refuses the whole archive on the first problem (spec Clarifications), including
//     a copy of a preset from the full library (ADR-0008) and a claim that rights were verified.
import Foundation
import LocalPortability

public enum UserPresetArchiveFormat {
    public static let name = "org.projectmios.user-presets"
    public static let version = 1
    public static let folder = "presets"
    /// 1,000 texts of at most 512 KiB, a manifest of at most 4 MiB (contract §2).
    public static let limits = PortableArchiveLimits(maxFiles: PresetImportLimits.maxUserPresets,
                                                     maxFileBytes: PresetImportLimits.maxFileBytes,
                                                     maxManifestBytes: PresetImportLimits.maxIndexBytes)
    /// The manifest's versioned constraints (FILE-007-R5; contract C2 of
    /// specs/068-file-007-document-schema-validator): version 1 only; 4 MiB; depth 8 (the largest
    /// valid manifest has 5: preset → license lines); strings up to 16 KiB (license lines are at most
    /// 200 characters); numbers up to 32 characters; 4,096 elements per list or object (1,000
    /// presets and files at most); no duplicate keys. Checked before any decoding.
    public static let manifestSchema = DocumentSchema(
        name: name, oldestReadableVersion: 1, currentVersion: version,
        limits: JSONLimits(maxBytes: PresetImportLimits.maxIndexBytes, maxDepth: 8, maxStringBytes: 16_384,
                           maxNumberBytes: 32, maxElements: 4_096))
    static let maxIDSuffixCharacters = 75
    static let maxAppVersionCharacters = 40

    /// `presets/<uuid>.milk` for an id `user/<uuid>` whose suffix is 1-75 of `[a-z0-9-]`; nil
    /// for any other id, which is then neither exported nor read.
    public static func path(for id: String) -> String? {
        guard id.hasPrefix(UserPreset.idPrefix) else { return nil }
        let suffix = id.dropFirst(UserPreset.idPrefix.count)
        guard !suffix.isEmpty, suffix.count <= maxIDSuffixCharacters,
              suffix.utf8.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }) else { return nil }
        return "\(folder)/\(suffix).milk"
    }
}

/// The portable part of a user preset record (data-model.md).
public struct ExportedUserPreset: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var author: String
    public var authorFromFileName: Bool
    public var originalFileName: String
    public var path: String
    public var sha256: String
    public var blobHash: String
    public var byteCount: Int
    public var origin: PresetLicenseMetadata.Origin
    public var rightsVerified: Bool
    public var licenseLines: [String]
    public var warnings: [PresetImportWarning]
    public var duplicateOf: PresetDuplicateOrigin?
    public var importedAt: Date
    public var modifiedAt: Date?

    /// Nil when the id cannot name a file in the archive.
    public init?(_ preset: UserPreset) {
        guard let path = UserPresetArchiveFormat.path(for: preset.id) else { return nil }
        id = preset.id; name = preset.name; author = preset.author
        authorFromFileName = preset.license.authorFromFileName
        originalFileName = preset.originalFileName
        self.path = path
        sha256 = preset.sha256; blobHash = preset.blobHash; byteCount = preset.byteCount
        origin = preset.license.origin; rightsVerified = preset.license.rightsVerified
        licenseLines = preset.license.linesFound
        warnings = preset.warnings
        duplicateOf = preset.duplicateOf
        importedAt = preset.importedAt
        modifiedAt = preset.modifiedAt
    }

    /// The record an importer stores before its own checks: waiting, not proven, no quarantine.
    public func userPreset(state: UserPresetState = .pending) -> UserPreset {
        UserPreset(id: id, name: name, author: author, originalFileName: originalFileName, sha256: sha256, blobHash: blobHash,
                   byteCount: byteCount, importedAt: importedAt, state: state, provenOnScreen: false, quarantine: nil, warnings: warnings,
                   license: PresetLicenseMetadata(origin: origin, rightsVerified: rightsVerified,
                                                  authorFromFileName: authorFromFileName, linesFound: licenseLines),
                   duplicateOf: duplicateOf, modifiedAt: modifiedAt)
    }

    /// ADR-0008: only copies of Included presets may leave or enter through an archive.
    var isFullLibraryCopy: Bool {
        guard let origin = duplicateOf else { return false }
        return origin.requiresLibraryUnlock || origin.packID != PresetLibrary.includedSource
    }
}

/// `manifest.json` (contracts/preset-archive-manifest-v1.schema.json).
public struct UserPresetArchiveManifest: Codable, Sendable, Equatable {
    public var format: String
    public var formatVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var files: [PortableFileRecord]
    public var presets: [ExportedUserPreset]

    public init(appVersion: String, exportedAt: Date, files: [PortableFileRecord], presets: [ExportedUserPreset]) {
        format = UserPresetArchiveFormat.name
        formatVersion = UserPresetArchiveFormat.version
        self.appVersion = String(appVersion.prefix(UserPresetArchiveFormat.maxAppVersionCharacters))
        self.exportedAt = exportedAt
        self.files = files
        self.presets = presets
    }

    /// Sorted keys, unescaped slashes, ISO 8601 dates in whole seconds: equal manifests are
    /// equal bytes (PRE-014-R11).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> UserPresetArchiveManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UserPresetArchiveManifest.self, from: data)
    }
}

/// A verified archive: the manifest and each preset's text, keyed by preset id.
public struct UserPresetArchive: Sendable, Equatable {
    public let manifest: UserPresetArchiveManifest
    /// The manifest's bytes as stored.
    public let manifestData: Data
    public let texts: [String: Data]
}

public enum UserPresetArchiveError: Error, Sendable, Equatable {
    case archive(PortableArchiveError)
    case tooManyPresets
    case invalidPreset(String)
    case duplicatePreset(String)
    case pathMismatch(String)
    case contentMismatch(String)
    case fullLibraryCopy(String)
    case rightsClaimed(String)
    case unreferencedFile(String)

    public var message: String {
        switch self {
        case .archive(let error): return error.message
        case .tooManyPresets:
            return "The archive contains more than \(PresetImportLimits.grouped(PresetImportLimits.maxUserPresets)) presets."
        case .invalidPreset(let id): return "A preset in the archive is not valid (\(id))."
        case .duplicatePreset(let id): return "The archive contains the preset \(id) more than once."
        case .pathMismatch(let id): return "The archive stores the preset \(id) under the wrong name."
        case .contentMismatch(let id): return "The text of \(id) does not match its manifest."
        case .fullLibraryCopy:
            return "The archive contains a copy of a preset from the full library, which cannot be exported or imported."
        case .rightsClaimed(let id): return "The archive claims verified rights for \(id); the app never verifies rights."
        case .unreferencedFile(let path): return "\(path) in the archive belongs to no preset."
        }
    }
}

public enum UserPresetArchiveWriter {
    public enum WriteError: Error, Equatable, Sendable {
        /// The stored text of this preset does not match its record, or its id names no file.
        case contentMismatch(String)
    }

    /// Writes `presets` (sorted by id) and then the manifest to `sink`. `contents` returns a
    /// preset's stored text; it is called once per preset, and the text must match the record's
    /// SHA-256 and size. Sink errors are passed on.
    public static func write(_ presets: [UserPreset], appVersion: String, exportedAt: Date,
                             contents: (UserPreset) throws -> Data?, sink: @escaping (Data) throws -> Void) throws {
        let date = Date(timeIntervalSince1970: exportedAt.timeIntervalSince1970.rounded(.down))
        let writer = PortableArchiveWriter(modified: date, sink: sink)
        var files: [PortableFileRecord] = []
        var exported: [ExportedUserPreset] = []
        for preset in presets.sorted(by: { $0.id < $1.id }) {
            guard let entry = ExportedUserPreset(preset), let data = try contents(preset), data.count == preset.byteCount,
                  PortableSHA256.hex(data) == preset.sha256 else { throw WriteError.contentMismatch(preset.id) }
            files.append(try writer.add(path: entry.path, data: data))
            exported.append(entry)
        }
        let manifest = UserPresetArchiveManifest(appVersion: appVersion, exportedAt: date, files: files, presets: exported)
        try writer.finish(manifest: try manifest.encoded())
    }
}

public enum UserPresetArchiveReader {
    /// The verified contents of an archive, or the first reason to refuse all of it (research D4).
    public static func read(_ data: Data) throws -> UserPresetArchive {
        let contents: PortableArchiveContents
        do {
            contents = try PortableArchive.read(data, schema: UserPresetArchiveFormat.manifestSchema, limits: UserPresetArchiveFormat.limits)
        } catch let error as PortableArchiveError {
            throw UserPresetArchiveError.archive(error)
        }
        guard let manifest = try? UserPresetArchiveManifest.decode(contents.manifest) else {
            throw UserPresetArchiveError.archive(.malformedManifest)
        }
        guard manifest.presets.count <= PresetImportLimits.maxUserPresets else { throw UserPresetArchiveError.tooManyPresets }
        guard manifest.appVersion.count <= UserPresetArchiveFormat.maxAppVersionCharacters else {
            throw UserPresetArchiveError.archive(.malformedManifest)
        }
        let records = Dictionary(contents.records.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var ids: Set<String> = []
        var hashes: Set<String> = []
        var used: Set<String> = []
        var texts: [String: Data] = [:]
        for preset in manifest.presets {
            guard let path = UserPresetArchiveFormat.path(for: preset.id) else { throw UserPresetArchiveError.invalidPreset(preset.id) }
            guard ids.insert(preset.id).inserted else { throw UserPresetArchiveError.duplicatePreset(preset.id) }
            if preset.rightsVerified { throw UserPresetArchiveError.rightsClaimed(preset.id) }
            if preset.isFullLibraryCopy { throw UserPresetArchiveError.fullLibraryCopy(preset.id) }
            guard preset.userPreset().isWellFormed else { throw UserPresetArchiveError.invalidPreset(preset.id) }
            guard preset.path == path else { throw UserPresetArchiveError.pathMismatch(preset.id) }
            guard let record = records[path], let text = contents.files[path], record.sha256 == preset.sha256,
                  record.byteCount == preset.byteCount, ContentHash.gitBlobSHA1Hex([UInt8](text)) == preset.blobHash else {
                throw UserPresetArchiveError.contentMismatch(preset.id)
            }
            guard hashes.insert(preset.sha256).inserted else { throw UserPresetArchiveError.duplicatePreset(preset.id) }
            used.insert(path)
            texts[preset.id] = text
        }
        if let unused = contents.records.first(where: { !used.contains($0.path) }) {
            throw UserPresetArchiveError.unreferencedFile(unused.path)
        }
        return UserPresetArchive(manifest: manifest, manifestData: contents.manifest, texts: texts)
    }
}
