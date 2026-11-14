// PresetSmartMatcher.swift — roadmap PRE-008: computing a smart collection's members (spec PRE-008-R3, R4;
// research PRE-008-D3; contract C1).
//
// Each known condition becomes a set of listed preset IDs (tag index sets, sources, the PRE-004 colour and
// PRE-005 energy filters, favorites); All intersects them, Any unions them; unknown kinds are skipped and a
// collection with no applicable condition lists nothing. The result is ordered alphabetically across packs
// (ties by ID) and holds each preset ID once and each non-empty content hash once (the first kept), so a
// preset matching several conditions, or the same text in several packs, is listed once.
import Foundation

/// What membership is computed from: the facets as the browser sees them now.
public struct PresetSmartContext: Sendable {
    public let library: PresetLibrary
    public let tags: PresetTagIndex
    public let favorites: Set<String>
    public let colors: PresetColorFilter
    public let energy: PresetEnergyFilter

    public init(library: PresetLibrary, tags: PresetTagIndex = .empty, favorites: Set<String> = [],
                colors: PresetColorFilter = .empty, energy: PresetEnergyFilter = .empty) {
        self.library = library
        self.tags = tags
        self.favorites = favorites
        self.colors = colors
        self.energy = energy
    }
}

public enum PresetSmartMatcher {
    /// The member preset IDs of `rules` in `context`: ordered, without duplicates (C1).
    public static func members(match: PresetSmartMatch, conditions: [PresetSmartCondition],
                               in context: PresetSmartContext) -> [String] {
        var result: Set<String>?
        for condition in conditions {
            guard let ids = matching(condition, in: context) else { continue }   // R4: unknown kinds are skipped
            if let current = result {
                result = match == .all ? current.intersection(ids) : current.union(ids)
            } else {
                result = ids
            }
        }
        guard let ids = result, !ids.isEmpty else { return [] }
        return ordered(ids, in: context.library)
    }

    public static func members(of collection: PresetSmartCollection, in context: PresetSmartContext) -> [String] {
        members(match: collection.match, conditions: collection.conditions, in: context)
    }

    /// The listed presets one known condition matches; nil for an unknown kind.
    static func matching(_ condition: PresetSmartCondition, in context: PresetSmartContext) -> Set<String>? {
        guard let kind = condition.knownKind else { return nil }
        let library: PresetLibrary = context.library
        let listed: (String) -> Bool = { (id: String) -> Bool in library.preset(id: id) != nil }
        switch kind {
        case .tag:
            return taggedAny(condition.values, context.tags)
        case .notTag:
            let tagged: Set<String> = taggedAny(condition.values, context.tags)
            return Set(library.presets.lazy.map(\.id).filter { (id: String) -> Bool in !tagged.contains(id) })
        case .pack:
            let sources = Set(condition.values)
            return Set(library.presets.lazy.filter { (p: IndexedPreset) -> Bool in sources.contains(p.source) }.map(\.id))
        case .motion:
            let classes: [PresetEnergy] = condition.values.compactMap(PresetEnergy.init(rawValue:))
            guard !classes.isEmpty else { return [] }   // `matching(any: [])` would mean every scored preset
            return context.energy.matching(any: classes).filter(listed)
        case .color:
            var ids: Set<String> = []
            for family in condition.values.compactMap(PresetColorFamily.init(rawValue:)) {
                ids.formUnion(context.colors.matching(all: [family]))
            }
            return ids.filter(listed)
        case .favorite:
            return context.favorites.filter(listed)
        }
    }

    private static func taggedAny(_ tags: [String], _ index: PresetTagIndex) -> Set<String> {
        var ids: Set<String> = []
        for tag in tags { ids.formUnion(index.idsByTag[PresetTagMap.fold(tag)] ?? []) }
        return ids
    }

    /// Alphabetical across packs; each ID once and each non-empty hash once (the first kept).
    static func ordered(_ ids: Set<String>, in library: PresetLibrary) -> [String] {
        var hashes: Set<String> = []
        var seen: Set<String> = []
        var result: [String] = []
        for preset in library.alphabeticalListing(ids) {
            guard seen.insert(preset.id).inserted else { continue }
            if !preset.hash.isEmpty, !hashes.insert(preset.hash).inserted { continue }
            result.append(preset.id)
        }
        return result
    }
}
