// UserPresetExport.swift — what can be exported, what is left out and why, and the words of an
// export (roadmap PRE-014, specs/012-pre-014-bulk-preset-export; PRE-014-R2, R5, R6; ADR-0008).
//
// Exportable: playable, not held, and either imported by the user or a copy of an Included
// preset. Every copy whose source is in a pack the purchase unlocks stays on the device, whatever
// the entitlement and however it was edited (ADR-0008, "Decision for PRE-014").
import Foundation

public enum UserPresetExportExclusion: String, Sendable, CaseIterable, Comparable {
    /// A copy of a preset from a pack the purchase unlocks (ADR-0008).
    case fullLibraryCopy
    case quarantined
    /// Waiting for its check.
    case notChecked
    /// Held after a failed save, an id that names no archive file, or removed meanwhile.
    case unavailable

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// "2 copies of presets from the full library (part of the purchase; they stay on this device)".
    public func phrase(count: Int) -> String {
        let one = count == 1
        switch self {
        case .fullLibraryCopy:
            return one ? "1 copy of a preset from the full library (part of the purchase; it stays on this device)"
                : "\(count) copies of presets from the full library (part of the purchase; they stay on this device)"
        case .quarantined:
            return one ? "1 file in Quarantine (it failed a check)" : "\(count) files in Quarantine (they failed a check)"
        case .notChecked:
            return one ? "1 preset waiting to be checked" : "\(count) presets waiting to be checked"
        case .unavailable:
            return one ? "1 preset that could not be read" : "\(count) presets that could not be read"
        }
    }

    /// "Not exported: …; …." or nil when nothing is left out.
    public static func sentence(_ counts: [UserPresetExportExclusion: Int]) -> String? {
        let parts = counts.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { $0.key.phrase(count: $0.value) }
        return parts.isEmpty ? nil : "Not exported: " + parts.joined(separator: "; ") + "."
    }
}

/// The presets the Export sheet lists and what it says about the rest.
public struct UserPresetExportPlan: Sendable, Equatable {
    /// Alphabetical by name.
    public var exportable: [UserPreset]
    public var excluded: [UserPresetExportExclusion: Int]

    public init(exportable: [UserPreset], excluded: [UserPresetExportExclusion: Int]) {
        self.exportable = exportable
        self.excluded = excluded
    }

    public static let empty = UserPresetExportPlan(exportable: [], excluded: [:])

    /// Why a record cannot be exported, or nil when it can. `held`: its quarantine could not be
    /// saved, so it is unplayable now.
    public static func exclusion(of preset: UserPreset, held: Bool) -> UserPresetExportExclusion? {
        if let origin = preset.duplicateOf, origin.requiresLibraryUnlock || origin.packID != PresetLibrary.includedSource {
            return .fullLibraryCopy
        }
        if held { return .unavailable }
        switch preset.state {
        case .quarantined: return .quarantined
        case .pending: return .notChecked
        case .playable: break
        }
        return UserPresetArchiveFormat.path(for: preset.id) == nil ? .unavailable : nil
    }
}

public struct UserPresetExportSummary: Sendable, Equatable {
    public var exported: Int
    public var excluded: [UserPresetExportExclusion: Int]
    public var fileName: String

    public init(exported: Int, excluded: [UserPresetExportExclusion: Int], fileName: String) {
        self.exported = exported
        self.excluded = excluded
        self.fileName = fileName
    }

    /// Shown in the Export sheet and announced (PRE-014-R5).
    public var message: String {
        let head = "Exported \(exported) \(exported == 1 ? "preset" : "presets")."
        guard let rest = UserPresetExportExclusion.sentence(excluded) else { return head }
        return head + " " + rest
    }
}

public enum UserPresetExportError: Error, Sendable, Equatable {
    case nothingSelected
    case libraryUnavailable
    /// A stored text does not match its record.
    case contentMismatch
    case writeFailed

    public var message: String {
        switch self {
        case .nothingSelected: return "Select at least one preset to export."
        case .libraryUnavailable: return UserPresetText.newerFormat
        case .contentMismatch, .writeFailed: return "The presets could not be exported. Nothing was shared."
        }
    }
}

public extension UserPresetText {
    static let exportTitle = "Export Presets"
    static let exportNothing = "No presets can be exported yet. Presets you imported or copied from Included presets can be exported once they have been checked."
    static let exportExplanation = "The presets are saved in one ZIP file with a list of their names and checksums. You choose where it goes in the next step."
}
