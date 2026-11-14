// CollectionSheets.swift — the two sheets of preset collections (roadmap PRE-007,
// specs/005-pre-007-preset-collections; PRE-007-R1, R2, R4, R9, R18): naming a collection, and
// adding a preset to one. All rules live in PresetLibrary (PresetCollectionStore); these views only
// show them.
import PresetLibrary
import SwiftUI

/// Names a new collection or renames one. The reason a name cannot be used is shown while typing,
/// and Save stays disabled until the name is valid (R9).
/// A change that is refused when saving (a limit, a failed save) keeps the sheet open and shows why.
struct CollectionNameSheet: View {
    @Bindable var presets: PresetCoordinator
    /// The collection to rename; nil creates a new one.
    var renaming: PresetCollection?
    /// Called with the new collection after it was created and saved. When set, the caller closes
    /// the sheets (closing its own sheet takes this one with it); when nil this sheet closes itself.
    var onCreated: ((PresetCollection) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var edited = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityLabel("Collection name")
                        .accessibilityIdentifier("collectionName")
                } footer: {
                    if edited, let reason = problem(name) {
                        Text(reason)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("collectionNameError")
                    } else {
                        Text("Up to \(PresetCollectionLimits.maxNameLength) characters.")
                    }
                }
            }
            .navigationTitle(renaming == nil ? "New Collection" : "Rename Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(problem(name) != nil)
                        .accessibilityIdentifier("saveCollectionName")
                }
            }
            .onAppear {
                name = renaming?.name ?? ""
                focused = true
            }
            .onChange(of: name) { edited = true }
            .collectionsAlert(presets)
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard problem(name) == nil else {
            edited = true
            return
        }
        if let renaming {
            if presets.renameCollection(renaming.id, to: name) { dismiss() }
        } else if let created = presets.createCollection(named: name) {
            if let onCreated { onCreated(created) } else { dismiss() }
        }
    }

    private func problem(_ name: String) -> String? {
        presets.collectionNameProblem(name, renaming: renaming?.id)
    }
}

/// Adds one preset to a collection: an existing one, or a new one made in the same step (R4).
struct AddToCollectionSheet: View {
    @Bindable var presets: PresetCoordinator
    let preset: IndexedPreset

    @Environment(\.dismiss) private var dismiss
    @State private var namingNew = false

    var body: some View {
        NavigationStack {
            List {
                if let unavailable = presets.collectionsUnavailableText {
                    Text(unavailable)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("collectionsUnavailable")
                } else {
                    Section {
                        Button {
                            namingNew = true
                        } label: {
                            Label("New Collection…", systemImage: "plus")
                        }
                        .accessibilityIdentifier("newCollection")
                    }
                    Section {
                        ForEach(presets.collections) { collection in
                            let contains = presets.isInCollection(preset, collection.id)
                            Button {
                                if presets.addToCollection(preset, collection.id) != .failed { dismiss() }
                            } label: {
                                HStack {
                                    Text(collection.name).foregroundStyle(Color.primary)   // ACC-004: label colour, not the tint
                                    Spacer()
                                    if contains { Image(systemName: "checkmark").accessibilityHidden(true) }
                                }
                            }
                            .disabled(contains)
                            .accessibilityLabel(contains ? "\(collection.name), already contains this preset" : collection.name)
                            .accessibilityIdentifier("addTo:\(collection.name)")
                        }
                    } footer: {
                        Text("“\(preset.name)” is added at the end of the collection you choose.")
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $namingNew) {
                CollectionNameSheet(presets: presets) { created in
                    // Whether or not the add succeeded, the collection exists now: close both
                    // sheets (a failed add is reported by the browser's alert).
                    presets.addToCollection(preset, created.id)
                    dismiss()
                }
            }
            .collectionsAlert(presets)
        }
        .accessibilityIdentifier("addToCollectionSheet")
    }
}

/// Shows `collectionsMessage` (a refused change or a failed save; PRE-007-R8) and clears it.
private struct CollectionsAlert: ViewModifier {
    @Bindable var presets: PresetCoordinator

    func body(content: Content) -> some View {
        content.alert("Collections",
                      isPresented: Binding(get: { presets.collectionsMessage != nil },
                                           set: { if !$0 { presets.collectionsMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presets.collectionsMessage ?? "")
        }
    }
}

extension View {
    func collectionsAlert(_ presets: PresetCoordinator) -> some View { modifier(CollectionsAlert(presets: presets)) }
}
