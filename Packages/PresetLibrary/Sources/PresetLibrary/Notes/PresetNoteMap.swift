// PresetNoteMap.swift — roadmap PRE-011: private free-text notes keyed by stable preset ID, in memory (spec
// PRE-011-R1; data-model "PresetNoteMap"). A value type: every change validates (preset ID, trimmed length,
// note count). Notes are the user's private text: nothing here logs, and no diagnostics code may read them
// (PRE-011-R6; enforced by scripts/check_compliance.py).
import Foundation

public enum PresetNoteError: Error, Sendable, Hashable {
    case tooLong(limit: Int)
    case invalidPreset
    case tooManyNotes(limit: Int)
    case newerFormat
    case saveFailed

    public var message: String {
        switch self {
        case let .tooLong(limit): "A note can be at most \(PresetNoteMap.grouped(limit)) characters."
        case .invalidPreset: "This preset cannot have a note."
        case let .tooManyNotes(limit): "At most \(PresetNoteMap.grouped(limit)) presets can have notes."
        case .newerFormat: "These notes were saved by a newer version of the app. Update the app to use them."
        case .saveFailed: "Your note could not be saved."
        }
    }
}

public struct PresetNoteMap: Sendable, Hashable {
    /// Characters as the user sees them (grapheme clusters; research PRE-011-D3).
    public static let maximumCharacters = 2_000
    public static let maximumNotes = 20_000
    public static let maximumPresetIDBytes = 512

    /// Preset ID → trimmed, non-empty note text.
    public private(set) var notes: [String: String]

    public init() { notes = [:] }

    public var isEmpty: Bool { notes.isEmpty }
    public var count: Int { notes.count }

    public func note(for presetID: String) -> String? { notes[presetID] }

    /// Leading and trailing whitespace and newlines removed.
    public static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func isValidPresetID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= maximumPresetIDBytes }

    /// Stores the trimmed text; empty text removes the note. Returns the stored text (nil when removed).
    @discardableResult
    public mutating func set(_ text: String, for presetID: String) throws(PresetNoteError) -> String? {
        guard Self.isValidPresetID(presetID) else { throw .invalidPreset }
        let stored: String = Self.trimmed(text)
        guard !stored.isEmpty else {
            notes.removeValue(forKey: presetID)
            return nil
        }
        guard stored.count <= Self.maximumCharacters else { throw .tooLong(limit: Self.maximumCharacters) }
        if notes[presetID] == nil, notes.count >= Self.maximumNotes { throw .tooManyNotes(limit: Self.maximumNotes) }
        notes[presetID] = stored
        return stored
    }

    /// Removes a preset's note; false when it had none.
    @discardableResult
    public mutating func remove(_ presetID: String) -> Bool { notes.removeValue(forKey: presetID) != nil }

    /// The preset IDs whose note contains `query` (case- and diacritic-insensitive; PRE-011-R5). Empty for blank text.
    public func presetIDs(containing query: String) -> Set<String> {
        let needle: String = Self.fold(query).trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        var found: Set<String> = []
        for (id, text) in notes where Self.fold(text).contains(needle) { found.insert(id) }
        return found
    }

    /// "2,000": digits grouped by commas (Foundation-only, the same on Linux).
    public static func grouped(_ value: Int) -> String {
        let digits: [Character] = Array(String(abs(value)))
        var out: [Character] = []
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return (value < 0 ? "-" : "") + String(out)
    }

    static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// Reads stored entries leniently: entries that are not text, are empty after trimming, are too long, have
    /// a bad ID, or exceed the note count are dropped and counted (contract C1).
    public static func repaired(_ stored: [String: String?]) -> (map: PresetNoteMap, dropped: Int) {
        var map = PresetNoteMap()
        var dropped = 0
        for presetID in stored.keys.sorted() {
            guard let text = stored[presetID] ?? nil, isValidPresetID(presetID), map.notes.count < maximumNotes else {
                dropped += 1
                continue
            }
            let note: String = trimmed(text)
            guard !note.isEmpty, note.count <= maximumCharacters else {
                dropped += 1
                continue
            }
            map.notes[presetID] = note
        }
        return (map, dropped)
    }
}
