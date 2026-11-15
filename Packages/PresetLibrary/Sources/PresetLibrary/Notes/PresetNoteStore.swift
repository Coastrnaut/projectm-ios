// PresetNoteStore.swift — roadmap PRE-011: loads and saves the user's private preset notes (spec PRE-011-R1,
// R2; contract C1), in `<directory>/notes.json` — in the app `Application Support/PresetCollections/`, beside
// tags, overrides and smart collections. The PRE-016 and PRE-008 store rules:
//
// * Every change is a transaction: applied to a copy, saved atomically, and only then visible. A refused change
//   or a failed save throws and leaves memory and disk as they were.
// * A document from a newer app version is never interpreted or written (`newerFormat`).
// * An unreadable document is renamed aside (one copy kept), never deleted; if it cannot be moved, nothing is
//   saved. An older one is migrated, its original kept as `notes.v<N>.backup.json` until the migrated document
//   is saved.
// Not Sendable: owned by one actor (the app's main actor). Nothing here logs (PRE-011-R6).
import Foundation

public final class PresetNoteStore {
    public enum Availability: Equatable, Sendable {
        case available
        case newerFormat(version: Int)
    }

    public enum LoadNotice: Equatable, Sendable {
        case none
        case unreadableSetAside
        case repaired(dropped: Int)
    }

    public static let fileName = PresetNotesFile.fileName
    public static let unreadableFileName = "notes.unreadable.json"
    public static let unreadableText = "Your notes could not be read and were set aside."
    public static let repairedText = "Some notes could not be read and were removed."

    /// `<Application Support>/PresetCollections` (PRE-007's folder).
    public static func defaultDirectory() -> URL { PresetCollectionStore.defaultDirectory() }

    public private(set) var map = PresetNoteMap()
    public let availability: Availability
    public private(set) var loadNotice: LoadNotice = .none
    public let fileURL: URL

    private let directory: URL
    private let write: (Data, URL) throws -> Void
    private var migrationBackup: URL?
    private var savingBlocked = false

    public init(directory: URL, write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                migrations: [Int: PresetNotesFile.Migration] = PresetNotesFile.migrations) {
        self.directory = directory
        self.write = write
        fileURL = directory.appendingPathComponent(Self.fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            availability = .available
            return
        }
        do {
            let loaded = try PresetNotesFile.decode(data, migrations: migrations)
            availability = .available
            map = loaded.map
            if loaded.dropped > 0 { loadNotice = .repaired(dropped: loaded.dropped) }
            if let from = loaded.migratedFrom { saveMigrated(from: from) }
        } catch PresetNotesFile.ReadError.newerVersion(let version) {
            availability = .newerFormat(version: version)
        } catch {
            availability = .available
            setAsideUnreadableFile()
        }
    }

    public func note(for presetID: String) -> String? { map.note(for: presetID) }

    // MARK: - Changes (each one is saved before it is visible)

    /// Saves the trimmed text as the preset's note; empty text removes it. Returns the stored text (nil = removed).
    @discardableResult
    public func set(_ text: String, for presetID: String) throws(PresetNoteError) -> String? {
        var draft = map
        let stored: String? = try draft.set(text, for: presetID)
        try commit(draft)
        return stored
    }

    /// Removes a preset's note; false when it had none.
    @discardableResult
    public func remove(_ presetID: String) throws(PresetNoteError) -> Bool {
        var draft = map
        guard draft.remove(presetID) else { return false }
        try commit(draft)
        return true
    }

    /// PRE-011-R8: the preset was removed (or the reference is dangling); its note goes with it.
    @discardableResult
    public func prune(_ presetID: String) throws(PresetNoteError) -> Bool { try remove(presetID) }

    private func commit(_ draft: PresetNoteMap) throws(PresetNoteError) {
        if case .newerFormat = availability { throw .newerFormat }
        guard draft != map else { return }
        guard !savingBlocked, save(draft) else { throw .saveFailed }
        map = draft
    }

    private func save(_ draft: PresetNoteMap) -> Bool {
        do {
            let data: Data = try PresetNotesFile.encode(draft)
            guard data.count <= PresetNotesFile.maxFileBytes else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(data, fileURL)
        } catch {
            return false
        }
        if let backup = migrationBackup {
            try? FileManager.default.removeItem(at: backup)
            migrationBackup = nil
        }
        return true
    }

    private func saveMigrated(from version: Int) {
        let files = FileManager.default
        let backup: URL = directory.appendingPathComponent("notes.v\(version).backup.json")
        try? files.removeItem(at: backup)
        do {
            try files.copyItem(at: fileURL, to: backup)
        } catch {
            savingBlocked = true
            return
        }
        migrationBackup = backup
        _ = save(map)
    }

    private func setAsideUnreadableFile() {
        let files = FileManager.default
        let aside: URL = directory.appendingPathComponent(Self.unreadableFileName)
        try? files.removeItem(at: aside)
        loadNotice = .unreadableSetAside
        do {
            try files.moveItem(at: fileURL, to: aside)
        } catch {
            savingBlocked = true
        }
    }
}
