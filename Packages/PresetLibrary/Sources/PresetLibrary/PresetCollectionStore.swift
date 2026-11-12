// PresetCollectionStore.swift — loads and saves the user's preset collections (PRE-007-R1-R10,
// R14-R16; contracts/preset-collections.md).
//
// * One document, `<directory>/collections.json`, replaced atomically on every change.
// * Every change is a transaction: it is applied to a copy, saved, and only then shown. A failed
//   save throws `saveFailed` and leaves memory and disk as they were (R8).
// * A document from a newer app version is never interpreted or written; the store is then
//   unavailable and every change throws `newerFormat` (R15).
// * An unreadable document is renamed aside (one copy is kept), never deleted (R15).
// * An older document is migrated; its original is kept as a backup until the migrated document
//   was saved (R15).
// * Entries are preset ids only. The store never looks at the library, so ids it cannot resolve
//   are kept through every operation (R14), and it knows nothing about purchases (R13).
// Not Sendable: owned by one actor (the app's main-actor PresetCoordinator), like FavoritesStore.
import Foundation

public final class PresetCollectionStore {
    public enum Availability: Equatable, Sendable {
        case available
        case newerFormat(version: Int)
    }

    public enum LoadNotice: Equatable, Sendable {
        case none
        /// The saved document could not be read and was renamed to `unreadableFileName`.
        case unreadableSetAside
    }

    public static let directoryName = "PresetCollections"
    public static let fileName = "collections.json"
    public static let unreadableFileName = "collections.unreadable.json"
    public static let newerFormatText = "These collections were saved by a newer version of the app. Update the app to use them."
    public static let unreadableText = "Your collections could not be read and were set aside."

    /// `<Application Support>/PresetCollections` (research D2). Created on the first save.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// In the user's order. Empty while unavailable.
    public private(set) var collections: [PresetCollection] = []
    public let availability: Availability
    public private(set) var loadNotice: LoadNotice = .none

    private let directory: URL
    private let fileURL: URL
    private let makeID: () -> String
    private let write: (Data, URL) throws -> Void
    /// The original of a migrated document, removed after the next successful save.
    private var migrationBackup: URL?
    /// An unreadable document could not be moved aside: saving would destroy it, so nothing is saved.
    private var savingBlocked = false

    public init(directory: URL,
                makeID: @escaping () -> String = { UUID().uuidString },
                write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                migrations: [Int: PresetCollectionsFile.Migration] = PresetCollectionsFile.migrations) {
        self.directory = directory
        self.makeID = makeID
        self.write = write
        fileURL = directory.appendingPathComponent(Self.fileName)

        let files = FileManager.default
        guard files.fileExists(atPath: fileURL.path) else {
            availability = .available
            return
        }
        do {
            let loaded = try PresetCollectionsFile.decode(Data(contentsOf: fileURL), migrations: migrations)
            availability = .available
            collections = loaded.file.collections
            if let from = loaded.migratedFrom { saveMigrated(from: from) }
        } catch PresetCollectionsFile.ReadError.newerVersion(let version) {
            availability = .newerFormat(version: version)
        } catch {
            availability = .available
            setAsideUnreadableFile()
        }
    }

    // MARK: - Reading

    public func collection(id: String) -> PresetCollection? { collections.first { $0.id == id } }

    /// Collection id → its preset ids in order: what `PresetLibrary.members(of:…collections:)` takes.
    public var presetIDsByCollection: [String: [String]] {
        Dictionary(collections.map { ($0.id, $0.presetIDs) }, uniquingKeysWith: { first, _ in first })
    }

    public var namesByCollection: [String: String] {
        Dictionary(collections.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Why `name` cannot be used for a new collection, or for renaming `id` (nil = it can). The
    /// same checks `create` and `rename` apply, for showing the reason while the user types.
    public func nameProblem(_ name: String, renaming id: String? = nil) -> PresetCollectionError? {
        if case .newerFormat(let version) = availability { return .newerFormat(version: version) }
        do {
            try Self.requireUnusedName(try PresetCollectionName.normalized(name), in: collections, except: id)
            return nil
        } catch {
            return error as? PresetCollectionError ?? .saveFailed
        }
    }

    // MARK: - Changes (each one is saved before it is visible)

    /// R1: a new, empty collection at the end of the list.
    @discardableResult
    public func create(name: String) throws -> PresetCollection {
        let created = PresetCollection(id: makeID(), name: try PresetCollectionName.normalized(name), presetIDs: [])
        try commit { list in
            guard list.count < PresetCollectionLimits.maxCollections else {
                throw PresetCollectionError.tooManyCollections(limit: PresetCollectionLimits.maxCollections)
            }
            try Self.requireUnusedName(created.name, in: list, except: nil)
            guard !list.contains(where: { $0.id == created.id }) else { throw PresetCollectionError.saveFailed }
            list.append(created)
        }
        return created
    }

    /// R2: only the name changes. The collection's own name (in any case) is accepted.
    public func rename(_ id: String, to name: String) throws {
        try commit { list in
            let index = try Self.index(of: id, in: list)
            let name = try PresetCollectionName.normalized(name)
            try Self.requireUnusedName(name, in: list, except: id)
            list[index].name = name
        }
    }

    /// R3: removes the collection and nothing else.
    public func delete(_ id: String) throws {
        try commit { list in
            list.remove(at: try Self.index(of: id, in: list))
        }
    }

    /// R4: appends the preset. Returns false, changing nothing, when it is already in the collection.
    @discardableResult
    public func add(_ presetID: String, to id: String) throws -> Bool {
        var added = false
        try commit { list in
            let index = try Self.index(of: id, in: list)
            guard !list[index].presetIDs.contains(presetID) else { return }
            guard list[index].presetIDs.count < PresetCollectionLimits.maxPresetsPerCollection else {
                throw PresetCollectionError.collectionFull(limit: PresetCollectionLimits.maxPresetsPerCollection)
            }
            list[index].presetIDs.append(presetID)
            added = true
        }
        return added
    }

    /// R5: removes those entries; the rest keep their order.
    public func remove(_ presetIDs: Set<String>, from id: String) throws {
        try commit { list in
            let index = try Self.index(of: id, in: list)
            list[index].presetIDs.removeAll(where: presetIDs.contains)
        }
    }

    /// R6, R14: the entries named in `visibleOrder` take that order; all others keep their slots.
    public func reorderPresets(in id: String, visibleOrder: [String]) throws {
        try commit { list in
            let index = try Self.index(of: id, in: list)
            list[index].presetIDs = try PresetCollectionOrder.applying(visibleOrder: visibleOrder, to: list[index].presetIDs)
        }
    }

    /// R7: `ids` must name every collection exactly once.
    public func reorderCollections(_ ids: [String]) throws {
        try commit { list in
            let byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard ids.count == list.count, Set(ids).count == ids.count, ids.allSatisfy({ byID[$0] != nil }) else {
                throw PresetCollectionError.invalidOrder
            }
            list = ids.compactMap { byID[$0] }
        }
    }

    // MARK: - Transactions and files

    private func commit(_ change: (inout [PresetCollection]) throws -> Void) throws {
        if case .newerFormat(let version) = availability { throw PresetCollectionError.newerFormat(version: version) }
        var draft = collections
        try change(&draft)
        guard draft != collections else { return }   // nothing changed: nothing to save
        guard !savingBlocked, save(draft) else { throw PresetCollectionError.saveFailed }
        collections = draft
    }

    /// Writes the whole document atomically; true on success.
    private func save(_ list: [PresetCollection]) -> Bool {
        do {
            let data = try PresetCollectionsFile(collections: list).encode()
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

    /// R15: keep the original until the migrated document is on disk. If the save fails the
    /// original is still the saved document; the store runs on the migrated list and the next
    /// successful save (or the next launch) completes the migration.
    private func saveMigrated(from version: Int) {
        let files = FileManager.default
        let backup = directory.appendingPathComponent("collections.v\(version).backup.json")
        try? files.removeItem(at: backup)
        do {
            try files.copyItem(at: fileURL, to: backup)
        } catch {
            savingBlocked = true   // no backup, so the original must not be replaced
            return
        }
        migrationBackup = backup
        _ = save(collections)
    }

    private func setAsideUnreadableFile() {
        let files = FileManager.default
        let aside = directory.appendingPathComponent(Self.unreadableFileName)
        try? files.removeItem(at: aside)
        do {
            try files.moveItem(at: fileURL, to: aside)
            loadNotice = .unreadableSetAside
        } catch {
            loadNotice = .unreadableSetAside
            savingBlocked = true
        }
    }

    private static func index(of id: String, in list: [PresetCollection]) throws -> Int {
        guard let index = list.firstIndex(where: { $0.id == id }) else { throw PresetCollectionError.unknownCollection }
        return index
    }

    private static func requireUnusedName(_ name: String, in list: [PresetCollection], except id: String?) throws {
        let key = PresetCollectionName.key(name)
        if list.contains(where: { $0.id != id && PresetCollectionName.key($0.name) == key }) {
            throw PresetCollectionError.duplicateName
        }
    }
}
