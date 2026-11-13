// PortableArchive.swift — an archive whose `manifest.json` lists every other file with its
// SHA-256 and length (PRE-014-R8, R9, R12-R14; roadmap "Local formats and migration policy";
// contracts/preset-archive.md §3). The preset export is its first user; scene archives (FILE-001)
// and checksum verification (FILE-002) are meant to reuse it.
//
// The manifest's top level must carry the generic header:
//   { "format": "<reverse-DNS name>", "formatVersion": <n ≥ 1>, "files": [ {path, sha256, byteCount} ] }
// Every other key belongs to the caller and is returned untouched as the manifest bytes.
//
// Reading checks, in order: the ZIP (StoredZipReader, with limits that give the manifest its own
// size limit, and every entry's CRC-32); a `manifest.json` entry; format name; version (newer →
// `newerVersion`, so an old app can say "update the app"); the file list; per record in manifest
// order: safe path, well-formed digest and size (`invalidRecord`, FILE-002), unique, present, the
// listed length, then the SHA-256 (hashed in place, no copy); no entry that is not listed. Every
// per-entry refusal names the entry. Checksums give integrity, not authenticity: a file changed
// together with its record and CRC-32 is not detected (FILE-002-R7, ADR-0029).
import Foundation

public struct PortableFileRecord: Codable, Sendable, Equatable {
    public var path: String
    /// Lowercase hex SHA-256 of the file's bytes.
    public var sha256: String
    public var byteCount: Int

    public init(path: String, sha256: String, byteCount: Int) {
        self.path = path
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct PortableArchiveLimits: Sendable, Equatable {
    /// Files besides the manifest.
    public var maxFiles: Int
    public var maxFileBytes: Int
    public var maxManifestBytes: Int

    public init(maxFiles: Int, maxFileBytes: Int, maxManifestBytes: Int) {
        self.maxFiles = maxFiles
        self.maxFileBytes = maxFileBytes
        self.maxManifestBytes = maxManifestBytes
    }

    /// The ZIP limits: one entry more for the manifest, its own size limit, and a total that
    /// allows every entry at its limit with the longest names.
    public var zip: StoredZipLimits {
        let perEntry = ZipFormat.localHeaderSize + ZipFormat.centralHeaderSize + 2 * ArchivePath.maxBytes
        let total = maxFiles * (maxFileBytes + perEntry) + maxManifestBytes + perEntry + ZipFormat.endRecordSize
        return StoredZipLimits(maxEntries: maxFiles + 1, maxEntryBytes: maxFileBytes, maxArchiveBytes: total,
                               entryLimits: [PortableArchive.manifestPath: maxManifestBytes])
    }
}

public enum PortableArchiveError: Error, Equatable, Sendable {
    case zip(StoredZipError)
    case missingManifest
    case malformedManifest
    case wrongFormat
    case newerVersion(Int)
    case unlistedFile(String)
    case missingFile(String)
    case duplicateListing(String)
    case lengthMismatch(String)
    case checksumMismatch(String)
    case unsafePath(String)
    /// The record's digest is not 64 lowercase hex characters, or its size is negative (FILE-002-R4).
    case invalidRecord(String)

    public var message: String {
        switch self {
        case .zip(let error): return error.message
        case .missingManifest: return "The archive has no manifest."
        case .malformedManifest: return "The archive's manifest could not be read."
        case .wrongFormat: return "This archive was not made by projectM-iOS for this purpose."
        case .newerVersion: return "This archive was made by a newer version of the app. Update the app to read it."
        case .unlistedFile(let path): return "\(path) in the archive is not listed in its manifest."
        case .missingFile(let path): return "\(path) is listed in the manifest but missing from the archive."
        case .duplicateListing(let path): return "The manifest lists \(path) more than once."
        case .lengthMismatch(let path): return "\(path) in the archive is not the size its manifest gives."
        case .checksumMismatch(let path): return "\(path) in the archive does not match its manifest checksum."
        case .invalidRecord(let path): return "The manifest's record for \(path) has an invalid size or checksum."
        case .unsafePath(let path): return StoredZipError.unsafePath(path).message
        }
    }
}

public struct PortableArchiveContents: Sendable, Equatable {
    /// The manifest's bytes, for the caller's own keys.
    public let manifest: Data
    public let formatVersion: Int
    /// In manifest order.
    public let records: [PortableFileRecord]
    /// Listed path → bytes (verified).
    public let files: [String: Data]
}

public enum PortableArchive {
    public static let manifestPath = "manifest.json"

    private struct Header: Decodable {
        let format: String
        let formatVersion: Int
    }

    private struct FileList: Decodable {
        let files: [PortableFileRecord]
    }

    public static func read(_ data: Data, format: String, supportedVersion: Int, limits: PortableArchiveLimits) throws -> PortableArchiveContents {
        let entries: [StoredZipEntry]
        do {
            entries = try StoredZipReader.read(data, limits: limits.zip)
        } catch let error as StoredZipError {
            throw PortableArchiveError.zip(error)
        }
        guard let manifest = entries.first(where: { $0.path == manifestPath })?.data else { throw PortableArchiveError.missingManifest }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: manifest) else { throw PortableArchiveError.malformedManifest }
        guard header.format == format else { throw PortableArchiveError.wrongFormat }
        guard header.formatVersion >= 1 else { throw PortableArchiveError.malformedManifest }
        guard header.formatVersion <= supportedVersion else { throw PortableArchiveError.newerVersion(header.formatVersion) }
        guard let list = try? decoder.decode(FileList.self, from: manifest), list.files.count <= limits.maxFiles else {
            throw PortableArchiveError.malformedManifest
        }
        var byPath: [String: Data] = [:]
        for entry in entries where entry.path != manifestPath { byPath[entry.path] = entry.data }
        var listed: Set<String> = []
        var files: [String: Data] = [:]
        for record in list.files {
            guard ArchivePath.isSafe(record.path), record.path != manifestPath else { throw PortableArchiveError.unsafePath(record.path) }
            guard isLowercaseHex(record.sha256, count: 64), record.byteCount >= 0 else { throw PortableArchiveError.invalidRecord(record.path) }
            guard listed.insert(ArchivePath.collisionKey(record.path)).inserted else { throw PortableArchiveError.duplicateListing(record.path) }
            guard let bytes = byPath[record.path] else { throw PortableArchiveError.missingFile(record.path) }
            guard bytes.count == record.byteCount else { throw PortableArchiveError.lengthMismatch(record.path) }
            guard PortableSHA256.hex(bytes) == record.sha256 else { throw PortableArchiveError.checksumMismatch(record.path) }
            files[record.path] = bytes
        }
        for entry in entries where entry.path != manifestPath && files[entry.path] == nil {
            throw PortableArchiveError.unlistedFile(entry.path)
        }
        return PortableArchiveContents(manifest: manifest, formatVersion: header.formatVersion, records: list.files, files: files)
    }

    static func isLowercaseHex(_ text: String, count: Int) -> Bool {
        text.utf8.count == count && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }
}

/// Writes files (recording their SHA-256 and length), then `manifest.json` last.
public final class PortableArchiveWriter {
    private let zip: StoredZipWriter

    public init(modified: Date, sink: @escaping (Data) throws -> Void) {
        zip = StoredZipWriter(modified: modified, sink: sink)
    }

    public var bytesWritten: Int { zip.bytesWritten }

    /// Adds a file; its record goes into the caller's manifest. The manifest's own name is refused.
    public func add(path: String, data: Data) throws -> PortableFileRecord {
        guard ArchivePath.collisionKey(path) != PortableArchive.manifestPath else { throw StoredZipError.duplicatePath(path) }
        try zip.add(path: path, data: data)
        return PortableFileRecord(path: path, sha256: PortableSHA256.hex(data), byteCount: data.count)
    }

    /// Writes the manifest and completes the archive.
    public func finish(manifest: Data) throws {
        try zip.add(path: PortableArchive.manifestPath, data: manifest)
        try zip.finish()
    }
}
