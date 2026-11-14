// PresetTagIndex.swift — PRE-003: the inverted tag index (spec PRE-003-R3, R7, R14; research
// PRE-003-D3; contract C3).
//
// Built from a tag map over the presets the library lists now (`isListed`): tags of other IDs are kept
// in the store but hidden here (orphans, PRE-003-R7). Maps each folded tag to the set of preset IDs
// carrying it, so a chip change intersects sets instead of scanning 12,847 presets. `matching(all:)`
// intersects from the smallest set and reports how many IDs it visited (`visitedCount`), which tests
// use instead of wall-clock time.
import Foundation

public struct PresetTagIndex: Sendable, Equatable {
    /// Folded tag → preset IDs carrying it (listed presets only).
    public let idsByTag: [String: Set<String>]
    /// Folded tag → the display spelling (the smallest by (fold, text) among listed presets).
    public let spelling: [String: String]
    /// Display spellings sorted by (fold, text): the browser's chips.
    public let vocabulary: [String]

    public static let empty = PresetTagIndex(map: PresetTagMap(), isListed: { (_: String) -> Bool in false })

    public init(map: PresetTagMap, isListed: (String) -> Bool) {
        var ids: [String: Set<String>] = [:]
        var names: [String: String] = [:]
        for (presetID, list) in map.tags where isListed(presetID) {
            for tag in list {
                let folded: String = PresetTagMap.fold(tag)
                ids[folded, default: []].insert(presetID)
                if let current = names[folded], !PresetTagMap.ordered(tag, current) { continue }
                names[folded] = tag
            }
        }
        idsByTag = ids
        spelling = names
        vocabulary = names.values.sorted(by: PresetTagMap.ordered)
    }

    public var isEmpty: Bool { idsByTag.isEmpty }

    /// How many listed presets carry the tag.
    public func count(of tag: String) -> Int { idsByTag[PresetTagMap.fold(tag)]?.count ?? 0 }

    /// The IDs carrying every tag in `tags` (AND, folded) and how many IDs were visited to find them.
    /// An empty `tags` matches nothing (the browser shows the home instead).
    public func matchingWithCost(all tags: [String]) -> (ids: Set<String>, visited: Int) {
        guard !tags.isEmpty else { return ([], 0) }
        var sets: [Set<String>] = []
        for tag in Set(tags.map(PresetTagMap.fold)) {
            guard let set = idsByTag[tag] else { return ([], 0) }   // an unknown tag matches nothing
            sets.append(set)
        }
        sets.sort { (a: Set<String>, b: Set<String>) -> Bool in a.count < b.count }
        var result: Set<String> = sets[0]
        var visited: Int = sets[0].count
        for other in sets.dropFirst() {
            visited += result.count
            result = result.filter { (id: String) -> Bool in other.contains(id) }
            if result.isEmpty { break }
        }
        return (result, visited)
    }

    public func matching(all tags: [String]) -> Set<String> { matchingWithCost(all: tags).ids }

    /// IDs carrying any tag whose folded text contains the folded `needle` (search, PRE-003-R9).
    public func presetIDs(tagContaining needle: String) -> Set<String> {
        let folded: String = PresetTagMap.fold(needle).trimmingCharacters(in: .whitespaces)
        guard !folded.isEmpty else { return [] }
        var result = Set<String>()
        for (tag, ids) in idsByTag where tag.contains(folded) { result.formUnion(ids) }
        return result
    }

    /// The selected tags that still exist, in their current spelling (a vanished chip is dropped).
    public func existing(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let folded: String = PresetTagMap.fold(tag)
            guard let name = spelling[folded], seen.insert(folded).inserted else { continue }
            result.append(name)
        }
        return result
    }
}
