// SmartCollectionViews.swift — PRE-008 smart collections (specs/228-pre-008-smart-collections, PRE-008-R4,
// R7-R9; contract C4): the section in the Collections screen (Smart marker, live count), one smart collection's
// members with Edit Rules, and the rule editor with the live count of the draft rules. All rules live in
// PresetLibrary (PresetSmartMatcher, PresetSmartCollectionStore); these views only show them.
import PresetLibrary
import SwiftUI

/// The smart collections, after the manual ones (R7).
struct SmartCollectionsSection: View {
    @Bindable var presets: PresetCoordinator
    @State private var editing: PresetSmartCollection?
    @State private var deleting: PresetSmartCollection?

    var body: some View {
        Section("Smart Collections") {
            if let unavailable = presets.smartUnavailableText {
                Text(unavailable).accessibilityIdentifier("smartUnavailable")
            } else if presets.smartCollections.isEmpty {
                Text("No smart collections yet. Tap the sparkles button to make one from tags, packs, motion and colours.")
                    .accessibilityIdentifier("smartEmpty")
            }
            ForEach(presets.smartCollections) { (collection: PresetSmartCollection) in
                row(collection)
            }
        }
        .sheet(item: $editing) { (collection: PresetSmartCollection) in
            SmartRulesSheet(presets: presets, editing: collection)
        }
        .alert("Delete “\(deleting?.name ?? "")”?",
               isPresented: Binding(get: { deleting != nil }, set: { (shown: Bool) in if !shown { deleting = nil } }),
               presenting: deleting) { (collection: PresetSmartCollection) in
            Button("Delete Smart Collection", role: .destructive) { presets.deleteSmartCollection(collection.id) }
                .accessibilityIdentifier("confirmDeleteSmartCollection")
            Button("Cancel", role: .cancel) {}
        } message: { (_: PresetSmartCollection) in
            Text("Only the rules are deleted. Their presets stay in your library.")
        }
    }

    private func row(_ collection: PresetSmartCollection) -> some View {
        let count: Int = presets.smartCount(collection.id)
        return NavigationLink(value: CollectionRoute.smart(collection.id)) {
            HStack {
                Image(systemName: "sparkles").accessibilityHidden(true)
                Text(collection.name)
                Text("Smart").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(count.formatted())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(PresetCoordinator.smartRowLabel(name: collection.name, count: count))
        }
        .accessibilityIdentifier("smartCollection:\(collection.name)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !presets.isCollectionEditLocked {   // SHOW-015-R4
                Button { deleting = collection } label: { Label("Delete", systemImage: "trash") }.tint(.red)
            }
            Button { editing = collection } label: { Label("Edit Rules", systemImage: "slider.horizontal.3") }
        }
        .contextMenu {
            Button { editing = collection } label: { Label("Edit Rules", systemImage: "slider.horizontal.3") }
            if !presets.isCollectionEditLocked {   // SHOW-015-R4
                Button(role: .destructive) { deleting = collection } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }
}

/// One smart collection: its members now; choosing one plays it in the smart collection's scope (R9).
struct SmartCollectionView: View {
    @Bindable var presets: PresetCoordinator
    let collectionID: String
    let onChoose: (IndexedPreset, PresetScope) -> Void
    let onDone: () -> Void
    @State private var editing = false

    var body: some View {
        let listing: [IndexedPreset] = presets.smartListing(collectionID)
        let collection: PresetSmartCollection? = presets.smartCollection(id: collectionID)
        List {
            if let unknown = collection?.unknownConditionCount, unknown > 0 {
                Text(PresetCoordinator.unknownRulesText(unknown)).accessibilityIdentifier("smartUnknownRules")
            }
            if listing.isEmpty {
                Text("No presets match these rules.").accessibilityIdentifier("smartCollectionEmpty")
            }
            ForEach(listing) { (preset: IndexedPreset) in
                PresetRow(presets: presets, preset: preset, showsPack: true, previewScope: .collection(collectionID)) {
                    onChoose(preset, .collection(collectionID))
                }
            }
        }
        .navigationTitle(collection?.name ?? "Smart Collection")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            if collection != nil {
                ToolbarItem(placement: .bottomBar) {
                    Button("Edit Rules") { editing = true }.accessibilityIdentifier("editSmartRules")
                }
            }
        }
        .sheet(isPresented: $editing) { SmartRulesSheet(presets: presets, editing: collection) }
    }
}

/// Creates a smart collection or edits one: name, All/Any, the choices of every kind, and the live count of
/// the draft rules (R8). Save commits in one atomic write; Cancel discards.
struct SmartRulesSheet: View {
    @Bindable var presets: PresetCoordinator
    /// The collection being edited; nil creates a new one.
    var editing: PresetSmartCollection?

    @Environment(\.dismiss) private var dismiss
    @State private var draft = SmartRulesDraft()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                matchSection
                SmartChoiceSection(title: "Favorites", kind: .favorite, options: [SmartOption(value: "", title: "Favorites only")],
                                   draft: $draft)
                SmartChoiceSection(title: "Tags", kind: .tag, options: tagOptions, draft: $draft)
                SmartChoiceSection(title: "Without tags", kind: .notTag, options: tagOptions, draft: $draft)
                SmartChoiceSection(title: "Packs", kind: .pack, options: packOptions, draft: $draft)
                SmartChoiceSection(title: "Motion", kind: .motion, options: motionOptions, draft: $draft)
                SmartChoiceSection(title: "Colours", kind: .color, options: colorOptions, draft: $draft)
            }
            .safeAreaInset(edge: .bottom) { draftCountBar }   // R8: the live count stays in view while scrolling
            .navigationTitle(editing == nil ? "New Smart Collection" : "Edit Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(nameProblem != nil).accessibilityIdentifier("smartSave")
                }
            }
            .onAppear(perform: load)
            .collectionsAlert(presets)
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Name", text: $draft.name)
                .accessibilityLabel("Smart collection name")
                .accessibilityIdentifier("smartName")
        } footer: {
            if !draft.name.isEmpty, let reason = nameProblem {
                Text(reason).foregroundStyle(.red)
            }
        }
    }

    private var matchSection: some View {
        Section {
            Picker("Match", selection: $draft.match) {
                Text("All rules").tag(PresetSmartMatch.all)
                Text("Any rule").tag(PresetSmartMatch.any)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Match")
            .accessibilityIdentifier("smartMatch")
        } footer: {
            Text("A preset matches a rule when it has any of the rule's choices.")
        }
    }

    private var draftCountBar: some View {
        let count: Int = presets.smartDraftCount(match: draft.match, conditions: draft.conditions)
        return Text(count == 1 ? "1 preset matches" : "\(count.formatted()) presets match")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.bar)
            .accessibilityIdentifier("smartDraftCount")
    }

    private var nameProblem: String? { presets.smartNameProblem(draft.name, renaming: editing?.id) }

    private var tagOptions: [SmartOption] {
        presets.tagVocabulary.map { (tag: String) -> SmartOption in SmartOption(value: tag, title: tag) }
    }

    private var packOptions: [SmartOption] {
        guard let library = presets.library else { return [] }
        var options: [SmartOption] = library.packs.filter { (pack: PresetPackInfo) -> Bool in pack.presetCount > 0 }
            .map { (pack: PresetPackInfo) -> SmartOption in SmartOption(value: pack.id, title: pack.title) }
        if !library.userPresets.isEmpty { options.append(SmartOption(value: PresetLibrary.userSource, title: UserPresetText.scopeTitle)) }
        return options
    }

    private var motionOptions: [SmartOption] {
        PresetEnergy.allCases.map { (energy: PresetEnergy) -> SmartOption in SmartOption(value: energy.rawValue, title: energy.name) }
    }

    private var colorOptions: [SmartOption] {
        PresetColorFamily.allCases.map { (family: PresetColorFamily) -> SmartOption in SmartOption(value: family.rawValue, title: family.name) }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing { draft = SmartRulesDraft(editing) }
    }

    private func save() {
        guard nameProblem == nil else { return }
        if let editing {
            let renamed: Bool = editing.name == draft.name || presets.renameSmartCollection(editing.id, to: draft.name)
            if renamed, presets.updateSmartCollection(editing.id, match: draft.match, conditions: draft.conditions) { dismiss() }
        } else if presets.createSmartCollection(named: draft.name, match: draft.match, conditions: draft.conditions) != nil {
            dismiss()
        }
    }
}

struct SmartOption: Hashable {
    let value: String
    let title: String
}

/// The editor's state: one condition per kind (the format allows more; the editor shows them merged), plus
/// the stored conditions of unknown kinds, kept unchanged (R4).
struct SmartRulesDraft: Equatable {
    var name = ""
    var match: PresetSmartMatch = .all
    var selected: [PresetSmartCondition.Kind: [String]] = [:]
    var favorite = false
    var unknown: [PresetSmartCondition] = []

    init() {}

    init(_ collection: PresetSmartCollection) {
        name = collection.name
        match = collection.match
        for condition in collection.conditions {
            guard let kind = condition.knownKind else { unknown.append(condition); continue }
            if kind == .favorite { favorite = true } else { selected[kind, default: []].append(contentsOf: condition.values) }
        }
    }

    func isOn(_ kind: PresetSmartCondition.Kind, _ value: String) -> Bool {
        kind == .favorite ? favorite : (selected[kind] ?? []).contains(value)
    }

    mutating func toggle(_ kind: PresetSmartCondition.Kind, _ value: String) {
        if kind == .favorite { favorite.toggle(); return }
        var values: [String] = selected[kind] ?? []
        if let index = values.firstIndex(of: value) { values.remove(at: index) } else { values.append(value) }
        selected[kind] = values
    }

    /// The conditions to save, in a fixed kind order.
    var conditions: [PresetSmartCondition] {
        var result: [PresetSmartCondition] = []
        for kind in PresetSmartCondition.Kind.allCases where kind != .favorite {
            let values: [String] = selected[kind] ?? []
            if !values.isEmpty { result.append(PresetSmartCondition(kind, values)) }
        }
        if favorite { result.append(PresetSmartCondition(.favorite)) }
        return result + unknown
    }
}

/// One kind's choices as rows with a checkmark (buttons, so VoiceOver and UI tests select them by name).
struct SmartChoiceSection: View {
    let title: String
    let kind: PresetSmartCondition.Kind
    let options: [SmartOption]
    @Binding var draft: SmartRulesDraft

    var body: some View {
        if !options.isEmpty {
            Section(title) {
                ForEach(options, id: \.self) { (option: SmartOption) in
                    choice(option)
                }
            }
        }
    }

    private func choice(_ option: SmartOption) -> some View {
        let on: Bool = draft.isOn(kind, option.value)
        return Button {
            draft.toggle(kind, option.value)
        } label: {
            HStack {
                Text(option.title).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
        }
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(kind == .favorite ? "smartRule:favorite" : "smartRule:\(kind.rawValue):\(option.value)")
    }
}
