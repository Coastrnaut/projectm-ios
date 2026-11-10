// PresetBrowserView.swift — the preset browser sheet (feature 001 T090; feature 002 T219-T222, T245;
// FR-111-FR-115, FR-124). A library home (Included, the four packs with counts and a lock before
// purchase, All A-Z), folder drill-down by each pack's own structure, search over names and
// authors grouped by pack and capped, and a Favorites view across packs. Choosing a preset makes
// its list the scope (FR-116); a locked preset opens the purchase sheet (FR-106).
import PresetLibrary
import SwiftUI

struct PresetBrowserView: View {
    @Bindable var presets: PresetCoordinator
    let onChoose: (IndexedPreset, PresetScope) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: (groups: [(source: String, presets: [IndexedPreset])], truncated: Bool) = ([], false)

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResults
                } else {
                    Picker("Show", selection: $presets.favoritesOnly) {
                        Text("All").tag(false)
                        Text("Favorites").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("favoritesFilter")
                    if presets.favoritesOnly {
                        favorites
                    } else {
                        home
                    }
                }
            }
            .navigationTitle("Presets")
            .navigationDestination(for: PresetNode.self) { node in
                PresetFolderView(presets: presets, node: node, onChoose: onChoose) { dismiss() }
            }
            .searchable(text: $query, prompt: "Presets and authors")
            .task(id: query) {
                // Debounced search over the in-memory index (FR-113, research R-26).
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                results = presets.library?.search(query, limit: PresetLibrary.searchLimit) ?? (groups: [], truncated: false)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("presetBrowser")
    }

    @ViewBuilder private var home: some View {
        if let library = presets.library {
            ForEach(library.home) { node in
                NavigationLink(value: node) {
                    FolderRow(title: node.title, count: node.presetCount, locked: node.locked && !presets.unlocked)
                }
                .accessibilityIdentifier("node:\(node.id)")
            }
        } else {
            ProgressView("Loading presets…")
        }
    }

    @ViewBuilder private var favorites: some View {
        if let empty = presets.emptyStateText {
            Text(empty)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("favoritesEmpty")
        }
        ForEach(presets.favoritesListing) { preset in
            PresetRow(presets: presets, preset: preset, showsPack: true) { onChoose(preset, .favorites) }
        }
    }

    @ViewBuilder private var searchResults: some View {
        // First, so it is seen without scrolling past the capped list.
        if results.truncated {
            Text("Showing the first \(PresetLibrary.searchLimit) matches. Refine your search to see more.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("refineSearch")
        }
        ForEach(results.groups, id: \.source) { group in
            Section(presets.library?.pack(id: group.source)?.title ?? group.source) {
                ForEach(group.presets) { preset in
                    PresetRow(presets: presets, preset: preset, showsPack: false) { onChoose(preset, .search(query)) }
                }
            }
        }
        if results.groups.isEmpty {
            Text("No presets match").foregroundStyle(.secondary)
        }
    }
}

struct FolderRow: View {
    let title: String
    let count: Int
    let locked: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if locked { Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true) }
            Text(count.formatted()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) presets\(locked ? ", locked" : "")")
    }
}

/// One preset: name, author (and pack), lock, current mark, star (FR-114, FR-124).
struct PresetRow: View {
    @Bindable var presets: PresetCoordinator
    let preset: IndexedPreset
    let showsPack: Bool
    let onChoose: () -> Void

    var body: some View {
        let locked = presets.isLocked(preset)
        let favorite = presets.isFavorite(preset)
        HStack {
            Button(action: onChoose) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).foregroundStyle(.primary)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if locked {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    } else if preset == presets.current {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityLabel("\(preset.name), by \(preset.author)\(locked ? ", locked" : "")\(preset == presets.current ? ", current preset" : "")")
            .accessibilityIdentifier("preset:\(preset.name)")
            Button {
                presets.toggleFavorite(preset)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityIdentifier("star:\(preset.name)")
        }
    }

    private var subtitle: String {
        guard showsPack, let pack = presets.library?.pack(id: preset.source) else { return preset.author }
        return "\(preset.author) · \(pack.title)"
    }
}
