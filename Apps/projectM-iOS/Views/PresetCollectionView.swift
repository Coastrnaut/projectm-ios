// PresetCollectionView.swift — one preset collection (roadmap PRE-007,
// specs/005-pre-007-preset-collections; PRE-007-R5, R6, R11, R13, R14, R18). Its presets in the
// user's order; choosing one plays it and makes the collection the scope. Locked presets are listed
// with a lock and open the purchase sheet (the row and PresetCoordinator.choose do that, FR-106).
// Presets that are not in the library are not shown. Reorder with Edit mode, the row menu, or the
// VoiceOver actions.
import PresetLibrary
import SwiftUI

struct PresetCollectionView: View {
    @Bindable var presets: PresetCoordinator
    let collectionID: String
    let onChoose: (IndexedPreset, PresetScope) -> Void
    /// Closes the whole browser.
    let onDone: () -> Void

    /// Drag handles appear only in Edit mode; outside it, touch and hold opens the row menu
    /// (a drag-to-reorder waiting on the same gesture would compete with it).
    @State private var editMode = EditMode.inactive
    @State private var renaming = false

    var body: some View {
        let listing = presets.collectionListing(collectionID)
        List {
            if listing.isEmpty {
                Text("No presets yet. In any preset list, touch and hold a preset (or swipe it to the right) and choose Add to Collection.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("collectionEmpty")
            }
            ForEach(listing) { preset in
                PresetRow(presets: presets, preset: preset, showsPack: true,
                          collection: PresetRow.CollectionPlace(id: collectionID, isFirst: preset == listing.first,
                                                                isLast: preset == listing.last)) {
                    onChoose(preset, .collection(collectionID))
                }
            }
            .onMove(perform: editMode.isEditing ? { presets.movePresets(in: collectionID, fromOffsets: $0, toOffset: $1) } : nil)
        }
        .navigationTitle(presets.collection(id: collectionID)?.name ?? "Collection")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            if presets.collection(id: collectionID) != nil {
                ToolbarItemGroup(placement: .bottomBar) {
                    EditButton().disabled(listing.count < 2)
                    Spacer()
                    Button("Rename") { renaming = true }
                        .accessibilityIdentifier("renameCollection")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $renaming) {
            CollectionNameSheet(presets: presets, renaming: presets.collection(id: collectionID))
        }
    }
}
