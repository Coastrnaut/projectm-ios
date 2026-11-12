// UserPresetStore.swift — the files of the user's imported presets (PRE-012-R4, R17, R18, R25;
// contracts/user-presets.md).
//
// Layout under `directory` (Application Support/UserPresets in the app):
//   index.json                 the versioned record, only ever replaced atomically
//   index.unreadable.json      an unreadable record, set aside (one copy is kept)
//   files/<sha256>.milk        copies of waiting and playable presets
//   quarantine/<sha256>.milk   copies of quarantined files; nothing that plays presets reads here
//   trial.json, proving.json   which preset is being tried / first shown (crash-loop protection)
//
// * Stored names come from the content hash only; nothing from the picked file's name or
//   location is ever used as a path (R4).
// * Every change is a transaction: files first, then the record; if the record cannot be saved
//   the files are put back and memory is unchanged (R25).
// * A record from a newer app version is never interpreted or written; an unreadable one is set
//   aside, not deleted.
// * Files no record names are left alone.
// Not Sendable: owned by the `UserPresetLibrary` actor.
import Foundation

public final class UserPresetStore {
    public enum Availability: Equatable, Sendable {
        case available
        case newerFormat(version: Int)
    }

    public enum LoadNotice: Equatable, Sendable {
        case none
        case unreadableSetAside
    }

    public enum StoreError: Error, Equatable, Sendable {
        case newerFormat
        case saveFailed
        case unknownPreset
    }

    public enum Phase: String, Codable, Sendable, CaseIterable {
        /// The off-screen trial is running (R17).
        case trial
        /// The preset is on the visible renderer for the first time (R18).
        case proving

        var fileName: String { rawValue + ".json" }
    }

    public struct LeftoverRecord: Equatable, Sendable {
        public let phase: Phase
        public let presetID: String
    }

    private struct TrialRecord: Codable {
        var schemaVersion = 1
        var presetID: String
        var phase: Phase
    }

    public static let directoryName = "UserPresets"
    public static let indexFileName = "index.json"
    public static let unreadableFileName = "index.unreadable.json"
    static let filesFolder = "files"
    static let quarantineFolder = "quarantine"

    /// `<Application Support>/UserPresets`. Created on the first save.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// In import order. Empty while unavailable.
    public private(set) var presets: [UserPreset] = []
    public let availability: Availability
    public private(set) var loadNotice: LoadNotice = .none

    private let directory: URL
    private let indexURL: URL
    private let write: (Data, URL) throws -> Void
    private var migrationBackup: URL?
    /// An unreadable record could not be moved aside: saving would destroy it.
    private var savingBlocked = false

    public init(directory: URL,
                write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                migrations: [Int: UserPresetsFile.Migration] = UserPresetsFile.migrations) {
        self.directory = directory
        self.write = write
        indexURL = directory.appendingPathComponent(Self.indexFileName)
        let files = FileManager.default
        guard files.fileExists(atPath: indexURL.path) else {
            availability = .available
            return
        }
        do {
            let loaded = try UserPresetsFile.decode(Data(contentsOf: indexURL), migrations: migrations)
            availability = .available
            presets = loaded.file.presets
            if let from = loaded.migratedFrom { saveMigrated(from: from) }
        } catch UserPresetsFile.ReadError.newerVersion(let version) {
            availability = .newerFormat(version: version)
        } catch {
            availability = .available
            let aside = directory.appendingPathComponent(Self.unreadableFileName)
            try? files.removeItem(at: aside)
            loadNotice = .unreadableSetAside
            if (try? files.moveItem(at: indexURL, to: aside)) == nil { savingBlocked = true }
        }
    }

    // MARK: - Reading

    public func preset(id: String) -> UserPreset? { presets.first { $0.id == id } }
    public func preset(sha256: String) -> UserPreset? { presets.first { $0.sha256 == sha256 } }

    /// The stored bytes, whatever the state. Only `UserPresetLibrary` calls this, and it hands
    /// bytes to a renderer for playable presets alone (R20).
    func contents(of id: String) -> Data? {
        guard let preset = preset(id: id) else { return nil }
        return try? Data(contentsOf: fileURL(preset))
    }

    // MARK: - Changes

    /// Stores the copy, then the record.
    public func add(_ preset: UserPreset, contents: Data) throws {
        try requireWritable()
        guard preset.isWellFormed, self.preset(id: preset.id) == nil, self.preset(sha256: preset.sha256) == nil else {
            throw StoreError.saveFailed
        }
        let url = fileURL(preset)
        let files = FileManager.default
        let existed = files.fileExists(atPath: url.path)
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !existed { try contents.write(to: url, options: .atomic) }
        } catch {
            throw StoreError.saveFailed
        }
        guard save(presets + [preset]) else {
            if !existed { try? files.removeItem(at: url) }
            removeIfEmpty(url.deletingLastPathComponent())
            throw StoreError.saveFailed
        }
        presets.append(preset)
    }

    /// Changes one record. When the state moves the preset into or out of quarantine, its copy
    /// moves with it. The id, hashes and size cannot be changed.
    public func update(_ id: String, _ change: (inout UserPreset) -> Void) throws {
        try requireWritable()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw StoreError.unknownPreset }
        let old = presets[index]
        var new = old
        change(&new)
        new.id = old.id; new.sha256 = old.sha256; new.blobHash = old.blobHash; new.byteCount = old.byteCount
        guard new != old else { return }
        guard new.isWellFormed else { throw StoreError.saveFailed }
        let from = fileURL(old), to = fileURL(new)
        let files = FileManager.default
        var moved = false
        if from != to {
            do {
                try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? files.removeItem(at: to)
                try files.moveItem(at: from, to: to)
                moved = true
            } catch {
                throw StoreError.saveFailed
            }
        }
        var draft = presets
        draft[index] = new
        guard save(draft) else {
            if moved {
                try? files.moveItem(at: to, to: from)
                removeIfEmpty(to.deletingLastPathComponent())
            }
            throw StoreError.saveFailed
        }
        presets = draft
    }

    /// Removes the record, then its copy.
    public func remove(_ id: String) throws {
        try requireWritable()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw StoreError.unknownPreset }
        let preset = presets[index]
        var draft = presets
        draft.remove(at: index)
        guard save(draft) else { throw StoreError.saveFailed }
        presets = draft
        let url = fileURL(preset)
        try? FileManager.default.removeItem(at: url)
        removeIfEmpty(url.deletingLastPathComponent())
    }

    // MARK: - Trial records (R17, R18)

    /// Durably notes that `presetID` is being tried or first shown. Throws when it cannot be
    /// written: the caller must then not start.
    public func writeRecord(_ phase: Phase, presetID: String) throws {
        try requireWritable()
        do {
            let data = try JSONEncoder().encode(TrialRecord(presetID: presetID, phase: phase))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: recordURL(phase), options: .atomic)
        } catch {
            throw StoreError.saveFailed
        }
    }

    public func clearRecord(_ phase: Phase) {
        try? FileManager.default.removeItem(at: recordURL(phase))
        removeIfEmpty(directory)
    }

    public func hasRecord(_ phase: Phase) -> Bool {
        FileManager.default.fileExists(atPath: recordURL(phase).path)
    }

    /// Records left by a launch that ended inside a trial or a proving period. A record that
    /// cannot be read names nothing and is removed. The readable ones stay on disk until the
    /// caller has dealt with them and calls `clearRecord`.
    public func leftoverRecords() -> [LeftoverRecord] {
        guard availability == .available else { return [] }
        var found: [LeftoverRecord] = []
        for phase in Phase.allCases {
            let url = recordURL(phase)
            guard let data = try? Data(contentsOf: url) else { continue }
            guard data.count <= 4_096, let record = try? JSONDecoder().decode(TrialRecord.self, from: data),
                  record.schemaVersion == 1, record.phase == phase, record.presetID.hasPrefix(UserPreset.idPrefix) else {
                clearRecord(phase)
                continue
            }
            found.append(LeftoverRecord(phase: phase, presetID: record.presetID))
        }
        return found
    }

    // MARK: - Files

    private func requireWritable() throws {
        if case .newerFormat = availability { throw StoreError.newerFormat }
        if savingBlocked { throw StoreError.saveFailed }
    }

    /// Built from the validated hash only.
    private func fileURL(_ preset: UserPreset) -> URL {
        directory.appendingPathComponent(preset.state == .quarantined ? Self.quarantineFolder : Self.filesFolder, isDirectory: true)
            .appendingPathComponent(preset.fileName)
    }

    private func recordURL(_ phase: Phase) -> URL { directory.appendingPathComponent(phase.fileName) }

    private func removeIfEmpty(_ folder: URL) {
        let files = FileManager.default
        if let items = try? files.contentsOfDirectory(atPath: folder.path), items.isEmpty { try? files.removeItem(at: folder) }
    }

    private func save(_ list: [UserPreset]) -> Bool {
        do {
            let data = try UserPresetsFile(presets: list).encode()
            guard data.count <= PresetImportLimits.maxIndexBytes else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(data, indexURL)
        } catch {
            return false
        }
        if let backup = migrationBackup {
            try? FileManager.default.removeItem(at: backup)
            migrationBackup = nil
        }
        return true
    }

    /// Keeps the original until the migrated record is on disk (the PRE-007 rule).
    private func saveMigrated(from version: Int) {
        let files = FileManager.default
        let backup = directory.appendingPathComponent("index.v\(version).backup.json")
        try? files.removeItem(at: backup)
        do {
            try files.copyItem(at: indexURL, to: backup)
        } catch {
            savingBlocked = true
            return
        }
        migrationBackup = backup
        _ = save(presets)
    }
}
