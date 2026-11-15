// PresetNoteView.swift — roadmap PRE-011: the Note sheet for one preset (spec PRE-011-R3, R4; contract C3).
// Opened from every preset row ("Note…" in the touch-and-hold menu, VoiceOver action "Note"). A multi-line text
// field limited to 2,000 characters with a live count, Save, Cancel and Delete Note. Swipe-to-dismiss is off while
// the text differs from the saved note, so nothing is lost by accident. Saving goes through PresetCoordinator,
// which announces on the library lane without the note text.
import PresetLibrary
import SwiftUI

struct PresetNoteView: View {
    let presets: PresetCoordinator
    let preset: IndexedPreset
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(presets: PresetCoordinator, preset: IndexedPreset) {
        self.presets = presets
        self.preset = preset
        _text = State(initialValue: presets.noteStore.note(for: preset.id) ?? "")
    }

    private var saved: String { presets.note(of: preset) ?? "" }
    private var isDirty: Bool { PresetNoteMap.trimmed(text) != saved }
    private var unavailable: Bool { presets.notesUnavailableText != nil }

    var body: some View {
        NavigationStack {
            Form {
                messageSection
                editorSection
                deleteSection
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isDirty)
        .accessibilityIdentifier("presetNote")
        .onAppear { focused = saved.isEmpty && !unavailable }
    }

    // MARK: - Sections

    @ViewBuilder private var messageSection: some View {
        if let message = presets.notesUnavailableText ?? presets.notesMessage {
            Section {
                Text(message).foregroundStyle(.red).accessibilityIdentifier("presetNoteMessage")
            }
        }
    }

    private var editorSection: some View {
        let count: Int = text.count
        return Section {
            TextEditor(text: $text)
                .frame(minHeight: 160)
                .focused($focused)
                .disabled(unavailable)
                .accessibilityLabel("Note")
                .accessibilityHint("Private to this device. Not included in diagnostics.")
                .accessibilityIdentifier("presetNoteText")
                .onChange(of: text) { (_: String, new: String) in limit(new) }
        } header: {
            Text(preset.name)
        } footer: {
            Text(PresetCoordinator.noteCountText(count))
                .accessibilityLabel(PresetCoordinator.noteCountText(count) + " characters")
                .accessibilityIdentifier("presetNoteCount")
        }
    }

    @ViewBuilder private var deleteSection: some View {
        if !saved.isEmpty && !unavailable {
            Section {
                Button("Delete Note", role: .destructive) {
                    if presets.deleteNote(of: preset) { dismiss() }
                }
                .accessibilityIdentifier("presetNoteDelete")
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                presets.dismissNotesMessage()
                dismiss()
            }
            .accessibilityIdentifier("presetNoteCancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                if presets.saveNote(text, for: preset) { dismiss() }
            }
            .disabled(unavailable || !isDirty)
            .accessibilityIdentifier("presetNoteSave")
        }
    }

    /// R3: the field keeps at most 2,000 characters (pasted text is cut at the limit).
    private func limit(_ value: String) {
        guard value.count > PresetNoteMap.maximumCharacters else { return }
        text = String(value.prefix(PresetNoteMap.maximumCharacters))
    }
}

/// PRE-011-R2: saved notes set aside or repaired, said once in the browser.
struct PresetNotesNoticeAlert: ViewModifier {
    let presets: PresetCoordinator

    func body(content: Content) -> some View {
        let shown = Binding<Bool>(get: { presets.notesNotice != nil },
                                  set: { (value: Bool) in if !value { presets.dismissNotesNotice() } })
        return content.alert("Preset notes", isPresented: shown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presets.notesNotice ?? "")
        }
    }
}
