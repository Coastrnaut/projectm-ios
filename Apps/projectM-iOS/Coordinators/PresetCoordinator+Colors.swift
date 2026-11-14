// PresetCoordinator+Colors.swift — PRE-004 colour facets in the browser (spec PRE-004-R7 to R11;
// contract C5).
//
// * Colours are the thumbnail model's mirror (`PresetThumbnailModel.colorEntries`), limited to listed
//   presets and to their current thumbnail ID; the filter is rebuilt only when colours or the library
//   change (`colorFilter`).
// * Selected colour chips (`selectedColors`) are in memory only and combine with AND, with the selected
//   tags, Favorites and the search text (`filteredListing`, `searchResults`).
// * A chip change announces the result count on the search lane (ACC-011), never a direct post.
// * Not a scope (R11): a preset chosen from the filtered list plays in the tag scope, or All presets.
import Foundation
import PresetLibrary

extension PresetCoordinator {
    nonisolated static let filteredEmptyText = "No presets match these filters"

    nonisolated static func filteredCountText(_ count: Int) -> String {
        count == 1 ? "1 preset matches" : "\(count.formatted(.number.locale(Locale(identifier: "en_US")))) presets match"
    }

    nonisolated static func colorCoverageText(_ count: Int) -> String {
        count == 1 ? "Colours from 1 preset with a picture" : "Colours from \(count.formatted(.number.locale(Locale(identifier: "en_US")))) presets with pictures"
    }

    /// The colours of listed presets whose thumbnail ID is the current one, cached per version.
    var colorFilter: PresetColorFilter {
        _ = colorsVersion
        guard let library, let thumbnails else { return .empty }
        let identity = ObjectIdentifier(library)
        if let cached = cachedColorFilter, cached.version == colorsVersion, cached.library == identity { return cached.filter }
        let spec: PresetThumbnailSpec = thumbnails.cache.spec
        var current: [String: [PresetColorFamily]] = [:]
        for (id, entry) in thumbnails.colorEntries {
            guard let preset = library.preset(id: id),
                  PresetThumbnailKey(preset: preset, spec: spec).stableID == entry.thumbnailID else { continue }
            current[id] = entry.colors
        }
        let filter = PresetColorFilter(colors: current)
        cachedColorFilter = (colorsVersion, identity, filter)
        return filter
    }

    /// The selected colours (kept even when no preset has them now; the list then shows nothing).
    var activeColors: [PresetColorFamily] { selectedColors }

    func isSelected(color: PresetColorFamily) -> Bool { selectedColors.contains(color) }

    /// Tags or colours narrow the browser.
    var hasActiveFilter: Bool { !activeTags.isEmpty || !activeColors.isEmpty }

    /// The preset IDs matching every selected tag and colour; nil when nothing is selected.
    var filterMatches: Set<String>? {
        var ids: Set<String>? = activeTags.isEmpty ? nil : tagIndex.matching(all: activeTags)
        let colors: [PresetColorFamily] = activeColors
        if !colors.isEmpty {
            let byColor: Set<String> = colorFilter.matching(all: colors)
            ids = ids.map { (tagged: Set<String>) -> Set<String> in tagged.intersection(byColor) } ?? byColor
        }
        return ids
    }

    /// R8: listed presets matching every selected tag and colour, alphabetical across packs (locked
    /// included); only favorites among them when `favoritesOnly`.
    var filteredListing: [IndexedPreset] {
        guard let library, let ids = filterMatches else { return [] }
        let listing: [IndexedPreset] = library.alphabeticalListing(ids)
        guard favoritesOnly else { return listing }
        _ = favoritesVersion
        return listing.filter { (preset: IndexedPreset) -> Bool in isFavorite(preset) }
    }

    /// R11: the scope a preset chosen from the filtered list plays in.
    var filteredScope: PresetScope { activeTags.isEmpty ? .all : .tagged(activeTags) }

    /// The empty text: PRE-003's for tags alone, otherwise the combined one.
    var filteredEmptyText: String { activeColors.isEmpty ? Self.taggedEmptyText : Self.filteredEmptyText }

    func toggleColor(_ color: PresetColorFamily) {
        if let index = selectedColors.firstIndex(of: color) {
            selectedColors.remove(at: index)
        } else {
            selectedColors.append(color)
        }
        announceSearch(hasActiveFilter ? Self.filteredCountText(filteredListing.count) : "Colour filter cleared")
    }

    func clearColors() {
        guard !selectedColors.isEmpty else { return }
        selectedColors = []
        announceSearch("Colour filter cleared")
    }
}
