// PresetLibrary.swift — the in-memory library: lookup, the browsing tree, lock state, scope members
// (feature 002 FR-111-FR-118; contracts/preset-library.md). Built once, off the main thread.
import Foundation

/// A pack or folder in the browser.
public struct PresetNode: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let scope: PresetScope
    public let children: [PresetNode]
    /// Presets in this node (total; the app shows the playable count after purchase, FR-111).
    public let presetCount: Int
    public let locked: Bool
}

public final class PresetLibrary: Sendable {
    public static let includedSource = "included"
    /// FR-102 pack priority after Included.
    public static let packOrder = ["cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d"]

    /// Every preset: Included first, then packs in `packOrder`, each alphabetical (FR-115).
    public let presets: [IndexedPreset]
    public let packs: [PresetPackInfo]
    public let home: [PresetNode]
    /// Ids of the pack presets in PresetIndex.json order: the order of PresetArchive.bin's table.
    public let archiveOrder: [String]
    private let byId: [String: Int]
    private let searchKeys: [String]
    private let lockedSources: Set<String>

    public init(index: Data, packs packsData: Data) throws {
        let decoder = JSONDecoder()
        let file = try decoder.decode(IndexFile.self, from: index)
        guard file.version == 1 else { throw PresetLibraryError.unsupportedVersion(file.version) }
        let packsFile = try decoder.decode(PacksFile.self, from: packsData)
        guard packsFile.version == 1 else { throw PresetLibraryError.unsupportedVersion(packsFile.version) }
        let rank = Dictionary(uniqueKeysWithValues: ([Self.includedSource] + Self.packOrder).enumerated().map { ($1, $0) })
        let sorted = file.presets.sorted {
            let (a, b) = (rank[$0.source] ?? 99, rank[$1.source] ?? 99)
            if a != b { return a < b }
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.id < $1.id
            }
        }
        presets = sorted
        if let positions = file.archive {
            guard positions.allSatisfy(file.presets.indices.contains) else { throw PresetLibraryError.badArchiveTable }
            archiveOrder = positions.map { file.presets[$0].id }
        } else {
            archiveOrder = file.presets.filter { !$0.isIncluded }.map(\.id)
        }
        packs = packsFile.packs
        byId = Dictionary(sorted.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        searchKeys = sorted.map { Self.fold($0.name + " " + $0.author) }
        lockedSources = Set(packsFile.packs.filter(\.locked).map(\.id))
        home = Self.buildHome(sorted, packs: packsFile.packs)
    }

    /// Reads `PresetIndex.json` and `PresetPacks.json` from the bundle off the main thread (SC-101).
    public static func load(from bundle: Bundle) async throws -> PresetLibrary {
        try await Task.detached(priority: .userInitiated) {
            guard let index = bundle.url(forResource: "PresetIndex", withExtension: "json") else {
                throw PresetLibraryError.missingResource("PresetIndex.json")
            }
            guard let packs = bundle.url(forResource: "PresetPacks", withExtension: "json") else {
                throw PresetLibraryError.missingResource("PresetPacks.json")
            }
            return try PresetLibrary(index: Data(contentsOf: index), packs: Data(contentsOf: packs))
        }.value
    }

    public func preset(id: String) -> IndexedPreset? { byId[id].map { presets[$0] } }

    public func pack(id: String) -> PresetPackInfo? { packs.first { $0.id == id } }

    public func isLocked(_ preset: IndexedPreset, unlocked: Bool) -> Bool {
        !unlocked && lockedSources.contains(preset.source)
    }

    /// Scope members: alphabetical, playable only (FR-115, FR-118). A collection's members are in
    /// the user's order (PRE-007-R11); `collections` maps a collection id to its preset ids.
    public func members(of scope: PresetScope, unlocked: Bool, favorites: Set<String>, excluded: Set<String>,
                        collections: [String: [String]] = [:]) -> [IndexedPreset] {
        let candidates: [IndexedPreset]
        switch scope {
        case .included: candidates = presets.filter(\.isIncluded)
        case .pack(let id): candidates = presets.filter { $0.source == id }
        case .folder(let id, let path): candidates = presets.filter { $0.source == id && $0.folder.starts(with: path) }
        case .favorites: candidates = favoritesListing(favorites)
        case .search(let query): candidates = search(query, limit: Self.searchLimit).groups.flatMap(\.presets)
        case .all: candidates = Self.alphabetical(presets)
        case .collection(let id): candidates = collectionListing(collections[id] ?? [])
        }
        return candidates.filter { !isLocked($0, unlocked: unlocked) && !excluded.contains($0.id) }
    }

    /// FR-114: every favorite that exists, alphabetical across packs, locked ones included.
    public func favoritesListing(_ favorites: Set<String>) -> [IndexedPreset] {
        Self.alphabetical(favorites.compactMap { preset(id: $0) })
    }

    /// PRE-007-R13, R14: a collection's entries that exist in this library, in the stored order,
    /// locked ones included (the view marks them). Ids that are not in the index are skipped.
    public func collectionListing(_ presetIDs: [String]) -> [IndexedPreset] {
        presetIDs.compactMap { preset(id: $0) }
    }

    /// A display title for a scope (FR-120). `collectionNames` maps a collection id to its name.
    public func title(of scope: PresetScope, collectionNames: [String: String] = [:]) -> String {
        switch scope {
        case .included: "Included"
        case .pack(let id): pack(id: id)?.title ?? id
        case .folder(_, let path): path.joined(separator: " › ")
        case .favorites: "Favorites"
        case .search(let query): "Search: \(query)"
        case .all: "All presets"
        case .collection(let id): collectionNames[id] ?? "Collection"
        }
    }

    /// Whether a stored scope still names something in this library (spec Edge Cases).
    public func resolves(_ scope: PresetScope) -> Bool {
        switch scope {
        case .pack(let id): presets.contains { $0.source == id }
        case .folder(let id, let path): presets.contains { $0.source == id && $0.folder.starts(with: path) }
        default: true
        }
    }

    // MARK: - Search (FR-113)

    public static let searchLimit = 200

    /// Name and author, case- and diacritic-insensitive substring; groups in pack order, each
    /// alphabetical; at most `limit` presets in total, `truncated` when more matched.
    public func search(_ query: String, limit: Int) -> (groups: [(source: String, presets: [IndexedPreset])], truncated: Bool) {
        let needle = Self.fold(query).trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return ([], false) }
        var groups: [(source: String, presets: [IndexedPreset])] = []
        var taken = 0
        var truncated = false
        for (index, key) in searchKeys.enumerated() where key.contains(needle) {
            if taken == limit { truncated = true; break }
            let preset = presets[index]
            if groups.last?.source == preset.source {
                groups[groups.count - 1].presets.append(preset)
            } else {
                groups.append((preset.source, [preset]))
            }
            taken += 1
        }
        return (groups, truncated)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func alphabetical(_ list: [IndexedPreset]) -> [IndexedPreset] {
        list.sorted {
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.id < $1.id
            }
        }
    }

    // MARK: - Tree (FR-111, FR-112)

    private static func buildHome(_ presets: [IndexedPreset], packs: [PresetPackInfo]) -> [PresetNode] {
        var nodes: [PresetNode] = []
        let included = presets.filter(\.isIncluded)
        nodes.append(PresetNode(id: includedSource, title: "Included", scope: .included, children: [],
                                presetCount: included.count, locked: false))
        for id in packOrder {
            let members = presets.filter { $0.source == id }
            let info = packs.first { $0.id == id }
            nodes.append(PresetNode(id: id, title: info?.title ?? id, scope: .pack(id),
                                    children: folderNodes(members.map { ($0.folder, $0) }, pack: id, prefix: []),
                                    presetCount: members.count, locked: info?.locked ?? true))
        }
        nodes.append(PresetNode(id: "all", title: "All presets A-Z", scope: .all, children: [],
                                presetCount: presets.count, locked: false))
        return nodes
    }

    private static func folderNodes(_ items: [([String], IndexedPreset)], pack: String, prefix: [String]) -> [PresetNode] {
        var groups: [String: [([String], IndexedPreset)]] = [:]
        for (rest, preset) in items where !rest.isEmpty {
            groups[rest[0], default: []].append((Array(rest.dropFirst()), preset))
        }
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            let path = prefix + [name]
            let members = groups[name] ?? []
            return PresetNode(id: ([pack] + path).joined(separator: "/"), title: name, scope: .folder(pack, path),
                              children: folderNodes(members, pack: pack, prefix: path),
                              presetCount: members.count, locked: true)
        }
    }
}
