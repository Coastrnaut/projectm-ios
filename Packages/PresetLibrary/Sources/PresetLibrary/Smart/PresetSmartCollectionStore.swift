// PresetSmartCollectionStore.swift — roadmap PRE-008: loads and saves the user's smart collections (spec
// PRE-008-R1, R4-R6; contract C3), in `<directory>/smart-collections.json` beside PRE-007's collections.json.
//
// The PRE-007 store's rules: every change is applied to a copy, saved atomically, and only then shown (a
// failed save throws `PresetCollectionError.saveFailed` and changes nothing); a newer document is never
// interpreted or written (`newerFormat`); an unreadable one is renamed aside; an older one is migrated with
// its original kept until the migrated document is saved. Names follow PRE-007's rules among smart
// collections. Unknown condition kinds pass through every change unchanged.
// Not Sendable: owned by the app's main-actor PresetCoordinator.
import Foundation

public final class PresetSmartCollectionStore {
    public enum Availability: Equatable, Sendable {
        case available
        case newerFormat(version: Int)
    }

    public static let fileName = PresetSmartCollectionsFile.fileName
    public static let unreadableFileName = "smart-collections.unreadable.json"
    public static let newerFormatText = "These smart collections were saved by a newer version of the app. Update the app to use them."
    public static let unreadableText = "Your smart collections could not be read and were set aside."

    /// The same folder as the manual collections (`PresetCollections`).
    public static func defaultDirectory() -> URL { PresetCollectionStore.defaultDirectory() }

    /// In creation order. Empty while unavailable.
    public private(set) var collections: [PresetSmartCollection] = []
    public let availability: Availability
    /// True once when an unreadable document was set aside at load.
    public private(set) var setAsideAtLoad = false

    private let directory: URL
    private let fileURL: URL
    private let makeID: () -> String
    private let write: (Data, URL) throws -> Void
    private var migrationBackup: URL?
    private var savingBlocked = false

    public init(directory: URL,
                makeID: @escaping () -> String = { PresetSmartCollection.idPrefix + UUID().uuidString },
                write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                migrations: [Int: PresetSmartCollectionsFile.Migration] = PresetSmartCollectionsFile.migrations) {
        self.directory = directory
        self.makeID = makeID
        self.write = write
        fileURL = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            availability = .available
            return
        }
        do {
            let loaded = try PresetSmartCollectionsFile.decode(Data(contentsOf: fileURL), migrations: migrations)
            availability = .available
            collections = loaded.file.smartCollections
            if let from = loaded.migratedFrom { saveMigrated(from: from) }
        } catch PresetSmartCollectionsFile.ReadError.newerVersion(let version) {
            availability = .newerFormat(version: version)
        } catch {
            availability = .available
            setAsideUnreadableFile()
        }
    }

    // MARK: - Reading

    public func collection(id: String) -> PresetSmartCollection? { collections.first { $0.id == id } }

    public var namesByCollection: [String: String] {
        Dictionary(collections.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Why `name` cannot be used (nil = it can), as `create` and `rename` check it.
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

    @discardableResult
    public func create(name: String, match: PresetSmartMatch, conditions: [PresetSmartCondition]) throws -> PresetSmartCollection {
        let created = PresetSmartCollection(id: makeID(), name: try PresetCollectionName.normalized(name), match: match,
                                            conditions: try PresetSmartCollectionError.validated(conditions))
        try commit { (list: inout [PresetSmartCollection]) throws -> Void in
            guard list.count < PresetSmartLimits.maxCollections else {
                throw PresetCollectionError.tooManyCollections(limit: PresetSmartLimits.maxCollections)
            }
            try Self.requireUnusedName(created.name, in: list, except: nil)
            guard !list.contains(where: { $0.id == created.id }) else { throw PresetCollectionError.saveFailed }
            list.append(created)
        }
        return created
    }

    /// Replaces the rules (match mode and conditions) of one smart collection.
    public func update(_ id: String, match: PresetSmartMatch, conditions: [PresetSmartCondition]) throws {
        let checked: [PresetSmartCondition] = try PresetSmartCollectionError.validated(conditions)
        try commit { (list: inout [PresetSmartCollection]) throws -> Void in
            let index: Int = try Self.index(of: id, in: list)
            list[index].match = match
            list[index].conditions = checked
        }
    }

    public func rename(_ id: String, to name: String) throws {
        try commit { (list: inout [PresetSmartCollection]) throws -> Void in
            let index: Int = try Self.index(of: id, in: list)
            let name: String = try PresetCollectionName.normalized(name)
            try Self.requireUnusedName(name, in: list, except: id)
            list[index].name = name
        }
    }

    public func delete(_ id: String) throws {
        try commit { (list: inout [PresetSmartCollection]) throws -> Void in
            list.remove(at: try Self.index(of: id, in: list))
        }
    }

    // MARK: - Transactions and files

    private func commit(_ change: (inout [PresetSmartCollection]) throws -> Void) throws {
        if case .newerFormat(let version) = availability { throw PresetCollectionError.newerFormat(version: version) }
        var draft: [PresetSmartCollection] = collections
        try change(&draft)
        guard draft != collections else { return }
        guard !savingBlocked, save(draft) else { throw PresetCollectionError.saveFailed }
        collections = draft
    }

    private func save(_ list: [PresetSmartCollection]) -> Bool {
        do {
            let data: Data = try PresetSmartCollectionsFile(smartCollections: list).encode()
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
        let backup: URL = directory.appendingPathComponent("smart-collections.v\(version).backup.json")
        try? files.removeItem(at: backup)
        do {
            try files.copyItem(at: fileURL, to: backup)
        } catch {
            savingBlocked = true
            return
        }
        migrationBackup = backup
        _ = save(collections)
    }

    private func setAsideUnreadableFile() {
        let files = FileManager.default
        let aside: URL = directory.appendingPathComponent(Self.unreadableFileName)
        try? files.removeItem(at: aside)
        setAsideAtLoad = true
        do {
            try files.moveItem(at: fileURL, to: aside)
        } catch {
            savingBlocked = true
        }
    }

    private static func index(of id: String, in list: [PresetSmartCollection]) throws -> Int {
        guard let index = list.firstIndex(where: { $0.id == id }) else { throw PresetCollectionError.unknownCollection }
        return index
    }

    private static func requireUnusedName(_ name: String, in list: [PresetSmartCollection], except id: String?) throws {
        let key: String = PresetCollectionName.key(name)
        if list.contains(where: { $0.id != id && PresetCollectionName.key($0.name) == key }) {
            throw PresetCollectionError.duplicateName
        }
    }
}
