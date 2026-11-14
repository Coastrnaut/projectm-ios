// PresetArchiveImportPlan.swift — FILE-003 (specs/105-file-003-import-dry-run; FILE-003-R2-R7,
// contract C1): the dry run of a user preset archive. `PresetArchiveImportPlanner.plan` is pure: it
// reads the archive bytes (PRE-014's verifying reader), the library's records and the import
// context, and returns what an install would do. Nothing is written, no clock or default is read,
// and equal inputs give equal plans (Keep both's identifiers are derived, research FILE-003-D3), so
// the install re-validates with `==` (FILE-003-R8).
//
// Classification per preset, in archive order (first match wins):
//   1. same text as a quarantined file → refused (inQuarantine)
//   2. same text as another library preset → identical (skipped)
//   3. on the takedown list → refused (blocked)
//   4. same text as a built-in preset (copies of Included presets excepted) → refused (builtIn)
//   5. fails the static checks → refused (failsChecks); never quarantined from an archive
//   6. identifier used by a different library preset → idConflict
//   7. name used by a library preset or an earlier planned one (any case) → nameConflict
//   8. otherwise → new
// Capacity: entries that would install beyond the 1,000-preset limit are refused (libraryFull).
//
// FILE-004 (specs/111-file-004-import-conflict-resolver; FILE-004-R1-R5, contract C1): each conflict
// has a choice, `overrides[incomingID] ?? policy` (the plan-wide default, "Apply to all"):
//   skip     → no action; keepBoth → FILE-003 (derived id, copy name);
//   replace  → the library preset with that id (ID conflict) or name (name conflict) keeps its id and
//              takes the incoming text and name (a copy name when the name is taken by another);
//              no library target, or one already replaced → Keep both with `fellBack` (research D6).
import Foundation
import LocalPortability

/// What happens to a preset whose identifier or name is taken (FILE-003-R6, FILE-004-R1).
public enum PresetArchiveConflictPolicy: String, Sendable, Equatable, CaseIterable {
    /// Install it under a new identifier and, when its name is taken, "<name> copy". The default.
    case keepBoth
    /// Leave it out.
    case skip
    /// FILE-004: the clashing library preset keeps its identifier and takes the incoming text and name.
    case replace
}

/// Why one preset of an accepted archive is not installed.
public enum PresetArchiveRefusal: Sendable, Equatable {
    case inQuarantine(name: String)
    case blocked
    case builtIn(name: String, pack: String)
    case failsChecks(String)
    case libraryFull

    public var message: String {
        switch self {
        case .inQuarantine: return "The same file is in Quarantine."
        case .blocked: return PresetImportRefusal.blocked.message
        case .builtIn(let name, let pack): return PresetImportRefusal.duplicateOfBuiltIn(name: name, pack: pack).message
        case .failsChecks(let reason): return "It failed a safety check: \(reason)"
        case .libraryFull: return PresetImportRefusal.libraryFull.message
        }
    }
}

public enum PresetArchiveEntryKind: Sendable, Equatable {
    case new
    /// The same text is already in My Presets under this name.
    case identical(existingName: String)
    case nameConflict(existingName: String)
    case idConflict(existingName: String)
    case refused(PresetArchiveRefusal)
}

/// One preset the install adds, with its final identifier and name.
public struct PresetArchiveAction: Sendable, Equatable {
    public let id: String
    public let name: String
    /// FILE-004: the identifier of the library preset this replaces (then equal to `id`), or nil.
    public let replacesID: String?

    public init(id: String, name: String, replacesID: String? = nil) {
        self.id = id
        self.name = name
        self.replacesID = replacesID
    }
}

public struct PresetArchivePlanEntry: Sendable, Equatable {
    public let incomingID: String
    public let incomingName: String
    public let sha256: String
    public let byteCount: Int
    public let kind: PresetArchiveEntryKind
    /// Nil when the preset is skipped or refused.
    public let install: PresetArchiveAction?
    /// Licence lines were found in the text, or it is a copy of an Included preset (pack statement).
    public let hasLicense: Bool
    /// FILE-004: the effective choice for a conflict; nil otherwise.
    public let choice: PresetArchiveConflictPolicy?
    /// FILE-004: the library preset (id and name before the import) that Replace overwrites.
    public let replaces: PresetArchiveAction?
    /// FILE-004-R4: Replace was chosen but had no library target, so the preset installs as Keep both.
    public let fellBack: Bool

    public var isConflict: Bool {
        switch kind {
        case .nameConflict, .idConflict: return true
        default: return false
        }
    }
}

public struct PresetArchiveCounts: Sendable, Equatable {
    public var new = 0
    public var identical = 0
    public var nameConflicts = 0
    public var idConflicts = 0
    public var refused = 0
    public var toInstall = 0

    public init() {}

    public var conflicts: Int { nameConflicts + idConflicts }
}

public struct PresetArchiveImportPlan: Sendable, Equatable {
    /// SHA-256 of the archive's bytes.
    public let archiveSHA256: String
    /// The default choice for every conflict ("Apply to all").
    public let policy: PresetArchiveConflictPolicy
    /// FILE-004: per-conflict choices by incoming identifier, as given (re-validation compares them).
    public let overrides: [String: PresetArchiveConflictPolicy]
    /// The reason the whole archive is refused; then `entries` is empty.
    public let refusal: String?
    /// In archive order.
    public let entries: [PresetArchivePlanEntry]

    public init(archiveSHA256: String, policy: PresetArchiveConflictPolicy, overrides: [String: PresetArchiveConflictPolicy] = [:],
                refusal: String?, entries: [PresetArchivePlanEntry]) {
        self.archiveSHA256 = archiveSHA256
        self.policy = policy
        self.overrides = overrides
        self.refusal = refusal
        self.entries = entries
    }

    /// The choice that applies to the entry with this incoming identifier when it is a conflict.
    public func choice(for incomingID: String) -> PresetArchiveConflictPolicy { overrides[incomingID] ?? policy }

    /// FILE-004: how many library presets the install replaces.
    public var replaceCount: Int {
        var count = 0
        for entry in entries where entry.install?.replacesID != nil { count += 1 }
        return count
    }

    public var counts: PresetArchiveCounts {
        var counts = PresetArchiveCounts()
        for entry in entries {
            switch entry.kind {
            case .new: counts.new += 1
            case .identical: counts.identical += 1
            case .nameConflict: counts.nameConflicts += 1
            case .idConflict: counts.idConflicts += 1
            case .refused: counts.refused += 1
            }
            if entry.install != nil { counts.toInstall += 1 }
        }
        return counts
    }

    /// Final names of the presets to install that carry no licence information (FILE-003-R5).
    public var missingLicense: [String] {
        entries.compactMap { (entry: PresetArchivePlanEntry) -> String? in
            guard let install = entry.install, !entry.hasLicense else { return nil }
            return install.name
        }
    }

    /// Bytes of the texts to install.
    public var totalBytes: Int {
        var total = 0
        for entry in entries where entry.install != nil { total += entry.byteCount }
        return total
    }

    /// What the install adds, in archive order.
    public var actions: [PresetArchiveAction] { entries.compactMap(\.install) }

    public var hasConflicts: Bool { entries.contains(where: \.isConflict) }
    public var canInstall: Bool { refusal == nil && !actions.isEmpty }
}

public enum PresetArchiveImportPlanner {
    /// The dry run (contract C1). `library` is every stored record, any state.
    public static func plan(archive data: Data, library: [UserPreset], context: PresetImportContext,
                            policy: PresetArchiveConflictPolicy = .keepBoth,
                            overrides: [String: PresetArchiveConflictPolicy] = [:]) -> PresetArchiveImportPlan {
        let archiveHash = ContentHash.sha256Hex([UInt8](data))
        let archive: UserPresetArchive
        do {
            archive = try UserPresetArchiveReader.read(data)
        } catch let error as UserPresetArchiveError {
            return PresetArchiveImportPlan(archiveSHA256: archiveHash, policy: policy, overrides: overrides, refusal: error.message, entries: [])
        } catch {
            return PresetArchiveImportPlan(archiveSHA256: archiveHash, policy: policy, overrides: overrides,
                                           refusal: UserPresetArchiveError.archive(.malformedManifest).message, entries: [])
        }

        var bySHA: [String: UserPreset] = [:]
        var byID: [String: UserPreset] = [:]
        var takenNames: [String] = []
        var takenIDs: Set<String> = []
        for preset in library {
            if bySHA[preset.sha256] == nil { bySHA[preset.sha256] = preset }
            byID[preset.id] = preset
            takenIDs.insert(preset.id)
            if preset.state != .quarantined { takenNames.append(preset.name) }
        }
        var namesByLowercase: [String: String] = [:]
        for name in takenNames where namesByLowercase[name.lowercased()] == nil { namesByLowercase[name.lowercased()] = name }
        // FILE-004: library presets by lowercase name (not quarantined, library order) for Replace targets
        // and "taken by another"; names planned earlier in this archive; targets already replaced.
        var libraryByLowercaseName: [String: [UserPreset]] = [:]
        for preset in library where preset.state != .quarantined { libraryByLowercaseName[preset.name.lowercased(), default: []].append(preset) }
        var plannedNames: Set<String> = []
        var replacedIDs: Set<String> = []
        let active = library.filter { (preset: UserPreset) -> Bool in preset.state != .quarantined }.count
        var room = max(0, PresetImportLimits.maxUserPresets - active)

        var entries: [PresetArchivePlanEntry] = []
        entries.reserveCapacity(archive.manifest.presets.count)
        for record in archive.manifest.presets {
            let bytes = [UInt8](archive.texts[record.id] ?? Data())
            let incomingName = cleanedName(record.name)
            let validation = MilkdropPresetValidator.validate(bytes, knownTextures: context.knownTextures)
            let hasLicense = !validation.licenseLines.isEmpty || record.duplicateOf != nil
            func entry(_ kind: PresetArchiveEntryKind, _ install: PresetArchiveAction?, choice: PresetArchiveConflictPolicy? = nil,
                       replaces: PresetArchiveAction? = nil, fellBack: Bool = false) -> PresetArchivePlanEntry {
                PresetArchivePlanEntry(incomingID: record.id, incomingName: incomingName, sha256: record.sha256,
                                       byteCount: record.byteCount, kind: kind, install: install, hasLicense: hasLicense,
                                       choice: choice, replaces: replaces, fellBack: fellBack)
            }

            // 1-5: refusals and identical texts.
            if let existing = bySHA[record.sha256] {
                if existing.state == .quarantined {
                    entries.append(entry(.refused(.inQuarantine(name: existing.originalFileName)), nil))
                } else {
                    entries.append(entry(.identical(existingName: existing.name), nil))
                }
                continue
            }
            if context.blockedHashes.contains(record.blobHash) {
                entries.append(entry(.refused(.blocked), nil))
                continue
            }
            if record.duplicateOf == nil, let builtIn = context.builtIn[record.blobHash] {
                entries.append(entry(.refused(.builtIn(name: builtIn.name, pack: builtIn.pack)), nil))
                continue
            }
            if let rejection = validation.rejection {
                entries.append(entry(.refused(.failsChecks(rejection.message)), nil))
                continue
            }

            // 6-8: conflicts and new presets.
            let kind: PresetArchiveEntryKind
            let existingByName = namesByLowercase[incomingName.lowercased()]
            if let existing = byID[record.id] {
                kind = .idConflict(existingName: existing.name)
            } else if takenIDs.contains(record.id) {
                kind = .idConflict(existingName: incomingName)   // an earlier planned copy took it
            } else if let existingByName {
                kind = .nameConflict(existingName: existingByName)
            } else {
                kind = .new
            }
            let isConflict: Bool = kind != .new
            let choice: PresetArchiveConflictPolicy? = isConflict ? (overrides[record.id] ?? policy) : nil
            if choice == .skip {
                entries.append(entry(kind, nil, choice: choice))
                continue
            }
            if choice == .replace {
                if let target = replaceTarget(kind: kind, incomingID: record.id, incomingName: incomingName, byID: byID,
                                              byName: libraryByLowercaseName, replaced: replacedIDs) {
                    let takenByOther: Bool = plannedNames.contains(incomingName.lowercased())
                        || (libraryByLowercaseName[incomingName.lowercased()] ?? []).contains { (other: UserPreset) -> Bool in other.id != target.id }
                    let finalName: String = takenByOther ? UserPresetName.copyName(of: incomingName, taken: Array(namesByLowercase.values)) : incomingName
                    replacedIDs.insert(target.id)
                    namesByLowercase[finalName.lowercased()] = finalName
                    plannedNames.insert(finalName.lowercased())
                    let action = PresetArchiveAction(id: target.id, name: finalName, replacesID: target.id)
                    entries.append(entry(kind, action, choice: choice, replaces: PresetArchiveAction(id: target.id, name: target.name)))
                    continue
                }
            }
            let fellBack: Bool = choice == .replace
            guard room > 0 else {
                entries.append(entry(.refused(.libraryFull), nil))
                continue
            }
            let finalID: String = takenIDs.contains(record.id) ? derivedID(for: record, avoiding: takenIDs) : record.id
            let finalName: String = existingByName == nil ? incomingName
                : UserPresetName.copyName(of: incomingName, taken: Array(namesByLowercase.values))
            takenIDs.insert(finalID)
            namesByLowercase[finalName.lowercased()] = finalName
            if existingByName == nil { namesByLowercase[incomingName.lowercased()] = incomingName }
            plannedNames.insert(finalName.lowercased())
            room -= 1
            entries.append(entry(kind, PresetArchiveAction(id: finalID, name: finalName), choice: choice, fellBack: fellBack))
        }
        return PresetArchiveImportPlan(archiveSHA256: archiveHash, policy: policy, overrides: overrides, refusal: nil, entries: entries)
    }

    /// FILE-004 contract C1: the library preset Replace overwrites, or nil (no library target, or it is
    /// already replaced by an earlier entry). ID conflict → the preset with that id; name conflict →
    /// the first library preset (not quarantined) with that name, any case.
    static func replaceTarget(kind: PresetArchiveEntryKind, incomingID: String, incomingName: String, byID: [String: UserPreset],
                              byName: [String: [UserPreset]], replaced: Set<String>) -> UserPreset? {
        let target: UserPreset?
        switch kind {
        case .idConflict: target = byID[incomingID]
        case .nameConflict: target = byName[incomingName.lowercased()]?.first
        default: target = nil
        }
        guard let target, !replaced.contains(target.id) else { return nil }
        return target
    }

    /// The archive's name cleaned like an imported name; "Preset" when nothing is left.
    static func cleanedName(_ raw: String) -> String {
        let cleaned = UserPresetName.cleanedName(raw)
        return cleaned.isEmpty ? "Preset" : cleaned
    }

    /// Research FILE-003-D3: `user/` + 32 hex digits of SHA-256("FILE-003|<id>|<sha256>|<n>"), smallest n ≥ 1 free.
    static func derivedID(for record: ExportedUserPreset, avoiding taken: Set<String>) -> String {
        var number = 1
        while true {
            let seed = "FILE-003|" + record.id + "|" + record.sha256 + "|" + String(number)
            let candidate = UserPreset.idPrefix + String(ContentHash.sha256Hex(Array(seed.utf8)).prefix(32))
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }
}

/// How an archive install ended (FILE-003-R8-R10).
public enum PresetArchiveInstallOutcome: Sendable, Equatable {
    /// Added, waiting for their trial, in archive order.
    case installed([UserPreset])
    /// The library or archive changed since the preview: the new plan; nothing was written.
    case changed(PresetArchiveImportPlan)
    /// Nothing was written; the words say why.
    case refused(String)
}

/// The preview's and install's words (spec Clarifications; FILE-003-R8, R9, R13).
public enum PresetArchiveText {
    public static let changed = "My Presets changed since this preview. Check the new counts and install again."
    public static let nothingToInstall = "Nothing to install."
    public static let saveFailed = "The presets could not be saved."
    /// FILE-004 research D6.
    public static let heldTarget = "A preset it would replace is waiting to be set aside after an interrupted check."

    public static func nothingInstalled(_ reason: String) -> String { "Nothing was installed. " + reason }

    /// "Import preview: 3 new, 1 already in My Presets, 0 conflicts, 1 refused."
    public static func previewAnnouncement(_ plan: PresetArchiveImportPlan) -> String {
        if let refusal = plan.refusal { return "Import preview: the archive cannot be imported. " + refusal }
        let counts = plan.counts
        let conflicts: String = counts.conflicts == 1 ? "1 conflict" : "\(counts.conflicts) conflicts"
        let parts: [String] = ["\(counts.new) new", "\(counts.identical) already in My Presets", conflicts, "\(counts.refused) refused"]
        return "Import preview: " + parts.joined(separator: ", ") + "."
    }

    /// "Installed 3 presets. They are checked before they can play."
    public static func installed(_ count: Int) -> String {
        if count == 1 { return "Installed 1 preset. It is checked before it can play." }
        return "Installed \(count) presets. They are checked before they can play."
    }

    /// FILE-004-R9: "Installed 3 presets (1 replaced). They are checked before they can play."
    public static func installed(_ count: Int, replaced: Int) -> String {
        guard replaced > 0 else { return installed(count) }
        if count == 1 { return "Installed 1 preset (1 replaced). It is checked before it can play." }
        return "Installed \(count) presets (\(replaced) replaced). They are checked before they can play."
    }
}
