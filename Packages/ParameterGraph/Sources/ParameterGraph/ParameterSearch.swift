// ParameterSearch.swift — search parameters by name, group and unit (UIX-009-R1 to R4; research UIX-009-D1 to D4;
// specs/219-uix-009-parameter-search/contracts/parameter-search.md S1-S3).
//
// Pure and deterministic. The search takes descriptors and a query only, never a visual, layer or group
// selection, so the current selection cannot change which IDs match or their order (UIX-009-R1).
import Foundation

/// How well one query word matched; lower is better (research D3).
public enum ParameterSearchTier: Int, Sendable, Comparable, CaseIterable {
    case namePrefix = 0
    case nameSubstring = 1
    case group = 2
    case unit = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One matching parameter.
public struct ParameterSearchHit: Sendable, Hashable {
    public let id: ParameterID
    /// The worst tier over the query's words.
    public let tier: ParameterSearchTier
    /// The sum of the words' tiers.
    public let score: Int
    /// The descriptor's index in the searched list (the final tie-break).
    public let index: Int
}

public enum ParameterSearch {
    /// Case-, diacritic- and width-insensitive text, as the preset, tag and scene searches fold it.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The query's folded words; empty for a blank query.
    public static func words(_ query: String) -> [String] {
        let folded: String = fold(query)
        let parts: [Substring] = folded.split(whereSeparator: { (c: Character) -> Bool in c.isWhitespace })
        return parts.map { (part: Substring) -> String in String(part) }
    }

    /// Matching parameters, best first (research D3). A blank query returns every descriptor in order.
    public static func search(_ query: String, in descriptors: [ParameterDescriptor]) -> [ParameterSearchHit] {
        let queryWords: [String] = words(query)
        var hits: [ParameterSearchHit] = []
        for (index, descriptor) in descriptors.enumerated() {
            if let hit = match(queryWords, descriptor: descriptor, index: index) { hits.append(hit) }
        }
        hits.sort(by: ranksBefore)
        return hits
    }

    /// The IDs of `search(_:in:)`, best first.
    public static func ids(_ query: String, in descriptors: [ParameterDescriptor]) -> [ParameterID] {
        search(query, in: descriptors).map(\.id)
    }

    static func ranksBefore(_ a: ParameterSearchHit, _ b: ParameterSearchHit) -> Bool {
        if a.tier != b.tier { return a.tier < b.tier }
        if a.score != b.score { return a.score < b.score }
        return a.index < b.index
    }

    static func match(_ queryWords: [String], descriptor: ParameterDescriptor, index: Int) -> ParameterSearchHit? {
        guard !queryWords.isEmpty else {
            return ParameterSearchHit(id: descriptor.id, tier: .namePrefix, score: 0, index: index)
        }
        let name: String = fold(descriptor.displayName)
        let groupName: String = fold(descriptor.group.displayName)
        let groupID: String = fold(descriptor.group.id)
        let unitTerms: [String] = descriptor.unit.searchTerms
        var worst: ParameterSearchTier = .namePrefix
        var score: Int = 0
        for word in queryWords {
            guard let tier = tier(of: word, name: name, groupName: groupName, groupID: groupID, unitTerms: unitTerms) else {
                return nil
            }
            worst = max(worst, tier)
            score += tier.rawValue
        }
        return ParameterSearchHit(id: descriptor.id, tier: worst, score: score, index: index)
    }

    /// The best tier `word` reaches, or nil (all inputs folded).
    static func tier(of word: String, name: String, groupName: String, groupID: String, unitTerms: [String]) -> ParameterSearchTier? {
        if name.hasPrefix(word) { return .namePrefix }
        if name.contains(word) { return .nameSubstring }
        if groupName.contains(word) || groupID.contains(word) { return .group }
        if unitTerms.contains(where: { (term: String) -> Bool in unitTerm(term, matches: word) }) { return .unit }
        return nil
    }

    /// A unit term matches a word that starts the term or starts one of its words ("second" in "per second").
    static func unitTerm(_ term: String, matches word: String) -> Bool {
        if term.hasPrefix(word) { return true }
        let parts: [Substring] = term.split(separator: " ")
        guard parts.count > 1 else { return false }
        return parts.contains { (part: Substring) -> Bool in part.hasPrefix(word) }
    }
}

extension ParameterUnit {
    /// The folded names and symbols a search matches for this unit (research UIX-009-D4).
    public var searchTerms: [String] {
        switch self {
        case .none: return []
        case .normalized: return ["percent", "%"]
        case .fractionOfOutput: return ["percent", "%", "fraction", "of output"]
        case .seconds: return ["seconds", "sec", "s", "ms", "milliseconds", "time"]
        case .perSecond: return ["per second", "/s", "hz", "hertz", "rate"]
        case .degrees: return ["degrees", "deg", "°", "angle"]
        case .count: return ["count", "number", "#"]
        }
    }
}
