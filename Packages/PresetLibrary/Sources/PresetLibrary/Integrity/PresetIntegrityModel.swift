// PresetIntegrityModel.swift — roadmap PRE-018 (specs/194-pre-018-integrity-scanner; R3-R9, R14;
// data-model.md; contracts/library-integrity.md): what the library check reports and the words it uses.
// Foundation only; nothing here is stored.
import Foundation

/// A store that names presets by ID (PRE-018-R1).
public enum PresetReferenceStore: String, Sendable, CaseIterable, Comparable {
    case favorites, tags, overrides, collections, recents

    public static func < (a: Self, b: Self) -> Bool {
        (allCases.firstIndex(of: a) ?? 0) < (allCases.firstIndex(of: b) ?? 0)
    }

    /// "Favorites", "Tags", … as a list title.
    public var title: String {
        switch self {
        case .favorites: "Favorites"
        case .tags: "Tags"
        case .overrides: "Adjustments"
        case .collections: "A collection"
        case .recents: "Recently Played"
        }
    }

    /// The safe fix's button title (R9).
    public var removalTitle: String {
        switch self {
        case .favorites: "Remove from Favorites"
        case .tags: "Remove Tag Entries"
        case .overrides: "Remove Adjustments"
        case .collections: "Remove from Collection"
        case .recents: "Remove from Recently Played"
        }
    }
}

/// What a fix does (R6-R9). Only `removeReference` is safe: Fix All Safe applies nothing else.
public enum PresetIntegrityAction: String, Sendable, Hashable, CaseIterable {
    case removeReference, relinkFile, restoreFromLibrary, moveToQuarantine, removePreset

    public var isSafe: Bool { self == .removeReference }
    /// Remove Preset and Move to Quarantine ask first (R10).
    public var needsConfirmation: Bool { self == .removePreset || self == .moveToQuarantine }
}

public struct PresetIntegrityIssue: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable, Comparable {
        case missingTexture, danglingReference, missingFile, unparsable

        public static func < (a: Self, b: Self) -> Bool {
            (allCases.firstIndex(of: a) ?? 0) < (allCases.firstIndex(of: b) ?? 0)
        }

        /// Section titles on the Library Check screen.
        public var sectionTitle: String {
            switch self {
            case .missingTexture: "Missing textures"
            case .danglingReference: "Broken references"
            case .missingFile: "Missing files"
            case .unparsable: "Presets that no longer pass the checks"
            }
        }
    }

    public let kind: Kind
    public let presetID: String
    /// The record's name; nil for a dangling reference (nothing names it any more).
    public let presetName: String?
    /// Texture name (missingTexture) or the static checks' reason (unparsable).
    public let detail: String?
    public let store: PresetReferenceStore?
    public let collectionID: String?
    public let collectionName: String?
    public let actions: [PresetIntegrityAction]

    public init(kind: Kind, presetID: String, presetName: String? = nil, detail: String? = nil,
                store: PresetReferenceStore? = nil, collectionID: String? = nil, collectionName: String? = nil,
                actions: [PresetIntegrityAction]) {
        self.kind = kind; self.presetID = presetID; self.presetName = presetName; self.detail = detail
        self.store = store; self.collectionID = collectionID; self.collectionName = collectionName
        self.actions = actions
    }

    /// Unique per issue (R5).
    public var id: String {
        [kind.rawValue, store?.rawValue ?? "", collectionID ?? "", presetID, detail ?? ""].joined(separator: "|")
    }

    public var isSafe: Bool { actions.allSatisfy(\.isSafe) }

    private var label: String { presetName ?? presetID }

    public var title: String {
        switch kind {
        case .missingTexture: return "“\(label)” uses a missing texture"
        case .danglingReference:
            if store == .collections, let collectionName { return "“\(collectionName)” names a preset that no longer exists" }
            return "\(store?.title ?? "A list") names a preset that no longer exists"
        case .missingFile: return "“\(label)”: file missing or damaged"
        case .unparsable: return "“\(label)” no longer passes the checks"
        }
    }

    /// The actionable suggestion (contract words).
    public var suggestion: String {
        switch kind {
        case .missingTexture:
            return "It uses the texture “\(detail ?? "")”, which the app does not have. The app cannot import textures, "
                + "so a blank texture is drawn instead. Keep it as it is, move it to Quarantine, or remove it."
        case .danglingReference:
            return "The entry for “\(presetID)” points to nothing. Remove it."
        case .missingFile:
            let restore = actions.contains(.restoreFromLibrary) ? ", restore it from the library" : ""
            return "The stored file of this preset is missing or damaged, so it cannot play. Re-import the original .milk file "
                + "(it must be the same file)\(restore), or remove the preset."
        case .unparsable:
            return "\(detail ?? "") Move it to Quarantine so it is never played, or remove it."
        }
    }

    /// The fix's button title.
    public func title(of action: PresetIntegrityAction) -> String {
        switch action {
        case .removeReference: store?.removalTitle ?? "Remove"
        case .relinkFile: "Re-import…"
        case .restoreFromLibrary: "Restore from Library"
        case .moveToQuarantine: "Move to Quarantine"
        case .removePreset: "Remove Preset"
        }
    }

    /// One accessibility element per issue (spec Clarifications).
    public var accessibilityLabel: String { "\(title). \(suggestion)" }
}

/// R14, research D7. Tests pass smaller values.
public struct PresetIntegrityLimits: Sendable, Equatable {
    public var maxRecords: Int
    public var maxTextBytes: Int
    public var maxReferences: Int
    public var maxIssues: Int
    public var maxTexturesPerPreset: Int

    public init(maxRecords: Int = 1_200, maxTextBytes: Int = 128 << 20, maxReferences: Int = 60_000,
                maxIssues: Int = 500, maxTexturesPerPreset: Int = 8) {
        self.maxRecords = maxRecords; self.maxTextBytes = maxTextBytes; self.maxReferences = maxReferences
        self.maxIssues = maxIssues; self.maxTexturesPerPreset = maxTexturesPerPreset
    }

    public static let standard = PresetIntegrityLimits()
}

public struct PresetIntegrityReport: Sendable, Equatable {
    public var issues: [PresetIntegrityIssue]
    public var presetsChecked: Int
    public var referencesChecked: Int
    /// A bound stopped part of the check (R14).
    public var incomplete: Bool
    /// The user preset list could not be read (newer format): user presets were not checked.
    public var userPresetsUnavailable: Bool

    public init(issues: [PresetIntegrityIssue], presetsChecked: Int, referencesChecked: Int, incomplete: Bool,
                userPresetsUnavailable: Bool) {
        self.issues = issues; self.presetsChecked = presetsChecked; self.referencesChecked = referencesChecked
        self.incomplete = incomplete; self.userPresetsUnavailable = userPresetsUnavailable
    }

    public var isClean: Bool { issues.isEmpty }
    public var safeIssues: [PresetIntegrityIssue] { issues.filter(\.isSafe) }

    public func issues(of kind: PresetIntegrityIssue.Kind) -> [PresetIntegrityIssue] { issues.filter { $0.kind == kind } }

    /// The sentence shown and announced after a scan (contract).
    public var summary: String {
        var text: String
        if issues.isEmpty {
            text = "No problems found."
        } else {
            text = "Found \(issues.count) \(issues.count == 1 ? "problem" : "problems")."
        }
        if userPresetsUnavailable { text += " " + UserPresetText.newerFormat }
        if incomplete { text += " The check was incomplete." }
        return text
    }
}

/// Words for fixes (contract).
public enum PresetIntegrityText {
    public static let notChecked = "Not checked yet."
    public static let checking = "Checking the library…"
    public static func removedReferences(_ count: Int) -> String {
        "Removed \(count) broken \(count == 1 ? "reference" : "references")."
    }
    public static func restored(_ name: String) -> String { "Restored “\(name)”." }
    public static let checksumMismatch = "That file is not the same preset. Nothing was changed."
    public static func quarantined(_ name: String) -> String { "Moved “\(name)” to Quarantine." }
    public static func removed(_ name: String) -> String { "Removed “\(name)”." }
    public static let fixFailed = "The change could not be saved. Nothing was changed."
}
