// PresetCoordinator+Tags.swift — PRE-003 preset tags in the app (spec PRE-003-R3 to R12; contract C4).
//
// * Tags live in PresetTagStore (`Application Support/PresetCollections/tags.json`); every change is
//   saved before it is shown, and a refusal or a failed save changes nothing and sets `tagsMessage`.
// * The inverted index is rebuilt only when the tags or the library change (`tagIndex`), over the
//   presets the library lists: tags of other IDs are kept but hidden (R7).
// * Selected chips (`selectedTags`) are in memory only; a chip whose tag vanished is dropped.
// * Edits announce on the shared announcer's library lane; a chip change announces the result count
//   on the search lane (never a direct post; ACC-011).
import Foundation
import PresetLibrary

extension PresetCoordinator {
    nonisolated static func tagsNoticeText(_ notice: PresetTagStore.LoadNotice) -> String? {
        switch notice {
        case .none: nil
        case .unreadableSetAside: PresetTagStore.unreadableText
        case let .repaired(dropped): PresetTagStore.repairedText(dropped)
        }
    }

    nonisolated static func taggedCountText(_ count: Int) -> String {
        count == 1 ? "1 preset with these tags" : "\(count.formatted(.number.locale(Locale(identifier: "en_US")))) presets with these tags"
    }

    nonisolated static let taggedEmptyText = "No presets have all these tags"

    // MARK: - Reading

    /// The index over the listed presets, cached per (tags version, library).
    var tagIndex: PresetTagIndex {
        _ = tagsVersion
        guard let library else { return .empty }
        let identity = ObjectIdentifier(library)
        if let cached = cachedTagIndex, cached.version == tagsVersion, cached.library == identity { return cached.index }
        let index = PresetTagIndex(map: tagStore.map) { (id: String) -> Bool in library.preset(id: id) != nil }
        cachedTagIndex = (tagsVersion, identity, index)
        return index
    }

    /// The chips: every tag a listed preset carries, sorted (R3).
    var tagVocabulary: [String] { tagIndex.vocabulary }

    func tags(of preset: IndexedPreset) -> [String] {
        _ = tagsVersion
        return tagStore.map.tags(of: preset.id)
    }

    func presetCount(withTag tag: String) -> Int { tagIndex.count(of: tag) }

    /// Non-nil when the saved tags come from a newer app version.
    var tagsUnavailableText: String? {
        tagStore.availability == .available ? nil : PresetTagError.newerFormat.message
    }

    /// ", tags Calm, Slow" for a row's VoiceOver label (R12); empty without tags.
    func tagsLabelSuffix(_ preset: IndexedPreset) -> String {
        let list: [String] = tags(of: preset)
        return list.isEmpty ? "" : ", tags " + list.joined(separator: ", ")
    }

    /// The selected chips that still exist, in their current spelling.
    var activeTags: [String] { tagIndex.existing(selectedTags) }

    func isSelected(tag: String) -> Bool {
        let folded: String = PresetTagMap.fold(tag)
        return activeTags.contains { (t: String) -> Bool in PresetTagMap.fold(t) == folded }
    }

    /// R8: the presets carrying every selected tag, alphabetical across packs (locked included);
    /// only favorites among them when `favoritesOnly`.
    var taggedListing: [IndexedPreset] {
        guard let library else { return [] }
        let listing: [IndexedPreset] = library.taggedListing(activeTags, index: tagIndex)
        guard favoritesOnly else { return listing }
        _ = favoritesVersion
        return listing.filter { (preset: IndexedPreset) -> Bool in isFavorite(preset) }
    }

    /// R9: search over names, authors and tags, narrowed by the selected chips.
    func searchResults(_ query: String) -> (groups: [(source: String, presets: [IndexedPreset])], truncated: Bool) {
        guard let library else { return ([], false) }
        let index: PresetTagIndex = tagIndex
        let chips: [String] = activeTags
        let within: Set<String>? = chips.isEmpty ? nil : index.matching(all: chips)
        return library.search(query, limit: PresetLibrary.searchLimit, tagMatches: index.presetIDs(tagContaining: query), within: within)
    }

    // MARK: - Chips

    func toggleTag(_ tag: String) {
        var chips: [String] = activeTags
        let folded: String = PresetTagMap.fold(tag)
        if let index = chips.firstIndex(where: { (t: String) -> Bool in PresetTagMap.fold(t) == folded }) {
            chips.remove(at: index)
        } else {
            chips.append(tag)
        }
        selectedTags = chips
        announceSearch(chips.isEmpty ? "Tag filter cleared" : Self.taggedCountText(taggedListing.count))
    }

    func clearTags() {
        guard !selectedTags.isEmpty else { return }
        selectedTags = []
        announceSearch("Tag filter cleared")
    }

    // MARK: - Editing (R4, R5)

    @discardableResult
    func addTag(_ text: String, to preset: IndexedPreset) -> Bool {
        do {
            let stored: String = try tagStore.add(text, to: preset.id)
            tagsChanged()
            announceLibrary("Tagged \(preset.name) \(stored).")
            return true
        } catch {
            refuseTagChange(error)
            return false
        }
    }

    @discardableResult
    func removeTag(_ tag: String, from preset: IndexedPreset) -> Bool {
        do {
            let removed: String = try tagStore.remove(tag, from: preset.id)
            tagsChanged()
            announceLibrary("Removed tag \(removed) from \(preset.name).")
            return true
        } catch {
            refuseTagChange(error)
            return false
        }
    }

    /// R7: the user removed one of their presets; its tags go with it (silently).
    func pruneTags(_ presetID: String) {
        do {
            if try tagStore.prune(presetID) { tagsChanged() }
        } catch {
            refuseTagChange(error)
        }
    }

    func dismissTagsMessage() { tagsMessage = nil }
    func dismissTagsNotice() { tagsNotice = nil }

    private func tagsChanged() {
        tagsVersion += 1
        tagsMessage = nil
        if case .tagged = scope { plannedRandomInvalidated() }
    }

    private func refuseTagChange(_ error: any Error) {
        let message: String = (error as? PresetTagError)?.message ?? PresetTagError.saveFailed.message
        tagsMessage = message
        tagsVersion += 1
        announceLibrary(message)
    }
}
