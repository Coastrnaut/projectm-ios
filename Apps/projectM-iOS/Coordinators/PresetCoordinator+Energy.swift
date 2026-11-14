// PresetCoordinator+Energy.swift — PRE-005 energy facets in the browser (spec PRE-005-R8 to R12;
// contract C5).
//
// * Scores are the thumbnail model's mirror (`PresetThumbnailModel.motionEntries`), limited to listed
//   presets and their current thumbnail ID; the filter is rebuilt only when scores or the library change.
// * Selected energy chips (`selectedEnergies`) match presets in ANY selected class (classes exclude each
//   other) and join PRE-004's `filterMatches` with AND: tags, colours, Favorites and search.
// * A chip change announces the result count on the search lane (ACC-011), never a direct post.
// * Not a scope (R12): `filteredScope` is unchanged (tags, or All presets).
import Foundation
import PresetLibrary

extension PresetCoordinator {
    nonisolated static func energyCoverageText(_ count: Int) -> String {
        count == 1 ? "Motion from 1 preset with a picture" : "Motion from \(count.formatted(.number.locale(Locale(identifier: "en_US")))) presets with pictures"
    }

    /// The scores of listed presets whose thumbnail ID is the current one, cached per version.
    var energyFilter: PresetEnergyFilter {
        _ = motionVersion
        guard let library, let thumbnails else { return .empty }
        let identity = ObjectIdentifier(library)
        if let cached = cachedEnergyFilter, cached.version == motionVersion, cached.library == identity { return cached.filter }
        let spec: PresetThumbnailSpec = thumbnails.cache.spec
        var current: [String: Int] = [:]
        for (id, entry) in thumbnails.motionEntries {
            guard let preset = library.preset(id: id),
                  PresetThumbnailKey(preset: preset, spec: spec).stableID == entry.thumbnailID else { continue }
            current[id] = entry.score
        }
        let filter = PresetEnergyFilter(scores: current)
        cachedEnergyFilter = (motionVersion, identity, filter)
        return filter
    }

    /// The presets in any selected class; nil when no energy chip is selected.
    var energyMatches: Set<String>? {
        selectedEnergies.isEmpty ? nil : energyFilter.matching(any: selectedEnergies)
    }

    func isSelected(energy: PresetEnergy) -> Bool { selectedEnergies.contains(energy) }

    func toggleEnergy(_ energy: PresetEnergy) {
        if let index = selectedEnergies.firstIndex(of: energy) {
            selectedEnergies.remove(at: index)
        } else {
            selectedEnergies.append(energy)
        }
        announceSearch(hasActiveFilter ? Self.filteredCountText(filteredListing.count) : "Motion filter cleared")
    }

    func clearEnergies() {
        guard !selectedEnergies.isEmpty else { return }
        selectedEnergies = []
        announceSearch("Motion filter cleared")
    }
}
