// PresetOverrideStore.swift — PRE-016: loads and saves the user's preset overrides (spec PRE-016-R4,
// R8; research D4; contract C2). Modelled on PresetTagStore (PRE-003):
//
// * One document, `<directory>/overrides.json` — in the app `Application Support/PresetCollections/`,
//   beside the collections and tags — replaced atomically on every change. Preset files are never
//   written (R7).
// * Every change is a transaction: applied to a copy, saved, and only then visible. A refused change
//   or a failed save throws and leaves memory and disk as they were.
// * A document from a newer app version is never interpreted or written (`newerFormat`).
// * An unreadable document is renamed aside (one copy kept), never deleted; if it cannot be moved,
//   nothing is saved.
// Not Sendable: owned by one actor (the app's main actor).
import Foundation

public final class PresetOverrideStore {
    public enum Availability: Equatable, Sendable {
        case available
        case newerFormat(version: Int)
    }

    public enum LoadNotice: Equatable, Sendable {
        case none
        case unreadableSetAside
        case repaired(dropped: Int)
    }

    public static let fileName = "overrides.json"
    public static let unreadableFileName = "overrides.unreadable.json"

    /// `<Application Support>/PresetCollections` (PRE-007's folder).
    public static func defaultDirectory() -> URL { PresetCollectionStore.defaultDirectory() }

    public private(set) var map = PresetOverrideMap()
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
            let loaded = try PresetOverridesFile.decode(data)
            availability = .available
            map = loaded.map
            if loaded.dropped > 0 { loadNotice = .repaired(dropped: loaded.dropped) }
        } catch PresetOverridesFile.ReadError.newerVersion(let version) {
            availability = .newerFormat(version: version)
        } catch {
            availability = .available
            setAsideUnreadableFile()
        }
    }

    public func overrides(for presetID: String) -> [String: Double] { map.overrides(for: presetID) }

    // MARK: - Changes (each one is saved before it is visible)

    /// Stores one override; returns the value stored (clamped, rounded).
    @discardableResult
    public func set(_ value: Double, for key: String, preset presetID: String) throws(PresetOverrideError) -> Double {
        var draft = map
        let stored: Double = try draft.set(value, for: key, preset: presetID)
        try commit(draft)
        return stored
    }

    /// Removes one override; false when it was not set.
    @discardableResult
    public func remove(_ key: String, preset presetID: String) throws(PresetOverrideError) -> Bool {
        var draft = map
        guard draft.remove(key, preset: presetID) else { return false }
        try commit(draft)
        return true
    }

    /// Reset to original (R15): removes every override of a preset; false when it had none.
    @discardableResult
    public func reset(_ presetID: String) throws(PresetOverrideError) -> Bool {
        var draft = map
        guard draft.reset(presetID) else { return false }
        try commit(draft)
        return true
    }

    /// R16: the preset was removed; its overrides go with it.
    @discardableResult
    public func prune(_ presetID: String) throws(PresetOverrideError) -> Bool { try reset(presetID) }

    private func commit(_ draft: PresetOverrideMap) throws(PresetOverrideError) {
        if case .newerFormat = availability { throw .newerFormat }
        guard draft != map else { return }
        guard !savingBlocked, save(draft) else { throw .saveFailed }
        map = draft
    }

    private func save(_ draft: PresetOverrideMap) -> Bool {
        do {
            let data = try PresetOverridesFile.encode(draft)
            guard data.count <= PresetOverridesFile.maxFileBytes else { return false }
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
