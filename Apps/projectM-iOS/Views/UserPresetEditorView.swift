// UserPresetEditorView.swift — the plain text editor for a user preset (roadmap PRE-015,
// specs/010-pre-015-user-preset-duplication; PRE-015-R10-R18; US2).
//
// * Name and the preset's full text in system text controls, so VoiceOver reads and edits both
//   and the text follows Dynamic Type (a monospaced body font).
// * Save sends the change to the library, which checks it statically and on the off-screen
//   engine before storing it. A refusal keeps the editor open with the user's text and shows
//   the reason; the last saved version keeps playing.
// * Cancel with unsaved changes asks Discard Changes or Keep Editing; swiping the sheet down is
//   blocked while there are unsaved changes or a save is running.
import PresetLibrary
import SwiftUI

struct UserPresetEditorView: View {
    let preset: UserPreset
    let userPresets: UserPresetsCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var opened: PresetEditorText?
    @State private var loadFailed = false
    @State private var name = ""
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @State private var confirmingDiscard = false

    private var dirty: Bool {
        guard let opened else { return false }
        return text != opened.text || UserPresetName.cleanedName(name) != preset.name
    }

    var body: some View {
        NavigationStack {
            Group {
                if let opened {
                    editor(opened)
                } else if loadFailed {
                    Text("This preset cannot be edited right now.")
                        .foregroundStyle(.secondary)
                        .padding()
                        .accessibilityIdentifier("presetEditorUnavailable")
                } else {
                    ProgressView("Opening the preset…")
                }
            }
            .navigationTitle("Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if dirty { confirmingDiscard = true } else { dismiss() }
                    }
                    .disabled(saving)
                    .accessibilityIdentifier("presetEditorCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || opened == nil)
                        .accessibilityIdentifier("presetEditorSave")
                }
            }
            // An alert, not a confirmation dialog: both choices are always shown as buttons.
            .alert("Discard your changes?", isPresented: $confirmingDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                    .accessibilityIdentifier("discardChanges")
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your last saved version is kept.")
            }
        }
        .interactiveDismissDisabled(dirty || saving)
        .accessibilityIdentifier("presetEditor")
        .task {
            guard opened == nil, !loadFailed else { return }
            if let loaded = await userPresets.editorText(for: preset) {
                name = preset.name
                text = loaded.text
                opened = loaded
            } else {
                loadFailed = true
            }
        }
    }

    private func editor(_ opened: PresetEditorText) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("presetEditorError")
            }
            if saving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking the preset…")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("presetEditorChecking")
            }
            if !opened.isUTF8 {
                Text(PresetEditorText.latin1Note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("presetEditorEncodingNote")
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("Name")
                .accessibilityIdentifier("presetEditorName")
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Preset text")
                .accessibilityIdentifier("presetEditorText")
        }
        .padding()
        .disabled(saving)
    }

    private func save() async {
        guard let opened, !saving else { return }
        saving = true
        error = nil
        let outcome = await userPresets.saveEdit(preset, name: name, text: text, opened: opened)
        saving = false
        switch outcome {
        case .saved, .unchanged: dismiss()
        case .refused: error = outcome.message
        }
    }
}
