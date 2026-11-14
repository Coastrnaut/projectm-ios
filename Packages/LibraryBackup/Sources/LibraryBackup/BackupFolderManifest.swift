// BackupFolderManifest.swift — FILE-006 contract B1 (specs/139-file-006-incremental-backup; data-model
// "BackupFolderManifest", research FILE-006-D5): the manifest of a folder backup and its layout.
//
//   projectM Backup/
//     backup-manifest.json          this file, written last (atomic)
//     projectM Library.pmbackup     the FILE-005 archive, unchanged format
//     media/<sha256>.<ext>          one copy per content
//
// The manifest comes from a folder the user chose, so it is untrusted: bounded JSON, a known format and
// version, and every entry validated; anything else reads as "no usable manifest" (a full backup, or a
// refused restore). Version table: 1 = read; anything else = unusable.
// `kind` is an open token so other features (SCN-004) can add kinds; this version restores only the
// kinds in `BackupAssetKind`.
import Foundation
import LocalPortability

public enum BackupFolderLayout {
    public static let folderName = "projectM Backup"
    public static let manifestName = "backup-manifest.json"
    public static let archiveName = "projectM Library.pmbackup"
    public static let mediaFolderName = "media"
    public static let partialPrefix = ".partial-"

    /// The folder a backup writes into: the picked folder itself when it already holds a manifest,
    /// otherwise `projectM Backup/` inside it.
    public static func backupFolder(in picked: URL) -> URL {
        if FileManager.default.fileExists(atPath: picked.appendingPathComponent(manifestName, isDirectory: false).path) { return picked }
        return picked.appendingPathComponent(folderName, isDirectory: true)
    }

    /// `media/<sha256>.<ext>` (no dot when the extension is empty).
    public static func location(sha256: String, fileExtension: String) -> String {
        mediaFolderName + "/" + sha256 + (fileExtension.isEmpty ? "" : "." + fileExtension)
    }

    /// True for `<64 lowercase hex>` or `<64 lowercase hex>.<ext>` (ext 1-8 of `[a-z0-9]`).
    public static func isContentName(_ name: String) -> Bool { contentAddress(of: name) != nil }

    /// The hash a content name carries.
    public static func contentAddress(of name: String) -> String? {
        let parts = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let stem = String(parts[0])
        guard MediaContentHash.isSHA256Hex(stem) else { return nil }
        if parts.count == 2 {
            guard isExtension(String(parts[1])), !parts[1].isEmpty else { return nil }
        }
        return stem
    }

    static func isExtension(_ text: String) -> Bool {
        text.utf8.count <= 8 && text.utf8.allSatisfy { (c: UInt8) -> Bool in (c >= 48 && c <= 57) || (c >= 97 && c <= 122) }
    }
}

/// The kinds this version backs up and restores (others in a manifest are kept and skipped).
public enum BackupAssetKind {
    public static let photo = "photo"
    public static let video = "video"
    public static let audio = "audio"
    public static let audioIndex = "audio-index"
    public static let known: Set<String> = [photo, video, audio, audioIndex]
}

public struct BackupArchiveRecord: Codable, Sendable, Equatable {
    public var path: String
    public var byteCount: Int64
    public var sha256: String
}

/// One asset (data-model "AssetEntry").
public struct BackupAssetEntry: Codable, Sendable, Equatable {
    public var kind: String
    /// The logical name (`<UUID>.png`, `<sha256>.m4a`, `index.json`).
    public var name: String
    public var byteCount: Int64
    /// Seconds since 1970 of the source file; only for assets without a content address.
    public var modified: Double?
    /// Absent only in older manifests (FILE-006-D5 migration): such an entry is never reused.
    public var sha256: String?
    /// `media/<sha256>.<ext>`.
    public var location: String

    public init(kind: String, name: String, byteCount: Int64, modified: Double?, sha256: String?, location: String) {
        self.kind = kind
        self.name = name
        self.byteCount = byteCount
        self.modified = modified
        self.sha256 = sha256
        self.location = location
    }

    public var key: String { kind + "/" + name }

    var isValid: Bool {
        guard BackupFolderManifest.isKind(kind), BackupFolderManifest.isSafeName(name), byteCount >= 0 else { return false }
        let prefix = BackupFolderLayout.mediaFolderName + "/"
        guard location.hasPrefix(prefix), let address = BackupFolderLayout.contentAddress(of: String(location.dropFirst(prefix.count))) else {
            return false
        }
        if let sha256 { return sha256 == address }
        return true
    }
}

public struct BackupFolderManifest: Codable, Sendable, Equatable {
    public static let format = "org.projectmios.backup-folder"
    public static let currentVersion = 1
    public static let readableVersions: [Int] = [1]
    public static let maxBytes = 4 << 20
    public static let maxAssets = 8_192

    public var format: String
    public var formatVersion: Int
    public var appVersion: String
    /// ISO 8601, UTC.
    public var createdAt: String
    public var library: BackupArchiveRecord?
    public var assets: [BackupAssetEntry]

    public init(appVersion: String, createdAt: String, library: BackupArchiveRecord?, assets: [BackupAssetEntry]) {
        format = Self.format
        formatVersion = Self.currentVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.library = library
        self.assets = assets.sorted { (a: BackupAssetEntry, b: BackupAssetEntry) -> Bool in a.key < b.key }
    }

    /// Deterministic bytes (sorted keys, entries sorted by kind and name).
    public func encoded() throws -> Data {
        var copy = self
        copy.assets.sort { (a: BackupAssetEntry, b: BackupAssetEntry) -> Bool in a.key < b.key }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(copy)
    }

    static let limits = JSONLimits(maxBytes: maxBytes, maxDepth: 6, maxStringBytes: 4_096, maxNumberBytes: 40, maxElements: maxAssets * 8 + 64)

    /// The manifest, or nil when it is not usable (research FILE-006-D5).
    public static func read(_ data: Data) -> BackupFolderManifest? {
        guard data.count <= maxBytes, (try? BoundedJSON.validate(data, limits: limits)) != nil,
              let manifest = try? JSONDecoder().decode(BackupFolderManifest.self, from: data),
              manifest.format == format, readableVersions.contains(manifest.formatVersion),
              manifest.appVersion.utf8.count <= 64, manifest.assets.count <= maxAssets else { return nil }
        var keys: Set<String> = []
        for entry in manifest.assets {
            guard entry.isValid, !keys.contains(entry.key) else { return nil }
            keys.insert(entry.key)
        }
        if let library = manifest.library {
            guard library.path == BackupFolderLayout.archiveName, library.byteCount >= 0, MediaContentHash.isSHA256Hex(library.sha256) else {
                return nil
            }
        }
        return manifest
    }

    /// The manifest at `folder`, or nil (missing, oversized or unusable).
    public static func read(folder: URL) -> BackupFolderManifest? {
        let url = folder.appendingPathComponent(BackupFolderLayout.manifestName, isDirectory: false)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return read(data)
    }

    static func isKind(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 32
            && text.utf8.allSatisfy { (c: UInt8) -> Bool in (c >= 48 && c <= 57) || (c >= 97 && c <= 122) || c == 45 }
    }

    /// One path component: no separators or NUL, not `.`/`..`, no leading dot, at most 255 bytes.
    static func isSafeName(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= 255, !text.hasPrefix(".") else { return false }
        return !text.utf8.contains { (c: UInt8) -> Bool in c == 47 || c == 92 || c == 0 }
    }
}
