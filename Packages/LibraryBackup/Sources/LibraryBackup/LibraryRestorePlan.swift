// LibraryRestorePlan.swift — FILE-005 contract C4 (FILE-005-R5, R10; spec Clarifications; research
// FILE-005-D5): the dry run of a restore. `LibraryRestorePlanner.plan` is pure: equal inputs give
// equal plans, so the installer plans again and compares with `==`.
//
// Per record (key "show", "scene/<ID>", "current-scene", "preset/<id>", "collection/<id>",
// "setting/<key>", "photo/<name>"): new, identical or a clash (same key, other content). A clash
// takes the override for its key or "Apply to all" (Keep both by default):
//   * keyed records — Skip leaves the device's record; Replace keeps the device's identifier and takes
//     the backup's content; Keep both adds the backup's record under a derived identifier
//     ("FILE-005|<kind>|<id>|<content sha256>|<n>", smallest n ≥ 1 free) and a copy name;
//   * single-valued records (the current scene, a setting, the last preset) and photos (scenes refer
//     to their names) cannot be kept twice: Keep both keeps the device's value (`fellBack`);
//   * favorites under Keep both: the union.
// Scenes: an empty show (no cues, no stored scenes) takes the backup's show and scenes exactly;
// otherwise FILE-004's scene planner decides (a new or copied scene gets a cue).
// Preset tags (PRE-003, key "tags/<preset id>", section `tags`): per preset, Keep both = the union
// (the device's tags, then the backup's, folded, at most 16; capped = `fellBack`), Replace = the
// backup's tags, Skip = the device's. Tags of a user preset that the presets section adds as a copy
// under a derived identifier follow that identifier.
// Preset overrides (PRE-016, key "overrides/<preset id>", section `overrides`): per preset, Keep both =
// the device's values plus the backup's other parameters (`union`), Replace = the backup's set, Skip =
// the device's; a Keep-both copy's overrides follow its derived identifier, as tags do.
// Presets: a backup text already stored under another identifier is identical (each text is stored
// once, PRE-012); a Keep both or Replace that would store a text twice keeps the device's record.
import Foundation
import LocalPortability
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage

public enum LibraryRestoreChoice: String, Codable, Sendable, Hashable, CaseIterable {
    case keepBoth, replace, skip

    var sceneChoice: ShowSceneImportChoice {
        switch self {
        case .keepBoth: .keepBoth
        case .replace: .replace
        case .skip: .skip
        }
    }
}

public enum LibraryRestoreSection: String, Sendable, Hashable, CaseIterable {
    case scenes, currentScene, presets, collections, settings, photos
    /// PRE-003: preset tags, one entry per tagged preset.
    case tags
    /// PRE-016: preset parameter overrides, one entry per preset with overrides.
    case overrides
}

public enum LibraryRecordKind: String, Sendable, Hashable {
    case new, identical, clash
}

public enum LibraryRestoreAction: Sendable, Hashable {
    /// The backup's record is added as it is.
    case add
    /// Added under this identifier and name (Keep both, or a new record whose name was taken).
    case addCopy(id: String, name: String)
    /// The device's record takes the backup's content under its identifier.
    case replace
    /// The device's record stays as it is.
    case keep
    /// Favorites: the union of both lists.
    case union
}

public struct LibraryRestoreEntry: Sendable, Hashable {
    public let key: String
    public let section: LibraryRestoreSection
    public let kind: LibraryRecordKind
    /// The effective choice for a clash; nil otherwise.
    public let choice: LibraryRestoreChoice?
    public let action: LibraryRestoreAction
    /// Keep both (or Replace) could not apply and the device's record was kept, or Replace became Keep both.
    public let fellBack: Bool

    public var changesLibrary: Bool { action != .keep }
}

public enum LibraryRestoreRefusal: Error, Sendable, Hashable {
    case library(LibraryReadError)
    case tooManyPresets(limit: Int)
    case tooManyCollections(limit: Int)
    case scenes(String)
    case interrupted

    public var message: String {
        switch self {
        case let .library(error): error.message
        case let .tooManyPresets(limit): "My Presets would hold more than \(limit) presets."
        case let .tooManyCollections(limit): "There would be more than \(limit) collections."
        case let .scenes(text): text
        case .interrupted: "An earlier restore did not finish."
        }
    }
}

public enum LibraryShowMode: String, Sendable, Hashable {
    /// Nothing about the show changes.
    case none
    /// The device's show is empty: the backup's show and scenes are written exactly.
    case exact
    /// FILE-004's scene installer adds, copies or replaces scenes in the device's show.
    case merge
}

public struct LibraryRestorePlan: Sendable, Equatable {
    public let choice: LibraryRestoreChoice
    /// As given (by record key).
    public let overrides: [String: LibraryRestoreChoice]
    public let libraryDigest: String
    public let backupDigest: String
    public let refusal: LibraryRestoreRefusal?
    public let entries: [LibraryRestoreEntry]
    public let showMode: LibraryShowMode
    /// The FILE-004 scene plan in merge mode (the installer plans again on its staged copy).
    public let scenePlan: ShowSceneImportPlan?
    /// Added presets with their final identifier and name, waiting for their check.
    public let presetsToAdd: [LibraryPreset]
    /// Replacements: the device's identifier with the backup's content.
    public let presetsToReplace: [LibraryPreset]
    /// The collections after the restore; nil when they do not change.
    public let collections: [PresetCollection]?
    /// PRE-003: the preset tags after the restore; nil when they do not change.
    public var presetTags: PresetTagMap? = nil
    /// PRE-016: the preset overrides after the restore; nil when they do not change.
    public var presetOverrides: PresetOverrideMap? = nil
    /// The current scene to write; nil when it does not change.
    public let currentScene: Data?
    public let photosToWrite: [String: Data]
    /// Applied after the commit point.
    public let settingsToApply: [String: LibrarySettingValue]

    public var canRestore: Bool { refusal == nil && entries.contains { (entry: LibraryRestoreEntry) -> Bool in entry.changesLibrary } }

    public func count(_ section: LibraryRestoreSection, _ kind: LibraryRecordKind) -> Int {
        entries.filter { (entry: LibraryRestoreEntry) -> Bool in entry.section == section && entry.kind == kind }.count
    }

    /// Records the restore writes in `section`.
    public func changeCount(_ section: LibraryRestoreSection) -> Int {
        entries.filter { (entry: LibraryRestoreEntry) -> Bool in entry.section == section && entry.changesLibrary && entry.key != "show" }.count
    }

    public var clashCount: Int { entries.filter { (entry: LibraryRestoreEntry) -> Bool in entry.kind == .clash }.count }

    /// The folders the install builds and swaps.
    public var changedFolders: [LibraryFolders.Folder] {
        var folders: [LibraryFolders.Folder] = []
        if showMode == .exact || (showMode == .merge && (scenePlan?.actions.isEmpty == false)) { folders.append(.show) }
        if currentScene != nil { folders.append(.currentScene) }
        if !presetsToAdd.isEmpty || !presetsToReplace.isEmpty { folders.append(.presets) }
        if collections != nil || presetTags != nil || presetOverrides != nil { folders.append(.collections) }
        if !photosToWrite.isEmpty { folders.append(.photos) }
        return folders
    }
}

public enum LibraryRestorePlanner {
    public static func plan(backup: LibraryContents, library: LibraryContents, choice: LibraryRestoreChoice = .keepBoth,
                            overrides: [String: LibraryRestoreChoice] = [:]) -> LibraryRestorePlan {
        var builder = Builder(choice: choice, overrides: overrides)
        builder.planShow(backup: backup, library: library)
        builder.planCurrentScene(backup: backup, library: library)
        builder.planPresets(backup: backup, library: library)
        builder.planCollections(backup: backup, library: library)
        builder.planTags(backup: backup, library: library)
        builder.planOverrides(backup: backup, library: library)
        builder.planSettings(backup: backup, library: library)
        builder.planPhotos(backup: backup, library: library)
        var plan = LibraryRestorePlan(choice: choice, overrides: overrides, libraryDigest: libraryDigest(library),
                                      backupDigest: LibraryRecords(backup).digest, refusal: builder.refusal, entries: builder.entries,
                                      showMode: builder.showMode, scenePlan: builder.scenePlan, presetsToAdd: builder.presetsToAdd,
                                      presetsToReplace: builder.presetsToReplace, collections: builder.collections,
                                      currentScene: builder.currentScene, photosToWrite: builder.photos, settingsToApply: builder.settings)
        plan.presetTags = builder.presetTags
        plan.presetOverrides = builder.presetOverrides
        return plan
    }

    /// A plan that installs nothing (the library could not be read, or an interrupted restore).
    public static func refused(_ refusal: LibraryRestoreRefusal, choice: LibraryRestoreChoice,
                               overrides: [String: LibraryRestoreChoice]) -> LibraryRestorePlan {
        LibraryRestorePlan(choice: choice, overrides: overrides, libraryDigest: "", backupDigest: "", refusal: refusal, entries: [],
                           showMode: .none, scenePlan: nil, presetsToAdd: [], presetsToReplace: [], collections: nil, currentScene: nil,
                           photosToWrite: [:], settingsToApply: [:])
    }

    /// The library's records plus the records it keeps out of backups (they still take identifiers).
    static func libraryDigest(_ library: LibraryContents) -> String {
        var lines: [String] = [LibraryRecords(library).digest]
        for record in library.otherPresets { lines.append(record.id + " " + record.sha256 + " " + record.name) }
        return PortableSHA256.hex(Array(lines.joined(separator: "\n").utf8))
    }

    /// Backup scenes in show order, then the rest by ID (FILE-004 cues are appended in this order).
    static func sceneDocuments(_ backup: LibraryContents) -> [SceneDocument] {
        var order: [String] = []
        if let show = backup.show, let list = try? ShowCueList.decode(show).list {
            for id in list.sceneIDs where backup.scenes[id] != nil && !order.contains(id) { order.append(id) }
        }
        for id in backup.scenes.keys.sorted() where !order.contains(id) { order.append(id) }
        return order.compactMap { (id: String) -> SceneDocument? in
            guard let bytes = backup.scenes[id] else { return nil }
            return try? SceneDocument.decode([UInt8](bytes)).document
        }
    }

    /// Research FILE-005-D5: `user/` + 32 hex of SHA-256("FILE-005|preset|<id>|<sha256>|<n>").
    public static func derivedPresetID(_ id: String, textSHA256: String, avoiding taken: Set<String>) -> String {
        var number = 1
        while true {
            let seed: String = "FILE-005|preset|" + id + "|" + textSHA256 + "|" + String(number)
            let candidate: String = UserPreset.idPrefix + String(PortableSHA256.hex(Array(seed.utf8)).prefix(32))
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// Research FILE-005-D5: an uppercase UUID from SHA-256("FILE-005|collection|<id>|<content sha256>|<n>").
    public static func derivedCollectionID(_ id: String, contentSHA256: String, avoiding taken: Set<String>) -> String {
        var number = 1
        while true {
            let seed: String = "FILE-005|collection|" + id + "|" + contentSHA256 + "|" + String(number)
            let candidate: String = ShowSceneImportPlanner.derivedUUID(seed).uuidString
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// "<name> copy", "<name> copy 2", … whose PRE-007 name key is not taken; at most 60 characters.
    public static func collectionCopyName(_ name: String, takenKeys: Set<String>) -> String {
        var number = 1
        while true {
            let suffix: String = number == 1 ? " copy" : " copy " + String(number)
            let room: Int = PresetCollectionLimits.maxNameLength - suffix.count
            let base: String = String(name.prefix(room)).trimmingCharacters(in: .whitespaces)
            let candidate: String = (base.isEmpty ? "Collection" : base) + suffix
            if !takenKeys.contains(PresetCollectionName.key(candidate)) { return candidate }
            number += 1
        }
    }
}

/// The planner's working state (one pass per section).
private struct Builder {
    let choice: LibraryRestoreChoice
    let overrides: [String: LibraryRestoreChoice]
    var entries: [LibraryRestoreEntry] = []
    var refusal: LibraryRestoreRefusal?
    var showMode: LibraryShowMode = .none
    var scenePlan: ShowSceneImportPlan?
    var presetsToAdd: [LibraryPreset] = []
    var presetsToReplace: [LibraryPreset] = []
    var collections: [PresetCollection]?
    var presetTags: PresetTagMap?
    var presetOverrides: PresetOverrideMap?
    var currentScene: Data?
    var photos: [String: Data] = [:]
    var settings: [String: LibrarySettingValue] = [:]

    init(choice: LibraryRestoreChoice, overrides: [String: LibraryRestoreChoice]) {
        self.choice = choice
        self.overrides = overrides
    }

    func choice(for key: String) -> LibraryRestoreChoice { overrides[key] ?? choice }

    mutating func add(_ key: String, _ section: LibraryRestoreSection, _ kind: LibraryRecordKind, _ action: LibraryRestoreAction,
                      choice: LibraryRestoreChoice? = nil, fellBack: Bool = false) {
        entries.append(LibraryRestoreEntry(key: key, section: section, kind: kind, choice: choice, action: action, fellBack: fellBack))
    }

    mutating func refuse(_ reason: LibraryRestoreRefusal) {
        if refusal == nil { refusal = reason }
    }

    // MARK: Show and scenes

    mutating func planShow(backup: LibraryContents, library: LibraryContents) {
        guard backup.show != nil || !backup.scenes.isEmpty else { return }
        if library.showIsEmpty {
            planExactShow(backup: backup, library: library)
        } else {
            planMergedShow(backup: backup, library: library)
        }
    }

    private mutating func planExactShow(backup: LibraryContents, library: LibraryContents) {
        if let show = backup.show {
            if show == library.show {
                add("show", .scenes, .identical, .keep)
            } else {
                add("show", .scenes, .new, .add)
                showMode = .exact
            }
        }
        for id in backup.scenes.keys.sorted() {
            add("scene/" + id, .scenes, .new, .add)
            showMode = .exact
        }
    }

    private mutating func planMergedShow(backup: LibraryContents, library: LibraryContents) {
        let documents = LibraryRestorePlanner.sceneDocuments(backup)
        guard !documents.isEmpty else { return }
        var stored: [ShowStoredSceneSummary] = []
        for id in library.scenes.keys.sorted() {
            guard let bytes = library.scenes[id] else { continue }
            let name: String? = (try? SceneDocument.decode([UInt8](bytes)).document.name) ?? nil
            stored.append(ShowStoredSceneSummary(id: id, name: name, contentSHA256: PortableSHA256.hex(bytes)))
        }
        let list: ShowCueList = library.show.flatMap { (data: Data) -> ShowCueList? in try? ShowCueList.decode(data).list } ?? ShowCueList()
        var sceneOverrides: [String: ShowSceneImportChoice] = [:]
        for (key, value) in overrides where key.hasPrefix("scene/") { sceneOverrides[String(key.dropFirst(6))] = value.sceneChoice }
        let plan = ShowSceneImportPlanner.plan(incoming: documents, stored: stored, show: list, libraryDigest: "",
                                               defaultChoice: choice.sceneChoice, overrides: sceneOverrides)
        scenePlan = plan
        showMode = .merge
        if let refused = plan.refusal { refuse(.scenes(refused.message)) }
        for entry in plan.entries {
            let key = "scene/" + entry.incomingID
            switch entry.kind {
            case .new:
                add(key, .scenes, .new, entry.install.map { (action: ShowSceneImportAction) -> LibraryRestoreAction in
                    action.sceneID == entry.incomingID && action.name == entry.incomingName ? .add : .addCopy(id: action.sceneID, name: action.name)
                } ?? .keep)
            case .identical:
                add(key, .scenes, .identical, .keep)
            case .idConflict:
                let picked: LibraryRestoreChoice = choice(for: key)
                let action: LibraryRestoreAction
                if let install = entry.install {
                    action = install.replaces ? .replace : .addCopy(id: install.sceneID, name: install.name)
                } else {
                    action = .keep
                }
                add(key, .scenes, .clash, action, choice: picked, fellBack: entry.fellBack)
            }
        }
    }

    // MARK: Current scene

    mutating func planCurrentScene(backup: LibraryContents, library: LibraryContents) {
        guard let incoming = backup.currentScene else { return }
        let key = "current-scene"
        guard let existing = library.currentScene else {
            add(key, .currentScene, .new, .add)
            currentScene = incoming
            return
        }
        if existing == incoming {
            add(key, .currentScene, .identical, .keep)
            return
        }
        let picked = choice(for: key)
        switch picked {
        case .replace:
            add(key, .currentScene, .clash, .replace, choice: picked)
            currentScene = incoming
        case .skip:
            add(key, .currentScene, .clash, .keep, choice: picked)
        case .keepBoth:
            add(key, .currentScene, .clash, .keep, choice: picked, fellBack: true)
        }
    }

    // MARK: Presets

    mutating func planPresets(backup: LibraryContents, library: LibraryContents) {
        guard !backup.presets.isEmpty else { return }
        var comparable: [String: LibraryPreset] = [:]
        for preset in library.presets { comparable[preset.record.id] = preset }
        var others: Set<String> = []
        for record in library.otherPresets { others.insert(record.id) }
        var takenIDs: Set<String> = Set(comparable.keys).union(others)
        var takenHashes: Set<String> = Set(library.presets.map { (p: LibraryPreset) -> String in p.record.sha256 })
            .union(library.otherPresets.map { (r: UserPreset) -> String in r.sha256 })
        var names: [String] = library.presets.map { (p: LibraryPreset) -> String in p.record.name }
            + library.otherPresets.map { (r: UserPreset) -> String in r.name }
        func nameTaken(_ name: String, except: String?) -> Bool {
            let lowered = name.lowercased()
            let exceptLowered = except?.lowercased()
            return names.contains { (n: String) -> Bool in n.lowercased() == lowered && n.lowercased() != exceptLowered }
        }
        for incoming in backup.presets {
            let id = incoming.record.id
            let key = "preset/" + id
            let hash = incoming.record.sha256
            guard takenIDs.contains(id) else {
                if takenHashes.contains(hash) {
                    add(key, .presets, .identical, .keep)   // the same text is already stored
                    continue
                }
                var added = incoming
                let renamed = nameTaken(incoming.record.name, except: nil)
                if renamed { added.record.name = UserPresetName.copyName(of: incoming.record.name, taken: names) }
                add(key, .presets, .new, renamed ? .addCopy(id: id, name: added.record.name) : .add)
                presetsToAdd.append(added)
                takenIDs.insert(id)
                takenHashes.insert(hash)
                names.append(added.record.name)
                continue
            }
            if let existing = comparable[id], LibraryRecords.presetDigest(existing) == LibraryRecords.presetDigest(incoming) {
                add(key, .presets, .identical, .keep)
                continue
            }
            let picked = choice(for: key)
            let existingHash: String? = comparable[id]?.record.sha256
            let hashUsedElsewhere: Bool = takenHashes.contains(hash) && existingHash != hash
            var effective = picked
            var fellBack = false
            if effective == .replace && comparable[id] == nil {   // the target is kept out of backups: Keep both
                effective = .keepBoth
                fellBack = true
            }
            switch effective {
            case .skip:
                add(key, .presets, .clash, .keep, choice: picked, fellBack: fellBack)
            case .replace:
                if hashUsedElsewhere {
                    add(key, .presets, .clash, .keep, choice: picked, fellBack: true)
                    continue
                }
                var replacement = incoming
                let oldName: String? = comparable[id]?.record.name
                if nameTaken(incoming.record.name, except: oldName) {
                    replacement.record.name = UserPresetName.copyName(of: incoming.record.name, taken: names)
                }
                add(key, .presets, .clash, .replace, choice: picked)
                presetsToReplace.append(replacement)
                takenHashes.insert(hash)
                if let oldName, let index = names.firstIndex(of: oldName) { names.remove(at: index) }
                names.append(replacement.record.name)
            case .keepBoth:
                if takenHashes.contains(hash) {
                    add(key, .presets, .clash, .keep, choice: picked, fellBack: true)
                    continue
                }
                var copy = incoming
                copy.record.id = LibraryRestorePlanner.derivedPresetID(id, textSHA256: hash, avoiding: takenIDs)
                if nameTaken(incoming.record.name, except: nil) {
                    copy.record.name = UserPresetName.copyName(of: incoming.record.name, taken: names)
                }
                add(key, .presets, .clash, .addCopy(id: copy.record.id, name: copy.record.name), choice: picked, fellBack: fellBack)
                presetsToAdd.append(copy)
                takenIDs.insert(copy.record.id)
                takenHashes.insert(hash)
                names.append(copy.record.name)
            }
        }
        let quarantined: Int = library.otherPresets.filter { (r: UserPreset) -> Bool in r.state == .quarantined }.count
        let total: Int = library.presets.count + library.otherPresets.count - quarantined + presetsToAdd.count
        if total > PresetImportLimits.maxUserPresets { refuse(.tooManyPresets(limit: PresetImportLimits.maxUserPresets)) }
    }

    // MARK: Collections

    mutating func planCollections(backup: LibraryContents, library: LibraryContents) {
        guard let incoming = backup.collections, !incoming.isEmpty else { return }
        var list: [PresetCollection] = library.collections ?? []
        var changed = false
        func keys(except index: Int?) -> Set<String> {
            var result: Set<String> = []
            for (i, collection) in list.enumerated() where i != index { result.insert(PresetCollectionName.key(collection.name)) }
            return result
        }
        for collection in incoming {
            let key = "collection/" + collection.id
            guard let index = list.firstIndex(where: { (c: PresetCollection) -> Bool in c.id == collection.id }) else {
                var added = collection
                let taken = keys(except: nil)
                let renamed = taken.contains(PresetCollectionName.key(collection.name))
                if renamed { added.name = LibraryRestorePlanner.collectionCopyName(collection.name, takenKeys: taken) }
                add(key, .collections, .new, renamed ? .addCopy(id: added.id, name: added.name) : .add)
                list.append(added)
                changed = true
                continue
            }
            if list[index] == collection {
                add(key, .collections, .identical, .keep)
                continue
            }
            let picked = choice(for: key)
            switch picked {
            case .skip:
                add(key, .collections, .clash, .keep, choice: picked)
            case .replace:
                var replacement = collection
                let taken = keys(except: index)
                if taken.contains(PresetCollectionName.key(collection.name)) {
                    replacement.name = LibraryRestorePlanner.collectionCopyName(collection.name, takenKeys: taken)
                }
                list[index] = replacement
                add(key, .collections, .clash, .replace, choice: picked)
                changed = true
            case .keepBoth:
                let content = (try? PresetCollectionsFile(collections: [collection]).encode()) ?? Data()
                let ids = Set(list.map { (c: PresetCollection) -> String in c.id })
                let newID = LibraryRestorePlanner.derivedCollectionID(collection.id, contentSHA256: PortableSHA256.hex(content), avoiding: ids)
                let taken = keys(except: nil)
                let name: String = taken.contains(PresetCollectionName.key(collection.name))
                    ? LibraryRestorePlanner.collectionCopyName(collection.name, takenKeys: taken) : collection.name
                list.append(PresetCollection(id: newID, name: name, presetIDs: collection.presetIDs))
                add(key, .collections, .clash, .addCopy(id: newID, name: name), choice: picked)
                changed = true
            }
        }
        if list.count > PresetCollectionLimits.maxCollections { refuse(.tooManyCollections(limit: PresetCollectionLimits.maxCollections)) }
        if changed { collections = list }
    }

    // MARK: Preset tags (PRE-003)

    /// The identifier a backup preset ends up under: a Keep-both copy's derived one, else its own.
    private func restoredPresetID(_ id: String) -> String {
        for entry in entries where entry.key == "preset/" + id {
            if case let .addCopy(newID, _) = entry.action { return newID }
        }
        return id
    }

    mutating func planTags(backup: LibraryContents, library: LibraryContents) {
        guard let incoming = backup.presetTags, !incoming.isEmpty else { return }
        var map: PresetTagMap = library.presetTags ?? PresetTagMap()
        var changed = false
        for backupID in incoming.tags.keys.sorted() {
            let theirs: [String] = incoming.tags(of: backupID)
            let id: String = restoredPresetID(backupID)
            let key = "tags/" + backupID
            let mine: [String] = map.tags(of: id)
            if mine.isEmpty {
                let (merged, dropped) = Self.adding(theirs, to: map, id: id)
                add(key, .tags, .new, .add, fellBack: dropped)
                changed = changed || merged != map
                map = merged
                continue
            }
            if Set(mine.map(PresetTagMap.fold)) == Set(theirs.map(PresetTagMap.fold)) {
                add(key, .tags, .identical, .keep)
                continue
            }
            let picked = choice(for: key)
            switch picked {
            case .skip:
                add(key, .tags, .clash, .keep, choice: picked)
            case .replace:
                var cleared = map
                cleared.prune(id)
                let (merged, dropped) = Self.adding(theirs, to: cleared, id: id)
                add(key, .tags, .clash, .replace, choice: picked, fellBack: dropped)
                changed = true
                map = merged
            case .keepBoth:
                let (merged, dropped) = Self.adding(theirs, to: map, id: id)
                add(key, .tags, .clash, merged == map ? .keep : .union, choice: picked, fellBack: dropped)
                changed = changed || merged != map
                map = merged
            }
        }
        if changed { presetTags = map }
    }

    /// `map` with `tags` added to `id` under every PRE-003 rule; true when any had to be left out.
    private static func adding(_ tags: [String], to map: PresetTagMap, id: String) -> (PresetTagMap, Bool) {
        var result = map
        var dropped = false
        for tag in tags {
            do {
                try result.add(tag, to: id)
            } catch .alreadyTagged {
                continue
            } catch {
                dropped = true
            }
        }
        return (result, dropped)
    }

    // MARK: Preset overrides (PRE-016)

    mutating func planOverrides(backup: LibraryContents, library: LibraryContents) {
        guard let incoming = backup.presetOverrides, !incoming.isEmpty else { return }
        var map: PresetOverrideMap = library.presetOverrides ?? PresetOverrideMap()
        var changed = false
        for backupID in incoming.values.keys.sorted() {
            let theirs: [String: Double] = incoming.overrides(for: backupID)
            let id: String = restoredPresetID(backupID)
            let key = "overrides/" + backupID
            let mine: [String: Double] = map.overrides(for: id)
            if mine == theirs {
                add(key, .overrides, .identical, .keep)
                continue
            }
            let picked: LibraryRestoreChoice = choice(for: key)
            if !mine.isEmpty, picked == .skip {
                add(key, .overrides, .clash, .keep, choice: picked)
                continue
            }
            var merged: PresetOverrideMap = map
            if !mine.isEmpty, picked == .replace { merged.reset(id) }
            var dropped = false
            for name in theirs.keys.sorted() {
                guard let value = theirs[name] else { continue }
                if !mine.isEmpty, picked == .keepBoth, mine[name] != nil { continue }   // the device's value wins
                do { try merged.set(value, for: name, preset: id) } catch { dropped = true }
            }
            if mine.isEmpty {
                add(key, .overrides, .new, .add, fellBack: dropped)
            } else if picked == .replace {
                add(key, .overrides, .clash, .replace, choice: picked, fellBack: dropped)
            } else {
                add(key, .overrides, .clash, merged == map ? .keep : .union, choice: picked, fellBack: dropped)
            }
            changed = changed || merged != map
            map = merged
        }
        if changed { presetOverrides = map }
    }

    // MARK: Settings

    mutating func planSettings(backup: LibraryContents, library: LibraryContents) {
        for name in backup.settings.keys.sorted() {
            guard let incoming = backup.settings[name] else { continue }
            let key = "setting/" + name
            guard let existing = library.settings[name] else {
                add(key, .settings, .new, .add)
                settings[name] = incoming
                continue
            }
            if existing == incoming {
                add(key, .settings, .identical, .keep)
                continue
            }
            let picked = choice(for: key)
            switch picked {
            case .replace:
                add(key, .settings, .clash, .replace, choice: picked)
                settings[name] = incoming
            case .skip:
                add(key, .settings, .clash, .keep, choice: picked)
            case .keepBoth:
                if name == LibrarySettingsPolicy.favoritesKey, case let .strings(mine) = existing, case let .strings(theirs) = incoming {
                    let union: [String] = Array(Set(mine).union(theirs)).sorted()
                    if union == mine {
                        add(key, .settings, .clash, .keep, choice: picked)
                    } else {
                        add(key, .settings, .clash, .union, choice: picked)
                        settings[name] = .strings(union)
                    }
                } else {
                    add(key, .settings, .clash, .keep, choice: picked, fellBack: true)
                }
            }
        }
    }

    // MARK: Photos

    mutating func planPhotos(backup: LibraryContents, library: LibraryContents) {
        for name in backup.photos.keys.sorted() {
            guard let incoming = backup.photos[name] else { continue }
            let key = "photo/" + name
            guard let existing = library.photos[name] else {
                add(key, .photos, .new, .add)
                photos[name] = incoming
                continue
            }
            if existing == incoming {
                add(key, .photos, .identical, .keep)
                continue
            }
            let picked = choice(for: key)
            switch picked {
            case .replace:
                add(key, .photos, .clash, .replace, choice: picked)
                photos[name] = incoming
            case .skip:
                add(key, .photos, .clash, .keep, choice: picked)
            case .keepBoth:
                add(key, .photos, .clash, .keep, choice: picked, fellBack: true)
            }
        }
        let total: Int = Set(library.photos.keys).union(photos.keys).count
        if total > LibraryBackupFormat.maxPhotos { refuse(.library(.tooManyPhotos(limit: LibraryBackupFormat.maxPhotos))) }
    }
}
