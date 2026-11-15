// UserPresetHistory.swift — roadmap PRE-017 (specs/250-pre-017-preset-restore-points; R1-R3, R7;
// data-model.md): the earlier texts of edited user presets. A version is a reference to a text kept
// content-addressed in `UserPresets/versions/<sha256>.milk`; the list of versions per preset lives in
// `UserPresets/history.json`. Pure value types and helpers; `UserPresetStore+History` does the files.
// Foundation only.
import Foundation
import LocalPortability

/// One earlier text of a user preset (PRE-017-R1).
public struct UserPresetVersion: Codable, Sendable, Equatable, Identifiable {
    public var sha256: String
    public var blobHash: String
    public var byteCount: Int
    /// When an edit or a revert replaced this text.
    public var replacedAt: Date
    /// The preset's name at that moment.
    public var name: String

    public var id: String { sha256 }

    public init(sha256: String, blobHash: String, byteCount: Int, replacedAt: Date, name: String) {
        self.sha256 = sha256; self.blobHash = blobHash; self.byteCount = byteCount; self.replacedAt = replacedAt; self.name = name
    }

    /// The stored file name, `<sha256>.milk`.
    public var fileName: String { sha256 + ".milk" }

    var isWellFormed: Bool {
        UserPresetStore.isStoredFileName(fileName) && byteCount > 0 && byteCount <= PresetImportLimits.maxFileBytes
            && blobHash.count == 40 && blobHash.allSatisfy(\.isHexDigit)
    }
}

/// PRE-017-R2: the bounds. Distinct texts count once toward `totalBytes`.
public struct UserPresetVersionLimits: Sendable, Equatable {
    public var perPreset: Int
    public var total: Int
    public var totalBytes: Int

    public init(perPreset: Int, total: Int, totalBytes: Int) {
        self.perPreset = perPreset; self.total = total; self.totalBytes = totalBytes
    }

    public static let standard = UserPresetVersionLimits(perPreset: 10, total: 500, totalBytes: 50_000_000)
}

/// Whether the version list can be shown and written (PRE-017-R3).
public enum UserPresetVersionsAvailability: Sendable, Equatable {
    case available
    /// `history.json` is from a newer app version: never written; edits save without versions.
    case newerFormat
}

/// What the Versions sheet shows (PRE-017-R8). Newest first.
public struct UserPresetVersionList: Sendable, Equatable {
    public var versions: [UserPresetVersion]
    public var availability: UserPresetVersionsAvailability

    public init(versions: [UserPresetVersion], availability: UserPresetVersionsAvailability) {
        self.versions = versions
        self.availability = availability
    }

    public static let empty = UserPresetVersionList(versions: [], availability: .available)

    public static let newerFormatText = "Earlier versions were saved by a newer version of the app."
    public static let emptyText = "No earlier versions."
}

/// `history.json` (schema 1).
public struct UserPresetHistoryFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let fileName = "history.json"
    public static let unreadableFileName = "history.unreadable.json"
    /// Room for 500 versions with long names and IDs.
    static let maxBytes = 2 << 20

    public static let schema = DocumentSchema(
        name: "org.projectmios.user-preset-history", oldestReadableVersion: 1, currentVersion: currentVersion,
        limits: JSONLimits(maxBytes: maxBytes, maxDepth: 6, maxStringBytes: 16_384, maxNumberBytes: 32,
                           maxElements: 4_096, requiresObjectRoot: true))

    public struct Entry: Codable, Sendable, Equatable {
        public var presetID: String
        /// Oldest first.
        public var versions: [UserPresetVersion]
    }

    public enum ReadError: Error, Equatable, Sendable {
        case newerVersion(Int)
        case unreadable
    }

    public var schemaVersion: Int
    public var presets: [Entry]

    public init(presets: [Entry] = []) {
        schemaVersion = Self.currentVersion
        self.presets = presets
    }

    private struct Header: Decodable { let schemaVersion: Int }

    public static func decode(_ data: Data) throws -> UserPresetHistoryFile {
        guard data.count <= maxBytes, let header = try? JSONDecoder().decode(Header.self, from: data) else { throw ReadError.unreadable }
        if header.schemaVersion > currentVersion { throw ReadError.newerVersion(header.schemaVersion) }
        guard (try? schema.validate(data)) != nil else { throw ReadError.unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(UserPresetHistoryFile.self, from: data), file.schemaVersion == currentVersion else {
            throw ReadError.unreadable
        }
        var ids: Set<String> = []
        for entry in file.presets {
            guard entry.presetID.hasPrefix(UserPreset.idPrefix), ids.insert(entry.presetID).inserted else { throw ReadError.unreadable }
            var hashes: Set<String> = []
            for version in entry.versions {
                guard version.isWellFormed, hashes.insert(version.sha256).inserted else { throw ReadError.unreadable }
            }
        }
        return file
    }

    /// Stable output (sorted keys).
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    // MARK: - Pure changes

    public func versions(of presetID: String) -> [UserPresetVersion] {
        presets.first { (entry: Entry) -> Bool in entry.presetID == presetID }?.versions ?? []
    }

    /// Every text any version names (PRE-017-D5).
    public var namedHashes: Set<String> {
        var hashes: Set<String> = []
        for entry in presets { for version in entry.versions { hashes.insert(version.sha256) } }
        return hashes
    }

    /// `version` appended as the newest of `presetID` (a repeated text moves to the newest place), then pruned.
    public func adding(_ version: UserPresetVersion, to presetID: String, limits: UserPresetVersionLimits) -> UserPresetHistoryFile {
        var copy = self
        if let index = copy.presets.firstIndex(where: { (entry: Entry) -> Bool in entry.presetID == presetID }) {
            copy.presets[index].versions.removeAll { (old: UserPresetVersion) -> Bool in old.sha256 == version.sha256 }
            copy.presets[index].versions.append(version)
        } else {
            copy.presets.append(Entry(presetID: presetID, versions: [version]))
        }
        return copy.pruned(limits)
    }

    /// Without the versions of `presetID`.
    public func removing(_ presetID: String) -> UserPresetHistoryFile {
        var copy = self
        copy.presets.removeAll { (entry: Entry) -> Bool in entry.presetID == presetID }
        return copy
    }

    /// Only the entries `keep` accepts; presets left without versions are dropped.
    public func filtered(_ keep: (String, UserPresetVersion) -> Bool) -> UserPresetHistoryFile {
        var copy = self
        for index in copy.presets.indices {
            let id: String = copy.presets[index].presetID
            copy.presets[index].versions.removeAll { (version: UserPresetVersion) -> Bool in !keep(id, version) }
        }
        copy.presets.removeAll { (entry: Entry) -> Bool in entry.versions.isEmpty }
        return copy
    }

    /// PRE-017-R2: per preset the newest `perPreset`; then the globally oldest go while the count or the
    /// distinct bytes exceed the totals.
    public func pruned(_ limits: UserPresetVersionLimits) -> UserPresetHistoryFile {
        var copy = self
        for index in copy.presets.indices where copy.presets[index].versions.count > limits.perPreset {
            copy.presets[index].versions.removeFirst(copy.presets[index].versions.count - max(limits.perPreset, 0))
        }
        while copy.exceeds(limits), let oldest = copy.oldestPosition() {
            copy.presets[oldest.entry].versions.remove(at: oldest.version)
        }
        copy.presets.removeAll { (entry: Entry) -> Bool in entry.versions.isEmpty }
        return copy
    }

    private func exceeds(_ limits: UserPresetVersionLimits) -> Bool {
        var count = 0
        var bytes: [String: Int] = [:]
        for entry in presets {
            count += entry.versions.count
            for version in entry.versions { bytes[version.sha256] = version.byteCount }
        }
        let total: Int = bytes.values.reduce(0, +)
        return count > limits.total || total > limits.totalBytes
    }

    private func oldestPosition() -> (entry: Int, version: Int)? {
        var best: (entry: Int, version: Int, date: Date)?
        for (entryIndex, entry) in presets.enumerated() {
            guard let first = entry.versions.first else { continue }
            if best == nil || first.replacedAt < best!.date { best = (entryIndex, 0, first.replacedAt) }
        }
        return best.map { (entry: $0.entry, version: $0.version) }
    }
}
