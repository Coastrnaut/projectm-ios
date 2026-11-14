// PresetIntegrityScanner.swift — roadmap PRE-018 (R3-R5, R14; research D5, D7): turns a user preset
// inventory and a reference snapshot into a report. Pure and deterministic: it reads nothing and
// changes nothing, so it runs anywhere (the app runs it in a detached utility task).
import Foundation

/// What `UserPresetLibrary.integrityInventory` found about one waiting or playable user preset.
public struct UserPresetIntegrityEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    /// The stored file exists with the record's size and SHA-256.
    public var fileIntact: Bool
    /// `sampler_<name>` textures neither the engine nor the app has (empty when the file is not intact).
    public var missingTextures: [String]
    /// The static checks' reason when the stored text no longer passes them.
    public var rejection: String?
    /// The bundled preset this unedited copy was made from (PRE-015), when its bytes could restore it.
    public var libraryOriginID: String?

    public init(id: String, name: String, fileIntact: Bool, missingTextures: [String] = [], rejection: String? = nil,
                libraryOriginID: String? = nil) {
        self.id = id; self.name = name; self.fileIntact = fileIntact; self.missingTextures = missingTextures
        self.rejection = rejection; self.libraryOriginID = libraryOriginID
    }
}

/// The user preset side of a check.
public struct UserPresetIntegrityInventory: Sendable, Equatable {
    public var entries: [UserPresetIntegrityEntry]
    /// Every user preset record's ID, in any state (R4).
    public var knownIDs: Set<String>
    /// False when the saved list is from a newer app version (not read).
    public var available: Bool
    /// A bound stopped the inventory (R14).
    public var incomplete: Bool

    public init(entries: [UserPresetIntegrityEntry], knownIDs: Set<String>, available: Bool = true, incomplete: Bool = false) {
        self.entries = entries; self.knownIDs = knownIDs; self.available = available; self.incomplete = incomplete
    }

    public static let empty = UserPresetIntegrityInventory(entries: [], knownIDs: [])
}

public enum PresetIntegrityScanner {
    /// `isBuiltIn`: whether the bundled library (any pack, locked or not) has this ID.
    public static func scan(inventory: UserPresetIntegrityInventory, references: PresetReferenceSnapshot,
                            isBuiltIn: (String) -> Bool, limits: PresetIntegrityLimits = .standard) -> PresetIntegrityReport {
        var issues: [PresetIntegrityIssue] = []
        var incomplete = inventory.incomplete
        for entry in inventory.entries { issues += presetIssues(entry, isBuiltIn: isBuiltIn, limits: limits) }

        func known(_ id: String) -> Bool {
            if isBuiltIn(id) || inventory.knownIDs.contains(id) { return true }
            // R4, research D5: never judge a user preset ID while the user preset list cannot be read.
            return !inventory.available && id.hasPrefix(UserPreset.idPrefix)
        }
        var counted = 0
        var seen: Set<String> = []
        func visit(_ id: String, _ store: PresetReferenceStore, _ collection: PresetReferenceSnapshot.Collection? = nil) -> Bool {
            guard counted < limits.maxReferences else {
                incomplete = true
                return false
            }
            counted += 1
            guard !known(id) else { return true }
            let issue = PresetIntegrityIssue(kind: .danglingReference, presetID: id, store: store, collectionID: collection?.id,
                                             collectionName: collection?.name, actions: [.removeReference])
            if seen.insert(issue.id).inserted { issues.append(issue) }
            return true
        }
        let flat: [(PresetReferenceStore, [String])] = [(.favorites, references.favorites), (.tags, references.tags),
                                                        (.overrides, references.overrides)]
        outer: for (store, ids) in flat {
            for id in ids where !visit(id, store) { break outer }
        }
        collections: for collection in references.collections {
            for id in collection.presetIDs where !visit(id, .collections, collection) { break collections }
        }
        for id in references.recents where !visit(id, .recents) { break }

        issues.sort(by: ordered)
        if issues.count > limits.maxIssues {
            issues.removeLast(issues.count - limits.maxIssues)
            incomplete = true
        }
        return PresetIntegrityReport(issues: issues, presetsChecked: inventory.entries.count, referencesChecked: counted,
                                     incomplete: incomplete, userPresetsUnavailable: !inventory.available)
    }

    private static func presetIssues(_ entry: UserPresetIntegrityEntry, isBuiltIn: (String) -> Bool,
                                     limits: PresetIntegrityLimits) -> [PresetIntegrityIssue] {
        guard entry.fileIntact else {
            var actions: [PresetIntegrityAction] = [.relinkFile]
            if let origin = entry.libraryOriginID, isBuiltIn(origin) { actions.append(.restoreFromLibrary) }
            actions.append(.removePreset)
            return [PresetIntegrityIssue(kind: .missingFile, presetID: entry.id, presetName: entry.name, actions: actions)]
        }
        if let rejection = entry.rejection {
            // Quarantine also settles any texture of this preset, so only the one issue is listed.
            return [PresetIntegrityIssue(kind: .unparsable, presetID: entry.id, presetName: entry.name, detail: rejection,
                                         actions: [.moveToQuarantine, .removePreset])]
        }
        let textures: [String] = Array(Set(entry.missingTextures)).sorted().prefix(limits.maxTexturesPerPreset).map { $0 }
        return textures.map { (texture: String) -> PresetIntegrityIssue in
            PresetIntegrityIssue(kind: .missingTexture, presetID: entry.id, presetName: entry.name, detail: texture,
                                 actions: [.moveToQuarantine, .removePreset])
        }
    }

    /// R5: kind, then the preset's name or ID, then detail, store and collection.
    static func ordered(_ a: PresetIntegrityIssue, _ b: PresetIntegrityIssue) -> Bool {
        if a.kind != b.kind { return a.kind < b.kind }
        let nameA: String = a.presetName ?? a.presetID
        let nameB: String = b.presetName ?? b.presetID
        if nameA != nameB { return nameA < nameB }
        if (a.detail ?? "") != (b.detail ?? "") { return (a.detail ?? "") < (b.detail ?? "") }
        if a.store != b.store, let sa = a.store, let sb = b.store { return sa < sb }
        return a.id < b.id
    }
}
