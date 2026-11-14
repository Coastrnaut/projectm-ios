// PresetBrowserView.swift — the preset browser sheet (feature 001 T090; feature 002 T219-T222, T245;
// FR-111-FR-115, FR-124). A library home (Included, the four packs with counts and a lock before
// purchase, All A-Z), folder drill-down by each pack's own structure, search over names and
// authors grouped by pack and capped, and a Favorites view across packs. Choosing a preset makes
// its list the scope (FR-116); a locked preset opens the purchase sheet (FR-106).
// Roadmap PRE-007: the home also leads to the user's collections, and every preset row offers
// "Add to Collection" (touch and hold, or swipe right).
// Roadmap PRE-012: the home leads to My Presets (imported presets, Import Preset…, Quarantine).
// Roadmap PRE-015: every built-in preset row offers "Duplicate to My Presets", every playable
// user preset row offers "Edit" (context menu, VoiceOver action; PRE-015-R1, R9).
import PresetLibrary
import SwiftUI

struct PresetBrowserView: View {
    @Bindable var presets: PresetCoordinator
    /// The user's imported presets (PRE-012).
    let userPresets: UserPresetsCoordinator
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
                    .accessibilityLabel("Show presets")   // ACC-004-R1: a segmented picker hides its title
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
            .navigationDestination(for: UserPresetRoute.self) { route in
                switch route {
                case .list: UserPresetsView(presets: presets, userPresets: userPresets, onChoose: onChoose) { dismiss() }
                case .quarantine: PresetQuarantineView(userPresets: userPresets) { dismiss() }
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
        // PRE-015: on the stack itself, so it shows over whichever list the row is in.
        .duplicateResultAlert(userPresets, isPresented: true)
        // ACC-002-R6: likewise the warning before a flagged preset loads; Load Anyway closes the browser.
        .flashWarningAlert(presets, isPresented: true) { dismiss() }
        .onDisappear { presets.cancelFlashWarning() }   // closing the browser answers Cancel
        .environment(userPresets)   // PRE-015: rows duplicate and edit through it
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
                    Text(presets.collections.count.formatted())   // ACC-004: full contrast (audit)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(PresetCoordinator.collectionsRowLabel(count: presets.collections.count))
            }
            .accessibilityIdentifier("node:collections")
            // PRE-012: the presets the user imported.
            NavigationLink(value: UserPresetRoute.list) {
                HStack {
                    Text(UserPresetText.scopeTitle)
                    Spacer()
                    Text(userPresets.playable.count.formatted())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(UserPresetsCoordinator.myPresetsRowLabel(count: userPresets.playable.count))
            }
            .accessibilityIdentifier("node:myPresets")
        } else {
            ProgressView("Loading presets…")
        }
    }

    @ViewBuilder private var favorites: some View {
        if let empty = presets.emptyStateText {
            Text(empty)
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
                .accessibilityIdentifier("refineSearch")
        }
        ForEach(results.groups, id: \.source) { group in
            Section(group.source == PresetLibrary.userSource ? UserPresetText.scopeTitle
                    : presets.library?.pack(id: group.source)?.title ?? group.source) {
                ForEach(group.presets) { preset in
                    PresetRow(presets: presets, preset: preset, showsPack: false) { onChoose(preset, .search(query)) }
                }
            }
        }
        if results.groups.isEmpty {
            Text("No presets match")
        }
    }
}

extension View {
    /// ACC-002-R6, R14: the warning before a flagged preset loads, with Load Anyway and Cancel. A
    /// standard alert, so VoiceOver announces it and its text follows Dynamic Type. `isPresented`
    /// lets the visualizer show it only while the browser, which shows its own, is closed.
    func flashWarningAlert(_ presets: PresetCoordinator, isPresented: Bool, afterLoad: @escaping () -> Void = {}) -> some View {
        let warning = presets.flashWarning
        return alert(PresetCoordinator.flashWarningTitle,
                     isPresented: Binding(get: { isPresented && presets.flashWarning != nil },
                                          set: { if !$0 && presets.flashWarning == warning { presets.cancelFlashWarning() } }),
                     presenting: warning) { shown in
            Button("Load Anyway") {
                Task { @MainActor in
                    await presets.confirmFlashWarning(shown)
                    afterLoad()
                }
            }
            .accessibilityIdentifier("loadFlaggedAnyway")
            Button("Cancel", role: .cancel) { presets.cancelFlashWarning() }
                .accessibilityIdentifier("cancelFlagged")
        } message: { shown in
            Text(PresetCoordinator.flashWarningMessage(shown.preset.name))
        }
    }

    /// The result of "Duplicate to My Presets" (PRE-015). `isPresented` lets the visualizer show
    /// it only while the browser, which shows its own, is closed.
    func duplicateResultAlert(_ userPresets: UserPresetsCoordinator, isPresented: Bool) -> some View {
        alert("Duplicate to My Presets",
              isPresented: Binding(get: { isPresented && userPresets.duplicateMessage != nil },
                                   set: { if !$0 { userPresets.duplicateMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(userPresets.duplicateMessage ?? "")
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
            Text(count.formatted())   // ACC-004: secondary grey failed the contrast audit at body size
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
    /// Set in My Presets: the row also offers Information and Remove (PRE-012-R24, US4).
    struct UserActions {
        let info: () -> Void
        let remove: () -> Void
    }
    var user: UserActions?
    let onChoose: () -> Void
    @State private var addingToCollection = false
    /// PRE-015: duplicating and editing; absent outside the browser.
    @Environment(UserPresetsCoordinator.self) private var userPresets: UserPresetsCoordinator?
    @State private var editing: UserPreset?

    private var isBundled: Bool { preset.source != PresetLibrary.userSource }

    private func duplicate() {
        guard let userPresets else { return }
        Task { await userPresets.duplicate(preset) }
    }

    private func edit() {
        editing = userPresets?.editableRecord(for: preset)
    }

    private var duplicateAction: (() -> Void)? {
        guard isBundled, userPresets != nil else { return nil }
        return { duplicate() }
    }

    private var editAction: () -> Void { { edit() } }

    var body: some View {
        let locked = presets.isLocked(preset)
        let editable = userPresets?.editableRecord(for: preset) != nil
        let favorite = presets.isFavorite(preset)
        HStack {
            Button(action: onChoose) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        // ACC-004: label colour. `.primary` inside a button resolves to the tint, and blue
                        // text on white failed the contrast audit ("nearly passed", about 4:1).
                        Text(preset.name).foregroundStyle(Color.primary)
                        Text(subtitle).font(.caption).foregroundStyle(Color.primary)
                    }
                    Spacer()
                    if presets.isFlagged(preset) {
                        // ACC-002-R7: a symbol and words, never color alone.
                        Label("May flash", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .accessibilityIdentifier("mayFlash:\(preset.name)")
                    }
                    if locked {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    } else if preset == presets.current {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityLabel(presets.rowLabel(preset, locked: locked))
            // ACC-004-R2, R4: the playing preset is selected; the hint says what activating does.
            .accessibilityAddTraits(preset == presets.current ? .isSelected : [])
            .accessibilityHint(locked ? "Opens the unlock sheet" : "Plays this preset")
            .accessibilityIdentifier("preset:\(preset.name)")
            .accessibilityAction(named: "Add to Collection") { addingToCollection = true }
            // ACC-004-R3: favoriting without finding the separate star.
            .accessibilityAction(named: favorite ? "Remove from Favorites" : "Add to Favorites") {
                presets.toggleFavoriteAnnounced(preset)
            }
            .modifier(CollectionMoveActions(presets: presets, preset: preset, collection: collection))
            .modifier(UserPresetActions(user: user))
            .modifier(CopyActions(duplicate: duplicateAction, edit: editable ? editAction : nil))
            Button {
                presets.toggleFavoriteAnnounced(preset)   // ACC-004-R5
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
            if let user {
                Button(action: user.remove) { Label("Remove", systemImage: "trash") }
                    .tint(.red)
                    .accessibilityIdentifier("removeUserPreset")
                Button(action: user.info) { Label("Info", systemImage: "info.circle") }
                    .accessibilityIdentifier("userPresetInfo")
                if editable {
                    Button(action: edit) { Label("Edit", systemImage: "pencil") }
                        .tint(.blue)
                        .accessibilityIdentifier("editUserPresetSwipe")
                }
            }
        }
        .contextMenu {
            Button { addingToCollection = true } label: { Label("Add to Collection…", systemImage: "folder.badge.plus") }
            if isBundled && userPresets != nil {
                Button(action: duplicate) { Label("Duplicate to My Presets", systemImage: "plus.square.on.square") }
                    .accessibilityIdentifier("duplicatePreset")
            }
            if editable {
                Button(action: edit) { Label("Edit", systemImage: "pencil") }
                    .accessibilityIdentifier("editUserPreset")
            }
            if let user {
                Button(action: user.info) { Label("Information", systemImage: "info.circle") }
                Button(role: .destructive, action: user.remove) { Label("Remove from My Presets", systemImage: "trash") }
            }
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
        .sheet(item: $editing) { record in
            if let userPresets { UserPresetEditorView(preset: record, userPresets: userPresets) }
        }
    }

    /// VoiceOver actions for duplicating a built-in preset and editing a user preset (PRE-015-R1, R9).
    private struct CopyActions: ViewModifier {
        let duplicate: (() -> Void)?
        let edit: (() -> Void)?

        func body(content: Content) -> some View {
            if let duplicate {
                content.accessibilityAction(named: "Duplicate to My Presets", duplicate)
            } else if let edit {
                content.accessibilityAction(named: "Edit", edit)
            } else {
                content
            }
        }
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

    /// VoiceOver actions for an imported preset (PRE-012-R29).
    private struct UserPresetActions: ViewModifier {
        let user: UserActions?

        func body(content: Content) -> some View {
            if let user {
                content
                    .accessibilityAction(named: "Information", user.info)
                    .accessibilityAction(named: "Remove from My Presets", user.remove)
            } else {
                content
            }
        }
    }

    private var subtitle: String {
        if showsPack && preset.source == PresetLibrary.userSource { return "\(preset.author) · \(UserPresetText.scopeTitle)" }
        guard showsPack, let pack = presets.library?.pack(id: preset.source) else { return preset.author }
        return "\(preset.author) · \(pack.title)"
    }
}
