// UserPresetModel.swift — an imported preset's record and the words shown for every outcome
// (PRE-012-R12, R13, R26, R28; data-model.md). All of it is Codable and Foundation only.
import Foundation

/// Why a file is not playable (R13). Stored as a code plus an optional detail, so a record
/// written by a later version with a new code still loads.
public struct PresetQuarantineReason: Codable, Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case binaryContent, lineTooLong, tooManyLines, missingHeader, noSettings
        case blockTooLarge, statementTooLong, nestingTooDeep, statementTooComplex, tooMuchControlFlow
        case unbalancedEquation, incompleteShader
        case engineRejected, timedOut, interruptedDuringCheck, interruptedOnScreen, failedOnScreen
    }

    public var code: String
    public var detail: String?

    public init(_ kind: Kind, detail: String? = nil) {
        code = kind.rawValue
        self.detail = detail.map { String($0.prefix(PresetImportLimits.maxDetailCharacters)) }
    }

    public var kind: Kind? { Kind(rawValue: code) }

    /// One plain sentence, with the limit where there is one.
    public var message: String {
        let n = PresetImportLimits.grouped
        switch kind {
        case .binaryContent: return "This file is not text. A Milkdrop preset is a plain text file."
        case .lineTooLong: return "A line in this file is longer than \(n(PresetImportLimits.maxLineBytes)) bytes."
        case .tooManyLines: return "This file has more than \(n(PresetImportLimits.maxLines)) lines."
        case .missingHeader: return "This file does not start with the [preset00] header of a Milkdrop preset."
        case .noSettings: return "This file contains no preset settings."
        case .blockTooLarge:
            return "The \(Self.blockName(detail)) is larger than \(n(PresetImportLimits.maxBlockBytes)) bytes."
        case .statementTooLong:
            return "A statement in the \(Self.blockName(detail)) is longer than \(n(PresetImportLimits.maxStatementBytes)) bytes."
        case .nestingTooDeep:
            return "Brackets in the \(Self.blockName(detail)) are nested more than \(PresetImportLimits.maxNestingDepth) deep."
        case .statementTooComplex:
            let limit = detail == "warp_" || detail == "comp_" ? PresetImportLimits.maxShaderStatementComplexity
                : PresetImportLimits.maxEquationStatementComplexity
            return "A statement in the \(Self.blockName(detail)) is too complex: more than \(limit) operators and brackets."
        case .tooMuchControlFlow:
            return "The \(Self.blockName(detail)) has more than \(PresetImportLimits.maxShaderControlKeywords) if, else and loop keywords."
        case .unbalancedEquation: return "The \(Self.blockName(detail)) has unbalanced parentheses."
        case .incompleteShader: return "The \(Self.blockName(detail)) is incomplete. The file may be cut off."
        case .engineRejected: return "The visualizer could not load this preset." + Self.suffix(detail)
        case .timedOut: return "This preset took too long to load and draw."
        case .interruptedDuringCheck: return "The app closed while checking this preset."
        case .interruptedOnScreen: return "The app closed while first showing this preset."
        case .failedOnScreen: return "This preset failed while it was being shown." + Self.suffix(detail)
        case nil: return "This preset could not be used."
        }
    }

    private static func suffix(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "" }
        return " (\(detail))"
    }

    /// "per_frame_" → "per-frame equations".
    static func blockName(_ prefix: String?) -> String {
        guard let prefix else { return "preset code" }
        switch prefix {
        case "per_frame_init_": return "per-frame init equations"
        case "per_frame_": return "per-frame equations"
        case "per_pixel_": return "per-pixel equations"
        case "warp_": return "warp shader"
        case "comp_": return "composite shader"
        default:
            if prefix.hasPrefix("wave_") { return "custom wave equations" }
            if prefix.hasPrefix("shape_") { return "custom shape equations" }
            return "preset code"
        }
    }
}

/// A finding that does not block the import (R9-R11).
public struct PresetImportWarning: Codable, Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case missingTexture, numberingGap, ignoredLines, repeatedKeys, notUTF8
    }

    public var code: String
    public var detail: String

    public init(_ kind: Kind, detail: String = "") {
        code = kind.rawValue
        self.detail = String(detail.prefix(PresetImportLimits.maxLicenseLineCharacters))
    }

    public var kind: Kind? { Kind(rawValue: code) }

    public var message: String {
        switch kind {
        case .missingTexture: return "Uses the texture “\(detail)”, which the app does not have. A blank texture is used instead."
        case .numberingGap:
            return "The \(PresetQuarantineReason.blockName(detail)) skip a line number. Lines after the gap are ignored."
        case .ignoredLines: return "\(detail) \(detail == "1" ? "line is" : "lines are") not a setting and \(detail == "1" ? "is" : "are") ignored."
        case .repeatedKeys: return "\(detail) \(detail == "1" ? "setting is" : "settings are") repeated. The first value is used."
        case .notUTF8: return "The text is not UTF-8. Some characters in comments may be shown wrongly."
        case nil: return detail
        }
    }
}

/// What is known about the rights to an imported preset (R12). Nothing here is ever guessed
/// except the author, which is marked as a guess.
public struct PresetLicenseMetadata: Codable, Sendable, Hashable {
    public enum Origin: String, Codable, Sendable { case userImport }

    public var origin: Origin
    /// Always false in this feature: the app verifies nothing.
    public var rightsVerified: Bool
    /// The record's `author` is the text before " - " in the file name.
    public var authorFromFileName: Bool
    /// Lines of the file that mention a license or copyright, verbatim.
    public var linesFound: [String]

    public init(origin: Origin = .userImport, rightsVerified: Bool = false, authorFromFileName: Bool, linesFound: [String]) {
        self.origin = origin
        self.rightsVerified = rightsVerified
        self.authorFromFileName = authorFromFileName
        self.linesFound = linesFound
    }

    public static let rightsText = "Imported by you. projectM-iOS has not verified any rights to this preset."
    public static let noLicenseText = "No license information was found in the file."
}

public enum UserPresetState: String, Codable, Sendable {
    /// Passed static validation; not tried by an engine yet. Not playable.
    case pending
    case playable
    case quarantined
}

/// One imported file (data-model.md).
public struct UserPreset: Codable, Sendable, Hashable, Identifiable {
    public static let idPrefix = "user/"

    /// `user/<lowercase uuid>`; permanent, independent of name and content.
    public var id: String
    public var name: String
    public var author: String
    /// Display text only; never used as a path.
    public var originalFileName: String
    public var sha256: String
    /// Git blob SHA-1: comparable with PresetIndex.json and PresetBlocklist.json.
    public var blobHash: String
    public var byteCount: Int
    public var importedAt: Date
    public var state: UserPresetState
    public var provenOnScreen: Bool
    public var quarantine: PresetQuarantineReason?
    public var warnings: [PresetImportWarning]
    public var license: PresetLicenseMetadata

    public init(id: String, name: String, author: String, originalFileName: String, sha256: String, blobHash: String,
                byteCount: Int, importedAt: Date, state: UserPresetState, provenOnScreen: Bool = false,
                quarantine: PresetQuarantineReason? = nil, warnings: [PresetImportWarning] = [], license: PresetLicenseMetadata) {
        self.id = id; self.name = name; self.author = author; self.originalFileName = originalFileName
        self.sha256 = sha256; self.blobHash = blobHash; self.byteCount = byteCount; self.importedAt = importedAt
        self.state = state; self.provenOnScreen = provenOnScreen; self.quarantine = quarantine
        self.warnings = warnings; self.license = license
    }

    /// The stored copy's file name.
    public var fileName: String { sha256 + ".milk" }

    /// The library entry of a playable preset.
    public var indexed: IndexedPreset {
        IndexedPreset(id: id, name: name, author: author.isEmpty ? "Unknown author" : author, source: PresetLibrary.userSource,
                      folder: [], path: fileName, hash: blobHash)
    }

    /// What the record must satisfy to be read back (UserPresetsFile).
    var isWellFormed: Bool {
        id.hasPrefix(Self.idPrefix) && id.count > Self.idPrefix.count && id.count <= 80
            && !name.isEmpty && name.count <= PresetImportLimits.maxNameCharacters
            && author.count <= PresetImportLimits.maxNameCharacters
            && originalFileName.count <= PresetImportLimits.maxFileNameCharacters
            && ContentHash.isHex(sha256, count: 64) && ContentHash.isHex(blobHash, count: 40)
            && byteCount >= 1 && byteCount <= PresetImportLimits.maxFileBytes
            && (state == .quarantined) == (quarantine != nil)
            && warnings.count <= PresetImportLimits.maxWarnings
            && license.linesFound.count <= PresetImportLimits.maxLicenseLines
    }
}

/// Display text from a picked file's name (R4): no control characters, no path separators, bounded.
public enum UserPresetName {
    /// The file name as display text, at most 255 characters.
    public static func cleanedFileName(_ raw: String) -> String {
        let cleaned = clean(raw)
        return String((cleaned.isEmpty ? "preset.milk" : cleaned).prefix(PresetImportLimits.maxFileNameCharacters))
    }

    /// "Author - Title.milk" → ("Title", "Author"); no " - " → (the whole name, "").
    public static func displayName(fromFileName raw: String) -> (name: String, author: String) {
        var base = clean(raw)
        if base.lowercased().hasSuffix(".milk") { base = String(base.dropLast(5)) }
        base = base.trimmingCharacters(in: .whitespaces)
        var author = ""
        var name = base
        if let range = base.range(of: " - ") {
            let before = base[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let after = base[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty && !after.isEmpty {
                author = before
                name = after
            }
        }
        if name.isEmpty { name = "Untitled preset" }
        return (String(name.prefix(PresetImportLimits.maxNameCharacters)), String(author.prefix(PresetImportLimits.maxNameCharacters)))
    }

    private static func clean(_ raw: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                // Zero-width joiners keep emoji sequences whole; every other invisible scalar goes.
                if scalar.value == 0x200D { out.append(scalar) } else if scalar.value == 0x0A || scalar.value == 0x09 { out.append(" ") }
            default:
                out.append(scalar == "/" || scalar == "\\" || scalar == ":" ? "_" : scalar)
            }
        }
        return String(out).trimmingCharacters(in: .whitespaces)
    }
}

/// Why a picked file was not kept at all (R3, R5, R6, R27). Nothing is stored for a refusal.
public enum PresetImportRefusal: Error, Sendable, Equatable {
    case notAFile
    case wrongType
    case empty
    case tooLarge
    case unreadable
    case duplicateOfImported(name: String)
    case duplicateOfQuarantined(name: String, reason: String)
    case duplicateOfBuiltIn(name: String, pack: String)
    case blocked
    case libraryFull
    case quarantineFull
    case libraryUnavailable
    case saveFailed

    public var message: String {
        let n = PresetImportLimits.grouped
        switch self {
        case .notAFile: return "This is not a file."
        case .wrongType: return "Only Milkdrop preset files (.milk) can be imported."
        case .empty: return "This file is empty."
        case .tooLarge: return "This file is larger than \(n(PresetImportLimits.maxFileBytes)) bytes, the most a preset can be."
        case .unreadable: return "This file could not be read."
        case .duplicateOfImported(let name): return "This preset is already in My Presets as “\(name)”."
        case .duplicateOfQuarantined(let name, let reason):
            return "This file is already in Quarantine as “\(name)”: \(reason) Delete it there to try again."
        case .duplicateOfBuiltIn(let name, let pack): return "This preset is already in the library: “\(name)” in \(pack)."
        case .blocked: return "This preset was removed from the library at its author's request and cannot be imported."
        case .libraryFull: return "My Presets is full (\(n(PresetImportLimits.maxUserPresets)) presets). Remove some to import more."
        case .quarantineFull: return "Quarantine is full (\(PresetImportLimits.maxQuarantined) files). Delete some to import more."
        case .libraryUnavailable: return UserPresetText.newerFormat
        case .saveFailed: return "The preset could not be saved. Nothing was changed."
        }
    }
}

/// How one import ended (R28).
public enum PresetImportOutcome: Sendable, Equatable {
    case added(UserPreset)
    /// Stored, passed the static checks, but could not be tried yet; not playable.
    case waiting(UserPreset)
    case quarantined(UserPreset)
    case refused(PresetImportRefusal)

    /// The sentence shown and announced. `fileName` is the cleaned name of the picked file.
    public func message(fileName: String) -> String {
        switch self {
        case .added(let preset):
            guard !preset.warnings.isEmpty else { return "Added “\(preset.name)” to My Presets." }
            let count = preset.warnings.count
            return "Added “\(preset.name)” to My Presets with \(count) \(count == 1 ? "warning" : "warnings"). See its information for details."
        case .waiting(let preset):
            return "“\(preset.name)” was saved and will be checked before it can play."
        case .quarantined(let preset):
            return "“\(preset.originalFileName)” was put in Quarantine. \(preset.quarantine?.message ?? "This preset could not be used.")"
        case .refused(let refusal):
            return "“\(fileName)” was not imported. \(refusal.message)"
        }
    }

    /// Outcomes that need the user's attention get an alert; a clean add is only announced.
    public var needsAlert: Bool {
        if case .added(let preset) = self { return !preset.warnings.isEmpty }
        return true
    }
}

public enum UserPresetText {
    public static let scopeTitle = "My Presets"
    public static let newerFormat = "Your imported presets were saved by a newer version of the app. Update the app to use them."
    public static let unreadable = "The list of your imported presets could not be read and was set aside."
    public static let empty = "No presets yet. Tap Import Preset to add a Milkdrop preset (.milk) from Files."
    public static let quarantineEmpty = "Nothing is in Quarantine."
    public static let quarantineExplanation = "Files here failed a check and are never played. You can delete them."
    public static let pending = "Waiting to be checked"
    public static let onScreenFailure = "Preset could not be loaded and was put in Quarantine"
}

/// The engine-side check of a preset, off the visible renderer (R14-R16). The rendering layer
/// implements it; tests use a fake.
public protocol PresetTrialRunning: Sendable {
    /// Loads `contents` on an engine that is not the visible one and draws it. Never throws and
    /// returns within `timeout` (plus scheduling slack).
    func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult
}

public enum PresetTrialResult: Sendable, Equatable {
    case passed
    /// The engine refused the preset; its message.
    case failed(String)
    case timedOut
    /// No trial is possible now (no renderer, app in the background, an earlier trial is stuck).
    case unavailable(String)
}
