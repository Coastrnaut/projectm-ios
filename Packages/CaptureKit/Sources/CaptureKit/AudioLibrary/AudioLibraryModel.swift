// AudioLibraryModel.swift — the imported-audio library's record and result types (AUD-001;
// specs/003-aud-001-import-drm-free-audio-files/data-model.md). Foundation only, all platforms.
//
// The record never holds an absolute path, the picked location or a bookmark (AUD-001-R3,
// AUD-001-R11): a track is found again by `fileName`, relative to the library's `assets` folder.
import Foundation

/// One audio file the user imported.
public struct ImportedTrack: Codable, Sendable, Hashable, Identifiable {
    public static let maxTitleLength = 200
    public static let maxOriginalFileNameLength = 255
    public static let maxStoredExtensionLength = 8
    public static let untitled = "Untitled"

    public var id: UUID
    /// The picked file's name without its extension.
    public var title: String
    /// Last path component of the picked file; never a path.
    public var originalFileName: String
    /// 64 lowercase hex digits; unique within the library.
    public var sha256: String
    /// `<sha256>.<ext>` or `<sha256>`, relative to `assets/`.
    public var fileName: String
    public var byteCount: Int64
    public var durationSeconds: Double
    public var sampleRate: Double
    public var channelCount: Int
    public var importedAt: Date

    public init(id: UUID, title: String, originalFileName: String, sha256: String, fileName: String, byteCount: Int64,
                durationSeconds: Double, sampleRate: Double, channelCount: Int, importedAt: Date) {
        self.id = id
        self.title = title
        self.originalFileName = originalFileName
        self.sha256 = sha256
        self.fileName = fileName
        self.byteCount = byteCount
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.importedAt = importedAt
    }

    /// The field rules of data-model.md. A record entry that breaks one is dropped on load: the
    /// record is untrusted input too.
    public var isValid: Bool {
        guard Self.isSHA256(sha256) else { return false }
        guard fileName == sha256 || fileName.hasPrefix(sha256 + "."),
              !fileName.contains("/"), !fileName.contains(".."),
              fileName.count <= sha256.count + 1 + Self.maxStoredExtensionLength else { return false }
        guard !title.isEmpty, title.count <= Self.maxTitleLength,
              originalFileName.count <= Self.maxOriginalFileNameLength, !originalFileName.contains("/") else { return false }
        guard byteCount >= 1, byteCount <= AudioLibraryIndex.maxTrackBytes else { return false }
        guard durationSeconds.isFinite, durationSeconds > 0, sampleRate.isFinite, sampleRate > 0 else { return false }
        return channelCount == 1 || channelCount == 2
    }

    static func isSHA256(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    /// Title rule: the name without its extension, trimmed, at most 200 characters, "Untitled" if empty.
    public static func title(fromFileName name: String) -> String {
        let base = name.split(separator: "/").last.map(String.init) ?? ""
        let stem: Substring
        if let dot = base.lastIndex(of: ".") { stem = base[..<dot] } else { stem = Substring(base) }
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitled : String(trimmed.prefix(maxTitleLength))
    }

    /// Stored-extension rule: lowercased, ASCII letters and digits only, at most 8 characters.
    public static func storedExtension(fromFileName name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        let kept = name[name.index(after: dot)...].lowercased().unicodeScalars.filter {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 122)
        }
        return String(String.UnicodeScalarView(kept.prefix(maxStoredExtensionLength)))
    }

    /// Title of a track rebuilt from its stored copy after the record was damaged (AUD-001-R14).
    public static func recoveredTitle(_ number: Int) -> String { "Recovered track \(number)" }

    public static func storedFileName(sha256: String, originalFileName: String) -> String {
        let ext = storedExtension(fromFileName: originalFileName)
        return ext.isEmpty ? sha256 : "\(sha256).\(ext)"
    }
}

/// `index.json`: the versioned record of the library (AUD-001-R12).
public struct AudioLibraryIndex: Sendable, Equatable {
    public static let currentSchemaVersion = 1
    /// The largest file a record entry may describe (the import limit, AUD-001-R4).
    public static let maxTrackBytes: Int64 = 500 * 1024 * 1024

    /// Import order, oldest first.
    public var tracks: [ImportedTrack]

    public init(tracks: [ImportedTrack] = []) {
        self.tracks = tracks
    }

    public enum Decoded: Equatable, Sendable {
        case index(AudioLibraryIndex)
        /// Written by a newer app; the payload is that version. Nothing else was read (AUD-001-R15).
        case newerFormat(Int)
    }

    private struct VersionProbe: Decodable { var schemaVersion: Int }
    private struct Lossy<Value: Decodable>: Decodable {
        var value: Value?
        init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
    }
    private struct Version1: Decodable { var tracks: [Lossy<ImportedTrack>] }
    private struct Envelope: Encodable { var schemaVersion: Int; var tracks: [ImportedTrack] }

    /// Reads a record of any known version. Throws when the data is not a record at all (damaged).
    /// Entries that do not decode or break a field rule are dropped; duplicates of a content hash
    /// or an id keep their first entry.
    public static func decode(_ data: Data) throws -> Decoded {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        guard version >= 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "schemaVersion \(version)"))
        }
        guard version <= currentSchemaVersion else { return .newerFormat(version) }
        // Migration chain (data-model.md, "Versioning"): a version below the current one is
        // upgraded here by pure functions before decoding. Version 1 is the first version.
        var hashes = Set<String>()
        var ids = Set<UUID>()
        let tracks = try decoder.decode(Version1.self, from: data).tracks.compactMap(\.value).filter {
            $0.isValid && hashes.insert($0.sha256).inserted && ids.insert($0.id).inserted
        }
        return .index(AudioLibraryIndex(tracks: tracks))
    }

    /// Canonical encoding: current version, sorted keys, ISO-8601 dates.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Envelope(schemaVersion: Self.currentSchemaVersion, tracks: tracks))
    }
}

public enum AudioLibraryState: Sendable, Equatable {
    public enum Unavailable: Sendable, Equatable {
        /// The record was written by a newer app version; nothing is touched (AUD-001-R15).
        case newerFormat
        /// The library folder cannot be created or read.
        case storage
    }
    case ready
    case unavailable(Unavailable)
}

/// Why a picked file was not imported (AUD-001-R6). Messages: CaptureUI `UIStrings.message(_:)`.
public enum AudioImportError: Error, Sendable, Equatable {
    case notAudio
    case unreadable
    case protectedContent
    case tooLarge(limitBytes: Int64)
    case unsupportedChannelCount(Int)
    case insufficientStorage
    case sourceUnavailable
    case libraryUnavailable
}

/// The result for one picked file.
public enum AudioImportOutcome: Sendable, Equatable {
    case imported(ImportedTrack)
    /// The content is already in the library; the payload is the existing track (AUD-001-R8).
    case duplicate(ImportedTrack)
    case failed(fileName: String, AudioImportError)
}

/// What the decoder reports about a file that passed inspection.
public struct AudioFileInfo: Sendable, Equatable {
    public var durationSeconds: Double
    public var sampleRate: Double
    public var channelCount: Int

    public init(durationSeconds: Double, sampleRate: Double, channelCount: Int) {
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

/// Validates an audio file that is already inside the library's own storage.
public protocol AudioFileInspecting: Sendable {
    /// Throws `.protectedContent`, `.unreadable` or `.unsupportedChannelCount`.
    func inspect(_ url: URL) async throws(AudioImportError) -> AudioFileInfo
}
