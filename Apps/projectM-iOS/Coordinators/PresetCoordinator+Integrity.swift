// PresetCoordinator+Integrity.swift — roadmap PRE-018 (specs/194-pre-018-integrity-scanner; R1, R4, R9):
// the library check's view of the reference stores this coordinator owns or reaches: favorites, tags,
// collections, adjustments (PRE-016) and recently played (PRE-006). `integrityReferences` copies their
// preset IDs on the main actor; `removeDanglingReference` removes one entry through the store's own
// save path (a refusal leaves the store unchanged and returns false). Nothing announces here: the
// check announces its result on the library lane.
import Foundation
import PresetLibrary

extension PresetCoordinator {
    /// The five stores' preset IDs, copied now (R1).
    func integrityReferences() -> PresetReferenceSnapshot {
        let collections: [PresetReferenceSnapshot.Collection] = collectionStore.collections.map {
            (collection: PresetCollection) -> PresetReferenceSnapshot.Collection in
            PresetReferenceSnapshot.Collection(id: collection.id, name: collection.name, presetIDs: collection.presetIDs)
        }
        let tagged: [String] = tagStore.map.tags.keys.sorted()
        let adjusted: [String] = overrides.map { (model: PresetOverridesCoordinator) -> [String] in
            model.store.map.values.keys.sorted()
        } ?? []
        return PresetReferenceSnapshot(favorites: store.favorites, tags: tagged, overrides: adjusted, collections: collections,
                                       recents: recent?.ids ?? [])
    }

    /// R4: a bundled preset of any pack (locked or not) or a playable user preset. The check adds the
    /// records of every other user preset.
    func isListedPreset(_ id: String) -> Bool { library?.preset(id: id) != nil }

    /// R9: removes one dangling entry from its store. True when the entry is gone afterwards.
    @discardableResult
    func removeDanglingReference(_ issue: PresetIntegrityIssue) -> Bool {
        guard issue.kind == .danglingReference, let reference = issue.store else { return false }
        let id: String = issue.presetID
        switch reference {
        case .favorites:
            if store.isFavorite(id) {
                store.toggle(id)
                favoritesVersion += 1
            }
            return !store.isFavorite(id)
        case .tags:
            pruneTags(id)
            return tagStore.map.tags(of: id).isEmpty
        case .overrides:
            guard let overrides else { return false }
            overrides.prune(id)
            return overrides.store.overrides(for: id).isEmpty
        case .collections:
            guard let collectionID = issue.collectionID else { return false }
            changeCollections { try collectionStore.remove([id], from: collectionID) }
            return collectionStore.collection(id: collectionID)?.presetIDs.contains(id) != true
        case .recents:
            guard let recent else { return false }
            recent.remove([id])
            return !recent.ids.contains(id)
        }
    }
}
