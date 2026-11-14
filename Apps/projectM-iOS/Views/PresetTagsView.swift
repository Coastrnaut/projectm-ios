// PresetTagsView.swift — PRE-003: the Tags sheet for one preset (spec PRE-003-R4, R11, R12; contract
// C4). Mirrors SCN-005's SceneTagsView: the preset's tags with Remove (button and VoiceOver action),
// a field with Add (Return adds), and suggestions from the other presets' tags narrowed by the field.
// Changes save at once through PresetCoordinator, never load a preset, and announce on its library
// lane (never a direct post). Opened from every preset row ("Tags…" in the context menu, VoiceOver
// action "Tags").
import PresetLibrary
import SwiftUI

struct PresetTagsView: View {
    let presets: PresetCoordinator
    let preset: IndexedPreset
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    private var tags: [String] { presets.tags(of: preset) }

    private var suggestions: [String] {
        let own: Set<String> = Set(tags.map(PresetTagMap.fold))
        let needle: String = PresetTagMap.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return presets.tagVocabulary.filter { (tag: String) -> Bool in
            let folded: String = PresetTagMap.fold(tag)
            return !own.contains(folded) && (needle.isEmpty || folded.contains(needle))
        }
    }

    private var canAdd: Bool {
        PresetTagMap.normalizedTag(text) != nil && tags.count < PresetTagMap.maximumTagsPerPreset && presets.tagsUnavailableText == nil
    }

    var body: some View {
        NavigationStack {
            List {
                messageSection
                tagsSection
                addSection
                suggestionsSection
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("presetTagsDone")
                }
            }
        }
        .accessibilityIdentifier("presetTags")
    }

    // MARK: - Sections

    @ViewBuilder private var messageSection: some View {
        if let message = presets.tagsUnavailableText ?? presets.tagsMessage {
            Section {
                Text(message).accessibilityIdentifier("presetTagsMessage")
                if presets.tagsMessage != nil { Button("OK") { presets.dismissTagsMessage() } }
            }
        }
    }

    private var tagsSection: some View {
        let current: [String] = tags
        let header: String = "\(preset.name) · \(current.count) of \(PresetTagMap.maximumTagsPerPreset)"
        return Section {
            if current.isEmpty {
                Text("No tags yet").foregroundStyle(.secondary)
            }
            ForEach(current, id: \.self) { (tag: String) in tagRow(tag) }
        } header: {
            Text(header)
        }
    }

    private func tagRow(_ tag: String) -> some View {
        HStack {
            Label(tag, systemImage: "tag").accessibilityHidden(true)
            Spacer(minLength: 8)
            Button("Remove", role: .destructive) { presets.removeTag(tag, from: preset) }
                .buttonStyle(.borderless)
                .accessibilityHidden(true)
                .accessibilityIdentifier("presetTagRemove.\(tag)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tag)
        .accessibilityValue("Tag")
        .accessibilityAction(named: "Remove") { presets.removeTag(tag, from: preset) }
        .accessibilityIdentifier("presetTag.\(tag)")
    }

    private var addSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("New tag", text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit { add(text) }
                    .accessibilityLabel("New tag")
                    .accessibilityIdentifier("presetTagField")
                Button("Add") { add(text) }
                    .buttonStyle(.borderless)
                    .disabled(!canAdd)
                    .accessibilityIdentifier("presetTagAdd")
            }
        } footer: {
            Text("1 to \(PresetTagMap.maximumTagLength) characters. Tags are kept on this device; the preset itself stays as it is.")
        }
    }

    @ViewBuilder private var suggestionsSection: some View {
        let shown: [String] = suggestions
        if !shown.isEmpty {
            Section("Suggestions") {
                ForEach(shown, id: \.self) { (tag: String) in
                    Button { add(tag) } label: {
                        Label(tag, systemImage: "plus.circle")
                    }
                    .accessibilityLabel("Add \(tag)")
                    .accessibilityIdentifier("presetTagSuggestion.\(tag)")
                }
            }
        }
    }

    private func add(_ tag: String) {
        guard presets.addTag(tag, to: preset) else { return }
        if tag == text { text = "" }
        fieldFocused = true
    }
}
