// PresetCollection.swift — user-made preset collections: the model, name rules, limits, errors and
// the pure ordering rules (roadmap PRE-007; specs/005-pre-007-preset-collections, R1-R10, R14).
// Foundation only, like the rest of the package.
import Foundation

/// A named list of presets in the user's own order. Presets are referenced by `IndexedPreset.id`;
/// an id may name a preset that is locked or absent from the current index (R13, R14).
public struct PresetCollection: Codable, Sendable, Hashable, Identifiable {
    /// Permanent and opaque; never changes on rename. A UUID string when the app creates it.
    public let id: String
    public var name: String
    /// In the user's order; each id at most once.
    public var presetIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case presetIDs = "presets"
    }

    public init(id: String, name: String, presetIDs: [String]) {
        self.id = id; self.name = name; self.presetIDs = presetIDs
    }
}

/// R9, R10 (spec Clarifications): bounds that keep the saved document small.
public enum PresetCollectionLimits {
    public static let maxNameLength = 60
    public static let maxCollections = 100
    public static let maxPresetsPerCollection = 1_000
    /// A saved document larger than this is treated as unreadable.
    public static let maxFileBytes = 16 * 1_024 * 1_024
}

public enum PresetCollectionError: Error, Equatable, Sendable {
    case emptyName
    case nameTooLong(limit: Int)
    case duplicateName
    case unknownCollection
    case tooManyCollections(limit: Int)
    case collectionFull(limit: Int)
    /// A reorder that is not a permutation of the stored entries.
    case invalidOrder
    /// The saved document was written by a newer app version; it is left untouched (R15).
    case newerFormat(version: Int)
    /// The change could not be saved; nothing changed (R8).
    case saveFailed

    /// The sentence shown to the user.
    public var message: String {
        switch self {
        case .emptyName: "Enter a name."
        case .nameTooLong(let limit): "Names can have up to \(Self.grouped(limit)) characters."
        case .duplicateName: "A collection with this name already exists."
        case .unknownCollection: "This collection no longer exists."
        case .tooManyCollections(let limit): "You can have up to \(Self.grouped(limit)) collections."
        case .collectionFull(let limit): "A collection can hold up to \(Self.grouped(limit)) presets."
        case .invalidOrder: "The order could not be changed."
        case .newerFormat: PresetCollectionStore.newerFormatText
        case .saveFailed: "The change could not be saved. Your collections are unchanged."
        }
    }

    /// "1,000": the app's text is English only, so the grouping does not follow the locale.
    static func grouped(_ value: Int) -> String {
        var digits = String(value)
        var index = digits.count - 3
        while index > 0 {
            digits.insert(",", at: digits.index(digits.startIndex, offsetBy: index))
            index -= 3
        }
        return digits
    }
}

public enum PresetCollectionName {
    /// Line breaks become spaces, surrounding white space is dropped, and the result must have
    /// 1 to `maxNameLength` user-perceived characters (R9).
    public static func normalized(_ raw: String) throws -> String {
        let singleLine = String(raw.map { $0.isNewline ? " " : $0 })
        let name = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PresetCollectionError.emptyName }
        guard name.count <= PresetCollectionLimits.maxNameLength else {
            throw PresetCollectionError.nameTooLong(limit: PresetCollectionLimits.maxNameLength)
        }
        return name
    }

    /// Two names are the same when their keys are equal: case and diacritics are ignored (R9).
    public static func key(_ name: String) -> String {
        PresetLibrary.fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Pure ordering rules (R6, R7, R14).
public enum PresetCollectionOrder {
    /// The standard list control's move: the items at `fromOffsets` are taken out and inserted, in
    /// their original relative order, before the item that was at `toOffset` (the end when
    /// `toOffset` is the count). Offsets outside the list are ignored or clamped.
    public static func moved<T>(_ items: [T], fromOffsets: IndexSet, toOffset: Int) -> [T] {
        let sources = fromOffsets.filter { items.indices.contains($0) }
        guard !sources.isEmpty else { return items }
        let target = min(max(toOffset, 0), items.count)
        let moving = sources.map { items[$0] }
        let taken = Set(sources)
        var result: [T] = []
        result.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if index == target { result.append(contentsOf: moving) }
            if !taken.contains(index) { result.append(item) }
        }
        if target == items.count { result.append(contentsOf: moving) }
        return result
    }

    /// Maps a new order of the *visible* entries onto the stored list: entries that are not in
    /// `visibleOrder` (presets absent from the current library) keep their slots, and the other
    /// slots are refilled in the new order. Nothing is added or dropped (R14).
    public static func applying(visibleOrder: [String], to stored: [String]) throws -> [String] {
        let visible = Set(visibleOrder)
        guard visible.count == visibleOrder.count, visible.isSubset(of: Set(stored)) else {
            throw PresetCollectionError.invalidOrder
        }
        var next = visibleOrder.makeIterator()
        return stored.map { visible.contains($0) ? (next.next() ?? $0) : $0 }
    }
}
