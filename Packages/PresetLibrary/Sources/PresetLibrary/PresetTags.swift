// PresetTags.swift — PRE-003 preset tags (spec PRE-003-R1 to R4, R7; research PRE-003-D2; contract C1).
//
// Tags are labels the user assigns to presets, kept by preset ID in the app's own data
// (`PresetTagStore`); bundled assets are never written. The rules are SCN-005's scene tag rules:
// trimmed 1…40 characters on one line; identity folds case, accents and width (`nil` locale, the same
// folding as SCN-004/005); a tag keeps its display case and adding a tag that already exists anywhere
// uses the existing spelling; each preset's tags are sorted by (folded text, text); at most 16 tags per
// preset and 256 distinct tags. PRE-003 adds a cap of 20,000 tagged presets (the bundled library plus
// the user's presets fit). A value type; every refused operation changes nothing. Foundation only.
import Foundation

public enum PresetTagError: Error, Sendable, Hashable {
    case invalidTag
    case alreadyTagged(String)
    case notTagged(String)
    case tooManyTags(limit: Int)
    case tooManyDistinctTags(limit: Int)
    case tooManyTaggedPresets(limit: Int)
    case newerFormat
    case saveFailed

    public var message: String {
        switch self {
        case .invalidTag: "A tag is 1 to \(PresetTagMap.maximumTagLength) characters on one line."
        case let .alreadyTagged(tag): "The preset is already tagged \(tag)."
        case let .notTagged(tag): "The preset is not tagged \(tag)."
        case let .tooManyTags(limit): "A preset has at most \(limit) tags."
        case let .tooManyDistinctTags(limit): "There are at most \(limit) different tags."
        case let .tooManyTaggedPresets(limit): "At most \(limit) presets can have tags."
        case .newerFormat: "These tags were saved by a newer version of the app. Update the app to use them."
        case .saveFailed: "Your tags could not be saved."
        }
    }
}

public struct PresetTagMap: Sendable, Hashable {
    public static let maximumTagLength = 40
    public static let maximumTagsPerPreset = 16
    public static let maximumDistinctTags = 256
    public static let maximumTaggedPresets = 20_000

    /// Preset ID → its tags, sorted by (folded text, text); a preset without tags has no entry.
    public private(set) var tags: [String: [String]]

    public init() { tags = [:] }

    public var isEmpty: Bool { tags.isEmpty }

    // MARK: - Rules

    /// Trimmed text of 1…40 characters with no line breaks or control characters, or nil.
    public static func normalizedTag(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumTagLength else { return nil }
        let bad: Bool = trimmed.unicodeScalars.contains { (u: Unicode.Scalar) -> Bool in
            u.properties.generalCategory == .control || CharacterSet.newlines.contains(u)
        }
        return bad ? nil : trimmed
    }

    /// The comparison form of a tag (case, accents and width; fixed locale), as SCN-004/005 fold.
    public static func fold(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// (folded text, text) order.
    public static func ordered(_ a: String, _ b: String) -> Bool {
        let fa: String = fold(a)
        let fb: String = fold(b)
        if fa != fb { return fa < fb }
        return a < b
    }

    // MARK: - Reading

    /// The preset's tags (sorted; empty when none).
    public func tags(of presetID: String) -> [String] { tags[presetID] ?? [] }

    /// Whether the preset carries the tag (folded comparison).
    public func has(_ presetID: String, tag: String) -> Bool {
        let folded: String = Self.fold(tag)
        return tags(of: presetID).contains { (t: String) -> Bool in Self.fold(t) == folded }
    }

    /// The spelling stored anywhere for a tag (the smallest by (fold, text)), or nil.
    public func existingSpelling(of tag: String) -> String? {
        let folded: String = Self.fold(tag)
        var best: String?
        for list in tags.values {
            for t in list where Self.fold(t) == folded {
                if let current = best, !Self.ordered(t, current) { continue }
                best = t
            }
        }
        return best
    }

    var distinctFolded: Set<String> {
        var result = Set<String>()
        for list in tags.values { for tag in list { result.insert(Self.fold(tag)) } }
        return result
    }

    // MARK: - Editing

    /// Adds a tag to a preset; returns the spelling stored (the existing one when the tag exists).
    @discardableResult
    public mutating func add(_ text: String, to presetID: String) throws(PresetTagError) -> String {
        guard !presetID.isEmpty, let tag = Self.normalizedTag(text) else { throw .invalidTag }
        var list: [String] = tags(of: presetID)
        let folded: String = Self.fold(tag)
        if let own = list.first(where: { (t: String) -> Bool in Self.fold(t) == folded }) { throw .alreadyTagged(own) }
        guard list.count < Self.maximumTagsPerPreset else { throw .tooManyTags(limit: Self.maximumTagsPerPreset) }
        if list.isEmpty, tags.count >= Self.maximumTaggedPresets { throw .tooManyTaggedPresets(limit: Self.maximumTaggedPresets) }
        let spelling: String
        if let existing = existingSpelling(of: tag) {
            spelling = existing
        } else {
            guard distinctFolded.count < Self.maximumDistinctTags else { throw .tooManyDistinctTags(limit: Self.maximumDistinctTags) }
            spelling = tag
        }
        list.append(spelling)
        tags[presetID] = list.sorted(by: Self.ordered)
        return spelling
    }

    /// Removes a tag (folded match) from a preset; returns the spelling removed.
    @discardableResult
    public mutating func remove(_ tag: String, from presetID: String) throws(PresetTagError) -> String {
        let folded: String = Self.fold(tag)
        var list: [String] = tags(of: presetID)
        guard let index = list.firstIndex(where: { (t: String) -> Bool in Self.fold(t) == folded }) else { throw .notTagged(tag) }
        let removed: String = list.remove(at: index)
        tags[presetID] = list.isEmpty ? nil : list
        return removed
    }

    /// Drops every tag of a preset (PRE-003-R7: the user removed their preset). True when it had tags.
    @discardableResult
    public mutating func prune(_ presetID: String) -> Bool {
        tags.removeValue(forKey: presetID) != nil
    }

    /// Replaces a preset's tags with a list that already satisfies every rule (restore merges).
    mutating func setTags(_ list: [String], of presetID: String) {
        tags[presetID] = list.isEmpty ? nil : list.sorted(by: Self.ordered)
    }

    // MARK: - Stored form

    /// Builds a map from stored entries, keeping what satisfies every rule (research PRE-003-D4).
    /// `stored` is preset ID → the stored list (nil = not a list of strings). Presets are visited in
    /// sorted ID order and each list in its stored order, so the result is deterministic. Returns the
    /// map and how many tags and entries were dropped.
    public static func repaired(_ stored: [String: [String]?]) -> (map: PresetTagMap, dropped: Int) {
        var map = PresetTagMap()
        var dropped = 0
        var distinct = Set<String>()
        for presetID in stored.keys.sorted() {
            let value: [String]? = stored[presetID] ?? nil
            guard let list = value else { dropped += 1; continue }
            guard !presetID.isEmpty, !list.isEmpty else { dropped += max(list.count, 1); continue }
            guard map.tags.count < maximumTaggedPresets else { dropped += list.count; continue }
            var kept: [String] = []
            var keptFolded = Set<String>()
            for text in list {
                // A stored tag must already be normalized and must not repeat on the preset.
                guard let tag = normalizedTag(text), tag == text else { dropped += 1; continue }
                let folded: String = fold(tag)
                guard !keptFolded.contains(folded), kept.count < maximumTagsPerPreset else { dropped += 1; continue }
                if !distinct.contains(folded) {
                    guard distinct.count < maximumDistinctTags else { dropped += 1; continue }
                    distinct.insert(folded)
                }
                kept.append(tag)   // each preset keeps its own stored spelling
                keptFolded.insert(folded)
            }
            if !kept.isEmpty { map.tags[presetID] = kept.sorted(by: ordered) }
        }
        return (map, dropped)
    }
}
