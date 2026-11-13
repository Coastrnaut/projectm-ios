// UserPresetEditing.swift — the vocabulary of duplicating a built-in preset and editing a user
// preset (roadmap PRE-015, specs/010-pre-015-user-preset-duplication; PRE-015-R2-R16;
// contracts/user-preset-duplication.md): what the app hands over, every outcome with its words,
// copy names and editor text. Foundation only.
import Foundation

/// A built-in preset as the app knows it, with the bytes read separately from the app bundle or
/// the preset archive (PRE-015-R2).
public struct BundledPresetSource: Sendable, Equatable {
    /// The library id, e.g. `included/…` or `cream-of-the-crop/…`.
    public var id: String
    public var name: String
    public var author: String
    /// The bundled file's name (display only).
    public var fileName: String
    public var packID: String
    public var packTitle: String
    /// The pack's license statement as `PresetPacks.json` states it.
    public var licenseStatement: String
    /// The git blob hash the library index records for this preset.
    public var blobHash: String
    /// The pack is locked until the full library is unlocked.
    public var requiresLibraryUnlock: Bool

    public init(id: String, name: String, author: String, fileName: String, packID: String, packTitle: String,
                licenseStatement: String, blobHash: String, requiresLibraryUnlock: Bool) {
        self.id = id; self.name = name; self.author = author; self.fileName = fileName
        self.packID = packID; self.packTitle = packTitle; self.licenseStatement = licenseStatement
        self.blobHash = blobHash; self.requiresLibraryUnlock = requiresLibraryUnlock
    }
}

/// Why nothing was stored for a duplicate (PRE-015-R2-R7).
public enum PresetDuplicateRefusal: Error, Sendable, Equatable {
    /// The preset is in a pack that needs the full-library unlock (R7).
    case locked
    /// The preset failed to load this session; decided by the app (R7).
    case notPlayable
    /// The bytes read are not the preset the index describes (R2).
    case sourceMismatch
    case blocked
    case alreadyCopied(name: String)
    case alreadyInQuarantine(name: String, reason: String)
    /// The import checks would quarantine it (R5).
    case invalid(reason: String)
    case libraryFull
    case libraryUnavailable
    case saveFailed

    public var message: String {
        switch self {
        case .locked: return "It is in a pack that needs the full library."
        case .notPlayable: return "It could not be loaded in this session."
        case .sourceMismatch: return "The built-in preset could not be read."
        case .blocked: return "This preset was removed from the library at its author's request."
        case .alreadyCopied(let name): return "Its unchanged copy is already in My Presets as “\(name)”."
        case .alreadyInQuarantine(let name, let reason):
            return "A copy with the same text is in Quarantine as “\(name)”: \(reason) Delete it there to try again."
        case .invalid(let reason): return "It does not pass the checks for presets you can edit: \(reason)"
        case .libraryFull: return PresetImportRefusal.libraryFull.message
        case .libraryUnavailable: return PresetImportRefusal.libraryUnavailable.message
        case .saveFailed: return PresetImportRefusal.saveFailed.message
        }
    }
}

/// How one duplicate ended.
public enum PresetDuplicateOutcome: Sendable, Equatable {
    case added(UserPreset)
    /// Stored and statically valid; not tried yet, so not playable.
    case waiting(UserPreset)
    /// The off-screen trial failed; the copy is in Quarantine.
    case quarantined(UserPreset)
    case refused(PresetDuplicateRefusal)

    /// The sentence shown and announced; `sourceName` is the built-in preset's name.
    public func message(sourceName: String) -> String {
        switch self {
        case .added(let preset):
            let base = "Duplicated “\(sourceName)” to My Presets as “\(preset.name)”."
            guard !preset.warnings.isEmpty else { return base }
            let count = preset.warnings.count
            return base + " It has \(count) \(count == 1 ? "warning" : "warnings"). See its information for details."
        case .waiting(let preset): return "“\(preset.name)” was saved and will be checked before it can play."
        case .quarantined(let preset):
            return "“\(preset.name)” was put in Quarantine. \(preset.quarantine?.message ?? "This preset could not be used.")"
        case .refused(let refusal): return "“\(sourceName)” was not duplicated. \(refusal.message)"
        }
    }

    public var needsAlert: Bool {
        if case .added(let preset) = self { return !preset.warnings.isEmpty }
        return true
    }
}

/// A preset's text as the editor shows it (PRE-015-R10).
public struct PresetEditorText: Sendable, Equatable {
    public var text: String
    /// False when the stored bytes were not UTF-8 and were read as ISO Latin-1; saving stores UTF-8.
    public var isUTF8: Bool
    /// The stored text the editor opened; an edit names it so a stale editor cannot overwrite.
    public var sha256: String

    public init(text: String, isUTF8: Bool, sha256: String) {
        self.text = text
        self.isUTF8 = isUTF8
        self.sha256 = sha256
    }

    public static func decode(_ data: Data, sha256: String) -> PresetEditorText {
        if let text = String(data: data, encoding: .utf8) { return PresetEditorText(text: text, isUTF8: true, sha256: sha256) }
        return PresetEditorText(text: String(decoding: data.map { UInt16($0) }, as: UTF16.self), isUTF8: false, sha256: sha256)
    }

    public static let latin1Note = "This preset is not UTF-8 text. It is shown as Latin-1 and will be saved as UTF-8."
}

/// Why an edit was not saved (PRE-015-R11-R13). Every case leaves the stored preset unchanged.
public enum PresetEditRefusal: Error, Sendable, Equatable {
    case notEditable
    case needsUnlock
    case emptyName
    case emptyText
    case tooLarge
    case blocked
    case sameAsBuiltIn(name: String, pack: String)
    case sameAsUserPreset(name: String)
    case invalid(reason: String)
    case checkFailed(message: String)
    case checkTimedOut
    /// No off-screen engine can try it now (none yet, the app is in the background, or another
    /// check is running).
    case checkUnavailable
    case libraryUnavailable
    case saveFailed
    /// The preset was changed or removed elsewhere while it was being edited.
    case changedMeanwhile

    public var message: String {
        let n = PresetImportLimits.grouped
        switch self {
        case .notEditable: return "Only presets in My Presets that can play can be edited."
        case .needsUnlock: return "This copy of a preset from the full library can be edited again once the library is unlocked."
        case .emptyName: return "The name is empty."
        case .emptyText: return "The preset text is empty."
        case .tooLarge: return "The preset is larger than \(n(PresetImportLimits.maxFileBytes)) bytes, the most a preset can be."
        case .blocked: return "This text is a preset that was removed from the library at its author's request."
        case .sameAsBuiltIn(let name, let pack): return "This text is the same as the built-in preset “\(name)” in \(pack)."
        case .sameAsUserPreset(let name): return "This text is the same as “\(name)”, which is already in My Presets."
        case .invalid(let reason): return reason
        case .checkFailed(let message):
            return "The visualizer could not load the edited preset (\(message)). Your last saved version still plays."
        case .checkTimedOut: return "The edited preset took too long to load and draw. Your last saved version still plays."
        case .checkUnavailable: return "The edited preset cannot be checked right now. Try Save again in a moment."
        case .libraryUnavailable: return UserPresetText.newerFormat
        case .saveFailed: return "The change could not be saved. Nothing was changed."
        case .changedMeanwhile: return "The preset was changed or removed while you were editing it."
        }
    }

    /// Shown once after a launch that ended during an edit's check (R13).
    public static func interruptedNotice(name: String) -> String {
        "An edit to “\(name)” was not saved because the app closed while checking it."
    }
}

public enum PresetEditOutcome: Sendable, Equatable {
    case saved(UserPreset)
    /// Nothing differed from what is stored.
    case unchanged
    case refused(PresetEditRefusal)

    public var message: String {
        switch self {
        case .saved(let preset): return "Saved “\(preset.name)”."
        case .unchanged: return "No changes to save."
        case .refused(let refusal): return "Not saved. " + refusal.message
        }
    }
}

extension UserPresetName {
    /// "Alpha copy", or "Alpha copy N" with the smallest N ≥ 2 not in `taken` (compared without
    /// regard to case). The original part is shortened so the whole fits the name limit (R3).
    public static func copyName(of original: String, taken: [String]) -> String {
        let used = Set(taken.map { $0.lowercased() })
        var number = 1
        while true {
            let suffix = number == 1 ? " copy" : " copy \(number)"
            let base = String(original.prefix(PresetImportLimits.maxNameCharacters - suffix.count)).trimmingCharacters(in: .whitespaces)
            let candidate = (base.isEmpty ? "Preset" : base) + suffix
            if !used.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }

    /// A name typed in the editor: cleaned like an imported name, trimmed, at most 120 characters.
    public static func cleanedName(_ raw: String) -> String {
        String(clean(raw).prefix(PresetImportLimits.maxNameCharacters)).trimmingCharacters(in: .whitespaces)
    }
}
