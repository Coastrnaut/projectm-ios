// BulkImportModel.swift — the values of a bulk preset import (roadmap PRE-013,
// specs/174-pre-013-bulk-import; data-model.md; contract C2 for the words).
//
// Every handled file ends as exactly one `BulkImportKind`; the report holds the exact count of each,
// the files not handled (a cancelled run), and one item per handled file in path order. Nothing here
// is written to disk (PRE-013-R14).
import Foundation

/// The bounds of one import (PRE-013-R2, R4; research PRE-013-D6).
public struct BulkImportLimits: Sendable, Equatable {
    /// Files listed (any type; hidden entries are not listed).
    public var maxFiles: Int
    /// Sum of the sizes of the `.milk` files within the per-file limit.
    public var maxTotalBytes: Int
    /// Folder levels opened below the picked folder.
    public var maxFolderDepth: Int
    /// The largest `.zip` read.
    public var maxArchiveBytes: Int
    /// Presets saved together, all or nothing (PRE-013-R13).
    public var batchSize: Int
    /// The per-file limit (PRE-012).
    public var maxFileBytes: Int
    /// Waiting or playable presets My Presets holds (PRE-012-R27).
    public var maxLibraryPresets: Int

    public init(maxFiles: Int, maxTotalBytes: Int, maxFolderDepth: Int, maxArchiveBytes: Int, batchSize: Int,
                maxFileBytes: Int = PresetImportLimits.maxFileBytes, maxLibraryPresets: Int = PresetImportLimits.maxUserPresets) {
        self.maxFiles = maxFiles
        self.maxTotalBytes = maxTotalBytes
        self.maxFolderDepth = maxFolderDepth
        self.maxArchiveBytes = maxArchiveBytes
        self.batchSize = batchSize
        self.maxFileBytes = maxFileBytes
        self.maxLibraryPresets = maxLibraryPresets
    }

    public static let standard = BulkImportLimits(maxFiles: 2_000, maxTotalBytes: 64 << 20, maxFolderDepth: 8,
                                                  maxArchiveBytes: 64 << 20, batchSize: 50)
}

/// What became of one file (PRE-013-R5).
public enum BulkImportKind: String, Sendable, CaseIterable, Codable {
    case added, duplicate, invalid, tooLarge, unsupported, failed
}

public struct BulkImportItem: Sendable, Equatable, Identifiable {
    /// Path inside the folder or archive ("/"-separated).
    public var path: String
    public var kind: BulkImportKind
    /// One line: the reason, or the added preset's name.
    public var detail: String
    /// The stored preset's identifier (added only).
    public var presetID: String?

    public var id: String { path }

    public init(path: String, kind: BulkImportKind, detail: String, presetID: String? = nil) {
        self.path = path; self.kind = kind; self.detail = detail; self.presetID = presetID
    }
}

public struct BulkImportCounts: Sendable, Equatable {
    public var added = 0
    public var duplicate = 0
    public var invalid = 0
    public var tooLarge = 0
    public var unsupported = 0
    public var failed = 0

    public init() {}

    public init(added: Int, duplicate: Int, invalid: Int, tooLarge: Int, unsupported: Int, failed: Int) {
        self.added = added; self.duplicate = duplicate; self.invalid = invalid
        self.tooLarge = tooLarge; self.unsupported = unsupported; self.failed = failed
    }

    public var skipped: Int { duplicate + invalid + tooLarge + unsupported }
    public var handled: Int { added + skipped + failed }

    public subscript(kind: BulkImportKind) -> Int {
        switch kind {
        case .added: return added
        case .duplicate: return duplicate
        case .invalid: return invalid
        case .tooLarge: return tooLarge
        case .unsupported: return unsupported
        case .failed: return failed
        }
    }

    mutating func record(_ kind: BulkImportKind) {
        switch kind {
        case .added: added += 1
        case .duplicate: duplicate += 1
        case .invalid: invalid += 1
        case .tooLarge: tooLarge += 1
        case .unsupported: unsupported += 1
        case .failed: failed += 1
        }
    }
}

/// Sent after each file (PRE-013-R7).
public struct BulkImportProgress: Sendable, Equatable {
    public var handled: Int
    public var total: Int
    /// Files whose outcome is final (drafts waiting for their batch are not counted yet).
    public var counts: BulkImportCounts

    public init(handled: Int, total: Int, counts: BulkImportCounts) {
        self.handled = handled; self.total = total; self.counts = counts
    }

    /// 0…1.
    public var fraction: Double { total > 0 ? Double(handled) / Double(total) : 1 }
}

public struct BulkImportReport: Sendable, Equatable {
    public var sourceName: String
    /// Files listed.
    public var total: Int
    public var counts: BulkImportCounts
    public var hiddenCount: Int
    public var foldersNotOpened: Int
    public var cancelled: Bool
    /// Why nothing was imported, or nil.
    public var refusal: String?
    /// Handled files in path order.
    public var items: [BulkImportItem]

    public init(sourceName: String, total: Int, counts: BulkImportCounts, hiddenCount: Int, foldersNotOpened: Int,
                cancelled: Bool, refusal: String?, items: [BulkImportItem]) {
        self.sourceName = sourceName; self.total = total; self.counts = counts; self.hiddenCount = hiddenCount
        self.foldersNotOpened = foldersNotOpened; self.cancelled = cancelled; self.refusal = refusal; self.items = items
    }

    public static func refused(_ sourceName: String, _ reason: String) -> BulkImportReport {
        BulkImportReport(sourceName: sourceName, total: 0, counts: BulkImportCounts(), hiddenCount: 0, foldersNotOpened: 0,
                         cancelled: false, refusal: reason, items: [])
    }

    public var notHandled: Int { max(0, total - counts.handled) }

    /// Contract C2.
    public var summary: String { BulkImportText.summary(self) }
}

/// The words of a bulk import (contract C2).
public enum BulkImportText {
    public static func summary(_ report: BulkImportReport) -> String {
        if let refusal = report.refusal { return "Nothing was imported. " + refusal }
        var text: String = counts(report.counts)
        if report.cancelled {
            let handled: String = PresetImportLimits.grouped(report.counts.handled)
            let total: String = PresetImportLimits.grouped(report.total)
            let rest: String = PresetImportLimits.grouped(report.notHandled)
            text = "Import cancelled after \(handled) of \(total) files. " + text + " \(rest) \(report.notHandled == 1 ? "file was" : "files were") not handled."
        }
        if let unopened = notOpened(hidden: report.hiddenCount, folders: report.foldersNotOpened) { text += " " + unopened }
        return text
    }

    /// "Added 70. Skipped 30: 15 duplicates, 8 invalid, 4 too large, 3 not presets. Failed 0."
    public static func counts(_ counts: BulkImportCounts) -> String {
        let g = PresetImportLimits.grouped
        var parts: [String] = []
        if counts.duplicate > 0 { parts.append("\(g(counts.duplicate)) \(counts.duplicate == 1 ? "duplicate" : "duplicates")") }
        if counts.invalid > 0 { parts.append("\(g(counts.invalid)) invalid") }
        if counts.tooLarge > 0 { parts.append("\(g(counts.tooLarge)) too large") }
        if counts.unsupported > 0 { parts.append("\(g(counts.unsupported)) \(counts.unsupported == 1 ? "not a preset" : "not presets")") }
        let skipped: String = parts.isEmpty ? "Skipped 0." : "Skipped \(g(counts.skipped)): " + parts.joined(separator: ", ") + "."
        return "Added \(g(counts.added)). " + skipped + " Failed \(g(counts.failed))."
    }

    static func notOpened(hidden: Int, folders: Int) -> String? {
        var parts: [String] = []
        if hidden > 0 { parts.append("\(PresetImportLimits.grouped(hidden)) hidden \(hidden == 1 ? "item" : "items")") }
        if folders > 0 { parts.append("\(PresetImportLimits.grouped(folders)) deeper \(folders == 1 ? "folder" : "folders")") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " and ") + (hidden + folders == 1 ? " was" : " were") + " not opened."
    }

    public static func start(sourceName: String, total: Int) -> String {
        "Importing \(sourceName): \(PresetImportLimits.grouped(total)) \(total == 1 ? "file" : "files")."
    }

    public static func progress(percent: Int, handled: Int, total: Int) -> String {
        "\(percent) percent imported, \(PresetImportLimits.grouped(handled)) of \(PresetImportLimits.grouped(total)) files."
    }

    /// The quarter (0-3) reached by `handled` of `total`; announcements are made when it grows (R10).
    public static func quarter(handled: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(3, handled * 4 / total)
    }

    // Item details.
    static func added(_ name: String) -> String { "Added as “\(name)”." }
    static func sameInImport(_ path: String) -> String { "Same as “\(path)” in this import." }
    static func inMyPresets(_ name: String) -> String { "Already in My Presets as “\(name)”." }
    static func builtIn(_ name: String, _ pack: String) -> String { "Same as the built-in preset “\(name)” (\(pack))." }
    static let blocked = "On the takedown list: removed from the library at its author's request."
    static let empty = "Empty file."
    static var tooLarge: String { "Larger than \(PresetImportLimits.grouped(PresetImportLimits.maxFileBytes)) bytes, the most a preset can be." }
    static let notPreset = "Not a preset file (.milk)."
    static let link = "A link; links are not followed."
    static let notRegular = "Not a regular file."
    static let unsafePath = "Its name points outside the archive's folder."
    static let tooDeep = "Too deeply nested in the archive."
    static let encrypted = "Encrypted."
    static let method = "Compressed in a way the app does not read."
    static let unreadable = "Could not be read."
    static let damaged = "Damaged in the archive."
    static func libraryFull(_ limit: Int) -> String { "My Presets is full (\(PresetImportLimits.grouped(limit)) presets)." }
    static let saveFailed = "Could not be saved."

    // Refusals of a whole source.
    public static func tooManyFiles(_ limit: Int) -> String { "It has more than \(PresetImportLimits.grouped(limit)) files." }
    public static func tooManyBytes(_ limit: Int) -> String { "Its presets add up to more than \(limit >> 20) MB." }
    public static func archiveTooLarge(_ limit: Int) -> String { "The archive is larger than \(limit >> 20) MB." }
    public static let notAnArchive = "The file is not a ZIP archive the app can read."
    public static let folderUnreadable = "The folder could not be read."
    public static let libraryUnavailable = UserPresetText.newerFormat
}
