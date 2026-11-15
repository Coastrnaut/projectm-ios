// PresetCoordinator+Smart.swift — PRE-008 smart collections in the browser (specs/228-pre-008-smart-collections,
// PRE-008-R3, R7-R9; contract C4).
//
// * Rules live in `smartStore` (`PresetCollections/smart-collections.json`); membership is computed, never
//   stored, from the library, the PRE-003 tag index, favorites and the PRE-004/PRE-005 filters, so a rule
//   edit, a new tag or a new favorite shows at once.
// * A smart collection is a `.collection(id)` scope: `members` merges the scope's smart membership into the
//   collections map (smart IDs start with `smart-`, so they never collide with manual ones).
// * Every change is saved before it is shown; a refusal or failed save sets `collectionsMessage` (PRE-007-R8).
import Foundation
import PresetLibrary

extension PresetCoordinator {
    /// The inputs to matching, as the browser sees them now.
    var smartContext: PresetSmartContext? {
        guard let library else { return nil }
        _ = favoritesVersion
        return PresetSmartContext(library: library, tags: tagIndex, favorites: Set(store.favorites),
                                  colors: colorFilter, energy: energyFilter)
    }

    /// The user's smart collections, in creation order.
    var smartCollections: [PresetSmartCollection] {
        _ = smartVersion
        return smartStore.collections
    }

    var smartUnavailableText: String? {
        smartStore.availability == .available ? nil : PresetSmartCollectionStore.newerFormatText
    }

    func smartCollection(id: String) -> PresetSmartCollection? {
        _ = smartVersion
        return smartStore.collection(id: id)
    }

    var smartNames: [String: String] {
        _ = smartVersion
        return smartStore.namesByCollection
    }

    /// The member IDs of a smart collection; nil when `id` is not one.
    func smartMembers(_ id: String) -> [String]? {
        guard let collection = smartCollection(id: id), let context = smartContext else { return nil }
        return PresetSmartMatcher.members(of: collection, in: context)
    }

    /// What a smart collection's screen lists (locked presets included; the rows mark them).
    func smartListing(_ id: String) -> [IndexedPreset] {
        guard let library, let ids = smartMembers(id) else { return [] }
        return library.collectionListing(ids)
    }

    func smartCount(_ id: String) -> Int { smartMembers(id)?.count ?? 0 }

    /// R8: the live count of rules being edited.
    func smartDraftCount(match: PresetSmartMatch, conditions: [PresetSmartCondition]) -> Int {
        guard let context = smartContext else { return 0 }
        return PresetSmartMatcher.members(match: match, conditions: conditions, in: context).count
    }

    func smartNameProblem(_ name: String, renaming id: String?) -> String? {
        _ = smartVersion
        return smartStore.nameProblem(name, renaming: id)?.message
    }

    @discardableResult
    func createSmartCollection(named name: String, match: PresetSmartMatch, conditions: [PresetSmartCondition]) -> PresetSmartCollection? {
        var created: PresetSmartCollection?
        changeSmart { created = try smartStore.create(name: name, match: match, conditions: conditions) }
        return created
    }

    @discardableResult
    func updateSmartCollection(_ id: String, match: PresetSmartMatch, conditions: [PresetSmartCondition]) -> Bool {
        changeSmart { try smartStore.update(id, match: match, conditions: conditions) }
    }

    @discardableResult
    func renameSmartCollection(_ id: String, to name: String) -> Bool {
        changeSmart { try smartStore.rename(id, to: name) }
    }

    /// Removes the rule set only; if it was the scope, the scope falls back (R9).
    func deleteSmartCollection(_ id: String) {
        if refusedByLock() { return }   // SHOW-015-R2
        if changeSmart({ try smartStore.delete(id) }) { resolveScope() }
    }

    /// "Calm, smart collection, 3 presets" (R7).
    nonisolated static func smartRowLabel(name: String, count: Int) -> String {
        let number: String = count.formatted(.number.locale(Locale(identifier: "en_US")))
        return "\(name), smart collection, \(number) \(count == 1 ? "preset" : "presets")"
    }

    nonisolated static func unknownRulesText(_ count: Int) -> String {
        count == 1 ? "1 rule from a newer version is not applied." : "\(count) rules from a newer version are not applied."
    }

    @discardableResult
    private func changeSmart(_ change: () throws -> Void) -> Bool {
        defer { smartVersion += 1 }
        do {
            try change()
            plannedRandomInvalidated()
            return true
        } catch let error as PresetSmartCollectionError {
            collectionsMessage = error.message
        } catch {
            collectionsMessage = (error as? PresetCollectionError)?.message ?? PresetCollectionError.saveFailed.message
        }
        return false
    }
}
