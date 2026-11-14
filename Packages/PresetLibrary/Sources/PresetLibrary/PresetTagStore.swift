// PresetTagStore.swift — PRE-003: loads and saves the user's preset tags (spec PRE-003-R5, R6;
// research PRE-003-D1; contract C2). Modelled on PresetCollectionStore (PRE-007):
//
// * One document, `<directory>/tags.json` — in the app `Application Support/PresetCollections/`,
//   beside the collections — replaced atomically on every change. Bundled assets are never written.
// * Every change is a transaction: applied to a copy, saved, and only then shown. A refused change or
//   a failed save throws and leaves memory and disk as they were.
// * A document from a newer app version is never interpreted or written; the store is then
//   unavailable and every change throws `newerFormat`.
// * An unreadable document is renamed aside (one copy is kept), never deleted; if it cannot be moved,
//   nothing is saved (saving would destroy it).
// * Damaged entries are dropped on reading (`PresetTagsFile`); `loadNotice` says how many. The
//   repaired map is written by the next change, not at launch.
// * Entries are preset IDs only; the store never looks at the library (orphans are kept, PRE-003-R7).
// Not Sendable: owned by one actor (the app's main-actor PresetCoordinator).
import Foundation

public final class PresetTagStore {
    public enum Availability: Equatable, Sendable {
        case available
        case newerFormat(version: Int)
    }

    public enum LoadNotice: Equatable, Sendable {
        case none
        /// The saved document could not be read and was renamed to `unreadableFileName`.
        case unreadableSetAside
        /// This many damaged entries or tags were dropped while reading.
        case repaired(dropped: Int)
    }

    /// The folder PRE-007's collections use, so backup, erase, storage and cleanup treat both alike.
    public static let directoryName = PresetCollectionStore.directoryName
    public static let fileName = "tags.json"
    public static let unreadableFileName = "tags.unreadable.json"
    public static let unreadableText = "Your preset tags could not be read and were set aside."

    public static func repairedText(_ dropped: Int) -> String {
        dropped == 1 ? "1 damaged preset tag was removed." : "\(dropped) damaged preset tags were removed."
    }

    /// `<Application Support>/PresetCollections`. Created on the first save.
    public static func defaultDirectory() -> URL { PresetCollectionStore.defaultDirectory() }

    public private(set) var map = PresetTagMap()
    public let availability: Availability
    public private(set) var loadNotice: LoadNotice = .none
    public let fileURL: URL

    private let directory: URL
    private let write: (Data, URL) throws -> Void
    private var savingBlocked = false

    public init(directory: URL, write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.directory = directory
        self.write = write
        fileURL = directory.appendingPathComponent(Self.fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            availability = .available
            return
        }
        do {
            let loaded = try PresetTagsFile.decode(data)
            availability = .available
            map = loaded.map
            if loaded.dropped > 0 { loadNotice = .repaired(dropped: loaded.dropped) }
        } catch PresetTagsFile.ReadError.newerVersion(let version) {
            availability = .newerFormat(version: version)
        } catch {
            availability = .available
            setAsideUnreadableFile()
        }
    }

    // MARK: - Changes (each one is saved before it is visible)

    /// Adds a tag; returns the spelling stored.
    @discardableResult
    public func add(_ tag: String, to presetID: String) throws(PresetTagError) -> String {
        var draft = map
        let spelling = try draft.add(tag, to: presetID)
        try commit(draft)
        return spelling
    }

    /// Removes a tag; returns the spelling removed.
    @discardableResult
    public func remove(_ tag: String, from presetID: String) throws(PresetTagError) -> String {
        var draft = map
        let removed = try draft.remove(tag, from: presetID)
        try commit(draft)
        return removed
    }

    /// Drops every tag of a preset (the user removed it). False when it had none.
    @discardableResult
    public func prune(_ presetID: String) throws(PresetTagError) -> Bool {
        var draft = map
        guard draft.prune(presetID) else { return false }
        try commit(draft)
        return true
    }

    private func commit(_ draft: PresetTagMap) throws(PresetTagError) {
        if case .newerFormat = availability { throw .newerFormat }
        guard draft != map else { return }
        guard !savingBlocked, save(draft) else { throw .saveFailed }
        map = draft
    }

    private func save(_ draft: PresetTagMap) -> Bool {
        do {
            let data = try PresetTagsFile.encode(draft)
            guard data.count <= PresetTagsFile.maxFileBytes else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(data, fileURL)
            return true
        } catch {
            return false
        }
    }

    private func setAsideUnreadableFile() {
        let files = FileManager.default
        let aside = directory.appendingPathComponent(Self.unreadableFileName)
        try? files.removeItem(at: aside)
        loadNotice = .unreadableSetAside
        do {
            try files.moveItem(at: fileURL, to: aside)
        } catch {
            savingBlocked = true
        }
    }
}
