// PresetTagChips.swift — PRE-003: the browser's tag chips and the tagged list (spec PRE-003-R8,
// R10, R12; contract C4). The chip row shows the vocabulary (tags of listed presets) when there is
// one; selected chips combine with AND and are kept in memory while the app runs. "Clear" deselects
// all. Each chip says how many presets carry it and is marked Selected for VoiceOver; chip changes
// announce the result count through PresetCoordinator (search lane), never a direct post.
import PresetLibrary
import SwiftUI

struct PresetTagChipRow: View {
    let presets: PresetCoordinator

    var body: some View {
        let vocabulary: [String] = presets.tagVocabulary
        if !vocabulary.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(vocabulary, id: \.self) { (tag: String) in chip(tag) }
                    if !presets.activeTags.isEmpty { clearChip }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter by tag")
            .accessibilityIdentifier("presetTagChips")
        }
    }

    private func chip(_ tag: String) -> some View {
        let selected: Bool = presets.isSelected(tag: tag)
        let count: Int = presets.presetCount(withTag: tag)
        let value: String = count == 1 ? "1 preset" : "\(count) presets"
        let traits: AccessibilityTraits = selected ? .isSelected : []
        let fill: Color = selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)
        return Button { presets.toggleTag(tag) } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark" : "tag").font(.caption2).accessibilityHidden(true)
                Text(tag).font(.footnote).foregroundStyle(Color.primary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(tag)
        .accessibilityValue(value)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("presetTagChip.\(tag)")
    }

    private var clearChip: some View {
        Button { presets.clearTags() } label: {
            Label("Clear", systemImage: "xmark.circle").font(.footnote)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Clear tag filter")
        .accessibilityIdentifier("presetTagClear")
    }
}

/// The presets carrying every selected tag (R8) and, PRE-004, every selected colour: alphabetical across
/// packs, locked ones marked by their rows. Choosing one makes "Tagged: …" the scope (R10), or All
/// presets when only colours are selected (PRE-004-R11).
struct TaggedPresetList: View {
    let presets: PresetCoordinator
    let onChoose: (IndexedPreset, PresetScope) -> Void

    var body: some View {
        let listing: [IndexedPreset] = presets.filteredListing   // PRE-004: tags AND colours
        let scope: PresetScope = presets.filteredScope   // PRE-004-R11
        if listing.isEmpty {
            Text(presets.filteredEmptyText).accessibilityIdentifier("taggedEmpty")
        }
        ForEach(listing) { (preset: IndexedPreset) in
            PresetRow(presets: presets, preset: preset, showsPack: true, previewScope: scope) { onChoose(preset, scope) }
        }
    }
}
