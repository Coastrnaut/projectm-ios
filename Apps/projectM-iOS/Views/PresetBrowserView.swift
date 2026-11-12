// PresetBrowserView.swift — the preset browser sheet (feature 001 T090; feature 002 T219-T222, T245;
// FR-111-FR-115, FR-124). A library home (Included, the four packs with counts and a lock before
// purchase, All A-Z), folder drill-down by each pack's own structure, search over names and
// authors grouped by pack and capped, and a Favorites view across packs. Choosing a preset makes
// its list the scope (FR-116); a locked preset opens the purchase sheet (FR-106).
// Roadmap PRE-007: the home also leads to the user's collections, and every preset row offers
// "Add to Collection" (touch and hold, or swipe right).
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
            .navigationDestination(for: CollectionRoute.self) { route in
                switch route {
                case .list: PresetCollectionsView(presets: presets) { dismiss() }
                case .collection(let id):
                    PresetCollectionView(presets: presets, collectionID: id, onChoose: onChoose) { dismiss() }
                }
            }
            .collectionsAlert(presets)
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
                    FolderRow(title: node.title, count: presets.displayCount(of: node), locked: node.locked && !presets.unlocked)
                }
                .accessibilityIdentifier("node:\(node.id)")
            }
            // PRE-007: the user's own collections, after the library's lists.
            NavigationLink(value: CollectionRoute.list) {
                HStack {
                    Text("Collections")
                    Spacer()
                    Text(presets.collections.count.formatted()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(PresetCoordinator.collectionsRowLabel(count: presets.collections.count))
            }
            .accessibilityIdentifier("node:collections")
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

/// One preset: name, author (and pack), lock, current mark, star (FR-114, FR-124). Every row offers
/// "Add to Collection" (PRE-007-R4); inside a collection it also offers Move Up, Move Down and
/// Remove (R5, R6, R18).
struct PresetRow: View {
    /// The row's place in the collection that lists it.
    struct CollectionPlace {
        let id: String
        let isFirst: Bool
        let isLast: Bool
    }

    @Bindable var presets: PresetCoordinator
    let preset: IndexedPreset
    let showsPack: Bool
    var collection: CollectionPlace?
    let onChoose: () -> Void
    @State private var addingToCollection = false

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
            .accessibilityAction(named: "Add to Collection") { addingToCollection = true }
            .modifier(CollectionMoveActions(presets: presets, preset: preset, collection: collection))
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                addingToCollection = true
            } label: {
                Label("Add to Collection", systemImage: "folder.badge.plus")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let collection {
                Button {
                    presets.removeFromCollection([preset], collection.id)
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .tint(.red)
            }
        }
        .contextMenu {
            Button { addingToCollection = true } label: { Label("Add to Collection…", systemImage: "folder.badge.plus") }
            if let collection {
                Button { presets.movePreset(preset, in: collection.id, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                    .disabled(collection.isFirst)
                Button { presets.movePreset(preset, in: collection.id, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                    .disabled(collection.isLast)
                Button(role: .destructive) {
                    presets.removeFromCollection([preset], collection.id)
                } label: {
                    Label("Remove from Collection", systemImage: "minus.circle")
                }
            }
        }
        .sheet(isPresented: $addingToCollection) { AddToCollectionSheet(presets: presets, preset: preset) }
    }

    /// VoiceOver actions for reordering and removing inside a collection (PRE-007-R18).
    private struct CollectionMoveActions: ViewModifier {
        let presets: PresetCoordinator
        let preset: IndexedPreset
        let collection: CollectionPlace?

        func body(content: Content) -> some View {
            if let collection {
                content
                    .accessibilityAction(named: "Move Up") { presets.movePreset(preset, in: collection.id, by: -1) }
                    .accessibilityAction(named: "Move Down") { presets.movePreset(preset, in: collection.id, by: 1) }
                    .accessibilityAction(named: "Remove from Collection") { presets.removeFromCollection([preset], collection.id) }
            } else {
                content
            }
        }
    }

    private var subtitle: String {
        guard showsPack, let pack = presets.library?.pack(id: preset.source) else { return preset.author }
        return "\(preset.author) · \(pack.title)"
    }
}
