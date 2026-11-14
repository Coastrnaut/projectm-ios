// SceneTagsView.swift — SCN-005: the Tags sheet for one scene (spec SCN-005-R4, R12, R13; contract
// T5). Lists the scene's tags with Remove (button and VoiceOver action), a field with Add (Return adds),
// and suggestions from the show's other tags (narrowed by the field's text). Changes save at once
// through ShowCoordinator, never apply a scene, and announce on its library lane (never a direct post).
// Opened from Scene Folders (swipe, context menu, VoiceOver action) and the switcher's row tag button.
import ShowControl
import SwiftUI

/// What a Tags sheet edits (a scene ID), for `.sheet(item:)`.
struct SceneTagsTarget: Identifiable, Equatable {
    let sceneID: String
    var id: String { sceneID }
}

struct SceneTagsView: View {
    let show: ShowCoordinator
    let sceneID: String
    /// Called after every change (the switcher drops vanished chips).
    var changed: () -> Void = { () -> Void in }
    let done: () -> Void

    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    private var tags: [String] { show.tags(ofScene: sceneID) }

    /// The show's other tags, those containing the field's text first-come in vocabulary order.
    private var suggestions: [String] {
        let own: Set<String> = Set(tags.map(SceneTagMap.fold))
        let needle: String = SceneTagMap.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return show.tagVocabulary.filter { (tag: String) -> Bool in
            let folded: String = SceneTagMap.fold(tag)
            return !own.contains(folded) && (needle.isEmpty || folded.contains(needle))
        }
    }

    private var canAdd: Bool { SceneTagMap.normalizedTag(text) != nil && tags.count < SceneTagMap.maximumTagsPerScene }

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
                    Button("Done") { done() }.accessibilityIdentifier("sceneTagsDone")
                }
            }
        }
        .accessibilityIdentifier("sceneTags")
    }

    // MARK: - Sections

    @ViewBuilder private var messageSection: some View {
        if let message = show.editorMessage {
            Section {
                Text(message).accessibilityIdentifier("sceneTagsMessage")
                Button("OK") { show.dismissEditorMessage() }
            }
        }
    }

    private var tagsSection: some View {
        let current: [String] = tags
        let header: String = "\(show.displayName(ofScene: sceneID)) · \(current.count) of \(SceneTagMap.maximumTagsPerScene)"
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
            Button("Remove", role: .destructive) { remove(tag) }
                .buttonStyle(.borderless)
                .accessibilityHidden(true)
                .accessibilityIdentifier("sceneTagRemove.\(tag)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tag)
        .accessibilityValue("Tag")
        .accessibilityAction(named: "Remove") { remove(tag) }
        .accessibilityIdentifier("sceneTag.\(tag)")
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
                    .accessibilityIdentifier("sceneTagField")
                Button("Add") { add(text) }
                    .buttonStyle(.borderless)
                    .disabled(!canAdd)
                    .accessibilityIdentifier("sceneTagAdd")
            }
        } footer: {
            Text("1 to \(SceneTagMap.maximumTagLength) characters. Tags only label scenes for filtering; the show stays as it is.")
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
                    .accessibilityIdentifier("sceneTagSuggestion.\(tag)")
                }
            }
        }
    }

    // MARK: - Actions

    private func add(_ tag: String) {
        guard show.addTag(tag, toScene: sceneID) else { return }
        if tag == text { text = "" }
        fieldFocused = true
        changed()
    }

    private func remove(_ tag: String) {
        guard show.removeTag(tag, fromScene: sceneID) else { return }
        changed()
    }
}
