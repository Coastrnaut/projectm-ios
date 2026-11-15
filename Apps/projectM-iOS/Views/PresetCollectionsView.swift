// PresetCollectionsView.swift — the list of the user's preset collections (roadmap PRE-007,
// specs/005-pre-007-preset-collections; PRE-007-R1-R3, R7, R15, R18). Create, rename, delete and
// reorder by hand. Reordering works three ways: Edit mode's drag handles, Move Up / Move Down in
// each row's menu, and the same two as VoiceOver actions, so no drag is ever required.
// SHOW-015-R4: while the scene (performance) lock is on, Delete, Edit, drag reorder and Move Up/Down are hidden and
// the lock note shows; New Collection and Rename stay (additive).
import PresetLibrary
import SwiftUI

/// Where the browser's collections screens lead.
enum CollectionRoute: Hashable {
    case list
    case collection(String)
    /// PRE-008: one smart collection.
    case smart(String)
}

struct PresetCollectionsView: View {
    @Bindable var presets: PresetCoordinator
    /// Closes the whole browser.
    let onDone: () -> Void

    @State private var namingNew = false
    @State private var namingSmart = false   // PRE-008
    /// Drag handles appear only in Edit mode; outside it, touch and hold opens the row menu
    /// (a drag-to-reorder waiting on the same gesture would compete with it).
    @State private var editMode = EditMode.inactive
    @State private var renaming: PresetCollection?
    @State private var deleting: PresetCollection?

    /// SHOW-015-R4.
    private var locked: Bool { presets.isCollectionEditLocked }

    var body: some View {
        List {
            if locked { Section { SceneLockNote() } }   // SHOW-015-R4
            if let unavailable = presets.collectionsUnavailableText {
                Text(unavailable)
                    .accessibilityIdentifier("collectionsUnavailable")
            } else {
                if let notice = presets.collectionsNotice {
                    Section {
                        Text(notice).accessibilityIdentifier("collectionsNotice")
                        Button("Dismiss") { presets.dismissCollectionsNotice() }
                            .accessibilityIdentifier("dismissCollectionsNotice")
                    }
                }
                if presets.collections.isEmpty {
                    Text("No collections yet. Tap New Collection to make one, then add presets to it from any list.")
                        .accessibilityIdentifier("collectionsEmpty")
                }
                ForEach(presets.collections) { collection in
                    row(collection)
                }
                .onMove(perform: editMode.isEditing && !locked ? { presets.moveCollections(fromOffsets: $0, toOffset: $1) } : nil)
            }
            SmartCollectionsSection(presets: presets)   // PRE-008
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            if presets.collectionsUnavailableText == nil {
                ToolbarItemGroup(placement: .bottomBar) {
                    if !locked { EditButton().disabled(presets.collections.count < 2) }   // SHOW-015-R4
                    Spacer()
                    Button {
                        namingNew = true
                    } label: {
                        Label("New Collection", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("newCollection")
                    Button {
                        namingSmart = true
                    } label: {
                        Label("New Smart Collection", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("newSmartCollection")   // PRE-008
                }
            }
        }
        .environment(\.editMode, $editMode)
        .onChange(of: locked) { if locked { editMode = .inactive } }   // SHOW-015: locking ends Edit mode
        .sheet(isPresented: $namingNew) {
            CollectionNameSheet(presets: presets)
        }
        .sheet(isPresented: $namingSmart) { SmartRulesSheet(presets: presets) }   // PRE-008
        .sheet(item: $renaming) { collection in
            CollectionNameSheet(presets: presets, renaming: collection)
        }
        .alert("Delete “\(deleting?.name ?? "")”?",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { collection in
            Button("Delete Collection", role: .destructive) { presets.deleteCollection(collection.id) }
                .accessibilityIdentifier("confirmDeleteCollection")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Only the collection is deleted. Its presets stay in your library, in Favorites and in other collections.")
        }
    }

    private func row(_ collection: PresetCollection) -> some View {
        let count = presets.collectionCount(collection.id)
        let isFirst = presets.collections.first?.id == collection.id
        let isLast = presets.collections.last?.id == collection.id
        return NavigationLink(value: CollectionRoute.collection(collection.id)) {
            HStack {
                Text(collection.name)
                Spacer()
                Text(count.formatted())   // ACC-004: full contrast (audit)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(PresetCoordinator.collectionRowLabel(name: collection.name, count: count))
        }
        .accessibilityIdentifier("collection:\(collection.name)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !locked {   // SHOW-015-R4
                Button {
                    deleting = collection
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
            Button {
                renaming = collection
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
        .contextMenu {
            Button { renaming = collection } label: { Label("Rename", systemImage: "pencil") }
            if !locked { reorderAndDeleteItems(collection, isFirst: isFirst, isLast: isLast) }   // SHOW-015-R4
        }
        .accessibilityActions {
            if !locked {   // SHOW-015-R4
                Button("Move Up") { presets.moveCollection(collection.id, by: -1) }
                Button("Move Down") { presets.moveCollection(collection.id, by: 1) }
            }
        }
    }

    @ViewBuilder
    private func reorderAndDeleteItems(_ collection: PresetCollection, isFirst: Bool, isLast: Bool) -> some View {
        Button { presets.moveCollection(collection.id, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
            .disabled(isFirst)
        Button { presets.moveCollection(collection.id, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
            .disabled(isLast)
        Button(role: .destructive) { deleting = collection } label: { Label("Delete", systemImage: "trash") }
    }
}
