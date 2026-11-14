// LibraryBackupFormat.swift — FILE-005 (data-model "Archive layout", "Manifest"; contract C1, C2;
// ADR-0041): the `.pmbackup` format: a FILE-002 portable archive named
// `org.projectmios.library-backup`, its limits, manifest and version table.
//
// Version table (QA-004 style; FILE-005-R3):
//
//   | formatVersion | Reader action                                                     |
//   |---------------|-------------------------------------------------------------------|
//   | 1             | current: read                                                     |
//   | ≥ 2           | refused: "made by a newer version of the app. Update the app."    |
//   | ≤ 0           | refused: the manifest could not be read                           |
//
// Records inside are migrated by their own readers (SCN-013 scenes, PRE-012 index versions 1-2,
// PRE-007 collections), so an older record inside a version-1 backup restores as the current format.
// PRE-003 (2026-11-14) added the optional record `collections/tags.json` without a version change: no
// release has shipped FILE-005, so no reader exists that would refuse it (research PRE-003-D6).
// PRE-016 (2026-11-14) added `collections/overrides.json` the same way (research PRE-016-D5).
import Foundation
import LocalPortability

public enum LibraryBackupFormat {
    public static let name = "org.projectmios.library-backup"
    public static let currentVersion = 1
    public static let fileExtension = "pmbackup"

    /// The version table (FILE-005-R3): versions this reader reads, in order.
    public static let readableVersions: [Int] = [1]

    /// Spec Clarifications: file, entry and manifest limits.
    public static let maxFileBytes = 512 * 1_024 * 1_024
    public static let maxEntries = 4_096
    public static let maxEntryBytes = 64 * 1_024 * 1_024
    public static let maxManifestBytes = 1_024 * 1_024
    public static let maxPhotos = 64

    public static let limits = PortableArchiveLimits(maxFiles: maxEntries, maxFileBytes: maxEntryBytes, maxManifestBytes: maxManifestBytes)

    public static let schema = DocumentSchema(name: name, oldestReadableVersion: 1, currentVersion: currentVersion,
                                              limits: JSONLimits(maxBytes: maxManifestBytes, maxDepth: 8, maxStringBytes: 4_096,
                                                                 maxNumberBytes: 32, maxElements: maxEntries + 16))

    // MARK: - Entry paths

    public static let showPath = "show/show.json"
    public static let scenesPrefix = "show/scenes/"
    public static let sceneSuffix = ".scene.json"
    public static let currentScenePath = "current/current.scene"
    public static let presetIndexPath = "presets/index.json"
    public static let presetTextsPrefix = "presets/texts/"
    public static let presetTextSuffix = ".milk"
    public static let collectionsPath = "collections/collections.json"
    /// PRE-003: the preset tags document (`PresetTagsFile`).
    public static let tagsPath = "collections/tags.json"
    /// PRE-016: the preset overrides document (`PresetOverridesFile`).
    public static let overridesPath = "collections/overrides.json"
    public static let settingsPath = "settings.json"
    public static let photosPrefix = "photos/"

    public static func scenePath(_ id: String) -> String { scenesPrefix + id + sceneSuffix }
    public static func presetTextPath(_ sha256: String) -> String { presetTextsPrefix + sha256 + presetTextSuffix }
    public static func photoPath(_ name: String) -> String { photosPrefix + name }

    /// `<canonical uppercase UUID>.png|jpg` (MED-001-R14's names).
    public static func isPhotoName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == "png" || parts[1] == "jpg" else { return false }
        let stem = String(parts[0])
        guard let id = UUID(uuidString: stem) else { return false }
        return id.uuidString == stem
    }

    /// "projectM Library 2026-11-14.pmbackup" (UTC date).
    public static func fileName(createdAt: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: createdAt)
        let year: Int = parts.year ?? 2026
        let month: Int = parts.month ?? 1
        let day: Int = parts.day ?? 1
        let date: String = String(year) + "-" + twoDigits(month) + "-" + twoDigits(day)
        return "projectM Library " + date + "." + fileExtension
    }

    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0" + String(value) : String(value) }
}

/// The manifest's own keys besides FILE-002's header (data-model "Manifest").
public struct LibraryBackupManifest: Codable, Sendable, Equatable {
    public var format: String
    public var formatVersion: Int
    public var files: [PortableFileRecord]
    public var appVersion: String
    /// ISO 8601, UTC.
    public var createdAt: String
    public var counts: LibraryBackupCounts
    public var excluded: LibraryExclusions
}

/// The settings entry (`settings.json`).
struct LibrarySettingsDocument: Codable, Equatable {
    var schemaVersion: Int
    var values: [String: LibrarySettingValue]
}

/// Why a backup was refused; nothing was interpreted beyond the failing check and nothing written.
public enum LibraryBackupError: Error, Sendable, Equatable {
    case tooLarge(limit: Int)
    case archive(PortableArchiveError)
    case unexpectedEntry(String)
    /// A record could not be read by its own reader; the entry path names it.
    case unreadableRecord(String)
    /// A record the backup must never hold (full-library copy, quarantined preset, an unknown setting).
    case excludedRecord(String)
    case tooManyPhotos(limit: Int)
    case writeFailed

    public var message: String {
        switch self {
        case .tooLarge: "This backup is larger than 512 MB and cannot be read."
        case let .archive(error):
            switch error {
            case .wrongFormat: "This file is not a projectM-iOS library backup."
            default: error.message
            }
        case let .unexpectedEntry(path): "The backup holds \(path), which a library backup never contains."
        case let .unreadableRecord(path): "\(path) in the backup could not be read."
        case let .excludedRecord(path): "The backup holds \(path), which a library backup never contains."
        case let .tooManyPhotos(limit): "A backup holds at most \(limit) photos."
        case .writeFailed: "The backup could not be written."
        }
    }
}
